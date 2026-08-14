with constateringen as (

    select * from {{ ref('fct_gebrek_constatering') }}

),

-- De joins op de surrogaatsleutels slagen per constructie: het feit coalescet elke
-- mislukte lookup naar '-1' en dat lid bestaat in beide dimensies. Inner join is hier
-- dus geen risico op rijverlies — dát is wat het onbekende lid koopt.
per_combinatie as (

    select
        dg.gebrek_identificatie,
        dg.gebrek_omschrijving,
        dv.voertuigsoort,

        -- Geen "bouwjaar": dat kent de bron niet. datum_eerste_toelating valt er voor
        -- NL-voertuigen vrijwel mee samen, voor import niet — vandaar deze naam.
        year(dv.datum_eerste_toelating) as jaar_eerste_toelating,

        sum(f.aantal_gebreken)          as aantal_gebreken

    from constateringen as f
    inner join {{ ref('dim_gebrek') }} as dg
        on f.gebrek_key = dg.gebrek_key
    inner join {{ ref('dim_voertuig') }} as dv
        on f.voertuig_key = dv.voertuig_key
    group by 1, 2, 3, 4

)

select
    *,
    -- Rangnummer per voertuigsoort × jaar, zodat "top-10" in BI een filter is.
    -- Deterministische tiebreaker op de code: gelijke aantallen krijgen altijd
    -- dezelfde volgorde, anders verspringt de mart per build.
    row_number() over (
        partition by voertuigsoort, jaar_eerste_toelating
        order by aantal_gebreken desc, gebrek_identificatie desc
    ) as rang

from per_combinatie
