"""Ingestie van RDW open data (Socrata) naar data/raw/*.parquet.

Steekproefopzet
---------------
De drie grote RDW-sets zijn allemaal op `kenteken` gesleuteld. Een losse steekproef
per set zou drie verschillende voertuigpopulaties opleveren en dan houdt geen enkele
`relationships`-test stand. Daarom wordt één kentekenbereik bepaald op de
voertuigenset, en worden brandstof en gebreken op datzelfde bereik opgehaald.

Het bereik is deterministisch (sortering op kenteken), dus de run is reproduceerbaar
zolang de bron niet wijzigt. Het bereik zelf komt in data/raw/_manifest.json te staan.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from common import (
    RAW_DIR,
    get_json,
    log,
    make_session,
    paginate,
    snapshot_date,
    update_manifest,
    write_parquet,
)

BASE = "https://opendata.rdw.nl"
PAGE_SIZE = 50_000

VOERTUIGEN = "m9d7-ebf2"
BRANDSTOF = "8ys7-d773"
GEBREKEN_GECONSTATEERD = "a34c-vvps"
GEBREKEN_CODES = "hx2c-gt7k"


def columns_of(session, dataset_id: str) -> list[str]:
    """Kolomnamen uit de datasetmetadata, zodat het parquet-schema vaststaat."""
    meta = get_json(session, f"{BASE}/api/views/{dataset_id}.json")
    return [c["fieldName"] for c in meta["columns"] if not c["fieldName"].startswith(":")]


def count(session, dataset_id: str, where: str | None = None) -> int:
    params = {"$select": "count(*)"}
    if where:
        params["$where"] = where
    result = get_json(session, f"{BASE}/resource/{dataset_id}.json", params)
    return int(result[0]["count"])


def fetch(session, dataset_id: str, order: str, where: str | None = None,
          limit: int | None = None):
    def page(offset: int, size: int):
        params = {"$order": order, "$offset": str(offset), "$limit": str(size)}
        if where:
            params["$where"] = where
        return get_json(session, f"{BASE}/resource/{dataset_id}.json", params)

    return paginate(page, PAGE_SIZE, limit)


def kenteken_at(session, offset: int) -> str:
    """Het kenteken op positie `offset` in de op kenteken gesorteerde voertuigenset."""
    rows = get_json(
        session,
        f"{BASE}/resource/{VOERTUIGEN}.json",
        {"$select": "kenteken", "$order": "kenteken", "$offset": str(offset), "$limit": "1"},
    )
    if not rows:
        raise RuntimeError(f"geen kenteken op offset {offset}")
    return rows[0]["kenteken"]


def ingest(sample_size: int) -> None:
    session = make_session()
    datum = snapshot_date()
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    log(f"RDW: kentekenbereik bepalen voor {sample_size:,} voertuigen")
    kenteken_min = kenteken_at(session, 0)
    kenteken_max = kenteken_at(session, sample_size - 1)
    where = f"kenteken >= '{kenteken_min}' AND kenteken <= '{kenteken_max}'"
    log(f"  bereik: {kenteken_min} .. {kenteken_max}")

    taken = [
        {
            "bestand": "rdw_gekentekende_voertuigen.parquet",
            "dataset_id": VOERTUIGEN,
            "omschrijving": "RDW gekentekende voertuigen",
            "order": "kenteken",
            "where": where,
        },
        {
            "bestand": "rdw_brandstof.parquet",
            "dataset_id": BRANDSTOF,
            "omschrijving": "RDW gekentekende voertuigen brandstof",
            "order": "kenteken,brandstof_volgnummer",
            "where": where,
        },
        {
            "bestand": "rdw_geconstateerde_gebreken.parquet",
            "dataset_id": GEBREKEN_GECONSTATEERD,
            "omschrijving": "RDW geconstateerde gebreken",
            "order": "kenteken,meld_datum_door_keuringsinstantie",
            "where": where,
        },
        {
            "bestand": "rdw_gebreken.parquet",
            "dataset_id": GEBREKEN_CODES,
            "omschrijving": "RDW gebrekcodes met omschrijving (volledige referentielijst)",
            "order": "gebrek_identificatie",
            "where": None,
        },
    ]

    for task in taken:
        path = RAW_DIR / task["bestand"]
        verwacht = count(session, task["dataset_id"], task["where"])
        log(f"RDW {task['dataset_id']}: {verwacht:,} rijen -> {task['bestand']}")
        cols = columns_of(session, task["dataset_id"])
        rows = fetch(session, task["dataset_id"], task["order"], task["where"])
        geschreven = write_parquet(path, rows, cols)
        log(f"  klaar: {geschreven:,} rijen, {path.stat().st_size / 1e6:.1f} MB")

        if geschreven != verwacht:
            log(f"  LET OP: {geschreven:,} geschreven vs {verwacht:,} verwacht")

        update_manifest(
            {
                "bestand": task["bestand"],
                "bron": "RDW open data",
                "omschrijving": task["omschrijving"],
                "dataset_id": task["dataset_id"],
                "url": f"{BASE}/resource/{task['dataset_id']}.json",
                "snapshotdatum": datum,
                "selectiequery": {
                    "$order": task["order"],
                    "$where": task["where"],
                },
                "rijen": geschreven,
                "rijen_in_bron_bij_selectie": verwacht,
                "kolommen": len(cols),
            }
        )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--sample-size",
        type=int,
        default=500_000,
        help="aantal voertuigen dat het kentekenbereik bepaalt (standaard 500000)",
    )
    args = parser.parse_args()
    ingest(args.sample_size)


if __name__ == "__main__":
    main()
