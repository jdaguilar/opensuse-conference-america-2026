#!/bin/bash
# install-processing.sh — deploy Spark Operator and upload the curation script to Ozone
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
PROCESSING_DIR="$REPO_ROOT/demo/opensuse/processing"

export KUBECONFIG=~/.kube/config

echo "=== Spark Operator setup ==="

echo "[1/5] Applying RBAC..."
kubectl apply -f "$PROCESSING_DIR/rbac.yaml"

echo "[2/5] Adding spark-operator Helm repo..."
helm repo add spark-operator https://kubeflow.github.io/spark-operator 2>/dev/null || true
helm repo update spark-operator

echo "[3/5] Installing spark-operator..."
helm upgrade --install spark-operator spark-operator/spark-operator \
  --namespace spark-operator \
  --create-namespace \
  --timeout 5m \
  -f "$PROCESSING_DIR/spark-operator-values.yaml"

echo "[4/5] Waiting for spark-operator to be ready..."
kubectl rollout status deployment/spark-operator-controller \
  -n spark-operator --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=spark-operator \
  -n spark-operator --timeout=120s

echo "[5/5] Uploading curation script to s3://artifacts/scripts/..."
CURATION_SCRIPT="$PROCESSING_DIR/scripts/github_curation.py"

# Use the notebook pod (has AWS CLI + Ozone credentials already configured)
NOTEBOOK_POD=$(kubectl get pods -n datalab -l component=singleuser-server \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$NOTEBOOK_POD" ]; then
  echo "  No running notebook pod found — uploading via a temporary pod..."
  kubectl cp "$CURATION_SCRIPT" "data-storage/ozone-om-0:/tmp/github_curation.py"
  kubectl exec -n data-storage ozone-om-0 -- \
    env AWS_ACCESS_KEY_ID=hadoop AWS_SECRET_ACCESS_KEY=ozone \
    aws s3 cp /tmp/github_curation.py s3://artifacts/scripts/github_curation.py \
    --endpoint-url http://ozone-s3g-rest.data-storage.svc.cluster.local:9878 \
    --no-verify-ssl 2>/dev/null || \
  kubectl exec -n data-storage ozone-om-0 -- \
    ozone sh key put /artifacts/scripts/github_curation.py < "$CURATION_SCRIPT" 2>/dev/null || \
  echo "  WARNING: upload skipped — run upload manually after starting a notebook server."
else
  echo "  Using notebook pod: $NOTEBOOK_POD"
  kubectl cp "$CURATION_SCRIPT" "datalab/$NOTEBOOK_POD:/tmp/github_curation.py"
  kubectl exec -n datalab "$NOTEBOOK_POD" -- \
    aws s3 cp /tmp/github_curation.py s3://artifacts/scripts/github_curation.py
fi

echo ""
echo "=== Done ==="
echo "Spark Operator: $(helm status spark-operator -n spark-operator --short 2>/dev/null)"
echo "Script uploaded to: s3://artifacts/scripts/github_curation.py"
