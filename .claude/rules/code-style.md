# Code Style

## Python

**Version: 3.11** (enforced). Format with `black` (88-char line limit) + `isort`. Lint with `flake8`.

```bash
black --check demo/opensuse/orchestration/dags/
isort --check demo/opensuse/orchestration/dags/
flake8 demo/opensuse/orchestration/dags/
```

Every Python module must import `logging`, `os`, and `sys`. Use virtualenv at `.venv`.

## Airflow DAGs (Airflow 3.x)

**Runtime: Airflow 3.x** — do not use any API removed or deprecated in Airflow 3.

DAGs live in `demo/opensuse/orchestration/dags/`.

### Required
- Define `schedule` and `start_date` on every DAG.
- Use `@dag` and `@task` taskflow decorators — never `BashOperator` or `PythonOperator`.
- Use `pendulum.datetime(...)` for `start_date` — never `days_ago()` (removed in Airflow 3).
- Reference execution date via `context["logical_date"]` or `{{ ds }}` — never `datetime.now()`.

### Forbidden (Airflow 3 breaking changes)
- `schedule_interval=` → use `schedule=`
- `days_ago()` → use `pendulum.datetime(year, month, day, tz="UTC")`
- `provide_context=True` → removed; context is passed automatically with taskflow
- `PythonOperator`, `BashOperator` → use `@task` and `@task.bash`
- `execution_date` → use `logical_date`
- Importing from `airflow.utils.dates` → module removed in Airflow 3
- `from airflow.decorators import dag, task` → use `from airflow.sdk import dag, task` (decorators path deprecated in Airflow 3)
- `params` as a `@task` argument name → reserved Airflow context key; use `job_params` or any other name

## Kubernetes Manifests

- All resources must carry `app` and `version` labels plus a `kubernetes.io/description` annotation.
- Use K3s cluster with context `rancher`.
- Do not create raw `Pod` or `ServiceAccount` resources directly; use higher-level controllers (Deployment, StatefulSet, etc.).
