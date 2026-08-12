with gebreken as (

    select * from {{ ref('stg_rdw__gebreken') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['gebrek_identificatie']) }}
        as gebrek_key,
    gebrek_identificatie,
    gebrek_omschrijving,
    gebrek_artikel_nummer,
    gebrek_paragraaf_nummer,
    ingangsdatum_gebrek,
    einddatum_gebrek,
    einddatum_gebrek is null
        as is_actueel

from gebreken

union all

select
    '-1'              as gebrek_key,
    '(onbekend)'      as gebrek_identificatie,
    'Onbekend gebrek' as gebrek_omschrijving,
    null              as gebrek_artikel_nummer,
    null              as gebrek_paragraaf_nummer,
    null              as ingangsdatum_gebrek,
    null              as einddatum_gebrek,
    false             as is_actueel
