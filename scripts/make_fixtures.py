"""Fixtures voor CI: een kleine, referentieel kloppende kopie van data/raw/.

CI mag niet van het netwerk afhangen, en data/raw/ staat niet in git. Dit script
schrijft een steekproef naar tests/fixtures/ met exact dezelfde bestandsnamen en
hetzelfde schema — alle kolommen VARCHAR, niets hernoemd, niets weggelaten. Daardoor
werkt `DBT_RAW_DIR=tests/fixtures dbt build` zonder dat er één model verandert.

Steekproefopzet
---------------
Dezelfde truc als de ingestie: eerst N kentekens kiezen, dan de andere RDW-bestanden op
datzelfde bereik filteren. Per bestand willekeurig samplen zou drie verschillende
voertuigpopulaties opleveren en elke relationships-test slopen.

Wat bewust NIET gefilterd wordt
-------------------------------
* Referentielijsten (rdw_gebreken, de CBS-codelijsten) gaan integraal mee. Het zijn
  hooguit een paar duizend rijen en een subset levert alleen valse relationships-fouten.
* De CBS-gebiedsbestanden worden niet op `Measure` gefilterd. De measurecode voor de
  gemeentecode heet niet in elk peiljaar hetzelfde (zie de valkuil in commit 4), dus een
  filter op codes gooit stilletjes hele peiljaren weg.
* Kolommen worden nooit weggelaten. Staging selecteert kolommen bij naam; een
  ontbrekende kolom is in CI een compileerfout die lokaal niet bestaat.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "data" / "raw"
FIXTURES = ROOT / "tests" / "fixtures"

# Deze rij is op alle acht kolommen dubbel en is de enige in de hele bron. Hij staat op
# positie 73.926 in de op kenteken gesorteerde set en valt dus buiten elke redelijke
# prefix. Zonder hem test CI de dedup uit commit 2 niet: je kunt de `qualify` weghalen
# en de build blijft groen. Daarom expliciet erbij.
EXTRA_KENTEKENS = ["02BND8"]

# cbs_gebieden begint bij 2015, dus eerdere peiljaren hebben geen gemeentedimensie om
# aan te hangen. Zie commit 10: 70072ned gaat terug tot 1995.
EERSTE_PEILJAAR = 2015

# Integraal mee, zonder filter.
VERBATIM = [
    "rdw_gebreken.parquet",
    "cbs_70072ned_measurecodes.parquet",
    "cbs_70072ned_regiocodes.parquet",
    "cbs_70072ned_periodencodes.parquet",
    "cbs_gebieden_measurecodes.parquet",
    "cbs_85237ned_measurecodes.parquet",
    "cbs_85237ned_personenautos_brandstof.parquet",
]


def bron(naam: str) -> str:
    return f"read_parquet('{(RAW / naam).as_posix()}')"


def schrijf(con: duckdb.DuckDBPyConnection, naam: str, select: str) -> int:
    """Schrijf één fixture weg en geef het aantal rijen terug."""
    doel = (FIXTURES / naam).as_posix()
    con.execute(f"copy ({select}) to '{doel}' (format parquet, compression zstd)")
    return con.execute(f"select count(*) from read_parquet('{doel}')").fetchone()[0]


def maak_fixtures(aantal: int) -> dict:
    if not RAW.exists():
        raise SystemExit("data/raw/ is leeg — draai eerst `make ingest`")
    FIXTURES.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect()  # in-memory; er komt geen databasebestand aan te pas

    extra = ", ".join(f"('{k}')" for k in EXTRA_KENTEKENS)
    con.execute(
        f"""
        create table kentekens as
        select kenteken from (
            select kenteken from {bron('rdw_gekentekende_voertuigen.parquet')}
            order by kenteken
            limit {aantal}
        )
        union
        select kenteken from (values {extra}) as t(kenteken)
        """
    )
    grens = con.execute("select max(kenteken) from kentekens").fetchone()[0]
    rijen: dict[str, int] = {}

    for naam in (
        "rdw_gekentekende_voertuigen.parquet",
        "rdw_brandstof.parquet",
        "rdw_geconstateerde_gebreken.parquet",
    ):
        rijen[naam] = schrijf(
            con,
            naam,
            f"select * from {bron(naam)} where kenteken in (select kenteken from kentekens)",
        )

    # 70072ned: filteren op entiteit en periode, niet op maat. Gemeenten (GM…) omdat het
    # model daarop staat, vanaf 2015 omdat dim_gemeente niet verder terugkijkt.
    naam = "cbs_70072ned_motorvoertuigen_gemeente.parquet"
    rijen[naam] = schrijf(
        con,
        naam,
        f"""
        select * from {bron(naam)}
        where RegioS like 'GM%'
          and cast(left(Perioden, 4) as int) >= {EERSTE_PEILJAAR}
        """,
    )

    for pad in sorted(RAW.glob("cbs_gebieden_[0-9][0-9][0-9][0-9].parquet")):
        rijen[pad.name] = schrijf(con, pad.name, f"select * from {bron(pad.name)}")

    for naam in VERBATIM:
        rijen[naam] = schrijf(con, naam, f"select * from {bron(naam)}")

    manifest = json.loads((RAW / "_manifest.json").read_text(encoding="utf-8"))
    snapshots = sorted({d["snapshotdatum"] for d in manifest["datasets"]})
    return {
        "aantal_kentekens": aantal,
        "extra_kentekens": EXTRA_KENTEKENS,
        "kenteken_grens": grens,
        "eerste_peiljaar": EERSTE_PEILJAAR,
        "snapshotdatum_bron": snapshots,
        "rijen": dict(sorted(rijen.items())),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--aantal",
        type=int,
        default=5_000,
        help="aantal kentekens in de fixture (standaard 5000, ~1,6 MB totaal)",
    )
    args = parser.parse_args()

    verslag = maak_fixtures(args.aantal)
    (FIXTURES / "_fixtures.json").write_text(
        json.dumps(verslag, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    for naam, n in verslag["rijen"].items():
        print(f"{naam:48s} {n:8d} rijen")


if __name__ == "__main__":
    main()