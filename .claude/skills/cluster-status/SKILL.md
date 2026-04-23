---
name: cluster-status
description: Show the health of the Kubernetes cluster and all platform components. Use when asked about cluster health, pod status, what's running, or whether a deployment succeeded.
---

Print a concise health overview of the data platform.

```bash
export KUBECONFIG=~/.kube/config

echo "=== Nodes ==="
kubectl get nodes

echo "=== Helm releases ==="
helm list -A

echo "=== Failed or pending pods ==="
kubectl get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null | grep -v "^NAMESPACE" || echo "None"

echo "=== Datalab ==="
kubectl get all -n datalab
```

Summarise the output: list any releases that are not `deployed`, any pods that are not `Running` or `Completed`, and highlight anything that needs attention. If everything looks healthy, say so clearly.
