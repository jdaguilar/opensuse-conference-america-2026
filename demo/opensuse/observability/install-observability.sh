#!/bin/bash
# observability/install-observability.sh
# [1/7] Deploys Observability (Prometheus/Grafana)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/7] Deploying Observability (Prometheus/Grafana)..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  -f "$SCRIPT_DIR/kube-prometheus-stack-values.yaml"

echo "Observability stack installed successfully."
