#!/bin/bash
# scripts/install-ingestion.sh
# [4/7] Deploys Ingestion (Airbyte)

set -e

echo "[4/7] Deploying Ingestion (Airbyte)..."

helm upgrade --install airbyte airbyte/airbyte \
  -f ingestion/airbyte-values.yaml \
  --create-namespace -n data-ingestion
