with bron as (
    select * from {{ source('cbs', '70072ned_motorvoertuigen_gemeente') }}
)

select
    regios                             as gemeente_code,
    cast(left(perioden, 4) as int)     as peiljaar,
    case measure
        when 'A018943_1' then 'Personenauto'
        when 'A018930' then 'Bedrijfsmotorvoertuig'
        when 'A018944_1' then 'Motorfiets'
        when 'A018934_1' then 'Bromfiets'
    end                                as voertuigsoort,
    cast(cast(value as double) as int) as aantal

from bron
where
    regios like 'GM%'
    and measure in ('A018943_1', 'A018930', 'A018944_1', 'A018934_1')
    and value is not null
