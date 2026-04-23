---
name: deploy-datalab
description: Build the custom notebook image and deploy JupyterHub to the datalab namespace.
disable-model-invocation: true
---

Build and deploy the JupyterHub datalab. Run from the repository root.

```bash
cd demo/opensuse/datalab
./install_lab.sh
```

After the script finishes:

1. Verify the Helm release status:
   ```bash
   export KUBECONFIG=~/.kube/config
   helm list -n datalab
   kubectl get pods -n datalab
   ```

2. Report whether the deployment succeeded or failed. If it failed, show the relevant pod logs:
   ```bash
   kubectl logs -n datalab -l component=hub --tail=50
   ```

3. On success, confirm JupyterHub is reachable at http://jupyterhub.localhost
