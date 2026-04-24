#!/bin/bash
# query-engine/install-query-engine.sh
# [5/7] Deploys Query Engine (Trino + Hive Metastore)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CATALOG_DIR="$(dirname "$SCRIPT_DIR")/catalog"

echo "[5/7] Deploying Query Engine (Trino + Hive Metastore)..."

# Ensure namespace exists
kubectl create namespace data-query --dry-run=client -o yaml | kubectl apply -f -

# Deploy Hive Metastore (required by the ozone_iceberg Trino catalog)
echo "  Deploying Hive Metastore..."
kubectl apply -f "$CATALOG_DIR/hive-metastore.yaml"

# Deploy Trino
echo "  Deploying Trino..."
helm upgrade --install trino trino/trino \
  -f "$SCRIPT_DIR/trino-values.yaml" \
  --create-namespace -n data-query

# Deploy CloudBeaver (web SQL client)
echo "  Deploying CloudBeaver..."
kubectl apply -f "$SCRIPT_DIR/cloudbeaver.yaml"

echo "[5/7] Query Engine deployed."
echo "  Trino:        http://trinodb.localhost"
echo "  CloudBeaver:  http://cloudbeaver.localhost  (admin / admin)"
