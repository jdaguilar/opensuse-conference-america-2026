# OpenSUSE Data Platform Troubleshooting Guide

## Common Issues and Solutions

### 1. Airflow Pods CrashLoopBackOff — git-sync Cannot Resolve github.com

**Symptoms**: `airflow-scheduler`, `airflow-dag-processor`, and/or `airflow-triggerer` stuck in
`CrashLoopBackOff` with only 2/3 containers ready. The crashing container is `git-sync`.

**Diagnosis**:
```bash
# Confirm git-sync is the failing container
kubectl logs airflow-scheduler-0 -n data-orchestration -c git-sync --tail=20

# Expected error line:
# "too many failures, aborting" "Could not resolve host: github.com"

# Confirm CoreDNS is returning REFUSED
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it -- nslookup github.com
# Returns "REFUSED" → CoreDNS upstream is broken
```

**Root cause**: CoreDNS `forward . /etc/resolv.conf` cannot reach the host's upstream DNS resolver
from inside the cluster network.

**Fix**:
```bash
# 1. Patch CoreDNS to use public DNS resolvers
kubectl patch configmap coredns -n kube-system --type merge -p \
  '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n      pods insecure\n      fallthrough in-addr.arpa ip6.arpa\n    }\n    hosts /etc/coredns/NodeHosts {\n      ttl 60\n      reload 15s\n      fallthrough\n    }\n    prometheus :9153\n    forward . 8.8.8.8 8.8.4.4\n    cache 30\n    loop\n    reload\n    loadbalance\n    }\n"}}'

# 2. Restart CoreDNS
kubectl rollout restart deployment/coredns -n kube-system
kubectl rollout status deployment/coredns -n kube-system --timeout=60s

# 3. Verify DNS works from a pod
kubectl run dns-test --image=busybox:1.36 --restart=Never --rm -it -- nslookup github.com
# Should return an IP address

# 4. Restart the Airflow pods
kubectl rollout restart deployment/airflow-dag-processor -n data-orchestration
kubectl delete pod airflow-scheduler-0 -n data-orchestration
```

**Persistence**: This patch is lost if the cluster is recreated. To make it permanent, edit
`/var/lib/rancher/k3s/server/manifests/coredns.yaml` on the host before starting K3s.

---

### 2. Spark Operator: SparkApplication Stuck in UNKNOWN State

**Symptoms**: `wait_for_spark_job` task logs show `state: UNKNOWN` forever. No driver or executor
pods appear in the `data-processing` namespace.

**Diagnosis**:
```bash
kubectl logs -n spark-operator deployment/spark-operator-controller --tail=5 | grep namespaces
# Bad: --namespaces=default   Good: --namespaces=data-processing
```

**Root cause**: Old values key `sparkJobNamespace` is silently ignored in spark-operator v2.x.

**Fix**:
```yaml
# demo/opensuse/processing/spark-operator-values.yaml
spark:
  jobNamespaces:
    - data-processing
```
```bash
helm upgrade spark-operator spark-operator/spark-operator \
  -n spark-operator -f demo/opensuse/processing/spark-operator-values.yaml
```

---

### 3. Spark Driver: Exit Code 127 — `driver: not found`

**Symptoms**: Driver pod exits immediately. Logs show:
```
/usr/local/bin/start.sh: line 259: exec: driver: not found
```

**Root cause**: The SparkApplication was pointed at the JupyterHub notebook image. Its entrypoint
(`start.sh`) does not handle the `driver`/`executor` subcommands that the Spark Operator passes.

**Fix**: Use `localhost:5000/spark_processing:latest` (built from
`demo/opensuse/processing/Dockerfile.spark`, base `apache/spark:4.0.0`). Rebuild after changes:
```bash
cd demo/opensuse/processing
docker build -f Dockerfile.spark -t localhost:5000/spark_processing:latest .
docker push localhost:5000/spark_processing:latest
```

---

### 4. Spark Driver: `NoSuchMethodError: ConfigurationHelper.resolveEnum`

**Symptoms**: Driver fails during S3A filesystem initialization:
```
java.lang.NoSuchMethodError: 'java.lang.Enum org.apache.hadoop.util.ConfigurationHelper.resolveEnum(...)'
```

**Root cause**: `apache/spark:4.0.0` bundles `hadoop-client-runtime-3.4.1`. Using
`hadoop-aws-3.4.2.jar` calls a method only available in Hadoop 3.4.2+.

**Fix**: Pin JARs to match `hadoop-project-3.4.1.pom` (already correct in `Dockerfile.spark`):

| JAR | Version |
|-----|---------|
| hadoop-aws | 3.4.1 |
| aws-sdk-v2 bundle | 2.24.6 |
| aws-java-sdk-bundle | 1.12.720 |

To find the right versions for a different base image:
```bash
docker run --rm apache/spark:<tag> ls /opt/spark/jars/ | grep hadoop-client-runtime
# Then check: https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-project/<ver>/hadoop-project-<ver>.pom
```

---

### 5. Spark Driver: 403 Forbidden on Pod/ConfigMap/Service Operations

**Symptoms**: Driver logs show:
```
pods is forbidden: User "system:serviceaccount:data-processing:spark" cannot create resource "pods"
configmaps is forbidden: ... cannot deletecollection resource "configmaps"
```

**Root cause**: `spark-role` was missing the `deletecollection` verb. Spark bulk-deletes executor
resources using label-selector DELETE calls which require `deletecollection`.

**Fix**:
```bash
kubectl apply -f demo/opensuse/processing/rbac.yaml
```

---

### 6. Superset: Redis or PostgreSQL Pods in ImagePullBackOff

**Symptoms**: `superset-redis-master-0` or `superset-postgresql-0` stuck with `ImagePullBackOff`.

**Root cause**: Bitnami removed old pinned tags from Docker Hub. The Helm chart's default tags
no longer exist.

**Fix** in `bi/superset-values.yaml`:
```yaml
postgresql:
  image:
    tag: latest
redis:
  image:
    tag: latest
```

---

### 7. Superset: `ModuleNotFoundError: No module named 'psycopg2'`

**Symptoms**: All Superset pods crash on startup with this error even after adding `psycopg2-binary`
to the Dockerfile.

**Root cause**: `apache/superset:5.0.0` uses a virtualenv at `/app/.venv`. The venv has no `pip`
binary. The system `pip` installs to the wrong Python location.

**Fix** in `bi/Dockerfile`:
```dockerfile
RUN pip install --no-cache-dir \
    --target /app/.venv/lib/python3.10/site-packages \
    psycopg2-binary sqlalchemy-trino trino[sqlalchemy]
```

---

### 8. Hive Metastore: `No suitable driver` (Missing PostgreSQL JDBC)

**Symptoms**: Hive Metastore crashes with `java.sql.SQLException: No suitable driver`.

**Root cause**: `apache/hive:4.0.0` does not include the PostgreSQL JDBC driver.

**Fix**: Already in `catalog/Dockerfile.hive-metastore`. Rebuild if needed:
```bash
cd demo/opensuse/catalog
docker build -f Dockerfile.hive-metastore -t localhost:5000/hive-metastore:4.0.0 .
docker push localhost:5000/hive-metastore:4.0.0
kubectl rollout restart deployment/hive-metastore -n data-query
```

---

### 9. Hive Metastore: `Version information not found in metastore`

**Symptoms**: Metastore pod CrashLoopBackOff with:
```
MetaException(message:Version information not found in metastore.)
```

**Root cause**: `datanucleus.schema.autoCreateAll=true` creates DB tables but does not insert the
Hive schema version record. On restart, Hive validates this record and fails.

**Fix**: `JAVA_TOOL_OPTIONS=-Dhive.metastore.schema.verification=false` is baked into the image
via `ENV` in `Dockerfile.hive-metastore`. If the PostgreSQL DB is corrupted, reset it:
```bash
kubectl delete statefulset hive-metastore-postgresql -n data-query
kubectl delete pvc data-hive-metastore-postgresql-0 -n data-query
kubectl apply -f demo/opensuse/catalog/hive-metastore.yaml
kubectl rollout restart deployment/hive-metastore -n data-query
```

---

### 10. Service Fails to Start

**Symptoms**: Pod stuck in "Pending" or "CrashLoopBackOff" state

**Solutions**:
```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod for error details
kubectl describe pod <pod-name> -n <namespace>

# Check resource requests vs limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Resources"
```

**Common Fixes**:
- Increase memory limits if OOMKilled
- Reduce CPU requests if scheduling issues
- Check image pull secrets if image not found

### 11. UI Not Accessible

**Symptoms**: Browser shows connection refused or timeout

**Solutions**:
```bash
# Check ingress status
kubectl get ingress -n <namespace>

# Verify service endpoints
kubectl get endpoints -n <namespace>

# Check service configuration
kubectl describe service <service-name> -n <namespace>
```

**Common Fixes**:
- Verify ingress controller is running
- Check TLS certificate configuration
- Ensure service port matches target port

### 12. High Memory Usage

**Symptoms**: System slow, pods being OOM killed

**Solutions**:
```bash
# Monitor memory usage
kubectl top pods -n <namespace>

# Check memory requests vs actual usage
kubectl describe nodes | grep -A 10 "Allocated resources"
```

**Common Fixes**:
- Reduce memory limits for non-critical services
- Stop unused components
- Add swap space temporarily
- Scale down replica counts

### 13. Data Not Loading

**Symptoms**: Services running but no data visible

**Solutions**:
```bash
# Check data ingestion logs
kubectl logs -n data-ingestion -l app=airbyte

# Verify storage connectivity
kubectl exec -it -n data-storage <ozone-pod> -- sh -c "ls -la /data"

# Check database connectivity
kubectl exec -it -n data-query <trino-pod> -- trino --execute "SHOW SCHEMAS"
```

**Common Fixes**:
- Verify storage class availability
- Check network policies
- Ensure data source is accessible
- Run sample data loading script

### 14. Slow Performance

**Symptoms**: Queries taking long, UI sluggish

**Solutions**:
```bash
# Check query execution time
kubectl logs -n data-query <trino-pod> | grep "Query"

# Monitor CPU usage
kubectl top pods -n <namespace> --containers

# Check disk I/O
kubectl top pods -n data-storage
```

**Common Fixes**:
- Increase memory limits for query engines
- Add more worker nodes
- Optimize queries
- Enable query caching

## Emergency Procedures

### Stop All Services
```bash
# Quick teardown
bash /demo/opensuse/demo-control/teardown.sh

# Or delete specific namespaces
kubectl delete namespace data-ingestion
kubectl delete namespace data-query
```

### Restart Failed Components
```bash
# Restart specific deployment
kubectl rollout restart deployment/<deployment-name> -n <namespace>

# Clear stuck pods
kubectl delete pod <pod-name> -n <namespace> --grace-period=0 --force
```

### Free Up Resources
```bash
# Delete old logs
kubectl logs --tail=100 -n <namespace> | grep -v "INFO"

# Clean up unused images
docker system prune -f

# Remove old PVCs
kubectl get pvc --all-namespaces | grep "Released" | awk '{print $2}' | xargs kubectl delete pvc
```

## Diagnostic Commands

### Check All Services
```bash
# List all deployments
kubectl get deployments --all-namespaces

# List all pods
kubectl get pods --all-namespaces

# List all services
kubectl get services --all-namespaces
```

### Monitor Resource Usage
```bash
# Real-time pod resource usage
kubectl top pods --all-namespaces

# Node resource usage
kubectl top nodes

# Memory usage by namespace
kubectl get pods --all-namespaces -o json | jq '.items[] | {name: .metadata.name, namespace: .metadata.namespace, cpu: .status.conditions[].cpu, memory: .status.conditions[].memory}'
```

### Check Logs
```bash
# All logs for a namespace
kubectl logs --all-containers=true -n <namespace>

# Follow logs in real-time
kubectl logs -f <pod-name> -n <namespace>

# Previous container logs (for restarts)
kubectl logs --previous <pod-name> -n <namespace>
```

## Performance Benchmarks

### Expected Performance
- **Startup Time**: 5-10 minutes for full deployment
- **Query Response**: < 5 seconds for simple queries
- **Data Ingestion**: 100-500 records/second
- **UI Response**: < 2 seconds for page loads

### Resource Usage Targets
- **Memory**: < 28GB for all services
- **CPU**: < 8 cores total
- **Storage**: < 30GB for demo data

## Common Configuration Errors

### 1. Incorrect Hostnames
**Error**: Services can't connect to each other
**Fix**: Verify all service URLs in config files match service names

### 2. Port Conflicts
**Error**: Services fail to bind to ports
**Fix**: Check for existing services using same ports
```bash
kubectl get services --all-namespaces | grep "<port>"
```

### 3. Storage Class Issues
**Error**: PVCs stuck in "Pending" state
**Fix**: Verify storage class exists
```bash
kubectl get storageclass
kubectl describe storageclass <storage-class-name>
```

### 4. Network Policies
**Error**: Services can't communicate
**Fix**: Check network policy configurations
```bash
kubectl get networkpolicies --all-namespaces
kubectl describe networkpolicy <policy-name> -n <namespace>
```

## Recovery Procedures

### Complete Recovery
1. Stop all services
2. Delete all namespaces
3. Clean up persistent volumes
4. Restart deployment

### Partial Recovery
1. Identify failed component
2. Delete specific deployment
3. Recreate with corrected configuration
4. Verify connectivity

## Support Resources

### Log Locations
- **Application Logs**: `/var/log/containers/`
- **Kubernetes Events**: `kubectl get events --all-namespaces`
- **System Logs**: `journalctl -u kubelet`

### Health Endpoints
- **Prometheus**: `http://grafana.localhost`
- **Grafana**: `http://grafana.localhost`
- **Service Status**: Check individual service UIs

## Prevention Best Practices

### Before Demo
- Test all components individually
- Verify resource limits
- Check network connectivity
- Backup configuration files

### During Demo
- Monitor resource usage
- Have recovery procedures ready
- Keep terminal access open
- Document any issues

### After Demo
- Clean up all resources
- Reset passwords
- Review logs for issues
- Update documentation