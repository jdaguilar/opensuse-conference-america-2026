#!/bin/bash
# scripts/install-query-engine.sh
# [5/7] Deploys Query Engine (Trino)

set -e

echo "[5/7] Deploying Query Engine (Trino)..."

helm upgrade --install trino trino/trino \
  -f query-engine/trino-values.yaml \
  --create-namespace -n data-query
