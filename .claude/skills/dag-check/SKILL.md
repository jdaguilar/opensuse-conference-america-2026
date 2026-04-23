---
name: dag-check
description: Lint and validate Airflow DAGs for Python 3.11 style and Airflow 3 compatibility. Use when editing DAGs, before committing DAG changes, or when asked to check DAG code quality.
---

Run all checks on the Airflow DAGs directory. All checks must pass before a DAG is considered ready.

```bash
cd demo/opensuse/orchestration/dags

echo "=== black ==="
black --check .

echo "=== isort ==="
isort --check .

echo "=== flake8 ==="
flake8 .

echo "=== Python 3.11 syntax ==="
for f in *.py; do python3.11 -m py_compile "$f" && echo "$f OK"; done

echo "=== Airflow 3 compatibility ==="
# Fail on any removed or deprecated Airflow 2 APIs
grep -rn "days_ago\|schedule_interval\|provide_context\|execution_date\|airflow\.utils\.dates\|PythonOperator\|BashOperator" . \
  && echo "FAIL: found forbidden Airflow 2 patterns above" && exit 1 \
  || echo "OK: no forbidden patterns found"

echo "=== Airflow 3 DAG import ==="
python3.11 - <<'EOF'
import sys, os
os.environ.setdefault("AIRFLOW__CORE__LOAD_EXAMPLES", "False")
os.environ.setdefault("AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", "sqlite:////tmp/airflow_check.db")
from airflow.models import DagBag
bag = DagBag(dag_folder=".", include_examples=False)
if bag.import_errors:
    for dag_file, err in bag.import_errors.items():
        print(f"IMPORT ERROR {dag_file}: {err}", file=sys.stderr)
    sys.exit(1)
print(f"OK: loaded {len(bag.dags)} DAG(s) — {list(bag.dags.keys())}")
EOF
```

Report each failure with the file name and line number. If all checks pass, confirm the DAGs are Airflow 3 compatible and lint-clean. If any check fails, show the full output and suggest the exact fix.
