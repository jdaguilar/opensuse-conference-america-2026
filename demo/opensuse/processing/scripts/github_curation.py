import logging
import os
import sys
from datetime import datetime

from pyspark.sql import SparkSession
from pyspark.sql.functions import col, dayofmonth, month, to_timestamp, year

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


def main(date_str: str, hour: int) -> None:
    # SparkSession picks up spark-defaults.conf from the image:
    # S3A endpoint/credentials + iceberg HadoopCatalog (warehouse s3a://curated/)
    spark = SparkSession.builder.appName("GHArchiveCuration").getOrCreate()
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
        .withColumn("year", year("created_at"))
        .withColumn("month", month("created_at"))
        .withColumn("day", dayofmonth("created_at"))
    )

    spark.sql("CREATE NAMESPACE IF NOT EXISTS iceberg.curated")

    (
        curated.writeTo("iceberg.curated.github_events")
        .partitionedBy("year", "month", "day")
        .createOrReplace()
    )

    count = spark.read.table("iceberg.curated.github_events").count()
    log.info("Wrote %d rows to iceberg.curated.github_events", count)
    spark.stop()


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: github_curation.py <YYYY-MM-DD> <hour>", file=sys.stderr)
        sys.exit(1)
    main(sys.argv[1], int(sys.argv[2]))
