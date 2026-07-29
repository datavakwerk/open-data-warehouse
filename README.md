# nl-open-data-warehouse

**End-to-end ELT-platform op Nederlandse open data, met een gedocumenteerd
Kimball-sterschema.**

Python-ingestie → warehouse → dbt (staging → sterschema → marts) → tests, docs en CI.
Gebouwd zoals een data-platformteam het oplevert: versiebeheer, code review,
geautomatiseerde tests en een lineage die klopt.

> **Status:** in aanbouw. Zie [Definition of done](#definition-of-done) voor wat er staat
> en wat nog niet. Claims in deze README die nog niet waar zijn, staan als openstaand
> vinkje — niet als proza.

## Data

Twee publieke bronnen, allebei zonder API-sleutel te bevragen:

| Bron | Wat | Rol in het model |
| --- | --- | --- |
| [RDW open data](https://opendata.rdw.nl) | gekentekende voertuigen, brandstof, geconstateerde gebreken | transactiefeiten (miljoenen rijen) |
| [CBS StatLine](https://opendata.cbs.nl) (odata) | motorvoertuigenpark en gemeentelijke indeling | snapshotfeit + gemeentedimensie |

De combinatie is bewust gekozen: RDW levert feiten op recordniveau, CBS levert een
periodieke snapshot op gemeenteniveau. Twee feiten met een verschillende korrel in
één schema is precies waar dimensioneel modelleren over gaat — en waar het misgaat
als je de korrel niet expliciet maakt.

Elke ingestie legt een **snapshotdatum** vast en de selectiequery staat in de repo,
zodat een run reproduceerbaar is.

Zie **[docs/data.md](docs/data.md)** voor wat er precies wordt opgehaald: de dataset-id's,
de korrel per bestand, de steekproefopzet en de controles daarop. De data zelf staat niet
in git — `make ingest` haalt hem op.

## Architectuur

```
  RDW / CBS API
        │  Python ingestie (incrementeel, gepagineerd, met retries)
        ▼
   data/raw/*.parquet
        │  dbt seed/source
        ▼
  ┌─────────────────────────────────────────────┐
  │ DuckDB                                       │
  │                                              │
  │  staging/    1:1 met de bron, hernoemd,      │
  │              getypeerd, gededuped            │
  │      ▼                                       │
  │  warehouse/  dim_* en fct_* (Kimball)        │
  │      ▼                                       │
  │  marts/      businessvragen, brede tabellen  │
  └─────────────────────────────────────────────┘
        │
        ▼
  dbt tests · dbt docs (lineage) · Evidence-pagina
```

DuckDB omdat het gratis is en in CI draait. Hetzelfde dbt-project richt zich met een
ander profiel op Snowflake of Databricks; de modellen zijn daarop geschreven (geen
DuckDB-specifieke SQL buiten `staging/`).

<!-- TODO: architectuurdiagram + screenshot van de dbt-lineagegraaf toevoegen -->

## Het sterschema

Per feittabel staat de **korrel** expliciet — één zin, geen interpretatie mogelijk.

| Feittabel | Korrel (één rij per …) | Type | Dimensies |
| --- | --- | --- | --- |
| `fct_voertuig_registratie` | kenteken per tenaamstelling | transactie | datum, voertuigtype, brandstof |
| `fct_gebrek_constatering` | geconstateerd gebrek per keuring per voertuig | transactie | datum, voertuigtype, gebrek |
| `fct_voertuigpark_gemeente` | gemeente per peiljaar per brandstofsoort | periodieke snapshot | datum, gemeente, brandstof |

| Dimensie | SCD | Waarom |
| --- | --- | --- |
| `dim_datum` | — | gegenereerd, met NL-feestdagen en kwartaal/weeknummers |
| `dim_gemeente` | **type 2** | gemeentelijke herindelingen; historische feiten moeten aan de gemeente van tóen hangen |
| `dim_voertuigtype` | type 1 | merk/handelsbenaming/voertuigsoort; correcties zijn correcties, geen historie |
| `dim_brandstof` | type 1 | kleine, stabiele referentielijst |
| `dim_gebrek` | type 1 | RDW-gebrekcode met omschrijving en ernstcategorie |

## Snel starten

```bash
make install     # dependencies (uv/pip) + dbt packages
make ingest      # haalt een snapshot op naar data/raw/
make build       # dbt build: modellen + tests
make docs        # dbt docs generate && serve
```

`make` zonder argument draait de hele keten van lege map tot bevraagbaar warehouse.

## Ontwerpkeuzes

- **Waarom deze korrel.** `fct_voertuig_registratie` staat op tenaamstelling, niet op
  voertuig: een voertuig wisselt van eigenaar en dat is precies de gebeurtenis die je
  wilt kunnen tellen. Op voertuigniveau verlies je die.
- **Waarom SCD2 op gemeente.** Nederland herindeelt gemiddeld elk jaar wel iets. Zonder
  type 2 verschuiven historische cijfers met terugwerkende kracht — een klassieke
  stille fout in stuurinformatie.
- **Waarom incrementeel.** De RDW-voertuigenset is te groot voor een volledige refresh
  per run. Incrementeel laden met een watermerk op wijzigingsdatum, met een
  gedocumenteerde `--full-refresh`-route voor als de brondefinitie verandert.
- **Waarom DuckDB.** Nul kosten, draait in CI, één bestand om te reviewen. De
  warehouse-keuze is geen onderdeel van de modellering — dat is juist het punt.
- **Waarom geen dashboardtool met een server.** Een statische Evidence-pagina is
  klikbaar vanaf GitHub zonder dat iemand iets hoeft te installeren.

## Kwaliteit en CI

Bij elke pull request draait GitHub Actions:

| Stap | Wat |
| --- | --- |
| lint | `ruff` (Python) en `sqlfluff` (dbt SQL) |
| build | `dbt build` tegen DuckDB — modellen én tests |
| docs | `dbt docs generate`, resultaat als artifact |

dbt-tests: `unique` en `not_null` op elke sleutel, `relationships` van elke
foreign key naar de dimensie, `accepted_values` op de referentiekolommen, plus
eigen tests op de korrel (geen dubbele rijen per korreldefinitie).

## Definition of done

- [ ] Repo met ingestie + dbt-project, end-to-end draaibaar met één `make`-commando
- [ ] ≥ 2 feittabellen en ≥ 4 dimensies, korrel gedocumenteerd per feittabel
- [ ] dbt-tests groen in GitHub Actions bij elke PR
- [ ] README met architectuurdiagram, lineage-screenshot en ontwerpkeuzes
- [ ] Evidence- of Streamlit-pagina over de marts (optioneel)
- [ ] Getagde release v1.0

## Wat dit project laat zien

SQL en dimensioneel modelleren (Kimball) · ELT-pipelines met dbt · incrementele
ingestie in Python · datakwaliteitstests · CI/CD en een PR-workflow · een
warehouse-opzet die overzet naar een cloud data platform.

## Bronnen en licentie

RDW- en CBS-data zijn open data; zie de voorwaarden van de betreffende bron. De code in
deze repo staat onder [LICENSE](LICENSE). Data wordt niet meegeleverd in git —
`make ingest` haalt een verse snapshot op.
