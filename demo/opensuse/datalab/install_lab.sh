#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Datalab setup ==="

# Step 1: Build and push the custom notebook image to the local registry
echo "[1/3] Building and pushing local_notebook:latest..."
cd "$SCRIPT_DIR"
docker build -t localhost:5000/local_notebook:latest -f Dockerfile .
docker push localhost:5000/local_notebook:latest

# Step 2: Deploy JupyterHub
echo "[2/3] Deploying JupyterHub to datalab namespace..."
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ 2>/dev/null || true
helm repo update jupyterhub

helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace datalab \
  --create-namespace \
  --timeout 10m \
  -f "$SCRIPT_DIR/jupyterhub-values.yaml"

echo ""
echo "Datalab ready — access JupyterHub at: http://jupyterhub.localhost"