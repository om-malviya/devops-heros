# kubernetes/ - raw manifests

Apply in order (or all at once with kustomize):

```bash
kubectl apply -k kubernetes/
# or
kubectl apply -f kubernetes/00-namespace.yaml
kubectl apply -f kubernetes/
kubectl -n taskboard get pods,svc,ingress,hpa,pvc
```

| File | Object | Notes |
|------|--------|-------|
| 00-namespace.yaml | Namespace `taskboard` | isolation |
| 01-configmap.yaml | ConfigMap | APP_NAME, APP_ENV, LOG_LEVEL, BACKEND_HOST/PORT, POSTGRES_DB |
| 02-secret.yaml | Secret (fake values) | POSTGRES_USER/PASSWORD, DATABASE_URL - see SECRETS.md |
| 03/04 | StatefulSet + PVC template + Services | PostgreSQL 16, 2Gi volume, pg_isready probes, runs as uid 70 with a read-only root FS (emptyDirs for /var/run/postgresql and /tmp) |
| 05/06 | Deployment + Service | backend, 2 replicas, startup/readiness/liveness probes, requests/limits, non-root, read-only root FS, drop ALL |
| 07/08 | Deployment + Service | frontend (nginx-unprivileged on 8080), service port 80, read-only root FS (emptyDirs for /tmp and /etc/nginx/conf.d) |
| 09-ingress.yaml | Ingress | host `taskboard.local`: `/api` -> backend:8000, `/` -> frontend:80 |
| 10-hpa.yaml | HPA | backend 2..6 replicas at 60 % CPU |

The Helm chart in `../helm/taskboard` renders the same objects with values per environment.

## Run on k3s (2026-10-08)

The cluster had Traefik instead of ingress-nginx and the images were in a local registry, so after the apply:

```bash
kubectl apply -k kubernetes/
kubectl -n taskboard set image deployment/taskboard-backend  backend=localhost:5002/taskboard-backend:local
kubectl -n taskboard set image deployment/taskboard-frontend frontend=localhost:5002/taskboard-frontend:local
kubectl -n taskboard patch ingress taskboard -p '{"spec":{"ingressClassName":"traefik"}}'
kubectl -n taskboard get pods,svc,ingress,hpa,pvc
```

```text
Output (captured 2026-10-08)
NAME                                      READY   STATUS    RESTARTS        AGE
pod/taskboard-backend-6db658b5f-2m82s     1/1     Running   0               77s
pod/taskboard-backend-6db658b5f-bw4kk     1/1     Running   4 (2m18s ago)   3m8s     <- started before Postgres was ready; alembic exited, kubelet restarted it
pod/taskboard-frontend-64b9ffd4fc-5sw6j   1/1     Running   0               2m58s
pod/taskboard-frontend-64b9ffd4fc-kklrt   1/1     Running   0               3m7s
pod/taskboard-postgres-0                  1/1     Running   0               3m9s
service/taskboard-backend             ClusterIP   10.43.253.57    <none>   8000/TCP
service/taskboard-frontend            ClusterIP   10.43.238.1     <none>   80/TCP
service/taskboard-postgres            ClusterIP   10.43.112.131   <none>   5432/TCP
service/taskboard-postgres-headless   ClusterIP   None            <none>   5432/TCP
ingress.networking.k8s.io/taskboard   traefik   taskboard.local   192.168.5.1   80
horizontalpodautoscaler.autoscaling/taskboard-backend   Deployment/taskboard-backend   cpu: 3%/60%   2   6   2
persistentvolumeclaim/data-taskboard-postgres-0   Bound   pvc-ef11743e-...   2Gi   RWO   local-path
$ kubectl -n taskboard exec deploy/taskboard-backend -- sh -c "id; touch /app/x"
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
touch: cannot touch '/app/x': Read-only file system
$ curl -s -H 'Host: taskboard.local' http://localhost/api/tasks/stats
{"total":1,"todo":1,"inProgress":0,"done":0}
```
