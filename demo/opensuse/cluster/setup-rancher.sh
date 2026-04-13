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
  --set hostname=rancher.localhost \
  --set bootstrapPassword=admin \
  --set replicas=1

echo "Rancher installation started successfully."
