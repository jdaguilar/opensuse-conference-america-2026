#!/bin/bash
# upload.sh — copy notebooks and scripts to the running JupyterHub notebook pod
set -euo pipefail

NAMESPACE="datalab"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export KUBECONFIG=~/.kube/config

POD=$(kubectl get pods -n "$NAMESPACE" -l component=singleuser-server \
      --field-selector=status.phase=Running \
      -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$POD" ]; then
    echo "No running notebook pod found in namespace $NAMESPACE."
    echo "Start your server at http://jupyterhub.localhost first."
    exit 1
fi

echo "Uploading to pod: $POD"

for f in "$SCRIPTS_DIR"/*.ipynb "$SCRIPTS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    kubectl cp "$f" "$NAMESPACE/$POD:/home/jovyan/scripts/$(basename "$f")"
    echo "  → $(basename "$f")"
done

echo "Done. Files available at ~/scripts/ in the notebook."
