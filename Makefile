.DEFAULT_GOAL := help

PYTHON      := .venv/bin/python
PIP         := .venv/bin/pip
DBT         := .venv/bin/dbt
RUFF        := .venv/bin/ruff
SQLFLUFF    := .venv/bin/sqlfluff
SAMPLE_SIZE ?= 500000

# Aantal kentekens in de CI-fixtures. 5000 komt uit op ~1,7 MB in git.
FIXTURE_KENTEKENS ?= 5000

.PHONY: all help install ingest ingest-rdw ingest-cbs fixtures lint build docs ci clean exports

help:  ## Toon de beschikbare targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

# .DEFAULT_GOAL blijft help: een kale `make` die ongevraagd een half uur gaat
# ingesten is onvriendelijker dan een die de targets toont.
all: install  ## Hele keten: install -> ingest (alleen bij lege data/raw/) -> build
	@test -f data/raw/_manifest.json || $(MAKE) ingest
	$(MAKE) build

install:  ## Maak de virtualenv en installeer de dependencies
	python3 -m venv .venv
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt -r requirements-dev.txt
	$(DBT) deps

ingest: ingest-rdw ingest-cbs  ## Haal een volledige snapshot op naar data/raw/

ingest-rdw:  ## RDW-datasets (SAMPLE_SIZE bepaalt het kentekenbereik)
	$(PYTHON) ingest/rdw.py --sample-size $(SAMPLE_SIZE)

ingest-cbs:  ## CBS-datasets (klein; ~1 minuut)
	$(PYTHON) ingest/cbs.py

fixtures:  ## Ververs de CI-fixtures in tests/fixtures/ uit data/raw/
	$(PYTHON) scripts/make_fixtures.py --aantal $(FIXTURE_KENTEKENS)

lint:  ## ruff op de Python, sqlfluff op de modellen
	$(RUFF) check .
	$(SQLFLUFF) lint models

build:  ## dbt build op data/raw: modellen en tests
	$(DBT) build

docs:  ## dbt docs genereren en serveren
	$(DBT) docs generate
	$(DBT) docs serve

exports:  ## Warehouse-tabellen naar exports/ als parquet (voor Power BI)
	$(PYTHON) scripts/export_warehouse.py

# Zelfde commando's als .github/workflows/ci.yml, zodat CI niets kan wat jij niet kunt.
ci: lint  ## Precies wat GitHub Actions doet, maar lokaal (op de fixtures)
	DBT_RAW_DIR=tests/fixtures $(DBT) build --target ci

clean:  ## Verwijder de opgehaalde parquet-bestanden (manifest blijft staan)
	rm -f data/raw/*.parquet
