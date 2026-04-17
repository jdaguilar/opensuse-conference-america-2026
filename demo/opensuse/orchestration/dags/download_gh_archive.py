from airflow import DAG
from airflow.decorators import task
from airflow.providers.amazon.aws.hooks.s3 import S3Hook
from airflow.macros import ds_add

import os
import requests
from datetime import datetime

# ---- CONFIG ----
AWS_CONN_ID = "ozone"   # Airflow connection to Ozone S3 gateway
BUCKET_NAME = "raw"

# ---- DAG ----
with DAG(
    dag_id="gharchive_to_ozone",
    start_date=datetime(2025, 1, 1),
    schedule="0 10 * * *",   # run daily at 10:00
    catchup=False,
    tags=["gharchive"],
) as dag:

    # ---- Get execution date (yesterday is typical for GH Archive) ----
    @task
    def get_date(ds=None):
        return ds_add(ds, -1)

    # ---- Generate 24 hours ----
    @task
    def generate_hours():
        return list(range(24))

    # ---- Process one hour ----
    @task(retries=1, retry_delay=60)
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

        # ---- Download ----
        response = requests.get(url, stream=True)
        if response.status_code == 404:
            # GH Archive sometimes misses hours — skip safely
            print(f"Missing file: {url}")
            return "missing"

        if response.status_code != 200:
            raise Exception(f"Failed to download {url}")

        with open(local_path, "wb") as f:
            for chunk in response.iter_content(chunk_size=8192):
                f.write(chunk)

        # ---- Upload to Ozone (S3-compatible) ----
        s3_key = f"gh_archive/year={year}/month={month}/day={day}/hour={hour}/{file_name}"

        hook = S3Hook(aws_conn_id=AWS_CONN_ID)
        hook.load_file(
            filename=local_path,
            key=s3_key,
            bucket_name=BUCKET_NAME,
            replace=True,
        )

        # ---- Cleanup (important in Airflow workers) ----
        os.remove(local_path)

        return f"uploaded {s3_key}"

    # ---- DAG wiring ----
    date_value = get_date()
    hours = generate_hours()

    process_hour.expand(
        hour=hours,
        date=date_value
    )