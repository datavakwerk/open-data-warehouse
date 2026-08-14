with constateringen as (

    select * from {{ ref('stg_rdw__gebrek_constateringen') }}

),

fact as (

    select
        coalesce(dt.datum_key, -1)      as meld_datum_key,
        coalesce(dv.voertuig_key, '-1') as voertuig_key,
        coalesce(dg.gebrek_key, '-1')   as gebrek_key,

        -- Degenerate dimensies: onderdeel van de natuurlijke sleutel, maar zonder eigen
        -- dimensietabel. Ze blijven hier staan zodat de korreltest hierop kan draaien.
        c.kenteken,
        c.meld_datum,
        c.meld_tijd,
        c.gebrek_identificatie,

        c.soort_erkenning_omschrijving,

        -- De maat. Eén rij is één geconstateerd gebrek; zie de valkuil over
        -- aantal_gebreken_keuring waarom dit geen kolom uit de bron is.
        1                               as aantal_gebreken

    from constateringen as c
    left join {{ ref('dim_datum') }} as dt
        on c.meld_datum = dt.datum
    left join {{ ref('dim_voertuig') }} as dv
        on c.kenteken = dv.kenteken
    left join {{ ref('dim_gebrek') }} as dg
        on c.gebrek_identificatie = dg.gebrek_identificatie

)

select * from fact
