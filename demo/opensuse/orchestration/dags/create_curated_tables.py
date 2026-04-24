import logging
import os
import sys

import pendulum
from airflow.providers.trino.operators.trino import TrinoOperator
from airflow.sdk import dag

log = logging.getLogger(__name__)

TRINO_CONN_ID = "trino_default"
CATALOG = "ozone_iceberg"
SCHEMA = "curated"

# Spark (HadoopCatalog, warehouse=s3a://curated/) writes the table to:
#   s3://curated/curated/github_events   (bucket=curated, key=curated/github_events/...)
# register_table makes it visible in the Hive Metastore so Trino can query it.
REGISTER_GITHUB_EVENTS = f"""
CALL {CATALOG}.system.register_table(
  schema_name    => '{SCHEMA}',
  table_name     => 'github_events',
  table_location => 's3://curated/curated/github_events'
)
"""


@dag(
    dag_id="create_curated_tables",
    start_date=pendulum.datetime(2025, 1, 1, tz="UTC"),
    schedule=None,
    catchup=False,
    tags=["iceberg", "setup", "ddl"],
)
def create_curated_tables():
    TrinoOperator(
        task_id="register_github_events",
        trino_conn_id=TRINO_CONN_ID,
        sql=REGISTER_GITHUB_EVENTS,
    )


create_curated_tables()
