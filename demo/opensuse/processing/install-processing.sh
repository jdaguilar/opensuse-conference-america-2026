#!/bin/bash
# processing/install-processing.sh — deploy Spark Operator and upload the curation script to Ozone
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=~/.kube/config

echo "=== Spark Operator setup ==="

echo "[1/5] Applying RBAC..."
kubectl apply -f "$SCRIPT_DIR/rbac.yaml"

echo "[2/5] Adding spark-operator Helm repo..."
helm repo add spark-operator https://kubeflow.github.io/spark-operator 2>/dev/null || true
helm repo update spark-operator

echo "[3/5] Installing spark-operator..."
helm upgrade --install spark-operator spark-operator/spark-operator \
  --namespace spark-operator \
  --create-namespace \
  --timeout 5m \
  -f "$SCRIPT_DIR/spark-operator-values.yaml"

echo "[4/5] Waiting for spark-operator to be ready..."
kubectl rollout status deployment/spark-operator-controller \
  -n spark-operator --timeout=120s 2>/dev/null || \
kubectl wait --for=condition=Ready pods \
  -l app.kubernetes.io/name=spark-operator \
  -n spark-operator --timeout=120s

echo "[5/5] Uploading curation scripts to s3://artifacts/scripts/..."

upload_via_om() {
  local local_path="$1"
  local key="$2"
  kubectl cp "$local_path" "data-storage/ozone-om-0:/tmp/$key"
  kubectl exec -n data-storage ozone-om-0 -- \
    env AWS_ACCESS_KEY_ID=hadoop AWS_SECRET_ACCESS_KEY=ozone \
    aws s3 cp "/tmp/$key" "s3://artifacts/scripts/$key" \
    --endpoint-url http://ozone-s3g-rest.data-storage.svc.cluster.local:9878 \
    --no-verify-ssl
}

upload_via_notebook() {
  local local_path="$1"
  local key="$2"
  local pod="$3"
  kubectl cp "$local_path" "datalab/$pod:/tmp/$key"
  kubectl exec -n datalab "$pod" -- \
    aws s3 cp "/tmp/$key" "s3://artifacts/scripts/$key"
}

NOTEBOOK_POD=$(kubectl get pods -n datalab -l component=singleuser-server \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

for script in "$SCRIPT_DIR"/scripts/*.py; do
  key="$(basename "$script")"
  echo "  Uploading $key..."
  if [ -z "$NOTEBOOK_POD" ]; then
    upload_via_om "$script" "$key" 2>/dev/null || \
      echo "  WARNING: upload of $key skipped — start a notebook server and re-run."
  else
    upload_via_notebook "$script" "$key" "$NOTEBOOK_POD"
  fi
done

echo ""
echo "=== Done ==="
echo "Spark Operator: $(helm status spark-operator -n spark-operator --short 2>/dev/null)"
echo "Scripts uploaded to: s3://artifacts/scripts/"
