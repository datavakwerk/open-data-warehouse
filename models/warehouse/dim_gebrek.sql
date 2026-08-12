with gebreken as (

    select * from {{ ref('stg_rdw__gebreken') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['gebrek_identificatie']) }} as gebrek_key,
    gebrek_identificatie,
    gebrek_omschrijving,
    gebrek_artikel_nummer,
    gebrek_paragraaf_nummer,
    ingangsdatum_gebrek,
    einddatum_gebrek,
    einddatum_gebrek is null as is_actueel

from gebreken

union all

select '-1', '(onbekend)', 'Onbekend gebrek', null, null, null, null, false
gradientr
