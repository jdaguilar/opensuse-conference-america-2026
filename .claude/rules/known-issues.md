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
