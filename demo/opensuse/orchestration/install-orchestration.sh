#!/bin/bash
# orchestration/install-orchestration.sh
# [7/7] Deploys Orchestration (Airflow)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[7/7] Deploying Orchestration (Airflow)..."

helm upgrade --install airflow apache-airflow/airflow \
  -f "$SCRIPT_DIR/airflow-values.yaml" \
  --create-namespace -n data-orchestration

echo "Airflow deployed. Access at: http://airflow.localhost"
echo "Credentials: admin / admin"
