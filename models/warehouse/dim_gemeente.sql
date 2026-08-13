with snapshots as (

    select * from {{ ref('stg_cbs__gemeenten') }}

),

-- Versioneren op de naam, niet op agglomeratie of arbeidsmarktregio.
met_vorige as (

    select
        peiljaar,
        gemeente_code,
        gemeente_naam,
        agglomeratie_naam,
        arbeidsmarktregio,
        lag(gemeente_naam) over (
            partition by gemeente_code order by peiljaar
        ) as vorige_naam
    from snapshots

),

-- Bewust geen `is distinct from`: sqlfluff 4.1.0 parseert dat niet in het
-- duckdb-dialect. gemeente_naam is not_null (test in staging), dus alleen vorige_naam
-- kan null zijn — de eerste rij per code — en die telt als wijziging.
gemarkeerd as (

    select
        peiljaar,
        gemeente_code,
        gemeente_naam,
        agglomeratie_naam,
        arbeidsmarktregio,
        case
            when vorige_naam is null then 1
            when gemeente_naam <> vorige_naam then 1
            else 0
        end as is_wijziging
    from met_vorige

),

-- Lopende som over de wijzigingsmarkeringen: elke wijziging start een nieuwe groep. De
-- eerste rij van een code telt óók als wijziging (lag is null), dus versie begint bij 1.
versies as (

    select
        *,
        sum(is_wijziging) over (
            partition by gemeente_code order by peiljaar
            rows between unbounded preceding and current row
        ) as versie
    from gemarkeerd

),

perioden as (

    select
        gemeente_code,
        versie,
        min(peiljaar)          as van_jaar,
        max(peiljaar)          as tot_jaar,
        max(gemeente_naam)     as gemeente_naam,      -- constant binnen de versie
        max(agglomeratie_naam) as agglomeratie_naam,  -- laatste stand; zie yml
        max(arbeidsmarktregio) as arbeidsmarktregio
    from versies
    group by gemeente_code, versie

),

laatste_peiljaar as (

    select max(peiljaar) as peiljaar from snapshots

),

dimensie as (

    select
        {{ dbt_utils.generate_surrogate_key(['p.gemeente_code', 'p.versie']) }} as gemeente_key,
        p.gemeente_code,
        p.gemeente_naam,
        p.agglomeratie_naam,
        p.arbeidsmarktregio,

        -- Niet p.versie zelf: die begint bij 1 omdat de eerste rij als wijziging telt,
        -- maar hij is niet gegarandeerd aaneengesloten. row_number() wel.
        row_number() over (partition by p.gemeente_code order by p.van_jaar)    as versienummer,

        make_date(p.van_jaar, 1, 1)                                             as geldig_van,
        case
            when p.tot_jaar = l.peiljaar then cast('9999-12-31' as date)
            else make_date(p.tot_jaar, 12, 31)
        end                                                                     as geldig_tot,
        p.tot_jaar = l.peiljaar                                                 as is_actueel

    from perioden as p
    cross join laatste_peiljaar as l

)

select * from dimensie

union all

select
    '-1'                       as gemeente_key,
    '(onbekend)'               as gemeente_code,
    'Onbekende gemeente'       as gemeente_naam,
    null                       as agglomeratie_naam,
    null                       as arbeidsmarktregio,
    1                          as versienummer,
    cast('1900-01-01' as date) as geldig_van,
    cast('9999-12-31' as date) as geldig_tot,
    false                      as is_actueel
