with bron as (
    select * from {{ source('rdw', 'gekentekende_voertuigen') }}
)

select
    -- identificatie
    kenteken,

    -- typekenmerken
    voertuigsoort,
    merk,
    handelsbenaming,
    inrichting,
    eerste_kleur,
    tweede_kleur,
    europese_voertuigcategorie,

    -- aantallen en maten
    cast(aantal_zitplaatsen as integer)                       as aantal_zitplaatsen,
    cast(aantal_deuren as integer)                            as aantal_deuren,
    cast(aantal_wielen as integer)                            as aantal_wielen,
    cast(aantal_cilinders as integer)                         as aantal_cilinders,
    cast(cilinderinhoud as integer)                           as cilinderinhoud,
    cast(massa_ledig_voertuig as integer)                     as massa_ledig_voertuig,
    cast(massa_rijklaar as integer)                           as massa_rijklaar,
    cast(toegestane_maximum_massa_voertuig as integer)        as toegestane_maximum_massa,
    cast(maximale_constructiesnelheid as integer)             as maximale_constructiesnelheid,
    cast(catalogusprijs as integer)                           as catalogusprijs,
    cast(bruto_bpm as integer)                                as bruto_bpm,

    -- datums: altijd de _dt-variant
    cast(datum_eerste_toelating_dt as date)                   as datum_eerste_toelating,
    cast(datum_tenaamstelling_dt as date)                     as datum_tenaamstelling,
    cast(vervaldatum_apk_dt as date)                          as vervaldatum_apk,
    cast(datum_eerste_tenaamstelling_in_nederland_dt as date)
        as datum_eerste_tenaamstelling_nl,

    -- indicatoren
    export_indicator = 'Ja'                                   as is_geexporteerd,
    tenaamstellen_mogelijk = 'Ja'                             as is_tenaamstellen_mogelijk,
    taxi_indicator = 'Ja'                                     as is_taxi,
    openstaande_terugroepactie_indicator = 'Ja'               as heeft_openstaande_terugroepactie,

    -- driewaardig, dus geen boolean; zie de valkuil hieronder
    wam_verzekerd                                             as wam_verzekerd_status

from bron
