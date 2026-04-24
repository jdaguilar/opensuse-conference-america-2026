#!/bin/bash
# cluster/setup-rancher.sh
# Provisions a local K3s cluster and deploys Rancher natively.

set -e

echo "Installing K3s..."
curl -sfL https://get.k3s.io | sh -

echo "Configuring KUBECONFIG..."
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
export KUBECONFIG=~/.kube/config

echo "Configuring local container registry..."
sudo cp "$(dirname "$0")/registries.yaml" /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s

echo "Starting local Docker registry..."
docker run -d \
  --name local-registry \
  --restart=always \
  -p 5000:5000 \
  registry:2

echo "Waiting for K3s nodes to become ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

echo "Installing cert-manager..."
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=Ready pods -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

echo "Installing Rancher..."
helm repo add rancher-latest https://releases.rancher.com/server-charts/latest
helm repo update
helm install rancher rancher-latest/rancher \
  --namespace cattle-system \
  --create-namespace \
  -f "$(dirname "$0")/rancher-values.yaml"

echo "Rancher installation started successfully."



# Rancher Server has been upgraded. Rancher may take several minutes to fully initialize.

# Please standby while Certificates are being issued, Containers are started and the Ingress rule comes up.

# Check out our docs at https://rancher.com/docs/

# ## First Time Login

# If you provided your own bootstrap password during installation, browse to https://rancher.localhost to get started.
# If this is the first time you installed Rancher, get started by running this command and clicking the URL it generates:

# ```
# echo https://rancher.localhost/dashboard/?setup=$(kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}')
# ```

# To get just the bootstrap password on its own, run:

# ```
# kubectl get secret --namespace cattle-system bootstrap-secret -o go-template='{{.data.bootstrapPassword|base64decode}}{{ "\n" }}'
# ```