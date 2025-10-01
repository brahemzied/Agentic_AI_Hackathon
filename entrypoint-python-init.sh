#!/bin/bash
set -e

echo "🐍 Starting Python Init Container..."

# Download large data files from Azure Blob Storage
echo "📦 Downloading data files from Azure Blob Storage..."

# Create directories if they don't exist
mkdir -p /workspace/dera_zips
mkdir -p /workspace/dbt/dera_dbt/seeds

# Download dera_zips/2024q4.zip (118 MB - too large for Git)
if [ -n "$DERA_ZIPS_URL" ]; then
  echo "  Downloading 2024q4.zip..."
  curl -L -o /workspace/dera_zips/2024q4.zip "$DERA_ZIPS_URL" || echo "  ⚠️  Warning: Failed to download 2024q4.zip"
fi

# Download dbt seeds if they are in blob storage
if [ -n "$DBT_SEEDS_URL" ]; then
  echo "  Downloading dbt seeds..."
  # Download each seed file (if they were uploaded to blob storage)
  for seed in esg_risk_factors.csv isin_cik.csv sic_isic.csv ticker.csv; do
    curl -L -o "/workspace/dbt/dera_dbt/seeds/$seed" "$DBT_SEEDS_URL/$seed" 2>/dev/null || echo "  Skipping $seed (not in blob storage or already in Git)"
  done
fi

echo "✅ Data files ready!"
echo "📅 Timestamp: $(date)"

# Setup SSH for Git
echo "🔑 Setting up SSH for Git..."
if [ -f /root/.ssh/git_deploy_key ]; then
    chmod 600 /root/.ssh/git_deploy_key
    eval $(ssh-agent -s)
    ssh-add /root/.ssh/git_deploy_key
    echo "✅ SSH key loaded"
else
    echo "⚠️ No SSH key found at /root/.ssh/git_deploy_key"
fi

# Clone repository
echo "📦 Cloning repository..."
cd /workspace
if [ ! -d ".git" ]; then
    git clone ${GIT_REPO} .
    echo "✅ Repository cloned"
else
    echo "⚠️ Repository already exists, pulling latest changes..."
    git pull origin ${GIT_BRANCH}
fi

git checkout ${GIT_BRANCH}
echo "✅ Checked out branch: ${GIT_BRANCH}"

# Setup Python environment
echo "🐍 Setting up Python environment..."
if [ ! -d ".venv" ]; then
    python -m venv .venv
    echo "✅ Virtual environment created"
fi

source .venv/bin/activate
echo "✅ Virtual environment activated"

# Install Python dependencies
echo "📦 Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt
echo "✅ Dependencies installed"

# Wait for OpenMetadata to be ready
echo "⏳ Waiting for OpenMetadata to be ready..."
MAX_RETRIES=60
RETRY_COUNT=0
until curl -f ${OM_API}/v1/system/version 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "❌ OpenMetadata did not become ready in time"
        exit 1
    fi
    echo "Waiting for OpenMetadata... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done
echo "✅ OpenMetadata is ready"

# Wait for PostgreSQL to be ready
echo "⏳ Waiting for PostgreSQL to be ready..."
RETRY_COUNT=0
until pg_isready -h ${PGHOST} -p ${PGPORT} -U ${PGUSER} 2>/dev/null; do
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "❌ PostgreSQL did not become ready in time"
        exit 1
    fi
    echo "Waiting for PostgreSQL... (attempt $RETRY_COUNT/$MAX_RETRIES)"
    sleep 5
done
echo "✅ PostgreSQL is ready"

# Run Make targets
echo "🔨 Running make targets..."

echo "📦 Running make install..."
make install || echo "⚠️ make install failed (might be ok if already installed)"

echo "📊 Running make load-data..."
make load-data || echo "⚠️ make load-data failed"

echo "🔧 Running make register-om-service..."
make register-om-service || echo "⚠️ make register-om-service failed"

echo "🔨 Running make dbt-run..."
make dbt-run || echo "⚠️ make dbt-run failed"

echo "📥 Running make ingest-postgres..."
make ingest-postgres || echo "⚠️ make ingest-postgres failed"

echo "📥 Running make ingest-dbt..."
make ingest-dbt || echo "⚠️ make ingest-dbt failed"

echo "✅ All make targets completed!"
echo "📅 Completed at: $(date)"

# Keep container running for debugging
echo "🔄 Keeping container alive for debugging..."
tail -f /dev/null

