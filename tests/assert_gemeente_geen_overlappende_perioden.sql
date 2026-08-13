-- Twee versies van dezelfde gemeente mogen elkaar niet overlappen. Faalt dit, dan levert
-- de between-join in commit 10 dubbele feitrijen.
select a.gemeente_code
from {{ ref('dim_gemeente') }} as a
inner join {{ ref('dim_gemeente') }} as b
    on
        a.gemeente_code = b.gemeente_code
        and a.gemeente_key <> b.gemeente_key
        and a.geldig_van <= b.geldig_tot
        and a.geldig_tot >= b.geldig_van
