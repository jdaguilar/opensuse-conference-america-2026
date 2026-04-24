#!/bin/bash
# bi/install-bi.sh
# [6/7] Deploys BI (Superset) with stable standalone databases.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[6/7] Deploying BI (Superset)..."

# 1. Ensure namespace exists
kubectl create namespace data-bi --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install superset superset/superset \
  -f "$SCRIPT_DIR/superset-values.yaml" \
  -n data-bi --wait
