#!/bin/bash
# ingestion/install-ingestion.sh
# [4/7] Deploys Ingestion (Airbyte)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[4/7] Deploying Ingestion (Airbyte)..."

helm upgrade --install airbyte airbyte/airbyte \
  -f "$SCRIPT_DIR/airbyte-values.yaml" \
  --create-namespace -n data-ingestion
