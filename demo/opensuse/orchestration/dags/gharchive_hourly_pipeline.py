"""Hourly GitHub Archive ingestion + curation pipeline.

Each run targets the same hour from 24h ago (today 16:00 UTC → ingests
yesterday 16:00). Downloads the single hourly file to s3://raw/, then
triggers a Spark curation job that writes Iceberg-partitioned data to
iceberg.curated.github_events_hourly (year/month/day/hour).

Idempotent: re-running for the same hour replaces only that hour's
partition (Iceberg overwritePartitions = dynamic partition overwrite).
"""

import logging
import os
import sys
import time
from datetime import timedelta

import pendulum
import requests
from airflow.exceptions import AirflowSkipException
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.sdk import dag, task

AWS_CONN_ID = "ozone"
TRINO_CONN_ID = "trino_default"
RAW_BUCKET = "raw"
ARTIFACTS_BUCKET = "artifacts"
SPARK_IMAGE = "localhost:5000/spark_processing:latest"
SPARK_NAMESPACE = "data-processing"
SPARK_SCRIPT = f"s3a://{ARTIFACTS_BUCKET}/scripts/github_curation_hourly.py"

# Registers any new partition directories in the ozone_hive.raw.gh_archive
# external table (mode='ADD' only adds, never drops). Idempotent.
SYNC_RAW_PARTITIONS_SQL = """
CALL ozone_hive.system.sync_partition_metadata(
  schema_name => 'raw',
  table_name  => 'gh_archive',
  mode        => 'ADD'
)
"""

# S3A + Iceberg conf injected into every SparkApplication.
# HiveCatalog (type=hive) — every write updates Hive Metastore directly so
# Trino's ozone_iceberg catalog sees new snapshots immediately. Avoids the
# HadoopCatalog drift problem where version-hint.text bumps in Ozone but
# Hive's metadata pointer stays frozen at the registration version.
SPARK_CONF = {
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
    "spark.hadoop.fs.s3a.endpoint": (
        "http://ozone-s3g-rest.data-storage.svc.cluster.local:9878"
    ),
    "spark.hadoop.fs.s3a.access.key": "hadoop",
    "spark.hadoop.fs.s3a.secret.key": "ozone",
    "spark.hadoop.fs.s3a.path.style.access": "true",
    "spark.hadoop.fs.s3a.aws.credentials.provider": (
        "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider"
    ),
    "spark.sql.extensions": (
        "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions"
    ),
    "spark.sql.catalog.iceberg": "org.apache.iceberg.spark.SparkCatalog",
    "spark.sql.catalog.iceberg.type": "hive",
    "spark.sql.catalog.iceberg.uri": (
        "thrift://hive-metastore.data-query.svc.cluster.local:9083"
    ),
    "spark.sql.catalog.iceberg.warehouse": "s3a://curated/warehouse/",
}


def _build_spark_application(date_str: str, hour: int, run_id: str) -> dict:
    name = f"gh-hourly-{date_str.replace('-', '')}-h{hour:02d}-{run_id}"
    return {
        "apiVersion": "sparkoperator.k8s.io/v1beta2",
        "kind": "SparkApplication",
        "metadata": {"name": name, "namespace": SPARK_NAMESPACE},
        "spec": {
            "type": "Python",
            "pythonVersion": "3",
            "mode": "cluster",
            "image": SPARK_IMAGE,
            "imagePullPolicy": "Always",
            "mainApplicationFile": SPARK_SCRIPT,
            "arguments": [date_str, str(hour)],
            "sparkVersion": "4.0.0",
            "restartPolicy": {"type": "Never"},
            "sparkConf": SPARK_CONF,
            "driver": {
                "cores": 1,
                "memory": "1g",
                "serviceAccount": "spark",
                "labels": {"app": "gh-curation-hourly", "version": "1.0"},
                "annotations": {
                    "kubernetes.io/description": (
                        "Hourly GHArchive curation Spark driver"
                    )
                },
            },
            "executor": {
                "cores": 1,
                "instances": 1,
                "memory": "1g",
                "labels": {"app": "gh-curation-hourly", "version": "1.0"},
                "annotations": {
                    "kubernetes.io/description": (
                        "Hourly GHArchive curation Spark executor"
                    )
                },
            },
        },
    }


@dag(
    dag_id="gharchive_hourly_pipeline",
    start_date=pendulum.datetime(2026, 4, 1, tz="UTC"),
    schedule="0 * * * *",
    catchup=False,
    max_active_runs=2,
    tags=["gharchive", "iceberg", "curation", "spark", "hourly"],
)
def gharchive_hourly_pipeline():
    @task
    def get_target_hour(logical_date=None) -> dict:
        """Lookback: 24h ago — yesterday at this same hour."""
        target = logical_date - timedelta(days=1)
        return {
            "date": target.strftime("%Y-%m-%d"),
            "hour": target.hour,
            "year": target.year,
            "month": target.month,
            "day": target.day,
        }

    @task(retries=3, retry_delay=timedelta(minutes=2))
    def ingest_hour(job_params: dict) -> dict:
        """Download a single GHArchive hourly file and upload to s3://raw/.

        Idempotent: replace=True overwrites the same key on re-runs.
        """
        date = job_params["date"]
        hour = job_params["hour"]
        year = job_params["year"]
        month = job_params["month"]
        day = job_params["day"]

        url = f"http://data.gharchive.org/{date}-{hour}.json.gz"
        logging.info("Downloading %s", url)

        local_folder = (
            f"/tmp/gh_archive/year={year}/month={month:02d}"
            f"/day={day:02d}/hour={hour}"
        )
        os.makedirs(local_folder, exist_ok=True)
        file_name = f"{date}-{hour}.json.gz"
        local_path = os.path.join(local_folder, file_name)

        r = requests.get(url, stream=True, timeout=60)
        if r.status_code == 404:
            raise AirflowSkipException(
                f"GHArchive file not yet published: {url}"
            )
        r.raise_for_status()

        with open(local_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)

        key = (
            f"gh_archive/year={year}/month={month:02d}"
            f"/day={day:02d}/hour={hour}/{file_name}"
        )
        S3Hook(aws_conn_id=AWS_CONN_ID).load_file(
            filename=local_path,
            key=key,
            bucket_name=RAW_BUCKET,
            replace=True,
        )
        os.remove(local_path)
        logging.info("Uploaded %s to s3://%s/%s", file_name, RAW_BUCKET, key)
        return job_params

    @task
    def submit_spark_job(job_params: dict) -> str:
        """Create a SparkApplication CRD and return its name for the wait task."""
        from kubernetes import client, config

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        run_id = str(int(time.time()))
        manifest = _build_spark_application(
            job_params["date"], job_params["hour"], run_id
        )
        app_name = manifest["metadata"]["name"]
        client.CustomObjectsApi().create_namespaced_custom_object(
            group="sparkoperator.k8s.io",
            version="v1beta2",
            namespace=SPARK_NAMESPACE,
            plural="sparkapplications",
            body=manifest,
        )
        logging.info("SparkApplication %s submitted", app_name)
        return app_name

    @task
    def wait_for_spark_job(app_name: str) -> None:
        """Poll until the SparkApplication reaches COMPLETED or FAILED state."""
        from kubernetes import client, config

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        custom_api = client.CustomObjectsApi()
        timeout, interval, elapsed = 1800, 30, 0

        while elapsed < timeout:
            obj = custom_api.get_namespaced_custom_object(
                group="sparkoperator.k8s.io",
                version="v1beta2",
                namespace=SPARK_NAMESPACE,
                plural="sparkapplications",
                name=app_name,
            )
            state = (
                obj.get("status", {})
                .get("applicationState", {})
                .get("state", "UNKNOWN")
            )
            logging.info("SparkApplication %s state: %s", app_name, state)
            if state == "COMPLETED":
                return
            if state == "FAILED":
                raise RuntimeError(f"SparkApplication {app_name} FAILED")
            time.sleep(interval)
            elapsed += interval

        raise TimeoutError(
            f"SparkApplication {app_name} did not finish within {timeout}s"
        )

    sync_raw_partition = SQLExecuteQueryOperator(
        task_id="sync_raw_partition",
        conn_id=TRINO_CONN_ID,
        sql=SYNC_RAW_PARTITIONS_SQL,
    )

    job_params = get_target_hour()
    ingested = ingest_hour(job_params)
    # After ingest: register the new partition in Trino (raw) and curate via
    # Spark in parallel — they don't depend on each other.
    ingested >> sync_raw_partition
    wait_for_spark_job(submit_spark_job(ingested))


gharchive_hourly_pipeline()
