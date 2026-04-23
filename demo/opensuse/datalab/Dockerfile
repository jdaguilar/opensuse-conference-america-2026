FROM quay.io/jupyter/all-spark-notebook:latest

# Must match the Hadoop version Spark was built against (spark/RELEASE: Hadoop 3.4.2)
ARG HADOOP_AWS_VERSION=3.4.2
# Versions pinned from hadoop-project-3.4.2.pom dependency management
ARG AWS_SDK_V2_VERSION=2.29.52
ARG AWS_SDK_V1_BUNDLE_VERSION=1.12.720
# Iceberg runtime for Spark 4.x (no 4.1 artifact exists — 4.0_2.13 covers Spark 4.x)
ARG ICEBERG_VERSION=1.10.1

USER root

# Remove JARs the base image ships (wrong versions) before adding the correct ones
RUN rm -f /usr/local/spark/jars/hadoop-aws*.jar* \
          /usr/local/spark/jars/aws-java-sdk*.jar* \
          /usr/local/spark/jars/bundle*.jar*

# hadoop-aws S3A connector — must match Spark's built Hadoop version (3.4.2)
RUN curl -fsSL \
    "https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_AWS_VERSION}/hadoop-aws-${HADOOP_AWS_VERSION}.jar" \
    -o /usr/local/spark/jars/hadoop-aws-${HADOOP_AWS_VERSION}.jar

# AWS SDK v2 bundle — version pinned from hadoop-project-3.4.2.pom
RUN curl -fsSL \
    "https://repo1.maven.org/maven2/software/amazon/awssdk/bundle/${AWS_SDK_V2_VERSION}/bundle-${AWS_SDK_V2_VERSION}.jar" \
    -o /usr/local/spark/jars/aws-sdk-v2-bundle-${AWS_SDK_V2_VERSION}.jar

# AWS SDK v1 bundle — kept for backward-compat codepaths in hadoop-aws
RUN curl -fsSL \
    "https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/${AWS_SDK_V1_BUNDLE_VERSION}/aws-java-sdk-bundle-${AWS_SDK_V1_BUNDLE_VERSION}.jar" \
    -o /usr/local/spark/jars/aws-java-sdk-bundle-${AWS_SDK_V1_BUNDLE_VERSION}.jar

# Iceberg Spark runtime — enables SparkSessionCatalog and IcebergSparkSessionExtensions
RUN curl -fsSL \
    "https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-4.0_2.13/${ICEBERG_VERSION}/iceberg-spark-runtime-4.0_2.13-${ICEBERG_VERSION}.jar" \
    -o /usr/local/spark/jars/iceberg-spark-runtime-4.0_2.13-${ICEBERG_VERSION}.jar

# S3A + Iceberg config applied to every SparkSession automatically
COPY spark-defaults.conf /usr/local/spark/conf/spark-defaults.conf

# Install AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp && \
    /tmp/aws/install && \
    rm -rf /tmp/awscliv2.zip /tmp/aws

# Install Python dependencies for Iceberg and object storage access
RUN pip install --no-cache-dir \
    pyiceberg[s3fs,hive,glue,duckdb,polars] \
    boto3 \
    duckdb

# Copy demo notebooks and scripts into the image
COPY scripts/ /home/jovyan/scripts/
RUN chmod +x /home/jovyan/scripts/*.sh && \
    chown -R ${NB_UID}:${NB_GID} /home/jovyan/scripts/

USER ${NB_UID}

WORKDIR /home/jovyan

# S3 credentials and endpoint are injected at runtime via Helm values (jupyterhub-values.yaml)
