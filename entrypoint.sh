#!/bin/sh
set -e

echo '=== Checking elt directory ==='
ls -la elt || true
export OM_TOKEN=$(grep '^OPENMETADATA_JWT_TOKEN=' .env | cut -d '=' -f2-)

python elt/pg_load_dera.py --zips-dir dera_zips --mode replace

curl -sS -X POST "http://openmetadata-server:8585/api/v1/services/databaseServices" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENMETADATA_JWT_TOKEN" \
  -d '{
    "name": "'"$DB_SERVICE_NAME"'",
    "serviceType": "Postgres",
    "connection": {
      "config": {
        "type": "Postgres",
        "username": "'"$PGUSER"'",
        "authType": { "password": "'"$PGPASSWORD"'" },
        "hostPort": "'"$PGHOST:$PGPORT"'",
        "database": "'"$PGDATABASE"'"
      }
    }
  }'



python upsert_glossary_terms.py glossary.json

cd ./dbt/dera_dbt
dbt seed --profiles-dir ./.dbt && dbt run --profiles-dir ./.dbt --threads 2 &&  dbt compile --profiles-dir ./.dbt &&  dbt docs generate --profiles-dir ./.dbt 

metadata ingest -c postgres_ingestion.yml

metadata ingest-dbt

python ../../update_display_names_from_dbt.py \
  --host "http://openmetadata-server:8585/api" \
  --service "dera-postgres" \
  --manifest "./target/manifest.json"
