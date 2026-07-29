.DEFAULT_GOAL := help

PYTHON      := .venv/bin/python
PIP         := .venv/bin/pip
SAMPLE_SIZE ?= 500000

.PHONY: help install ingest ingest-rdw ingest-cbs clean

help:  ## Toon de beschikbare targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

install:  ## Maak de virtualenv en installeer de dependencies
	python3 -m venv .venv
	$(PIP) install --upgrade pip
	$(PIP) install -r requirements.txt

ingest: ingest-rdw ingest-cbs  ## Haal een volledige snapshot op naar data/raw/

ingest-rdw:  ## RDW-datasets (SAMPLE_SIZE bepaalt het kentekenbereik)
	$(PYTHON) ingest/rdw.py --sample-size $(SAMPLE_SIZE)

ingest-cbs:  ## CBS-datasets (klein; ~1 minuut)
	$(PYTHON) ingest/cbs.py

clean:  ## Verwijder de opgehaalde parquet-bestanden (manifest blijft staan)
	rm -f data/raw/*.parquet
