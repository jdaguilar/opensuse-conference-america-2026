"""Hourly GHArchive curation.

Reads s3a://raw/gh_archive/year=Y/month=M/day=D/hour=H/*.json.gz for one
specific hour and writes Iceberg-partitioned data to
iceberg.curated.github_events_hourly partitioned by (year, month, day, hour).

Partition values come from the file's date/hour args (lit()) — not from
the events' created_at — so re-runs of the same hour are deterministic and
overwritePartitions() touches exactly one partition.
"""

import logging
import os
import sys
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, lit, to_timestamp

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

TABLE_NAME = "iceberg.curated.github_events_hourly"


def main(date_str: str, hour: int) -> None:
    spark = (
        SparkSession.builder.appName("GHArchiveHourlyCuration").getOrCreate()
    )
    spark.sparkContext.setLogLevel("WARN")

    dt = datetime.strptime(date_str, "%Y-%m-%d")
    path = (
        f"s3a://raw/gh_archive/"
        f"year={dt.year}/month={dt.month:02d}"
        f"/day={dt.day:02d}/hour={hour}/*.json.gz"
    )

    log.info("Reading raw data from %s", path)
    df = spark.read.json(path)

    if df.rdd.isEmpty():
        log.warning("No data found at %s — skipping.", path)
        spark.stop()
        return

    curated = (
        df.select(
            col("id"),
            col("type"),
            col("actor.login").alias("actor"),
            col("repo.name").alias("repo"),
            to_timestamp(col("created_at")).alias("created_at"),
        )
        .withColumn("year", lit(dt.year))
        .withColumn("month", lit(dt.month))
        .withColumn("day", lit(dt.day))
        .withColumn("hour", lit(hour))
    )

    spark.sql("CREATE NAMESPACE IF NOT EXISTS iceberg.curated")

    if spark.catalog.tableExists(TABLE_NAME):
        log.info(
            "Table %s exists — overwriting partition (y=%d, m=%d, d=%d, h=%d)",
            TABLE_NAME, dt.year, dt.month, dt.day, hour,
        )
        curated.writeTo(TABLE_NAME).overwritePartitions()
    else:
        log.info("Table %s does not exist — creating", TABLE_NAME)
        (
            curated.writeTo(TABLE_NAME)
            .partitionedBy("year", "month", "day", "hour")
            .create()
        )

    count = spark.read.table(TABLE_NAME).count()
    log.info("Total rows in %s: %d", TABLE_NAME, count)
    spark.stop()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(
            "Usage: github_curation_hourly.py <YYYY-MM-DD> <hour>",
            file=sys.stderr,
        )
        sys.exit(1)
    main(sys.argv[1], int(sys.argv[2]))
