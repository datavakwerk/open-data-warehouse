with spine as (

    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('1990-01-01' as date)",
        end_date="cast('2030-01-01' as date)"
    ) }}

),

kalender as (
    select cast(date_day as date) as datum from spine
),

feestdagen as (
    {{ nl_feestdagen(1990, 2029) }}
),

-- Nederlandse namen; strftime('%B') geeft Engelse. Lijstindexering in DuckDB is
-- 1-based, dus month() en isodow() kunnen er rechtstreeks in.
namen as (
    select
        [
            'januari', 'februari', 'maart', 'april', 'mei', 'juni', 'juli',
            'augustus', 'september', 'oktober', 'november', 'december'
        ] as maanden,
        [
            'maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag',
            'zaterdag', 'zondag'
        ] as dagen
),

kalenderdagen as (

    select
        cast(strftime(k.datum, '%Y%m%d') as integer) as datum_key,
        k.datum,
        year(k.datum)                                as jaar,
        quarter(k.datum)                             as kwartaal,
        month(k.datum)                               as maand,
        n.maanden[month(k.datum)]                    as maand_naam,
        day(k.datum)                                 as dag,
        dayofyear(k.datum)                           as dag_van_jaar,
        isodow(k.datum)                              as dag_van_week,
        n.dagen[isodow(k.datum)]                     as dag_naam,
        week(k.datum)                                as weeknummer,
        isoyear(k.datum)                             as iso_jaar,
        isodow(k.datum) >= 6                         as is_weekend,
        f.datum is not null                          as is_feestdag,
        f.feestdag                                   as feestdag_naam,
        isodow(k.datum) <= 5 and f.datum is null     as is_werkdag

    from kalender as k
    cross join namen as n
    left join feestdagen as f on k.datum = f.datum

)

select * from kalenderdagen

union all

-- Onbekend lid. Zie de sleutelconventie in stap 1: elk feit coalesct hiernaartoe.
select
    -1                         as datum_key,
    cast('1900-01-01' as date) as datum,
    1900                       as jaar,
    1                          as kwartaal,
    1                          as maand,
    'onbekend'                 as maand_naam,
    1                          as dag,
    1                          as dag_van_jaar,
    1                          as dag_van_week,
    'onbekend'                 as dag_naam,
    1                          as weeknummer,
    1900                       as iso_jaar,
    false                      as is_weekend,
    false                      as is_feestdag,
    null                       as feestdag_naam,
    false                      as is_werkdag
