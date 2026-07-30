"""Ingestie van CBS StatLine (odata v1) naar data/raw/*.parquet.

Wat wordt opgehaald
-------------------
1. 70072ned  Regionale kerncijfers Nederland -> motorvoertuigenpark per gemeente per
             peiljaar. Dit is de enige lopende CBS-tabel met voertuigaantallen op
             gemeenteniveau; de tabellen "Motorvoertuigenpark" zelf gaan niet lager
             dan provincie. Alleen de voertuig- en bevolkingsmaten worden gefilterd,
             anders zijn het 7,5 miljoen observaties waarvan het merendeel niet
             over voertuigen gaat.
2. 85237NED  Personenauto's actief; voertuigkenmerken, regio's -> de brandstofsplitsing.
             Let op: die splitsing bestaat bij CBS alleen op provincieniveau, niet per
             gemeente. Zie data/raw/_manifest.json.
3. Gebieden in Nederland, één tabel per jaar -> bron voor de SCD2-gemeentedimensie.
             Elk jaar is een aparte tabel; het verschil tussen twee jaren is precies
             de herindeling die SCD2 moet vastleggen.

CBS levert observaties in lang formaat (één rij per meting). Dat blijft zo in
`data/raw/`; het pivotten naar bruikbare kolommen hoort in dbt `staging/`. De
bijbehorende code-tabellen worden meegeleverd, anders is een observatie niet te duiden.
"""

from __future__ import annotations

import argparse

from common import (
    RAW_DIR,
    get_json,
    log,
    make_session,
    snapshot_date,
    update_manifest,
    write_parquet,
)

BASE = "https://datasets.cbs.nl/odata/v1/CBS"

KERNCIJFERS = "70072ned"
PERSONENAUTOS = "85237NED"

# Titelfragmenten waarop de maten van 70072ned worden geselecteerd. Op titel en niet
# op code, omdat CBS codes hernummert tussen tabelversies maar de titels stabiel houdt.
KERNCIJFER_MATEN = (
    "personenauto",
    "bedrijfsmotorvoertuig",
    "motorfiets",
    "bromfietskenteken",
    "totale bevolking",
)

# Gebieden in Nederland: één tabel per jaar. Dit venster dekt onder meer de
# herindelingen van 2015, 2018, 2019, 2021, 2022, 2023 en 2025.
GEBIEDEN = {
    2015: "82949NED", 2016: "83287NED", 2017: "83553NED", 2018: "83859NED",
    2019: "84378NED", 2020: "84721NED", 2021: "84929NED", 2022: "85067NED",
    2023: "85385NED", 2024: "85755NED", 2025: "86059NED", 2026: "86247NED",
}


def fetch_all(session, url: str, params: dict | None = None):
    """Loop door een odata-collectie heen via @odata.nextLink."""
    total = 0
    while url:
        payload = get_json(session, url, params)
        params = None  # nextLink bevat de parameters al
        rows = payload.get("value", [])
        yield from rows
        total += len(rows)
        if total:
            log(f"    {total:,} rijen")
        url = payload.get("@odata.nextLink")


def dimensions_of(session, dataset: str) -> list[str]:
    payload = get_json(session, f"{BASE}/{dataset}/Dimensions")
    return [d["Identifier"] for d in payload["value"]]


def observation_columns(session, dataset: str) -> list[str]:
    """Vaste kolomvolgorde voor observaties: de meetvelden plus elke dimensie."""
    return ["Id", "Measure", "ValueAttribute", "Value", "StringValue"] + dimensions_of(
        session, dataset
    )


def dump_codes(session, dataset: str, endpoint: str, bestand: str, datum: str,
               omschrijving: str) -> None:
    """Schrijf een code-tabel (MeasureCodes, RegioSCodes, ...) weg als lookup."""
    rows = list(fetch_all(session, f"{BASE}/{dataset}/{endpoint}"))
    if not rows:
        log(f"  {endpoint}: leeg, overgeslagen")
        return
    columns = sorted({k for r in rows for k in r})
    path = RAW_DIR / bestand
    geschreven = write_parquet(path, rows, columns)
    log(f"  {endpoint}: {geschreven:,} rijen -> {bestand}")
    update_manifest(
        {
            "bestand": bestand,
            "bron": "CBS StatLine",
            "omschrijving": omschrijving,
            "dataset_id": dataset,
            "url": f"{BASE}/{dataset}/{endpoint}",
            "snapshotdatum": datum,
            "selectiequery": {"$filter": None},
            "rijen": geschreven,
            "kolommen": len(columns),
        }
    )


def ingest_kerncijfers(session, datum: str) -> None:
    """70072ned: voertuigaantallen per gemeente per peiljaar."""
    log(f"CBS {KERNCIJFERS}: maten selecteren")
    alle_maten = get_json(session, f"{BASE}/{KERNCIJFERS}/MeasureCodes")["value"]
    gekozen = [
        m for m in alle_maten
        if any(frag in (m.get("Title") or "").lower() for frag in KERNCIJFER_MATEN)
    ]
    if not gekozen:
        raise RuntimeError("geen maten gevonden in 70072ned — is de tabel gewijzigd?")
    for m in gekozen:
        log(f"  {m['Identifier']:<12} {m['Title']}")

    measure_filter = " or ".join(f"Measure eq '{m['Identifier']}'" for m in gekozen)
    # Gemeenten voor de gemeentegrain, provincie en NL als controletotaal.
    regio_filter = "(startswith(RegioS,'GM') or startswith(RegioS,'PV') or RegioS eq 'NL01')"
    odata_filter = f"({measure_filter}) and {regio_filter}"

    columns = observation_columns(session, KERNCIJFERS)
    bestand = "cbs_70072ned_motorvoertuigen_gemeente.parquet"
    log(f"CBS {KERNCIJFERS}: observaties ophalen -> {bestand}")
    rows = fetch_all(
        session, f"{BASE}/{KERNCIJFERS}/Observations", {"$filter": odata_filter}
    )
    path = RAW_DIR / bestand
    geschreven = write_parquet(path, rows, columns)
    log(f"  klaar: {geschreven:,} rijen, {path.stat().st_size / 1e6:.1f} MB")

    update_manifest(
        {
            "bestand": bestand,
            "bron": "CBS StatLine",
            "omschrijving": "Regionale kerncijfers: motorvoertuigenpark per gemeente per peiljaar",
            "dataset_id": KERNCIJFERS,
            "url": f"{BASE}/{KERNCIJFERS}/Observations",
            "snapshotdatum": datum,
            "selectiequery": {"$filter": odata_filter},
            "rijen": geschreven,
            "kolommen": len(columns),
            "grain": "regio x peiljaar x maat (lang formaat)",
        }
    )

    for endpoint, suffix, oms in (
        ("MeasureCodes", "measurecodes", "maatcodes bij 70072ned"),
        ("RegioSCodes", "regiocodes", "regiocodes bij 70072ned"),
        ("PeriodenCodes", "periodencodes", "periodecodes bij 70072ned"),
    ):
        dump_codes(session, KERNCIJFERS, endpoint,
                   f"cbs_70072ned_{suffix}.parquet", datum, oms)


def ingest_personenautos(session, datum: str) -> None:
    """85237NED: personenauto's naar brandstof — provincieniveau."""
    bestand = "cbs_85237ned_personenautos_brandstof.parquet"
    log(f"CBS {PERSONENAUTOS}: observaties ophalen -> {bestand}")
    columns = observation_columns(session, PERSONENAUTOS)
    rows = fetch_all(session, f"{BASE}/{PERSONENAUTOS}/Observations")
    path = RAW_DIR / bestand
    geschreven = write_parquet(path, rows, columns)
    log(f"  klaar: {geschreven:,} rijen, {path.stat().st_size / 1e6:.1f} MB")

    update_manifest(
        {
            "bestand": bestand,
            "bron": "CBS StatLine",
            "omschrijving": "Personenauto's actief naar brandstof en bouwjaar (regio = provincie)",
            "dataset_id": PERSONENAUTOS,
            "url": f"{BASE}/{PERSONENAUTOS}/Observations",
            "snapshotdatum": datum,
            "selectiequery": {"$filter": None},
            "rijen": geschreven,
            "kolommen": len(columns),
            "let_op": "brandstofsplitsing is bij CBS alleen beschikbaar tot provincieniveau",
        }
    )
    dump_codes(session, PERSONENAUTOS, "MeasureCodes",
               "cbs_85237ned_measurecodes.parquet", datum,
               "maatcodes bij 85237NED (bevat zowel regio als brandstof)")


def ingest_gebieden(session, datum: str, jaren: list[int]) -> None:
    """Gebieden in Nederland per jaar — voedt de SCD2-gemeentedimensie."""
    for jaar in jaren:
        dataset = GEBIEDEN[jaar]
        bestand = f"cbs_gebieden_{jaar}.parquet"
        log(f"CBS {dataset} (Gebieden {jaar}) -> {bestand}")
        columns = observation_columns(session, dataset)
        rows = fetch_all(session, f"{BASE}/{dataset}/Observations")
        path = RAW_DIR / bestand
        geschreven = write_parquet(path, rows, columns)
        log(f"  klaar: {geschreven:,} rijen")

        update_manifest(
            {
                "bestand": bestand,
                "bron": "CBS StatLine",
                "omschrijving": f"Gebieden in Nederland {jaar} (gemeentelijke indeling)",
                "dataset_id": dataset,
                "url": f"{BASE}/{dataset}/Observations",
                "snapshotdatum": datum,
                "peiljaar": jaar,
                "selectiequery": {"$filter": None},
                "rijen": geschreven,
                "kolommen": len(columns),
            }
        )

    # Eén codetabel volstaat om de Measure-kolom in alle jaren te duiden.
    laatste = GEBIEDEN[max(jaren)]
    dump_codes(session, laatste, "MeasureCodes",
               "cbs_gebieden_measurecodes.parquet", datum,
               f"maatcodes bij Gebieden in Nederland ({max(jaren)})")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vanaf", type=int, default=min(GEBIEDEN),
                        help="eerste peiljaar voor Gebieden in Nederland")
    parser.add_argument("--tot", type=int, default=max(GEBIEDEN),
                        help="laatste peiljaar voor Gebieden in Nederland")
    args = parser.parse_args()

    jaren = [j for j in sorted(GEBIEDEN) if args.vanaf <= j <= args.tot]
    if not jaren:
        raise SystemExit(f"geen peiljaren in bereik {args.vanaf}-{args.tot}")

    session = make_session()
    datum = snapshot_date()
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    ingest_kerncijfers(session, datum)
    ingest_personenautos(session, datum)
    ingest_gebieden(session, datum, jaren)


if __name__ == "__main__":
    main()
