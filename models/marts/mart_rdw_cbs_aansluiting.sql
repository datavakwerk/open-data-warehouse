with rdw as (

    select
        -- Expliciete lijsten, geen else: een nieuwe RDW-soort komt hier als null uit
        -- en de not_null-test maakt hem zichtbaar. Bus -> Bedrijfsmotorvoertuig en
        -- zijspan -> Motorfiets zijn oordelen; zie de yml.
        case
            when voertuigsoort = 'Personenauto'
                then 'Personenauto'
            when voertuigsoort in ('Bedrijfsauto', 'Bus')
                then 'Bedrijfsmotorvoertuig'
            when voertuigsoort in ('Motorfiets', 'Motorfiets met zijspan')
                then 'Motorfiets'
            when voertuigsoort = 'Bromfiets'
                then 'Bromfiets'
            when
                voertuigsoort in (
                    'Aanhangwagen', 'Middenasaanhangwagen', 'Oplegger',
                    'Autonome aanhangwagen', 'Driewielig motorrijtuig',
                    'Land- of bosbouwtrekker', 'Motorrijtuig met beperkte snelheid'
                )
                then '(niet vergelijkbaar)'
        end      as voertuigsoort_cbs,
        count(*) as aantal_steekproef
    from {{ ref('dim_voertuig') }}
    where voertuig_key <> '-1'
    group by 1

),

cbs as (

    -- Alleen het laatst beschikbare peiljaar: de steekproef is één momentopname
    -- (snapshot 2026-07-29), geen jaarreeks.
    select
        voertuigsoort as voertuigsoort_cbs,
        sum(aantal)   as aantal_park
    from {{ ref('fct_voertuigpark_gemeente') }}
    where
        peiljaar = (
            select max(f.peiljaar) from {{ ref('fct_voertuigpark_gemeente') }} as f
        )
    group by 1

),

vergelijkbaar as (

    select
        coalesce(r.voertuigsoort_cbs, c.voertuigsoort_cbs) as voertuigsoort_cbs,
        r.aantal_steekproef,
        c.aantal_park
    from rdw as r
    full outer join cbs as c
        on r.voertuigsoort_cbs = c.voertuigsoort_cbs

)

select
    voertuigsoort_cbs,
    aantal_steekproef,
    aantal_park,

    -- Aandelen alleen binnen de vergelijkbare soorten: '(niet vergelijkbaar)' doet
    -- niet mee aan teller óf noemer, anders vergelijk je een deel met een geheel.
    case
        when voertuigsoort_cbs <> '(niet vergelijkbaar)'
            then round(aantal_steekproef / sum(aantal_steekproef) filter (
                where voertuigsoort_cbs <> '(niet vergelijkbaar)'
            ) over (), 4)
    end                                              as aandeel_rdw,
    round(aantal_park / sum(aantal_park) over (), 4) as aandeel_cbs

from vergelijkbaar
