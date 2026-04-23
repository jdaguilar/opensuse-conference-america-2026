# Security

## Credentials (demo only — do not use in production)

| Service | Username | Password |
|---------|----------|----------|
| Airflow | admin | admin |
| Rancher | admin | admin (bootstrap) |
| Ozone S3 | hadoop (access key) | ozone (secret key) |

## Kubernetes

- Never create raw `Pod` or `ServiceAccount` resources; use Deployments, StatefulSets, or Jobs.
- All workloads must declare resource `requests` and `limits`.
- Do not store secrets in plain-text ConfigMaps; use Kubernetes Secrets or Helm secret values.

## Local Registry

The cluster uses a local Docker registry at `localhost:5000` configured as insecure in `/etc/rancher/k3s/registries.yaml`. Only push internal demo images here — never production or sensitive images.
