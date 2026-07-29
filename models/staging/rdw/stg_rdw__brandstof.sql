with bron as (
    select * from {{ source('rdw', 'brandstof') }}
)

select
    kenteken,
    cast(brandstof_volgnummer as integer)                as brandstof_volgnummer,
    brandstof_omschrijving,

    -- verbruik en uitstoot: double, niet integer
    cast(brandstofverbruik_gecombineerd as double)       as brandstofverbruik_gecombineerd,
    cast(co2_uitstoot_gecombineerd as double)            as co2_uitstoot_gecombineerd,
    cast(co2_uitstoot_gewogen as double)                 as co2_uitstoot_gewogen,
    cast(nettomaximumvermogen as double)                 as nettomaximumvermogen,

    -- geluid, in hele dB
    cast(geluidsniveau_rijdend as integer)               as geluidsniveau_rijdend,
    cast(geluidsniveau_stationair as integer)            as geluidsniveau_stationair,

    emissiecode_omschrijving,
    uitlaatemissieniveau,
    milieuklasse_eg_goedkeuring_licht

from bron