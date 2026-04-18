from airflow import DAG
from airflow.sdk import task
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

import os
import requests
from datetime import datetime, timedelta

AWS_CONN_ID = "ozone"
BUCKET_NAME = "raw"

with DAG(
    dag_id="gharchive_to_ozone",
    start_date=datetime(2025, 1, 1),
    schedule="0 10 * * *",
    catchup=False,
    tags=["gharchive"],
) as dag:

    @task
    def get_date(logical_date=None):
        return (logical_date - timedelta(days=1)).strftime("%Y-%m-%d")

    @task
    def generate_hours():
        return list(range(24))

    @task(retries=3, retry_delay=timedelta(minutes=1))
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

        if r.status_code == 404:
            print(f"Missing: {url}")
            return

        if r.status_code != 200:
            raise Exception(f"Failed: {url}")

        with open(local_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                f.write(chunk)

        # Upload
        key = f"gh_archive/year={year}/month={month}/day={day}/hour={hour}/{file_name}"

        hook = S3Hook(aws_conn_id=AWS_CONN_ID)
        hook.load_file(
            filename=local_path,
            key=key,
            bucket_name=BUCKET_NAME,
            replace=True,
        )

        os.remove(local_path)

    # ---- wiring ----
    date_value = get_date()
    hours = generate_hours()

    process_hour.partial(
        date=date_value   # ✅ constant (not mapped)
    ).expand(
        hour=hours        # ✅ mapped
    )