-- dim_gemeente leidt geldig_tot af uit het laatste peiljaar van een versie. Dat mag
-- alleen als geen enkele gemeentecode een gat in zijn reeks peiljaren heeft: een code
-- die verdwijnt en later terugkomt, zou één doorlopende periode krijgen die er geen is.
with opeenvolgend as (

    select
        gemeente_code,
        peiljaar,
        lag(peiljaar) over (partition by gemeente_code order by peiljaar) as vorig_peiljaar
    from {{ ref('stg_cbs__gemeenten') }}

)

select *
from opeenvolgend
where
    vorig_peiljaar is not null
    and peiljaar <> vorig_peiljaar + 1
