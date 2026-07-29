"""Gedeelde bouwstenen voor de ingestie: HTTP met retries en parquet wegschrijven.

Alles wordt als string weggeschreven. De bron levert JSON zonder betrouwbare
typering en laat lege velden weg; typeren en hernoemen gebeurt in dbt `staging/`,
zodat `data/raw/` een letterlijke kopie van de bron blijft.
"""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path
from typing import Iterable, Iterator, Sequence

import pyarrow as pa
import pyarrow.parquet as pq
import requests

ROOT = Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "data" / "raw"

USER_AGENT = "nl-open-data-warehouse/0.1 (ingestie; open data)"
MAX_RETRIES = 5
BACKOFF_BASE = 2.0


def log(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def make_session() -> requests.Session:
    session = requests.Session()
    session.headers.update({"User-Agent": USER_AGENT, "Accept": "application/json"})
    return session


def get_json(session: requests.Session, url: str, params: dict | None = None,
             timeout: int = 180) -> object:
    """GET met exponentiële backoff op netwerkfouten en 5xx/429."""
    last_error: Exception | None = None
    for attempt in range(MAX_RETRIES):
        if attempt:
            delay = BACKOFF_BASE ** attempt
            log(f"    retry {attempt}/{MAX_RETRIES - 1} over {delay:.0f}s ({last_error})")
            time.sleep(delay)
        try:
            response = session.get(url, params=params, timeout=timeout)
            if response.status_code in (429, 500, 502, 503, 504):
                last_error = RuntimeError(f"HTTP {response.status_code}")
                continue
            response.raise_for_status()
            return response.json()
        except (requests.RequestException, ValueError) as exc:
            last_error = exc
    raise RuntimeError(f"opgegeven na {MAX_RETRIES} pogingen: {url} ({last_error})")


def normalise(row: dict, columns: Sequence[str]) -> dict:
    """Rij naar een vaste kolomvolgorde met strings; ontbrekende velden worden None.

    Nodig omdat de bron lege velden weglaat: zonder dit verschilt het schema per
    pagina en klapt het samenvoegen om.
    """
    out = {}
    for col in columns:
        value = row.get(col)
        if value is None:
            out[col] = None
        elif isinstance(value, str):
            out[col] = value
        elif isinstance(value, (dict, list)):
            out[col] = json.dumps(value, ensure_ascii=False)
        else:
            out[col] = str(value)
    return out


def write_parquet(path: Path, rows: Iterable[dict], columns: Sequence[str],
                  batch_size: int = 50_000) -> int:
    """Schrijf rijen batchgewijs weg, zodat een grote set niet volledig in geheugen hoeft."""
    path.parent.mkdir(parents=True, exist_ok=True)
    schema = pa.schema([(col, pa.string()) for col in columns])
    writer: pq.ParquetWriter | None = None
    buffer: list[dict] = []
    total = 0

    def flush() -> None:
        nonlocal writer, buffer
        if not buffer:
            return
        table = pa.Table.from_pylist([normalise(r, columns) for r in buffer], schema=schema)
        if writer is None:
            writer = pq.ParquetWriter(path, schema, compression="zstd")
        writer.write_table(table)
        buffer = []

    try:
        for row in rows:
            buffer.append(row)
            total += 1
            if len(buffer) >= batch_size:
                flush()
        flush()
        if writer is None:
            # Lege bron: toch een bestand met het juiste schema wegschrijven,
            # anders faalt dbt op een ontbrekende source.
            writer = pq.ParquetWriter(path, schema, compression="zstd")
            writer.write_table(pa.Table.from_pylist([], schema=schema))
    finally:
        if writer is not None:
            writer.close()
    return total


def update_manifest(entry: dict) -> None:
    """Leg per dataset de snapshotdatum, selectiequery en rijaantal vast."""
    manifest_path = RAW_DIR / "_manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    else:
        manifest = {"datasets": []}
    manifest["datasets"] = [d for d in manifest["datasets"] if d["bestand"] != entry["bestand"]]
    manifest["datasets"].append(entry)
    manifest["datasets"].sort(key=lambda d: d["bestand"])
    manifest_path.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )


def snapshot_date() -> str:
    return time.strftime("%Y-%m-%d")


def paginate(fetch_page, page_size: int, limit: int | None = None) -> Iterator[dict]:
    """Loop offset-gebaseerd door een bron tot die leeg is of `limit` bereikt is."""
    offset = 0
    yielded = 0
    while True:
        want = page_size if limit is None else min(page_size, limit - yielded)
        if want <= 0:
            return
        page = fetch_page(offset, want)
        if not page:
            return
        for row in page:
            yield row
            yielded += 1
        offset += len(page)
        log(f"    {yielded:,} rijen")
        if len(page) < want:
            return
