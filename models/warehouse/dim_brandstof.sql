with soorten as (

    select distinct brandstof_omschrijving
    from {{ ref('stg_rdw__brandstof') }}
    where brandstof_omschrijving is not null

),

dimensie as (

    select
        {{ dbt_utils.generate_surrogate_key(['brandstof_omschrijving']) }}
            as brandstof_key,
        brandstof_omschrijving,

        -- Expliciete lijsten en géén else-tak: een negende brandstofsoort komt hier als
        -- null uit en maakt tests/assert_brandstof_energiedrager_bekend.sql rood. Met
        -- `else 'Fossiel'` zou waterstof-2 stilzwijgend fossiel heten.
        case
            when brandstof_omschrijving in ('Benzine', 'Diesel', 'LPG', 'CNG', 'LNG')
                then 'Fossiel'
            when brandstof_omschrijving in ('Elektriciteit', 'Waterstof')
                then 'Emissievrij'
            when brandstof_omschrijving in ('Alcohol')
                then 'Biobrandstof'
        end
            as energiedrager

    from soorten

)

select * from dimensie

union all

select
    '-1'         as brandstof_key,
    '(onbekend)' as brandstof_omschrijving,
    null         as energiedrager
