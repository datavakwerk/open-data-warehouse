with bron as (
    select * from {{ source('rdw', 'gebreken') }}
)

select
    gebrek_identificatie,
    gebrek_omschrijving,
    gebrek_artikel_nummer,
    gebrek_paragraaf_nummer,
    cast(ingangsdatum_gebrek_dt as date)  as ingangsdatum_gebrek,
    cast(einddatum_gebrek_dt as date)     as einddatum_gebrek
from bron