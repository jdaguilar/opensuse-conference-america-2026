# Testing & CI

## CI Pipeline

Defined in `demo/opensuse/.gitlab-ci.yml` with three stages:

- `lint` — DAG syntax check using Python 3.10-slim image.
- `build` — `docker build -f processing/Dockerfile.spark` triggered when Spark sources change.
- `deploy` — `helm upgrade --install` for Airflow triggered when `airflow-values.yaml` changes.

## Linting

Run locally before pushing:

```bash
black --check demo/opensuse/orchestration/dags/
isort --check demo/opensuse/orchestration/dags/
flake8 demo/opensuse/orchestration/dags/
```
