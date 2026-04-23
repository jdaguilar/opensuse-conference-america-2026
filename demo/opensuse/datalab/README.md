# Datalab — JupyterHub + Spark + Iceberg

Interactive notebook environment deployed in the `datalab` Kubernetes namespace. Provides Spark 4.1.1, Iceberg 1.10.1, and direct S3A access to Apache Ozone.

## Stack

| Component | Detail |
|-----------|--------|
| Notebook platform | JupyterHub 5.4.4 (Helm chart `jupyterhub/jupyterhub:4.3.3`) |
| Base image | `quay.io/jupyter/all-spark-notebook:latest` (Spark 4.1.1 / Hadoop 3.4.2) |
| Object storage | Apache Ozone S3 gateway (`s3a://`) |
| Iceberg catalog | HadoopCatalog — metadata stored in `s3a://curated/` |
| URL | http://jupyterhub.localhost |

## Prerequisites

- Local Docker registry running at `localhost:5000` (configured by `cluster/setup-rancher.sh`)
- K3s cluster with `datalab` namespace and NetworkPolicy egress to `data-storage:9878`

## Build and deploy

```bash
cd demo/opensuse/datalab
./install_lab.sh
```

The script builds the custom image, pushes it to `localhost:5000/local_notebook:latest`, then runs `helm upgrade`.

To rebuild the image only:

```bash
docker build -t localhost:5000/local_notebook:latest -f Dockerfile .
docker push localhost:5000/local_notebook:latest
```

## Image contents

The `Dockerfile` extends `quay.io/jupyter/all-spark-notebook` with:

| Addition | Version | Purpose |
|----------|---------|---------|
| `hadoop-aws` | 3.4.2 | S3A filesystem connector |
| `aws-java-sdk-bundle` (v1) | 1.12.720 | Backward-compat codepaths |
| `software.amazon.awssdk:bundle` (v2) | 2.29.52 | Hadoop 3.4.x S3A primary SDK |
| `iceberg-spark-runtime-4.0_2.13` | 1.10.1 | Iceberg catalog + extensions |
| AWS CLI v2 | latest | Shell access to Ozone buckets |
| pyiceberg, boto3, duckdb | latest | Python data access |

All JARs are downloaded from Maven Central during `docker build`. Versions are pinned via `ARG` in the Dockerfile and come from `hadoop-project-3.4.2.pom`.

## Spark configuration

`spark-defaults.conf` is baked into the image at `/usr/local/spark/conf/spark-defaults.conf`. It pre-configures every SparkSession with:

- **S3A**: endpoint, path-style access, credentials, `SimpleAWSCredentialsProvider`
- **Iceberg**: `IcebergSparkSessionExtensions` + `SparkCatalog` named `iceberg` (HadoopCatalog, warehouse `s3a://curated/`)

No per-session Spark config is needed in notebooks.

## Environment variables (injected at runtime by Helm)

| Variable | Value |
|----------|-------|
| `AWS_ACCESS_KEY_ID` | `hadoop` |
| `AWS_SECRET_ACCESS_KEY` | `ozone` |
| `AWS_S3_ENDPOINT` | `http://ozone-s3g-rest.data-storage.svc.cluster.local:9878` |
| `AWS_ENDPOINT_URL_S3` | same — read by AWS CLI v2 |

## Writing Iceberg tables from a notebook

```python
# namespace must exist before writing
spark.sql("CREATE NAMESPACE IF NOT EXISTS iceberg.curated")

df.writeTo("iceberg.curated.my_table") \
  .partitionedBy("year", "month") \
  .createOrReplace()
```

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `NoClassDefFoundError: software/amazon/awssdk/...` | Wrong SDK v2 version | Rebuild image — version pinned in Dockerfile |
| `NoSuchMethodError: crossRegionAccessEnabled` | SDK v2 too old (< 2.21) | Ensure `AWS_SDK_V2_VERSION=2.29.52` in Dockerfile |
| `Connection refused` to Ozone | NetworkPolicy blocking egress | Check `singleuser.networkPolicy.egress` in `jupyterhub-values.yaml` |
| `REPLACE TABLE AS SELECT` unsupported | Hive metastore not deployed | Use `iceberg` HadoopCatalog (already configured) |
| `hook-image-awaiter` stuck in Helm | Image not in local registry | Run `docker push localhost:5000/local_notebook:latest` |
