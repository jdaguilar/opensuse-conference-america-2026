#!/bin/bash
# cluster/install-repos.sh
# Centralized Helm repository management for openSUSE Data Platform.

set -e

echo "Updating Helm repositories..."

# Add repositories
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add bitnami              https://charts.bitnami.com/bitnami
helm repo add airbyte              https://airbytehq.github.io/charts
helm repo add trino                https://trinodb.github.io/charts
helm repo add superset             https://apache.github.io/superset
helm repo add apache-airflow       https://airflow.apache.org
helm repo add jetstack             https://charts.jetstack.io
helm repo add rancher-latest       https://releases.rancher.com/server-charts/latest
helm repo add flink-operator-repo https://archive.apache.org/dist/flink/flink-kubernetes-operator-1.8.0/

# Update repositories
helm repo update
