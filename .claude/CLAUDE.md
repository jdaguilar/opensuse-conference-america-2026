# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A complete open-source data platform deployed on Kubernetes (K3s + SUSE Rancher), demonstrated at the openSUSE Conference America 2026. It processes GitHub Archive data through a full medallion architecture using exclusively Apache open-source tools.

**Host requirement**: 32GB RAM minimum.

## Setup & Teardown

```bash
# Validate prerequisites (Docker, k3d, kubectl, helm)
./check_prerequisites.sh

# Deploy the full stack
./setup.sh

# Tear down (remove all Helm releases but keep k3s)
./teardown.sh --keep-k3s

# Tear down everything including k3s
./teardown.sh
```

Individual components each have an install script co-located in their directory:
```bash
demo/opensuse/cluster/install-repos.sh            # Register Helm repos (run first)
demo/opensuse/observability/install-observability.sh
demo/opensuse/storage/install-storage.sh
demo/opensuse/storage/create-artifacts-bucket.sh  # Initialize Ozone buckets
demo/opensuse/streaming/install-streaming.sh
demo/opensuse/ingestion/install-ingestion.sh
demo/opensuse/processing/install-processing.sh
demo/opensuse/query-engine/install-query-engine.sh
demo/opensuse/orchestration/install-orchestration.sh
demo/opensuse/bi/install-bi.sh
demo/opensuse/catalog/install-catalog.sh
demo/opensuse/datalab/install-datalab.sh          # Build image + deploy JupyterHub
```

## Architecture

The platform implements a medallion data lakehouse:

```
gharchive.org → Airflow (ingestion DAG) → Ozone S3 (raw/)
                                              ↓
                               Airflow (Spark DAG) → Ozone Iceberg (curated/)
                                              ↓
                                      dbt via Trino → views/models
                                              ↓
                        Superset dashboards ← Trino (federated query)
```

### Components by Layer

| Layer | Technology | Namespace | External URL |
|-------|-----------|-----------|-------------|
| Cluster | K3s + Rancher | cattle-system | https://rancher.localhost |
| Observability | Prometheus + Grafana | observability | http://grafana.localhost |
| Object Storage | Apache Ozone | data-storage | http://ozone-recon.localhost |
| S3 Browser | Filestash | data-storage | (via Rancher) |
| Streaming | Apache Kafka | data-streaming | :9092 (internal) |
| Ingestion | Airbyte | data-ingestion | http://airbyte.localhost |
| Processing | Spark Operator 2.5 + Spark 4.0.0 | spark-operator / data-processing | — |
| Metastore | Hive Metastore 4.0.0 | data-query | thrift://hive-metastore:9083 |
| Query | Trino | data-query | http://trinodb.localhost |
| BI | Apache Superset 5.0.0 | data-bi | http://superset.localhost |
| Orchestration | Airflow 3.x | data-orchestration | http://airflow.localhost |
| Data Catalog | OpenMetadata | catalog | — |
| Notebooks | JupyterHub | datalab | http://jupyterhub.localhost |

### Storage Layout (Apache Ozone)

- `s3://raw/gh_archive/year={Y}/month={M}/day={D}/hour={H}/` — raw GitHub Archive JSON.gz
- `s3://curated/` — Iceberg tables (processed output)
- `s3://artifacts/` — processing scripts and metadata

S3 gateway (within cluster): `http://ozone-s3g-rest.data-storage.svc.cluster.local:9878`

## Airflow DAGs

Located in `demo/opensuse/orchestration/dags/`:

- **`download_gh_archive.py`** — Daily at 10:00 UTC. Downloads 24 hourly GitHub Archive files and uploads to Ozone `s3://raw/`.
- **`curate_github_data.py`** — Daily at 12:00 UTC. Runs a Spark job that reads `s3a://raw/` and writes Iceberg tables to `s3a://curated/`.
- **`create_curated_tables.py`** — Creates Iceberg table DDL in Trino/Hive metastore.

Airflow syncs DAGs from GitHub via git-sync (repo: `jdaguilar/opensuse-conference-america-2026`).

## Notebooks (datalab/)

Base image: `quay.io/jupyter/all-spark-notebook:latest` (Spark 4.1.1 / Hadoop 3.4.2). Extended with:
- `hadoop-aws-3.4.2.jar` + `aws-sdk-v2-bundle-2.29.52.jar` + `aws-java-sdk-bundle-1.12.720.jar` (versions from `hadoop-project-3.4.2.pom`)
- `iceberg-spark-runtime-4.0_2.13-1.10.1.jar`
- AWS CLI v2, pyiceberg, boto3, duckdb
- `spark-defaults.conf` baked in — every SparkSession gets S3A + Iceberg pre-configured

Image is built and pushed to `localhost:5000/local_notebook:latest` by `install-datalab.sh`.

**Iceberg catalog**: `HadoopCatalog` named `iceberg`, warehouse `s3a://curated/`. No Hive metastore required.

```python
spark.sql("CREATE NAMESPACE IF NOT EXISTS iceberg.curated")
df.writeTo("iceberg.curated.my_table").partitionedBy("year").createOrReplace()
```

**NetworkPolicy**: notebook pods require egress to `data-storage:9878` (Ozone) — configured in `jupyterhub-values.yaml`.

## Spark Configuration (notebook)

`datalab/spark-defaults.conf` pre-configures every SparkSession:
```
spark.hadoop.fs.s3a.impl=org.apache.hadoop.fs.s3a.S3AFileSystem
spark.hadoop.fs.s3a.endpoint=http://ozone-s3g-rest.data-storage.svc.cluster.local:9878
spark.hadoop.fs.s3a.access.key=hadoop
spark.hadoop.fs.s3a.secret.key=ozone
spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalog.iceberg=org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.iceberg.type=hadoop
spark.sql.catalog.iceberg.warehouse=s3a://curated/
```

## Spark Processing Image

Spark Operator jobs use a **dedicated image** (`localhost:5000/spark_processing:latest`), NOT the notebook image. The notebook image uses JupyterHub's entrypoint which does not handle `driver`/`executor` subcommands.

Built from `demo/opensuse/processing/Dockerfile.spark` (base: `apache/spark:4.0.0`). JAR versions pinned to match `hadoop-client-runtime-3.4.1` bundled in the image (from `hadoop-project-3.4.1.pom`):
- `hadoop-aws-3.4.1.jar`
- `aws-sdk-v2-bundle-2.24.6.jar`
- `aws-java-sdk-bundle-1.12.720.jar`
- `iceberg-spark-runtime-4.0_2.13-1.10.1.jar`

Rebuild and push after any JAR or config change:
```bash
cd demo/opensuse/processing
docker build -f Dockerfile.spark -t localhost:5000/spark_processing:latest .
docker push localhost:5000/spark_processing:latest
```

## BI (Apache Superset)

Deployed in `data-bi` namespace. Custom image `localhost:5000/superset:5.0.0` extends `apache/superset:5.0.0` with `psycopg2-binary`, `sqlalchemy-trino`, and `trino[sqlalchemy]`.

**Installation note**: packages must be installed with `pip install --target /app/.venv/lib/python3.10/site-packages` — the image has no `pip` binary in the venv, only `python`.

Access: `http://superset.localhost` — admin / admin.

Rebuild:
```bash
cd demo/opensuse/bi
docker build -t localhost:5000/superset:5.0.0 .
docker push localhost:5000/superset:5.0.0
helm upgrade superset superset/superset -n data-bi -f superset-values.yaml
```

**Trino connection string** (add in Settings → Database Connections):
```
trino://admin@trino.data-query.svc.cluster.local:8080/tpch
```

## Hive Metastore

Hive Metastore 4.0.0 runs in `data-query` alongside Trino. It stores Iceberg table metadata in a PostgreSQL 15 backend (`postgres:15-alpine`, StatefulSet `hive-metastore-postgresql`).

Custom image `localhost:5000/hive-metastore:4.0.0` extends `apache/hive:4.0.0` (Hadoop 3.3.6) with:
- `hadoop-aws-3.3.6.jar` + `aws-java-sdk-bundle-1.12.262.jar` — S3A for Ozone access
- `postgresql-42.7.4.jar` — JDBC driver for PostgreSQL backend
- `ENV JAVA_TOOL_OPTIONS=-Dhive.metastore.schema.verification=false` — bypasses schema version check; DataNucleus `autoCreateAll=true` initialises tables on first boot

Rebuild:
```bash
cd demo/opensuse/catalog
docker build -f Dockerfile.hive-metastore -t localhost:5000/hive-metastore:4.0.0 .
docker push localhost:5000/hive-metastore:4.0.0
kubectl rollout restart deployment/hive-metastore -n data-query
```

## Trino / Iceberg Query

Trino uses the `ozone_iceberg` catalog (Iceberg connector) backed by Hive Metastore at `thrift://hive-metastore.data-query.svc.cluster.local:9083` and Ozone S3 at `http://ozone-s3g-rest.data-storage.svc.cluster.local:9878`.

```sql
SHOW SCHEMAS IN ozone_iceberg;          -- default, curated, information_schema
SHOW TABLES IN ozone_iceberg.curated;   -- Iceberg tables written by Spark
```

dbt project (`transformation/dbt-project/`) targets Trino with profile `gharchive`. Models default to `view` materialization.

## Cluster Interaction

```bash
# Check cluster context
kubectl config get-contexts

# Inspect a namespace
kubectl get all -n <namespace>

# Follow logs
kubectl logs -f deployment/<name> -n <namespace>

# Helm release status
helm list -A
helm get values <release> -n <namespace>
```

Status and health scripts (no cluster changes):
```bash
./demo/opensuse/demo-control/verify-health.sh
./demo/opensuse/demo-control/get-urls.sh
./demo/opensuse/demo-control/status-dashboard.sh
```

## Helm Values Files

Each component has a `*-values.yaml` in its directory. Key files:
- `storage/ozone-values.yaml` — Ozone cluster sizing (1 OM, 1 SCM, 3 datanodes)
- `query-engine/trino-values.yaml` — Trino workers + `ozone_iceberg` catalog (Hive metastore URI + S3 creds)
- `orchestration/airflow-values.yaml` — Git-sync repo, executor, K8s connection
- `datalab/jupyterhub-values.yaml` — Notebook server config and resource limits
- `bi/superset-values.yaml` — Superset with custom image, Celery concurrency=2
- `processing/spark-operator-values.yaml` — Watches `data-processing` namespace (`spark.jobNamespaces`)

@rules/code-style.md
@rules/testing.md
@rules/security.md
@rules/known-issues.md
