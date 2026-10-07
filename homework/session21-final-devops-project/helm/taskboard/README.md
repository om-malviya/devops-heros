# helm/taskboard

Templates: ConfigMap, Secret (or `postgres.existingSecret`), PostgreSQL StatefulSet + PVC template + Services,
backend Deployment (startup/readiness/liveness probes, requests/limits, securityContext) + Service,
frontend Deployment + Service, Ingress, HPA, ServiceMonitor, PrometheusRule, NOTES.txt.

```bash
helm lint helm/taskboard
helm template taskboard helm/taskboard -f helm/taskboard/values-dev.yaml | less
helm upgrade --install taskboard helm/taskboard -n taskboard --create-namespace -f helm/taskboard/values-dev.yaml
helm upgrade --install taskboard helm/taskboard -n taskboard -f helm/taskboard/values-prod.yaml \
  --set backend.image.tag=$GIT_SHA --set frontend.image.tag=$GIT_SHA
helm history taskboard -n taskboard && helm rollback taskboard 1 -n taskboard
```

| values file | purpose |
|-------------|---------|
| `values.yaml` | defaults (2 replicas, HPA on, ingress off, chart-managed demo Secret, read-only root FS + drop ALL on every container) |
| `values-dev.yaml` | kind/minikube: 1 replica, ingress `taskboard.local`, HPA off, monitoring on |
| `values-prod.yaml` | EKS: 3 replicas, HPA 3..10, TLS ingress, gp3 20Gi, external Secret |

## Run on k3s (2026-10-08)

```text
Output (captured 2026-10-08)
$ helm install taskboard helm/taskboard -n taskboard --create-namespace -f helm/taskboard/values-dev.yaml \
    --set backend.image.repository=localhost:5002/taskboard-backend --set backend.image.tag=local \
    --set frontend.image.repository=localhost:5002/taskboard-frontend --set frontend.image.tag=local \
    --set ingress.className=traefik --wait --timeout 5m
NAME: taskboard   NAMESPACE: taskboard   STATUS: deployed   REVISION: 1   DESCRIPTION: Install complete
$ helm list -n taskboard
NAME        NAMESPACE   REVISION   UPDATED                                STATUS     CHART             APP VERSION
taskboard   taskboard   1          2026-10-08 03:01:42.198531 +0530 IST   deployed   taskboard-1.1.0   1.0.0
$ kubectl -n taskboard get pods
taskboard-taskboard-backend-7b5746d45d-f47vl    1/1   Running   3 (32s ago)   47s
taskboard-taskboard-frontend-79fdfc557c-2xknz   1/1   Running   0             47s
taskboard-taskboard-postgres-0                  1/1   Running   0             47s
$ helm upgrade taskboard helm/taskboard -n taskboard -f helm/taskboard/values-dev.yaml <same --set flags> --set backend.replicaCount=2 --wait
Release "taskboard" has been upgraded. Happy Helming!      REVISION: 2
$ helm history taskboard -n taskboard
1   Thu Oct  8 03:01:42 2026   superseded   taskboard-1.1.0   1.0.0   Install complete
2   Thu Oct  8 03:02:34 2026   deployed     taskboard-1.1.0   1.0.0   Upgrade complete
$ helm rollback taskboard 1 -n taskboard --wait
Rollback was a success! Happy Helming!
$ helm history taskboard -n taskboard
1   superseded   Install complete
2   superseded   Upgrade complete
3   deployed     Rollback to 1
$ helm uninstall taskboard -n taskboard
release "taskboard" uninstalled
```

`--set ingress.className=traefik` and the `localhost:5002` image overrides are local-cluster adaptations; on EKS with
ingress-nginx and GHCR the values files apply unchanged.
