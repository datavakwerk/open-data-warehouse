-- Elke feitrij moet op een gemeenteversie landen die in dat peiljaar geldig was. Een
-- '-1' hier betekent óf een join op is_actueel in plaats van op de periode, óf een
-- peiljaar buiten de dekking van dim_gemeente.
select *
from {{ ref('fct_voertuigpark_gemeente') }}
where gemeente_key = '-1'
