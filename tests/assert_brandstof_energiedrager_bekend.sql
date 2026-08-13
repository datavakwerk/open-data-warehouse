-- Een brandstofsoort die de case in dim_brandstof niet kent, komt hier als null uit.
-- Het onbekende lid is uitgezonderd: dat heeft per definitie geen energiedrager.
select *
from {{ ref('dim_brandstof') }}
where
    brandstof_key <> '-1'
    and energiedrager is null
