#!/bin/bash
# datalab/install-datalab.sh
# Builds the custom notebook image and deploys JupyterHub for the Datalab layer.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[7/8] Deploying Datalab (JupyterHub + custom notebook image)..."

# 1. Build custom notebook image
echo "  Building custom notebook Docker image..."
docker build -t localhost:5000/local_notebook:latest -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"

# 2. Push image to local registry
echo "  Pushing image to local registry..."
docker push localhost:5000/local_notebook:latest

# 3. Ensure namespace exists
kubectl create namespace datalab --dry-run=client -o yaml | kubectl apply -f -

# 4. Deploy JupyterHub
echo "  Deploying JupyterHub..."
helm repo add jupyterhub https://hub.jupyter.org/helm-chart/ 2>/dev/null || true
helm repo update jupyterhub
helm upgrade --install jupyterhub jupyterhub/jupyterhub \
  --namespace datalab \
  --create-namespace \
  -f "$SCRIPT_DIR/jupyterhub-values.yaml" \
  --wait --timeout 10m

echo "[7/8] Datalab deployed."
echo "  Access at: http://jupyterhub.localhost"
