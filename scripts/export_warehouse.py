"""Exporteer de warehouse-laag naar exports/ als parquet, voor Power BI.

Power BI heeft geen native DuckDB-connector; parquet leest hij wel. Dit script
exporteert de dimensies, de bridge en de feiten — niet de marts: het semantisch
model in Power BI hoort het sterschema te spiegelen (PRD F9), dus de joins en
measures gebeuren dáár.

exports/ staat in .gitignore: afgeleide data, net als data/raw/. Draai
`make build` vóór dit script, anders exporteer je een verouderd warehouse.
"""

from __future__ import annotations

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
DATABASE = ROOT / "dev.duckdb"
EXPORTS = ROOT / "exports"

TABELLEN = [
    "dim_datum",
    "dim_brandstof",
    "dim_gebrek",
    "dim_voertuig",
    "dim_gemeente",
    "bridge_voertuig_brandstof",
    "fct_gebrek_constatering",
    "fct_voertuigpark_gemeente",
]


def main() -> None:
    if not DATABASE.exists():
        raise SystemExit("dev.duckdb ontbreekt — draai eerst `make build`")
    EXPORTS.mkdir(exist_ok=True)

    # read_only: exporteren mag niet botsen met (of wachten op) een lopende build.
    con = duckdb.connect(str(DATABASE), read_only=True)
    for tabel in TABELLEN:
        doel = (EXPORTS / f"{tabel}.parquet").as_posix()
        con.execute(f"copy (select * from main.{tabel}) to '{doel}' (format parquet)")
        rijen = con.execute(f"select count(*) from main.{tabel}").fetchone()[0]
        print(f"{tabel:28s} {rijen:9d} rijen -> {doel}")


if __name__ == "__main__":
    main()
