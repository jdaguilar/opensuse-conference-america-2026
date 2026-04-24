#!/bin/bash
# streaming/install-streaming.sh
# [3/7] Deploys Streaming Layer (Strimzi Kafka & Flink)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[3/7] Deploying Streaming Layer (Strimzi Kafka & Flink)..."

# Ensure namespace exists
kubectl create namespace data-streaming --dry-run=client -o yaml | kubectl apply -f -

echo "Installing Strimzi Cluster Operator from manifestations..."
kubectl apply -f 'https://strimzi.io/install/latest?namespace=data-streaming' -n data-streaming

echo "Waiting for Strimzi Cluster Operator to be ready..."
kubectl wait deployment/strimzi-cluster-operator --for=condition=Available --timeout=300s -n data-streaming

echo "Deploying Strimzi Kafka Cluster (KRaft mode)..."
kubectl apply -f "$SCRIPT_DIR/kafka-cr.yaml"

echo "Deploying Flink Kubernetes Operator..."
helm upgrade --install flink-kubernetes-operator flink-operator-repo/flink-kubernetes-operator \
  -f "$SCRIPT_DIR/flink-values.yaml" \
  --create-namespace -n data-streaming
