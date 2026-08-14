with feiten as (

    select * from {{ ref('fct_voertuigpark_gemeente') }}

),

versies as (

    select * from {{ ref('dim_gemeente') }}
    where gemeente_key <> '-1'

),

-- Per code de nieuwste versie — niet is_actueel: 72 opgeheven codes hebben geen
-- actuele versie en zouden met hun hele historie uit de mart vallen.
laatste_versie as (

    select
        gemeente_code,
        gemeente_naam as gemeente_naam_nu,
        is_actueel    as bestaat_nog
    from versies
    qualify row_number() over (
        partition by gemeente_code order by geldig_van desc
    ) = 1

)

select
    l.gemeente_naam_nu,
    v.gemeente_naam as naam_destijds,
    l.bestaat_nog,
    f.gemeente_code,
    f.peiljaar,
    f.voertuigsoort,
    f.aantal

from feiten as f
inner join versies as v
    on f.gemeente_key = v.gemeente_key
inner join laatste_versie as l
    on f.gemeente_code = l.gemeente_code
