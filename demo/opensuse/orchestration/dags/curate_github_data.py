import logging
import os
import sys
from datetime import timedelta

import pendulum
from airflow.sdk import dag, task

SPARK_IMAGE = "localhost:5000/spark_processing:latest"
SPARK_NAMESPACE = "data-processing"
ARTIFACTS_BUCKET = "artifacts"

# S3A + Iceberg conf injected into every SparkApplication — mirrors spark-defaults.conf
SPARK_CONF = {
    "spark.hadoop.fs.s3a.impl": "org.apache.hadoop.fs.s3a.S3AFileSystem",
    "spark.hadoop.fs.s3a.endpoint": "http://ozone-s3g-rest.data-storage.svc.cluster.local:9878",
    "spark.hadoop.fs.s3a.access.key": "hadoop",
    "spark.hadoop.fs.s3a.secret.key": "ozone",
    "spark.hadoop.fs.s3a.path.style.access": "true",
    "spark.hadoop.fs.s3a.aws.credentials.provider": "org.apache.hadoop.fs.s3a.SimpleAWSCredentialsProvider",
    "spark.sql.extensions": "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions",
    "spark.sql.catalog.iceberg": "org.apache.iceberg.spark.SparkCatalog",
    "spark.sql.catalog.iceberg.type": "hadoop",
    "spark.sql.catalog.iceberg.warehouse": "s3a://curated/",
}


def _build_spark_application(date_str: str, hour: int, run_id: str) -> dict:
    """Return a SparkApplication manifest for a single date/hour partition."""
    # run_id makes the name unique per attempt so retries don't collide with
    # the driver pod left behind by a previous attempt.
    name = f"gh-curation-{date_str.replace('-', '')}-h{hour:02d}-{run_id}"
    return {
        "apiVersion": "sparkoperator.k8s.io/v1beta2",
        "kind": "SparkApplication",
        "metadata": {
            "name": name,
            "namespace": SPARK_NAMESPACE,
        },
        "spec": {
            "type": "Python",
            "pythonVersion": "3",
            "mode": "cluster",
            "image": SPARK_IMAGE,
            "imagePullPolicy": "Always",
            "mainApplicationFile": f"s3a://{ARTIFACTS_BUCKET}/scripts/github_curation.py",
            "arguments": [date_str, str(hour)],
            "sparkVersion": "4.0.0",
            "restartPolicy": {"type": "Never"},
            "sparkConf": SPARK_CONF,
            "driver": {
                "cores": 1,
                "memory": "2g",
                "serviceAccount": "spark",
                "labels": {"app": "gh-curation", "version": "1.0"},
                "annotations": {"kubernetes.io/description": "GHArchive curation Spark driver"},
            },
            "executor": {
                "cores": 1,
                "instances": 2,
                "memory": "2g",
                "labels": {"app": "gh-curation", "version": "1.0"},
                "annotations": {"kubernetes.io/description": "GHArchive curation Spark executor"},
            },
        },
    }


@dag(
    dag_id="curate_github_data",
    start_date=pendulum.datetime(2026, 4, 1, tz="UTC"),
    schedule="0 12 * * *",
    catchup=False,
    tags=["iceberg", "curation", "github", "spark"],
)
def curate_github_data():
    @task
    def get_date_and_hour(logical_date=None) -> dict:
        target = logical_date - timedelta(days=1)
        return {"date": target.strftime("%Y-%m-%d"), "hour": target.hour}

    @task
    def submit_spark_job(job_params: dict) -> str:
        """Create SparkApplication CRD and return its name for the wait task."""
        import time

        from kubernetes import client, config

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        run_id = str(int(time.time()))
        manifest = _build_spark_application(job_params["date"], job_params["hour"], run_id)
        app_name = manifest["metadata"]["name"]
        custom_api = client.CustomObjectsApi()

        custom_api.create_namespaced_custom_object(
            group="sparkoperator.k8s.io",
            version="v1beta2",
            namespace=SPARK_NAMESPACE,
            plural="sparkapplications",
            body=manifest,
        )
        logging.info("SparkApplication %s submitted to namespace %s", app_name, SPARK_NAMESPACE)
        return app_name

    @task
    def wait_for_spark_job(app_name: str) -> None:
        """Poll until the SparkApplication reaches COMPLETED or FAILED state."""
        import time

        from kubernetes import client, config

        try:
            config.load_incluster_config()
        except config.ConfigException:
            config.load_kube_config()

        name = app_name
        custom_api = client.CustomObjectsApi()
        timeout = 1800
        interval = 30
        elapsed = 0

        while elapsed < timeout:
            obj = custom_api.get_namespaced_custom_object(
                group="sparkoperator.k8s.io",
                version="v1beta2",
                namespace=SPARK_NAMESPACE,
                plural="sparkapplications",
                name=name,
            )
            state = obj.get("status", {}).get("applicationState", {}).get("state", "UNKNOWN")
            logging.info("SparkApplication %s state: %s", name, state)

            if state == "COMPLETED":
                return
            if state == "FAILED":
                raise RuntimeError(f"SparkApplication {name} FAILED")

            time.sleep(interval)
            elapsed += interval

        raise TimeoutError(f"SparkApplication {name} did not finish within {timeout}s")

    job_params = get_date_and_hour()
    wait_for_spark_job(submit_spark_job(job_params))


curate_github_data()
