#!/bin/bash
# scripts/install-orchestration.sh
# [7/7] Deploys Orchestration (Airflow)

set -e

echo "[7/7] Deploying Orchestration (Airflow)..."

helm upgrade --install airflow apache-airflow/airflow \
  -f orchestration/airflow-values.yaml \
  --create-namespace -n data-orchestration



# Thank you for installing Apache Airflow 3.1.8!

# Your release is named airflow.
# You can now access your service(s) by following defined Ingress urls:

# DEPRECATION WARNING:
#    `ingress.web.tls` has been renamed to `ingress.web.hosts[*].tls` and can be set per host.
#    Please change your values as support for the old name will be dropped in a future release.

# DEPRECATION WARNING:
#    `ingress.flower.tls` has been renamed to `ingress.flower.hosts[*].tls` and can be set per host.
#    Please change your values as support for the old name will be dropped in a future release.
# Airflow Webserver:
#       http://airflow.localhost/
# Default user (Airflow UI) Login credentials:
#     username: admin
#     password: admin
# Default Postgres connection credentials:
#     username: postgres
#     password: postgres
#     port: 5432

# You can get Fernet Key value by running the following:

#     echo Fernet Key: $(kubectl get secret --namespace data-orchestration airflow-fernet-key -o jsonpath="{.data.fernet-key}" | base64 --decode)

#  DEPRECATION WARNING:
#     Dags Git-Sync bevaiour with `dags.gitSync.recommendedProbeSetting` equal `false` is deprecated and will be removed in future.
#     Please change your values as support for the old name will be dropped in a future release.

# #####################################################
# #  WARNING: You should set a static API secret key  #
# #####################################################

# You are using a dynamically generated API secret key, which can lead to
# unnecessary restarts of your Airflow components.

# Information on how to set a static API secret key can be found here:
# https://airflow.apache.org/docs/helm-chart/stable/production-guide.html#api-secret-key