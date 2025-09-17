
# Use official dbt Postgres image
FROM ghcr.io/dbt-labs/dbt-postgres:1.7.8
RUN pip install --no-cache-dir "protobuf==3.20.*" \
 && apt-get update && apt-get install -y --no-install-recommends vim less jq \
 && rm -rf /var/lib/apt/lists/*


# Optional: add common CLI tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim less jq && rm -rf /var/lib/apt/lists/*
