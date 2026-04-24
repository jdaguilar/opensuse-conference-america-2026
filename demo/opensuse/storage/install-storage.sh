#!/bin/bash
# storage/install-storage.sh
# [2/7] Deploys Storage (Apache Ozone & Filestash)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[2/7] Deploying Storage (Apache Ozone & Filestash)..."

# Ensure namespace exists
kubectl create namespace data-storage --dry-run=client -o yaml | kubectl apply -f -

# Add Helm Repo
helm repo add apache https://apache.github.io/ozone-helm-charts/
helm repo update

# Install Ozone (Apache)
helm upgrade --install ozone apache/ozone \
  -f "$SCRIPT_DIR/ozone-values.yaml" \
  -n data-storage

# Install Filestash (UI Tooling)
kubectl apply -f "$SCRIPT_DIR/filestash.yaml"
