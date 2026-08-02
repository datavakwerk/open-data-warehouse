{% macro nl_feestdagen(eerste_jaar, laatste_jaar) -%}

with jaren as (
    select unnest(range({{ eerste_jaar }}, {{ laatste_jaar }} + 1)) as jaar
),

-- Anonieme Gregoriaanse paasberekening. Elke deling hieronder is een INTEGER-deling
-- (`//`). Schrijf je `/`, dan krijg je een double en klopt geen enkele modulo meer.
basis as (
    select
        jaar,
        jaar % 19   as a,
        jaar // 100 as b,
        jaar % 100  as c
    from jaren
),

hulp as (
    select
        jaar, a, b, c,
        b // 4        as d,
        b % 4         as e,
        (b + 8) // 25 as f,
        c // 4        as i,
        c % 4         as k
    from basis
),

maand_h as (
    select
        jaar, a, e, i, k,
        (19 * a + b - d - (b - f + 1) // 3 + 15) % 30 as h
    from hulp
),

maand_l as (
    select
        jaar, a, h,
        (32 + 2 * e + 2 * i - h - k) % 7 as l
    from maand_h
),

pasen as (
    select
        jaar,
        make_date(
            jaar,
            (h + l - 7 * ((a + 11 * h + 22 * l) // 451) + 114) // 31,
            ((h + l - 7 * ((a + 11 * h + 22 * l) // 451) + 114) % 31) + 1
        ) as eerste_paasdag
    from maand_l
),

-- Koningsdag is 27 april, tenzij dat een zondag is — dan 26 april. Vóór 2014 was het
-- Koninginnedag op 30 april, met dezelfde zondagregel naar 29 april. De spine begint in
-- 1990, dus die tak wordt echt gebruikt.
koningsdag as (
    select
        jaar,
        case
            when jaar >= 2014 and isodow(make_date(jaar, 4, 27)) = 7 then make_date(jaar, 4, 26)
            when jaar >= 2014                                        then make_date(jaar, 4, 27)
            when isodow(make_date(jaar, 4, 30)) = 7                  then make_date(jaar, 4, 29)
            else make_date(jaar, 4, 30)
        end as datum,
        case when jaar >= 2014 then 'Koningsdag' else 'Koninginnedag' end as feestdag
    from jaren
),

los as (
    select make_date(jaar, 1, 1) as datum, 'Nieuwjaarsdag' as feestdag from jaren
    union all select eerste_paasdag - 2,      'Goede Vrijdag'      from pasen
    union all select eerste_paasdag,          'Eerste Paasdag'     from pasen
    union all select eerste_paasdag + 1,      'Tweede Paasdag'     from pasen
    union all select datum,                   feestdag             from koningsdag
    union all select make_date(jaar, 5, 5),   'Bevrijdingsdag'     from jaren
    union all select eerste_paasdag + 39,     'Hemelvaartsdag'     from pasen
    union all select eerste_paasdag + 49,     'Eerste Pinksterdag' from pasen
    union all select eerste_paasdag + 50,     'Tweede Pinksterdag' from pasen
    union all select make_date(jaar, 12, 25), 'Eerste Kerstdag'    from jaren
    union all select make_date(jaar, 12, 26), 'Tweede Kerstdag'    from jaren
)

-- Eén rij per datum. Zie de valkuil hieronder: zonder deze group by is de macro geen
-- lookup maar een fan-out.
select
    datum,
    string_agg(feestdag, ' en ' order by feestdag) as feestdag
from los
group by datum

{%- endmacro %}