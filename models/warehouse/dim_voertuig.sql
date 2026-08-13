with voertuigen as (

    select * from {{ ref('stg_rdw__voertuigen') }}

),

hoofdbrandstof as (

    -- Volgnummer 1 is per definitie de hoofdbrandstof. stg_rdw__brandstof heeft het
    -- volgnummer al naar integer gecast, dus vergelijken met 1 en niet met '1'.
    select
        kenteken,
        brandstof_omschrijving
    from {{ ref('stg_rdw__brandstof') }}
    where brandstof_volgnummer = 1

),

dimensie as (

    select
        {{ dbt_utils.generate_surrogate_key(['voertuigen.kenteken']) }} as voertuig_key,
        voertuigen.kenteken,
        upper(trim(voertuigen.merk))                                    as merk,
        upper(trim(voertuigen.handelsbenaming))                         as handelsbenaming,
        voertuigen.voertuigsoort,
        voertuigen.inrichting,
        voertuigen.eerste_kleur,
        voertuigen.catalogusprijs,
        voertuigen.massa_ledig_voertuig,
        voertuigen.datum_eerste_toelating,
        b.brandstof_omschrijving                                        as hoofdbrandstof

    from voertuigen
    left join hoofdbrandstof as b
        on voertuigen.kenteken = b.kenteken

)

select * from dimensie

union all

select
    '-1'         as voertuig_key,
    '(onbekend)' as kenteken,
    'ONBEKEND'   as merk,
    'ONBEKEND'   as handelsbenaming,
    'Onbekend'   as voertuigsoort,
    null         as inrichting,
    null         as eerste_kleur,
    null         as catalogusprijs,
    null         as massa_ledig_voertuig,
    null         as datum_eerste_toelating,
    null         as hoofdbrandstof
