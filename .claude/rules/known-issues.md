# Known Issues & Fixes

## CoreDNS: external DNS resolution fails inside the cluster

**Symptom**: Pods cannot resolve public hostnames (e.g. `github.com`). CoreDNS returns `REFUSED`.
Affects git-sync sidecars in Airflow pods, causing `CrashLoopBackOff` with:
```
fatal: unable to access '...': Could not resolve host: github.com
```

**Root cause**: The default CoreDNS configmap uses `forward . /etc/resolv.conf`. On this host the
upstream resolver reported in `/etc/resolv.conf` is not reachable from inside the cluster network.

**Fix** (applied 2026-04-23): Patch the CoreDNS configmap to forward to public resolvers, then
restart CoreDNS:
```bash
kubectl patch configmap coredns -n kube-system --type merge -p \
  '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    hosts /etc/coredns/NodeHosts {\n      ttl 60\n      reload 15s\n      fallthrough\n    }\n    prometheus :9153\n    forward . 8.8.8.8 8.8.4.4\n    cache 30\n    loop\n    reload\n    loadbalance\n    }\n"}}'

kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s
```

**Verify**:
```bash
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it -- nslookup github.com
# Should return an IP, not REFUSED
```

**After the fix**: restart any pods that were in CrashLoopBackOff due to this DNS issue:
```bash
kubectl rollout restart deployment/airflow-dag-processor -n data-orchestration
kubectl delete pod airflow-scheduler-0 -n data-orchestration
```

**Note**: This patch is not persistent across cluster recreations. If the cluster is torn down and
rebuilt, reapply the patch or bake it into the K3s CoreDNS configuration file at
`/var/lib/rancher/k3s/server/manifests/coredns.yaml` before starting K3s.

---

## Airflow: reserved `params` argument name in `@task`

**Symptom**: `ValueError: The key 'params' in args is a part of kwargs and therefore reserved.`

**Root cause**: `params` is a reserved Airflow context key. Using it as a `@task` function argument
causes Airflow 3 to raise a ValueError at runtime.

**Fix**: Rename any `params` argument to something else (e.g. `job_params`). Already applied in
`curate_github_data.py`.

---

## Airflow: deprecated imports from `airflow.decorators`

**Symptom**: `DeprecatedImportWarning: The 'airflow.decorators.dag' attribute is deprecated.`

**Fix**: Use `from airflow.sdk import dag, task` instead of `from airflow.decorators import dag, task`.

---

## Spark Operator: SparkApplication stuck in UNKNOWN state

**Symptom**: `wait_for_spark_job` logs show `state: UNKNOWN` indefinitely. No driver or executor
pods are created in `data-processing`.

**Root cause**: `spark-operator-values.yaml` used the old key `sparkJobNamespace: data-processing`
which is silently ignored in spark-operator v2.x. The operator started with `--namespaces=default`.

**Fix**: Use the correct v2.x key in `demo/opensuse/processing/spark-operator-values.yaml`:
```yaml
spark:
  jobNamespaces:
    - data-processing
```
Then: `helm upgrade spark-operator spark-operator/spark-operator -n spark-operator -f ...`

**Verify**: `--namespaces=data-processing` must appear in the controller deployment args.

---

## Spark driver: exit code 127 — `driver: not found`

**Symptom**: Driver pod exits with code 127:
```
/usr/local/bin/start.sh: line 259: exec: driver: not found
```

**Root cause**: The SparkApplication was using the JupyterHub notebook image whose entrypoint
(`start.sh`) does not understand `driver`/`executor` subcommands from the Spark Operator.

**Fix**: Use the dedicated processing image built from `demo/opensuse/processing/Dockerfile.spark`
(base: `apache/spark:4.0.0` which has the correct `/opt/entrypoint.sh`). The DAG constant
`SPARK_IMAGE = "localhost:5000/spark_processing:latest"`.

---

## Spark driver: `NoSuchMethodError: ConfigurationHelper.resolveEnum`

**Symptom**: Driver fails at S3A initialization:
```
java.lang.NoSuchMethodError: 'java.lang.Enum org.apache.hadoop.util.ConfigurationHelper.resolveEnum(...)'
```

**Root cause**: `apache/spark:4.0.0` bundles `hadoop-client-runtime-3.4.1`. Using
`hadoop-aws-3.4.2.jar` calls a method added in Hadoop 3.4.2 that does not exist in 3.4.1.

**Fix**: Pin JARs to match `hadoop-project-3.4.1.pom`:
- `hadoop-aws`: `3.4.1`
- `aws-sdk-v2 bundle`: `2.24.6`
- `aws-sdk-v1 bundle`: `1.12.720`

**How to find correct versions for a different Spark base image**:
```bash
docker run --rm apache/spark:<tag> ls /opt/spark/jars/ | grep hadoop-client-runtime
# Then fetch: https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-project/<ver>/hadoop-project-<ver>.pom
```

---

## Spark driver: 403 Forbidden on pod/configmap/service operations

**Symptom**: Driver pod fails with:
```
pods is forbidden: ... cannot create resource "pods" in API group "" in the namespace "data-processing"
configmaps is forbidden: ... cannot deletecollection resource "configmaps"
```

**Root cause**: `spark-role` in `demo/opensuse/processing/rbac.yaml` was missing the
`deletecollection` verb. Spark driver bulk-deletes executor resources using label-selector DELETE
calls, which require `deletecollection`, not just `delete`.

**Fix**: `deletecollection` is now in the role. Re-apply: `kubectl apply -f demo/opensuse/processing/rbac.yaml`

---

## Airflow retry creates duplicate driver pod name

**Symptom**: Airflow retry of `submit_spark_job` fails because `{app-name}-driver` pod from the
previous attempt still exists.

**Root cause**: `_build_spark_application` generated the name from `date + hour` only, producing
the same name on every retry of the same DAG run.

**Fix** (in `curate_github_data.py`): `submit_spark_job` now appends a Unix epoch timestamp to the
app name (`gh-curation-YYYYMMDD-hHH-{epoch}`) and returns it as a string. `wait_for_spark_job`
accepts the name directly via XCom.

---

## Superset: Bitnami sub-chart image tags missing from Docker Hub

**Symptom**: `superset-redis-master-0` or `superset-postgresql-0` stuck in `ImagePullBackOff`.

**Root cause**: Bitnami stopped hosting old pinned image tags on Docker Hub. The Helm chart's
default pinned tags (e.g. `7.0.10-debian-11-r4`) no longer exist.

**Fix**: Override both sub-chart images to `tag: latest` in `bi/superset-values.yaml`:
```yaml
postgresql:
  image:
    tag: latest
redis:
  image:
    tag: latest
```

---

## Superset: `ModuleNotFoundError: No module named 'psycopg2'`

**Symptom**: All Superset pods crash with `No module named 'psycopg2'` despite it being installed.

**Root cause**: `apache/superset:5.0.0` runs inside `/app/.venv`. The venv has no `pip` binary,
only `python`. Installing with the system `pip` puts packages in the wrong location.

**Fix**: Install directly into the venv's site-packages:
```dockerfile
RUN pip install --no-cache-dir \
    --target /app/.venv/lib/python3.10/site-packages \
    psycopg2-binary sqlalchemy-trino trino[sqlalchemy]
```

---

## Superset worker OOMKilled

**Symptom**: `superset-worker` pod in CrashLoopBackOff, exit code 137 (OOMKilled).

**Root cause**: Celery defaults to 8 prefork workers, exceeding the 512Mi memory limit.

**Fix** in `bi/superset-values.yaml`: pin concurrency to 2 and raise limit to 1Gi:
```yaml
supersetWorker:
  command:
    - "/bin/sh"
    - "-c"
    - ". /app/.venv/bin/activate && celery --app=superset.tasks.celery_app:app worker --concurrency=2 -Ofair -l INFO"
  resources:
    limits:
      memory: 1Gi
```

---

## Hive Metastore: `No module named 'psycopg2'` / `No suitable driver`

**Symptom**: Hive Metastore fails with `java.sql.SQLException: No suitable driver`.

**Root cause**: `apache/hive:4.0.0` does not include the PostgreSQL JDBC driver.

**Fix**: Add to `demo/opensuse/catalog/Dockerfile.hive-metastore`:
```dockerfile
RUN wget -q "https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar" \
    -O /opt/hive/lib/postgresql-42.7.4.jar
```

---

## Hive Metastore: `Version information not found in metastore`

**Symptom**: Metastore crashes with `MetaException: Version information not found in metastore`.

**Root cause**: DataNucleus `autoCreateAll=true` creates the tables but does not insert the schema
version record that Hive validates on startup.

**Fix**: Bake `JAVA_TOOL_OPTIONS=-Dhive.metastore.schema.verification=false` into the image via
the Dockerfile `ENV` directive. This bypasses the version check permanently regardless of ConfigMap
values. Already applied in `Dockerfile.hive-metastore`.

---

## Hive Metastore: `curl: not found` / `wget: not found` during image build

**Symptom**: Dockerfile build fails with `curl: not found` or `wget: not found` at exit code 127.

**Root cause**: `apache/hive:4.0.0` is Ubuntu-based but ships without `curl` or `wget`.

**Fix**: Install `wget` before downloading JARs:
```dockerfile
RUN apt-get update -qq && apt-get install -y --no-install-recommends wget && rm -rf /var/lib/apt/lists/*
```
