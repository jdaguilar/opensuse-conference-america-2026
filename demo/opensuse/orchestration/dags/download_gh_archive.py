from airflow import DAG
from airflow.decorators import task
from airflow.utils.dates import days_ago
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

import os
import requests
from datetime import datetime

MINIO_PROFILE_NAME = "ozone"  # your Airflow connection ID
BUCKET_NAME = "raw"

default_args = {
    "owner": "data-eng",
}

with DAG(
    dag_id="gharchive_to_ozone",
    start_date=days_ago(1),
    schedule=None,  # trigger manually with date params
    catchup=False,
    default_args=default_args,
    tags=["gharchive"],
) as dag:

    @task
    def generate_hours():
        return list(range(24))

    @task
    def process_hour(date: str, hour: int):
        dt = datetime.strptime(date, "%Y-%m-%d")
        year = dt.strftime("%Y")
        month = dt.strftime("%m")
        day = dt.strftime("%d")

        url = f"http://data.gharchive.org/{date}-{hour}.json.gz"

        local_folder = f"/tmp/gh_archive/year={year}/month={month}/day={day}/hour={hour}"
        os.makedirs(local_folder, exist_ok=True)

        file_name = f"{date}-{hour}.json.gz"
        local_path = os.path.join(local_folder, file_name)

        # Download
        r = requests.get(url, stream=True)
        if r.status_code != 200:
            raise Exception(f"Failed to download {url}")

        with open(local_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)

        # Upload to Ozone (via S3 API)
        s3_key = f"gh_archive/year={year}/month={month}/day={day}/hour={hour}/{file_name}"

        hook = S3Hook(aws_conn_id=MINIO_PROFILE_NAME)
        hook.load_file(
            filename=local_path,
            key=s3_key,
            bucket_name=BUCKET_NAME,
            replace=True,
        )

        return f"Uploaded {s3_key}"

    # DAG wiring
    hours = generate_hours()
    process_hour.expand(
        hour=hours,
        date=["{{ dag_run.conf['date'] }}"] * 24
    )