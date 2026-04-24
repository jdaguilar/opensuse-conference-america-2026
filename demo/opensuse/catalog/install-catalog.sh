#!/bin/bash
# catalog/install-catalog.sh
# Deploys OpenMetadata (data catalog) with its MySQL and Elasticsearch dependencies.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[8/8] Deploying Data Catalog (OpenMetadata)..."

# 1. Ensure namespace exists
kubectl create namespace data-catalog --dry-run=client -o yaml | kubectl apply -f -

# 2. Add OpenMetadata Helm repo
helm repo add open-metadata https://helm.open-metadata.org 2>/dev/null || true
helm repo update open-metadata

# 3. Deploy OpenMetadata dependencies (MySQL + Elasticsearch)
echo "  Deploying OpenMetadata dependencies (MySQL + Elasticsearch)..."
helm upgrade --install openmetadata-dependencies open-metadata/openmetadata-dependencies \
  -n data-catalog \
  --set mysql.primary.persistence.size=2Gi \
  --set elasticsearch.replicas=1 \
  --set elasticsearch.minimumMasterNodes=1 \
  --set elasticsearch.resources.requests.memory=512Mi \
  --set elasticsearch.resources.limits.memory=1Gi \
  --wait --timeout 10m

# 4. Deploy OpenMetadata server
echo "  Deploying OpenMetadata server..."
helm upgrade --install openmetadata open-metadata/openmetadata \
  -n data-catalog \
  -f "$SCRIPT_DIR/openmetadata-values.yaml" \
  --wait --timeout 10m

echo "[8/8] OpenMetadata deployed."
echo "  Access at: http://openmetadata.localhost"
echo "  Default credentials: admin / admin"
