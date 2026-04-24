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

Individual components can be installed via `demo/opensuse/scripts/`:
```bash
demo/opensuse/scripts/install-repos.sh        # Register Helm repos (run first)
demo/opensuse/scripts/install-storage.sh
demo/opensuse/scripts/install-streaming.sh
demo/opensuse/scripts/install-orchestration.sh
demo/opensuse/scripts/install-bi.sh
demo/opensuse/scripts/create-artifacts-bucket.sh   # Initialize Ozone buckets
```

Datalab (JupyterHub notebooks):
```bash
cd demo/opensuse/datalab
./install_lab.sh   # Build image, push to local registry, deploy JupyterHub
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
| Processing | Spark 3.5.0 | (operator) | — |
| Query | Trino | data-query | http://trinodb.localhost:8080 |
| BI | Apache Superset | data-bi | http://superset.localhost |
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

Image is built and pushed to `localhost:5000/local_notebook:latest` by `install_lab.sh`.

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

## Trino / Iceberg Query

Trino is configured with an Iceberg connector pointing to Ozone. **Note**: Hive metastore (`thrift://hive-metastore:9083`) is referenced in Trino config but not yet deployed — Trino Iceberg queries will fail until a metastore is added.

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
- `query-engine/trino-values.yaml` — Trino workers + Iceberg catalog config
- `orchestration/airflow-values.yaml` — Git-sync repo, executor, connections
- `datalab/jupyterhub-values.yaml` — Notebook server config and resource limits

@rules/code-style.md
@rules/testing.md
@rules/security.md
@rules/known-issues.md
