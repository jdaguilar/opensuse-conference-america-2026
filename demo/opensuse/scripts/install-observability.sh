#!/bin/bash
# scripts/install-observability.sh
# [1/7] Deploys Observability (Prometheus/Grafana)

set -e

echo "[1/7] Deploying Observability (Prometheus/Grafana)..."

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace observability \
  --create-namespace \
  -f observability/kube-prometheus-stack-values.yaml

echo "Observability stack installed successfully."