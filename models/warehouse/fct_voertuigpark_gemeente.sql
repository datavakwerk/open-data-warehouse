-- dim_gemeente is opgebouwd uit de CBS-gebiedsbestanden en die beginnen bij peiljaar
-- 2015. stg_cbs__voertuigpark_gemeente gaat terug tot 2000. Zonder dit filter landen
-- 23.910 oudere rijen op gemeente_key '-1'. De grens wordt uit de dimensie afgeleid en
-- niet als 2015 ingetypt: komt er ooit een gebiedsbestand 2014 bij, dan schuift het
-- filter vanzelf mee.
with dekking as (

    select min(dg.geldig_van) as vroegste_peildatum
    from {{ ref('dim_gemeente') }} as dg
    where dg.gemeente_key <> '-1'

),

voertuigpark as (

    select *
    from {{ ref('stg_cbs__voertuigpark_gemeente') }}
    where make_date(peiljaar, 1, 1) >= (
        select d.vroegste_peildatum
        from dekking as d
    )

),

fact as (

    select
        coalesce(dd.datum_key, -1)      as peildatum_key,
        coalesce(dg.gemeente_key, '-1') as gemeente_key,

        -- Degenerate dimensies. voertuigsoort krijgt geen eigen dimensie: vier waarden,
        -- geen attributen om aan te hangen.
        v.gemeente_code,
        v.peiljaar,
        v.voertuigsoort,

        v.aantal

    from voertuigpark as v

    -- DE TEMPORELE JOIN. Dit is het hele punt van SCD2: het cijfer van 2016 hangt aan de
    -- gemeente zoals die in 2016 heette, niet aan de huidige.
    left join {{ ref('dim_gemeente') }} as dg
        on
            v.gemeente_code = dg.gemeente_code
            and make_date(v.peiljaar, 1, 1) between dg.geldig_van and dg.geldig_tot

    left join {{ ref('dim_datum') }} as dd
        on dd.datum = make_date(v.peiljaar, 1, 1)

)

select * from fact
