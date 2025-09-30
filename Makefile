SHELL := /bin/sh

# Paths & executables
PYTHON        := python3
VENV          := .venv
PIP           := $(VENV)/bin/pip
PYTHON_VENV   := $(VENV)/bin/python
DBT           := $(VENV)/bin/dbt

# Project settings
REQUIREMENTS  := requirements.txt
DBT_DIR       := ./dbt/dera_dbt
OM_API        := http://localhost:8585/api
ZIPS_DIR      := dera_zips
LOAD_MODE     := replace
DBT_DIR=$(CURDIR)/dbt/dera_dbt
DBT_BIN=$(CURDIR)/.venv/bin/dbt
METADATA := $(CURDIR)/.venv/bin/metadata

# Database settings
DB_SERVICE_NAME ?= dera-postgres
PGHOST ?= localhost
PGPORT ?= 5432
PGDATABASE ?= dera
PGUSER ?= dbt
PGPASSWORD ?= dbt

SHELL := /bin/bash
# Load .env if it exists
# Load .env if it exists
# Load .env
ifneq (,$(wildcard .env))
include .env
export
endif



.PHONY: help check-python venv install load-data register-om-service \
        upsert-glossary dbt-run ingest-postgres ingest-dbt update-display-names \
        all clean

help:
	@echo ""
	@echo "Targets:"
	@echo "  make check-python         - Verify system Python >= 3.10"
	@echo "  make venv                 - Create .venv (if missing)"
	@echo "  make install              - Install dependencies into .venv"
	@echo "  make load-data            - Load SEC DERA ZIPs into Postgres"
	@echo "  make register-om-service  - Register Postgres service in OpenMetadata"
	@echo "  make upsert-glossary      - Upsert glossary terms"
	@echo "  make dbt-run              - Run dbt pipeline"
	@echo "  make ingest-postgres      - Ingest Postgres metadata"
	@echo "  make ingest-dbt           - Ingest dbt metadata"
	@echo "  make update-display-names - Sync display names from dbt manifest"
	@echo "  make all                  - Run the full pipeline"
	@echo "  make clean                - Remove .venv"
	@echo ""

print-env:
	@echo "DB_SERVICE_NAME=$(DB_SERVICE_NAME)"
	@echo "PGUSER=$(PGUSER)"
	@echo "PGPASSWORD=$(PGPASSWORD)"
	@echo "PGHOST=$(PGHOST)"
	@echo "PGPORT=$(PGPORT)"
	@echo "PGDATABASE=$(PGDATABASE)"
	@echo "OPENMETADATA_URL=$(OPENMETADATA_HOST_PORT)"
	@echo "OPENMETADATA_JWT_TOKEN=$(OPENMETADATA_JWT_TOKEN)"


check-python:
	@PYTHON=$$(command -v python3.10 || command -v python3 || echo ""); \
	if [ -z "$$PYTHON" ]; then \
	  echo "❌ Python 3.10+ not found. Please install it (sudo apt install python3.10)"; \
	  exit 1; \
	fi; \
	VERSION=$$($$PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")'); \
	if [ $$(echo "$$VERSION >= 3.10" | bc -l) -eq 0 ]; then \
	  echo "❌ Python 3.10+ required, found $$VERSION"; \
	  exit 1; \
	fi; \
	echo "✔ Python $$VERSION found at $$PYTHON"

venv: check-python
	@if [ ! -d "$(VENV)" ]; then \
		echo "▶ Creating virtual environment..."; \
		$(PYTHON) -m venv $(VENV); \
	else \
		echo "✔ Virtual environment already exists"; \
	fi

install: venv
	@echo "▶ Installing dependencies into $(VENV)..."; \
	$(PIP) install --upgrade pip; \
	$(VENV)/bin/pip install dbt-postgres==1.9.1; \
	if [ -f "$(REQUIREMENTS)" ]; then \
		$(PIP) install -r $(REQUIREMENTS); \
	else \
		$(PIP) install psycopg2-binary; \
	fi; \
	$(PIP) install dbt-core dbt-postgres; \
	$(PIP) install "openmetadata-ingestion[postgres]==1.9.11" "openmetadata-ingestion[dbt]==1.9.11"

load-data: venv
	@echo "▶ Loading SEC DERA ZIPs from $(ZIPS_DIR) with mode $(LOAD_MODE)..."; \
	$(PYTHON_VENV) elt/pg_load_dera.py --zips-dir "$(ZIPS_DIR)" --mode "$(LOAD_MODE)"


register-om-service: venv
	@echo "▶ Registering Postgres service in OpenMetadata..."
	@curl -sS -X POST "$(OPENMETADATA_HOST_PORT)/v1/services/databaseServices" \
	  -H "Content-Type: application/json" \
	  -H "Authorization: Bearer $(OPENMETADATA_JWT_TOKEN)" \
	  -d '{"name":"$(DB_SERVICE_NAME)","serviceType":"Postgres","connection":{"config":{"type":"Postgres","username":"$(PGUSER)","authType":{"password":"$(PGPASSWORD)"},"hostPort":"$(PGHOST):$(PGPORT)","database":"$(PGDATABASE)"}}}'

upsert-glossary: venv
	$(PYTHON_VENV) upsert_glossary_terms.py glossary.json

dbt-run: venv
	@echo "▶ Running DBT inside virtual environment..."
	@cd $(DBT_DIR) && \
	$(DBT_BIN) seed --profiles-dir ./.dbt --threads 2 && \
	$(DBT_BIN) run --profiles-dir ./.dbt --threads 2 && \
	$(DBT_BIN) compile --profiles-dir ./.dbt && \
	$(DBT_BIN) docs generate --profiles-dir ./.dbt

ingest-postgres: venv
	@echo "▶ Ingesting Postgres metadata..."
	@$(VENV)/bin/metadata ingest -c ./dbt/dera_dbt/postgres_ingestion.yml

ingest-dbt: venv
	@echo "▶ Ingesting DBT metadata..."
	@cd ./dbt/dera_dbt && "$(METADATA)" ingest-dbt
	@echo "✔ dbt metadata ingestion done."

update-display-names: venv
	$(PYTHON_VENV) update_display_names_from_dbt.py \
		--host "$(OM_API)" \
		--service "$(DB_SERVICE_NAME)" \
		--manifest "$(DBT_DIR)/target/manifest.json"

all: load-data register-om-service upsert-glossary dbt-run ingest-postgres ingest-dbt update-display-names
	@echo "🎉 All steps completed successfully."

clean:
	rm -rf "$(VENV)"
	@echo "✔ Removed $(VENV)"
