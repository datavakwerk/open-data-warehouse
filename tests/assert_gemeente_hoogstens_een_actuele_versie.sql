-- Een opgeheven gemeente heeft nul actuele rijen, een bestaande precies één. Twee is
-- altijd fout.
select gemeente_code
from {{ ref('dim_gemeente') }}
where is_actueel
group by gemeente_code
having count(*) > 1
