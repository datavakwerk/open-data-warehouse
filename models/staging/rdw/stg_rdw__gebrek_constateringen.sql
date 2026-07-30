with bron as (
    select * from {{ source('rdw', 'geconstateerde_gebreken') }}
),

hernoemd as (
    select
        kenteken,
        cast(meld_datum_door_keuringsinstantie_dt as date) as meld_datum,
        lpad(meld_tijd_door_keuringsinstantie, 4, '0')     as meld_tijd,
        gebrek_identificatie,
        soort_erkenning_keuringsinstantie                  as soort_erkenning_code,
        soort_erkenning_omschrijving,
        cast(aantal_gebreken_geconstateerd as integer)     as aantal_gebreken_keuring
    from bron
)

select *
from hernoemd
qualify row_number() over (
    partition by kenteken, meld_datum, meld_tijd, gebrek_identificatie
    order by soort_erkenning_code
) = 1
