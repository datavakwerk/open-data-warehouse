with brandstof as (

    select * from {{ ref('stg_rdw__brandstof') }}

)

select
    {{ dbt_utils.generate_surrogate_key(['kenteken']) }}               as voertuig_key,
    {{ dbt_utils.generate_surrogate_key(['brandstof_omschrijving']) }} as brandstof_key,
    kenteken,
    brandstof_volgnummer                                               as volgnummer,
    brandstof_volgnummer = 1                                           as is_hoofdbrandstof

from brandstof
