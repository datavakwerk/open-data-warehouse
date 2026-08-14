with telling as (

    select
        (select count(*) from {{ ref('fct_gebrek_constatering') }})        as feit_rijen,
        (select count(*) from {{ ref('stg_rdw__gebrek_constateringen') }}) as staging_rijen,
        (
            select count(*) from {{ ref('fct_gebrek_constatering') }}
            where meld_datum_key = -1
        )                                                                  as onbekende_datum,
        (
            select count(*) from {{ ref('fct_gebrek_constatering') }}
            where voertuig_key = '-1'
        )                                                                  as onbekend_voertuig,
        (
            select count(*) from {{ ref('fct_gebrek_constatering') }}
            where gebrek_key = '-1'
        )                                                                  as onbekend_gebrek

)

select *
from telling
where
    feit_rijen <> staging_rijen
    or onbekende_datum > 0
    or onbekend_voertuig > 0
    or onbekend_gebrek > 0
