# De data

Wat `make ingest` ophaalt, hoe de selectie tot stand komt en waarom.

De data zelf staat **niet** in deze repository. `data/raw/` is genegeerd door git; alleen
[`data/raw/_manifest.json`](../data/raw/_manifest.json) is meegecommit, zodat zichtbaar
blijft welke snapshot, selectiequery en rijaantallen bij een run hoorden.

## Bronnen

Beide bronnen zijn zonder API-sleutel te bevragen.

| Bron | API | Datasets |
| --- | --- | --- |
| [RDW open data](https://opendata.rdw.nl) | Socrata | `m9d7-ebf2`, `8ys7-d773`, `a34c-vvps`, `hx2c-gt7k` |
| [CBS StatLine](https://opendata.cbs.nl) | odata v1 | `70072ned`, `85237NED`, `Gebieden in Nederland` 2015–2026 |

## Wat er wordt opgehaald

Standaardrun: **2.807.740 rijen** over 23 bestanden, ~47 MB parquet (zstd).

### RDW

| Bestand | Rijen | Grain |
| --- | ---: | --- |
| `rdw_gekentekende_voertuigen.parquet` | 500.000 | één rij per kenteken (98 kolommen) |
| `rdw_geconstateerde_gebreken.parquet` | 1.333.714 | één rij per geconstateerd gebrek per keuring |
| `rdw_brandstof.parquet` | 443.167 | één rij per kenteken per brandstofvolgnummer |
| `rdw_gebreken.parquet` | 1.006 | één rij per gebrekcode (volledige referentielijst) |

### CBS

| Bestand | Rijen | Grain |
| --- | ---: | --- |
| `cbs_70072ned_motorvoertuigen_gemeente.parquet` | 213.101 | regio × peiljaar × maat (lang formaat) |
| `cbs_85237ned_personenautos_brandstof.parquet` | 80.592 | bouwjaar × periode × maat (lang formaat) |
| `cbs_gebieden_2015…2026.parquet` | 12 × ~19.000 | regio × maat, één bestand per peiljaar |
| `cbs_*_measurecodes` / `regiocodes` / `periodencodes` | 5 bestanden | lookups |

CBS levert observaties in lang formaat: één rij per meting, met codes in plaats van
labels. Dat blijft zo in `data/raw/` — pivotten en labelen hoort in dbt `staging/`.
Zonder de meegeleverde code-tabellen is een observatie niet te duiden.

## De steekproefopzet

De drie grote RDW-sets zijn samen ~58 miljoen rijen. De standaardrun neemt daar een
begrensde snapshot uit. **Hoe** die snapshot wordt genomen is de belangrijkste keuze in
de ingestie.

De sets zijn allemaal op `kenteken` gesleuteld. Drie losse steekproeven — de eerste
500k van elke set — zouden drie verschillende voertuigpopulaties opleveren: de
gebrekenset heeft meerdere rijen per voertuig en zou dus een veel smaller kentekenbereik
beslaan dan de voertuigenset. Feiten zouden dan naar dimensierijen wijzen die niet in de
snapshot zitten, en geen enkele `relationships`-test zou standhouden.

In plaats daarvan wordt één bereik bepaald op de voertuigenset, en worden de andere
sets op datzélfde bereik opgehaald:

```
$order=kenteken, positie 0 en positie 499.999   ->  0001TJ .. 10ZFXT
$where=kenteken >= '0001TJ' AND kenteken <= '10ZFXT'
```

Het bereik is deterministisch (sortering op kenteken), dus de run is reproduceerbaar
zolang de bron niet wijzigt. Het gekozen bereik wordt vastgelegd in `_manifest.json`.

Resultaat: één voertuigpopulatie, met de bijbehorende brandstof- en gebrekrijen.

## Verificatie van de standaardrun

| Controle | Uitkomst |
| --- | --- |
| Brandstofrijen met bestaand voertuig | 430.496 / 430.496 — **0 weesrijen** |
| Gebrekrijen met bestaand voertuig | 303.532 / 303.532 — **0 weesrijen** |
| Gebruikte gebrekcodes in de codelijst | 622 / 622 |
| Voertuigen uniek op `kenteken` | 500.000 / 500.000 |
| Brandstof uniek op `kenteken` + `volgnummer` | 443.167 / 443.167 |
| Gebreken uniek op natuurlijke sleutel | 1.333.713 / 1.333.714 — **1 dubbeling** |

Die ene dubbeling is identiek op alle acht kolommen en zit in de bron. Precies waar de
dedup-stap in `staging/` voor bedoeld is; niet in de ingestie oplossen, want `data/raw/`
hoort een letterlijke kopie van de bron te zijn.

## Bekende beperking: brandstof per gemeente bestaat niet bij CBS

De README beschrijft `fct_voertuigpark_gemeente` met de grain *gemeente per peiljaar
per brandstofsoort*. Die grain is bij CBS niet te maken:

- De tabellen **Motorvoertuigenpark** (`85235NED`, `7374hvv`) gaan niet lager dan
  provincie — ze bevatten geen enkele gemeentecode.
- **`70072ned`** (Regionale kerncijfers) heeft wél 728 gemeenten over 1995–2026, maar
  splitst voertuigen naar *soort* (personenauto, bedrijfsmotorvoertuig, motorfiets),
  niet naar brandstof.
- **`85237NED`** heeft wél de brandstofsplitsing (benzine, diesel, LPG, elektriciteit,
  CNG), maar alleen tot provincieniveau.

Beide zijn opgehaald, zodat de keuze open ligt: gemeente × voertuigsoort, óf
provincie × brandstof. Gemeente × brandstof kan niet zonder cijfers te verzinnen.

## De gemeentedimensie

`Gebieden in Nederland` is één tabel per jaar. Het verschil tussen twee opeenvolgende
jaren ís de herindeling die een SCD type 2-dimensie moet vastleggen:

| Peiljaar | Gemeenten | Mutatie |
| ---: | ---: | --- |
| 2015 | 393 | |
| 2016 | 390 | +3 / −6 |
| 2017 | 388 | +1 / −3 |
| 2018 | 380 | +3 / −11 |
| 2019 | 355 | +9 / −34 |
| 2021 | 352 | +1 / −4 |
| 2022 | 345 | +3 / −10 |
| 2023 | 342 | +1 / −4 |
| 2026 | 342 | — |

## Draaien

```bash
make install     # virtualenv + dependencies
make ingest      # RDW + CBS naar data/raw/
```

Losse stappen: `make ingest-cbs` (~1 minuut) en `make ingest-rdw` (~30 minuten voor de
standaardrun; de gebrekenset is de traagste).

Opschalen gaat via één variabele:

```bash
make ingest-rdw SAMPLE_SIZE=2000000
```

`SAMPLE_SIZE` is het aantal voertuigen dat het kentekenbereik bepaalt; brandstof en
gebreken volgen dat bereik automatisch. Bij de volledige set (~16,8 miljoen) praat je
over ~11 GB.

## Ingestiemechaniek

Drie bestanden in `ingest/`:

- **`common.py`** — HTTP met exponentiële backoff (5 pogingen, retry op 429/5xx en
  netwerkfouten), batchgewijs wegschrijven naar parquet, en het manifest bijwerken.
- **`rdw.py`** — Socrata, offset-paginatie in pagina's van 50.000.
- **`cbs.py`** — odata, paginatie via `@odata.nextLink`.

Twee keuzes die het schema stabiel houden:

**Alle kolommen als string.** De bronnen leveren JSON zonder betrouwbare typering.
Typeren gebeurt in dbt `staging/`, zodat `data/raw/` een letterlijke kopie blijft en een
typefout niet stilletjes in de ingestie verdwijnt.

**Kolomlijst uit de datasetmetadata, niet uit de respons.** Socrata laat lege velden weg
uit de JSON. De voertuigenset lijkt daardoor 52 kolommen te hebben terwijl het er 98
zijn, en verschillende pagina's leveren verschillende sleutels op. De kolomlijst wordt
daarom vooraf uit `/api/views/{id}.json` gehaald en elke rij daarop genormaliseerd —
anders klapt het samenvoegen van batches om op schemaverschillen.
