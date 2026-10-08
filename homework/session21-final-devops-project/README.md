# Session 21 – Final DevOps Project & Troubleshooting
Student: Om Malviya | Enrollment No: 24BCS10448

This folder is my end-to-end capstone: the **TaskBoard** application (React + FastAPI + PostgreSQL) carried from a
laptop through Git, CI, security gates, container registry, Terraform-provisioned EKS, Helm, monitoring and GitOps,
plus a troubleshooting challenge with six intentionally broken manifests.

The README is organised by the Tasks of the spec; the fifteen sections the spec requires for the final README are
the `###` headings inside them:

| Required section | Where |
|------------------|-------|
| Project overview, Architecture diagram, Technologies used, Application setup, Docker setup | Task 1 |
| Terraform infrastructure | Task 2 |
| Kubernetes deployment, Helm deployment | Task 3 |
| CI/CD pipeline | Task 4 |
| DevSecOps implementation | Task 5 |
| Monitoring, GitOps | Task 6 |
| Troubleshooting | Task 7 |
| Screenshots, Lessons learned | Task 8 |

Validation happened in two passes on this machine (macOS arm64). The first pass had no Docker daemon and no
cluster: pytest, ruff, bandit, pip-audit, the Vite build, `helm lint`/`helm template`, `terraform init/validate` and
`kubectl kustomize`. The second pass (2026-10-08) had a Docker daemon (Colima) and a single-node k3s cluster
(Traefik ingress, `local-path` StorageClass, metrics-server) shared with other work, so the Compose stack, every
security gate, the raw-manifest and Helm deployments, kube-prometheus-stack, Argo CD and all six troubleshooting
scenarios ran for real. Two local adaptations apply wherever a cluster command appears below: the images were
served from a local registry (`localhost:5002/...`) because nothing has been pushed to GHCR yet, and the Ingress
class was `traefik` instead of `nginx`. Only GitHub Actions/GHCR and AWS/EKS stay labelled **Expected output**
(no push to GitHub yet, no AWS account).

---

## Task 1: Application (frontend, backend, PostgreSQL, tests, Docker)

### Project overview

TaskBoard is a small task-management SaaS: a dashboard with KPI cards, a task table with status filters, priority
badges and a create-task modal. The backend is a FastAPI service with six REST endpoints over a `tasks` table that
Alembic migrates. The DevOps layer is the point of the project: every change travels

```text
Application -> Git -> GitHub -> CI pipeline -> Build & Test -> Security scanning -> Docker image
            -> Container registry (GHCR) -> Kubernetes -> Helm -> Monitoring -> GitOps (Argo CD)
```

Compared with the reference app I (1) made the nginx config an env-substituted template so one frontend image works
in Compose and in Kubernetes, (2) switched to the non-root `nginx-unprivileged` image, (3) extended the tests from 3
to 12 and added a `conftest.py` that isolates them on SQLite, (4) added a ConfigMap-driven `APP_ENV`/`LOG_LEVEL`,
(5) fixed a real bug in the reference Helm chart (ingress pointed to port 8080, service listens on 8000), and
(6) upgraded dependencies after the SCA gate found 8 CVEs in the pinned versions.

### Architecture diagram

```text
                        developer laptop
                 git push  |        ^ helm/kubectl/argocd
                           v        |
 +----------------- GitHub (om-malviya/devops-heros) -----------------+
 |  .github/workflows: lint+test | frontend build | SAST | SCA | secrets|
 |            -> docker build -> Trivy gate -> push ghcr.io/...:<sha>   |
 +---------------------------------------------------------------------+
            |                                        ^ pull (GitOps)
            | (optional helm deploy)                 |
            v                                        |
 +======================= AWS (Terraform) ============================+
 |  VPC 10.20.0.0/16  (2 AZ, 2 public + 2 private subnets, NAT GW)    |
 |  EKS taskboard-eks  ---  managed node group t3.medium x2..4        |
 |                                                                    |
 |  ns: ingress-nginx   ns: argocd        ns: monitoring              |
 |  [ingress ctrl]      [Argo CD]         [Prometheus][Grafana][AM]   |
 |        |                                      ^ scrape /metrics    |
 |  taskboard.local     ns: taskboard            |                    |
 |   /    -> Service frontend:80 -> Deployment frontend (nginx) x2    |
 |   /api -> Service backend:8000 -> Deployment backend (FastAPI) x2..6 (HPA)
 |                                        |  DATABASE_URL (Secret)    |
 |                                        v                           |
 |                         Service postgres:5432 -> StatefulSet postgres + PVC 2Gi
 +====================================================================+
```

### Technologies used

| Layer | Technology |
|-------|-----------|
| Frontend | React 18, Vite 7, nginx-unprivileged 1.30 (alpine, arm64/amd64) |
| Backend | Python 3.12, FastAPI 0.142, SQLAlchemy 2.0, Alembic, psycopg 3, prometheus-fastapi-instrumentator, uvicorn |
| Database | PostgreSQL 16 (alpine) |
| Tests / quality | pytest 9, ruff |
| Containers | Docker multi-stage builds, Docker Compose |
| CI/CD | GitHub Actions, GHCR |
| Security | Bandit, Semgrep, pip-audit, npm audit, Gitleaks, Trivy |
| Infrastructure | Terraform 1.16, terraform-aws-modules vpc 5.8.1 / eks 20.37.1, AWS VPC + EKS |
| Orchestration | Kubernetes 1.31, kustomize, Helm 3 (chart taskboard 1.1.0), ingress-nginx, metrics-server/HPA |
| Observability | kube-prometheus-stack (Prometheus Operator, Grafana, Alertmanager), ServiceMonitor, PrometheusRule |
| GitOps | Argo CD |

### Application setup

```text
application/
├── backend/   app/ (config, db, models, schemas, main) · alembic/ · tests/ (conftest.py, test_api.py) · requirements*.txt · ruff.toml
└── frontend/  src/ (main.jsx, styles.css) · index.html · vite.config.js · nginx.conf.template · package.json
```

REST API (`GET /docs` for Swagger): `GET/POST /api/tasks`, `GET/PUT/DELETE /api/tasks/{id}`, `GET /api/tasks/stats`,
plus `GET /health` (liveness), `GET /ready` (readiness, runs a query), `GET /metrics` (Prometheus).

Run the backend locally against SQLite (no Postgres needed for development) and run the tests:

```bash
cd homework/session21-final-devops-project/application/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt -r requirements-dev.txt
DATABASE_URL=sqlite:///./dev.db uvicorn app.main:app --reload --port 8000   # http://localhost:8000/docs
ruff check app tests
pytest -v
```

```text
Output (captured 2026-10-07)
$ ruff check app tests
All checks passed!

$ pytest -v
============================= test session starts ==============================
platform darwin -- Python 3.12.0, pytest-9.1.1, pluggy-1.6.0 -- <venv>/bin/python
rootdir: /Users/ommalviya/Desktop/DevOps/devops-heros/homework/session21-final-devops-project/application/backend
configfile: pytest.ini
testpaths: tests
plugins: cov-6.0.0, platformdirs-4.12.3, anyio-4.15.1
collecting ... collected 12 items
tests/test_api.py::test_health PASSED                                    [  8%]
tests/test_api.py::test_ready_checks_database PASSED                     [ 16%]
tests/test_api.py::test_root PASSED                                      [ 25%]
tests/test_api.py::test_metrics_endpoint_is_prometheus_format PASSED     [ 33%]
tests/test_api.py::test_create_task PASSED                               [ 41%]
tests/test_api.py::test_create_task_validation_error PASSED              [ 50%]
tests/test_api.py::test_list_tasks_contains_created_task PASSED          [ 58%]
tests/test_api.py::test_get_task_by_id PASSED                            [ 66%]
tests/test_api.py::test_get_missing_task_returns_404 PASSED              [ 75%]
tests/test_api.py::test_update_task_status PASSED                        [ 83%]
tests/test_api.py::test_delete_task PASSED                               [ 91%]
tests/test_api.py::test_stats_counts_match_list PASSED                   [100%]
======================== 12 passed, 1 warning in 0.15s =========================
```

I observed that the original suite set `DATABASE_URL` inside the test module; moving that to `conftest.py` (temp
SQLite file, `APP_ENV=test`) means the production Postgres is never touched and the tests run identically on my
laptop and in GitHub Actions. The 12 tests cover all six API endpoints plus health/ready/metrics.

Frontend build (Node 22):

```bash
cd application/frontend && npm install && npm run build
```

```text
Output (captured 2026-10-07)
> taskboard-frontend@1.0.0 build
> vite build

vite v5.4.21 building for production...
transforming...
✓ 30 modules transformed.
rendering chunks...
computing gzip size...
dist/index.html                   0.34 kB │ gzip:  0.25 kB
dist/assets/index-C-SicZRS.css    6.44 kB │ gzip:  2.07 kB
dist/assets/index-CkcTZHAS.js   149.15 kB │ gzip: 47.89 kB
✓ built in 4.01s
```

### Docker setup

`docker/backend.Dockerfile`: python:3.12-slim, dependencies layer first, non-root uid 10001, HEALTHCHECK on
`/health`, CMD runs `alembic upgrade head` then uvicorn. `docker/frontend.Dockerfile`: stage 1 node:22-alpine
builds `dist/`, stage 2 `nginxinc/nginx-unprivileged:1.30-alpine` (uid 101, port 8080) serves it; the nginx config is a
template rendered by the image entrypoint from `BACKEND_HOST`/`BACKEND_PORT`. `docker/docker-compose.yml` wires
postgres (healthcheck + named volume) -> backend -> frontend.

```bash
cd homework/session21-final-devops-project
docker compose -f docker/docker-compose.yml up --build -d
docker compose -f docker/docker-compose.yml ps
curl -s localhost:8000/health; curl -s localhost:3000/api/tasks/stats
docker compose -f docker/docker-compose.yml down -v
```

Host ports 8000, 3000 and 5432 were taken by other stacks on this machine, so I ran the same Compose file with a
small override that only remaps the host side (`!override` replaces the list instead of merging it):

```yaml
# compose.ports.override.yml (local only, not committed)
services:
  postgres: {ports: !override ["8232:5432"]}
  backend:  {ports: !override ["8200:8000"]}
  frontend: {ports: !override ["8201:8080"]}
```

```text
Output (captured 2026-10-08)
$ docker compose -f docker/docker-compose.yml -f compose.ports.override.yml up -d --build
 ...
 Container taskboard-postgres-1 Healthy
 Container taskboard-backend-1 Started
 Container taskboard-frontend-1 Started
$ docker compose -f docker/docker-compose.yml -f compose.ports.override.yml ps
NAME                   IMAGE                      STATUS                        PORTS
taskboard-backend-1    taskboard-backend:local    Up 56 seconds (healthy)       0.0.0.0:8200->8000/tcp
taskboard-frontend-1   taskboard-frontend:local   Up 55 seconds (healthy)       0.0.0.0:8201->8080/tcp
taskboard-postgres-1   postgres:16-alpine         Up About a minute (healthy)   0.0.0.0:8232->5432/tcp
$ curl -s localhost:8200/health; echo; curl -s localhost:8200/ready; echo
{"status":"UP"}
{"status":"READY"}
$ curl -s -X POST localhost:8200/api/tasks -H "Content-Type: application/json" -d '{"title":"Write session 21 README","priority":"HIGH","assignee":"Om"}'
{"title":"Write session 21 README","description":"","priority":"HIGH","status":"TODO","assignee":"Om","id":1,"created_at":"2026-10-07T20:58:50.217921Z"}
$ curl -s -X POST localhost:8200/api/tasks -H "Content-Type: application/json" -d '{"title":"Deploy to k3s","status":"IN_PROGRESS"}'
{"title":"Deploy to k3s","description":"","priority":"MEDIUM","status":"IN_PROGRESS","assignee":"Unassigned","id":2,"created_at":"2026-10-07T20:58:50.239615Z"}
$ curl -s localhost:8200/api/tasks/stats
{"total":2,"todo":1,"inProgress":1,"done":0}
$ curl -s localhost:8201/api/tasks/stats        # same call through the nginx /api proxy of the frontend
{"total":2,"todo":1,"inProgress":1,"done":0}
$ curl -s localhost:8201/ | head -c 120; curl -s localhost:8201/healthz
<!doctype html><html><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>TaskBoard</title>
ok
$ curl -s localhost:8200/metrics | grep -E "^http_requests_total" | head -5
http_requests_total{handler="/health",method="GET",status="2xx"} 4.0
http_requests_total{handler="/ready",method="GET",status="2xx"} 1.0
http_requests_total{handler="/api/tasks",method="POST",status="2xx"} 2.0
http_requests_total{handler="/api/tasks",method="GET",status="2xx"} 1.0
http_requests_total{handler="/api/tasks/stats",method="GET",status="2xx"} 2.0
$ docker compose -f docker/docker-compose.yml logs backend --no-log-prefix | head -4
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tasks
INFO:     Started server process [8]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
$ docker compose -f docker/docker-compose.yml -f compose.ports.override.yml down -v
 ...
 Volume taskboard_postgres-data Removed
 Network taskboard_default Removed
$ docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' | grep taskboard
taskboard-frontend   local   90.5MB      (rebuilt on nginx-unprivileged:1.30-alpine after the Trivy gate in Task 5; the Compose run above still used the 1.27 build, 76.2MB)
taskboard-backend    local   358MB
```

I observed that the Postgres healthcheck gates the backend start (`depends_on: condition: service_healthy`), the
Alembic migration runs once at container start, the frontend proxies `/api/` to the backend container and both
app containers report `healthy` from their Dockerfile HEALTHCHECKs.

---

## Task 2: Infrastructure – Terraform (VPC + EKS)

### Terraform infrastructure

`terraform/` provisions a VPC (`10.20.0.0/16`, two AZs, two public and two private subnets, one NAT gateway,
EKS subnet tags) and an EKS 1.31 cluster with a managed node group (2..4 x t3.medium) in the private subnets, the
core add-ons and the EBS CSI driver (needed for the PostgreSQL PVC). Variables cover region, sizing and CIDRs;
`terraform.tfvars.example` documents them and `terraform.tfvars` is git-ignored. No credentials live in the repo.

```bash
cd terraform
terraform fmt -check -recursive
terraform init -backend=false
terraform validate
```

```text
Output (captured 2026-10-07)
$ terraform fmt -check -recursive            (exit 0 - no formatting diff)
$ terraform init -backend=false
Initializing modules...
Downloading registry.terraform.io/terraform-aws-modules/eks/aws 20.37.1 for eks...
Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 5.8.1 for vpc...
Downloading registry.terraform.io/terraform-aws-modules/kms/aws 2.1.0 for eks.kms...
Initializing provider plugins...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
- Installed hashicorp/tls v4.4.1, hashicorp/time v0.14.2, hashicorp/cloudinit v2.4.1, hashicorp/null v3.3.2
Terraform has been successfully initialized!

$ terraform validate
Success! The configuration is valid.
```

`terraform plan/apply/destroy` need AWS credentials; the expected output (58 resources, outputs, kubeconfig command)
and the **cost warning** are in `terraform/README.md`.

---

## Task 3: Kubernetes (Deployment, Service, ConfigMap, Secret, Ingress, HPA, Probes, Storage) and Helm

### Kubernetes deployment

`kubernetes/` holds the raw manifests, numbered in apply order and listed in `kustomization.yaml`:

| Object | File | Notes |
|--------|------|-------|
| Namespace `taskboard` | 00 | |
| ConfigMap `taskboard-config` | 01 | APP_NAME, APP_ENV, LOG_LEVEL, BACKEND_HOST/PORT, POSTGRES_DB |
| Secret `taskboard-secrets` | 02 (+ `.example`, `SECRETS.md`) | POSTGRES_USER/PASSWORD, DATABASE_URL (fake demo values) |
| StatefulSet postgres + PVC template 2Gi + headless/ClusterIP Services | 03, 04 | `pg_isready` probes, fsGroup |
| Deployment backend (2 replicas) + Service :8000 | 05, 06 | startup/readiness/liveness probes, requests/limits, non-root, drop ALL caps |
| Deployment frontend (2 replicas) + Service :80->8080 | 07, 08 | `/healthz` probes |
| Ingress `taskboard.local` | 09 | `/api` -> backend:8000, `/` -> frontend:80 |
| HPA backend 2..6 @ 60 % CPU | 10 | |

```bash
kubectl kustomize kubernetes/ | grep -E "^kind:" | sort | uniq -c
```

```text
Output (captured 2026-10-07)
   1 kind: ConfigMap
   2 kind: Deployment
   1 kind: HorizontalPodAutoscaler
   1 kind: Ingress
   1 kind: Namespace
   1 kind: Secret
   4 kind: Service
   1 kind: StatefulSet
```

```bash
kubectl apply -k kubernetes/
kubectl -n taskboard get pods,svc,ingress,hpa,pvc
```

On the k3s cluster the images came from a local registry (`docker run -d -p 5002:5000 registry:2`, then
`docker push localhost:5002/taskboard-{backend,frontend}:local`; containerd allows plain HTTP for localhost) and the
Ingress class was switched to Traefik, so two commands follow the apply:

```text
Output (captured 2026-10-08) - single-node k3s
$ kubectl apply -k kubernetes/
namespace/taskboard created
configmap/taskboard-config created
secret/taskboard-secrets created
service/taskboard-backend created
service/taskboard-frontend created
service/taskboard-postgres created
service/taskboard-postgres-headless created
deployment.apps/taskboard-backend created
deployment.apps/taskboard-frontend created
statefulset.apps/taskboard-postgres created
horizontalpodautoscaler.autoscaling/taskboard-backend created
ingress.networking.k8s.io/taskboard created
$ kubectl -n taskboard set image deployment/taskboard-backend backend=localhost:5002/taskboard-backend:local
$ kubectl -n taskboard set image deployment/taskboard-frontend frontend=localhost:5002/taskboard-frontend:local
$ kubectl -n taskboard patch ingress taskboard -p '{"spec":{"ingressClassName":"traefik"}}'
$ kubectl -n taskboard rollout status statefulset/taskboard-postgres deployment/taskboard-backend deployment/taskboard-frontend
partitioned roll out complete: 1 new pods have been updated...
deployment "taskboard-backend" successfully rolled out
deployment "taskboard-frontend" successfully rolled out
$ kubectl get all,ingress,hpa,pvc -n taskboard
NAME                                      READY   STATUS    RESTARTS        AGE
pod/taskboard-backend-6db658b5f-2m82s     1/1     Running   0               77s
pod/taskboard-backend-6db658b5f-bw4kk     1/1     Running   4 (2m18s ago)   3m8s
pod/taskboard-frontend-64b9ffd4fc-5sw6j   1/1     Running   0               2m58s
pod/taskboard-frontend-64b9ffd4fc-kklrt   1/1     Running   0               3m7s
pod/taskboard-postgres-0                  1/1     Running   0               3m9s

NAME                                  TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/taskboard-backend             ClusterIP   10.43.253.57    <none>        8000/TCP   3m10s
service/taskboard-frontend            ClusterIP   10.43.238.1     <none>        80/TCP     3m10s
service/taskboard-postgres            ClusterIP   10.43.112.131   <none>        5432/TCP   3m10s
service/taskboard-postgres-headless   ClusterIP   None            <none>        5432/TCP   3m10s

NAME                                 READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/taskboard-backend    2/2     2            2           3m9s
deployment.apps/taskboard-frontend   2/2     2            2           3m9s

NAME                                  READY   AGE
statefulset.apps/taskboard-postgres   1/1     3m9s

NAME                                                    REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/taskboard-backend   Deployment/taskboard-backend   cpu: 3%/60%   2         6         2          3m9s

NAME                                  CLASS     HOSTS             ADDRESS       PORTS   AGE
ingress.networking.k8s.io/taskboard   traefik   taskboard.local   192.168.5.1   80      3m9s

NAME                                              STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/data-taskboard-postgres-0   Bound    pvc-ef11743e-4b20-4d28-86f3-ad39893e50a8   2Gi        RWO            local-path     3m9s
```

The `RESTARTS 4` on the first backend pod is real and worth explaining: that pod was scheduled while Postgres was
still initialising, `alembic upgrade head` failed with `connection to server at "10.43.112.131", port 5432 failed:
Connection refused`, the container exited and the kubelet restarted it with back-off until the database was ready.
A startupProbe cannot help a process that exits; an init container that waits for `pg_isready` would make the
first start quiet (noted under lessons learned).

```bash
kubectl -n taskboard describe pod -l app=taskboard-backend | grep -E "Image:|Liveness|Readiness|Startup"
kubectl -n taskboard describe pod taskboard-postgres-0 | grep -E "Liveness|Readiness|ClaimName"
kubectl -n taskboard get pods -o custom-columns="POD:.metadata.name,RUNASUSER:.spec.securityContext.runAsUser,RO_ROOTFS:.spec.containers[0].securityContext.readOnlyRootFilesystem"
kubectl -n taskboard exec deploy/taskboard-backend -- sh -c "id; touch /app/x"
kubectl -n taskboard exec taskboard-postgres-0 -- sh -c "id; touch /x; touch /var/run/postgresql/ok && echo scratch-volume-writable"
curl -s -X POST -H 'Host: taskboard.local' -H 'Content-Type: application/json' http://localhost/api/tasks -d '{"title":"Verify ingress on k3s","priority":"HIGH"}'
curl -s -H 'Host: taskboard.local' http://localhost/api/tasks/stats
curl -s -H 'Host: taskboard.local' http://localhost/ | head -c 120
```

```text
Output (captured 2026-10-08)
    Image:          localhost:5002/taskboard-backend:local
    Liveness:   http-get http://:http/health delay=0s timeout=1s period=15s successThreshold=1 failureThreshold=3
    Readiness:  http-get http://:http/ready delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
    Startup:    http-get http://:http/health delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=24
    Liveness:   exec [sh -c pg_isready -U $POSTGRES_USER -d $POSTGRES_DB] delay=30s timeout=1s period=20s successThreshold=1 failureThreshold=3
    Readiness:  exec [sh -c pg_isready -U $POSTGRES_USER -d $POSTGRES_DB] delay=5s timeout=1s period=10s successThreshold=1 failureThreshold=3
    ClaimName:  data-taskboard-postgres-0
POD                                   RUNASUSER   RO_ROOTFS
taskboard-backend-6db658b5f-2m82s     10001       true
taskboard-backend-6db658b5f-bw4kk     10001       true
taskboard-frontend-64b9ffd4fc-5sw6j   <none>      true       (runAsNonRoot; uid 101 comes from the image)
taskboard-frontend-64b9ffd4fc-kklrt   <none>      true
taskboard-postgres-0                  70          true
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
touch: cannot touch '/app/x': Read-only file system
uid=70(postgres) gid=70(postgres) groups=70(postgres)
touch: /x: Read-only file system
scratch-volume-writable
{"title":"Verify ingress on k3s","description":"","priority":"HIGH","status":"TODO","assignee":"Unassigned","id":1,"created_at":"2026-10-07T21:10:50.663895Z"}
{"total":1,"todo":1,"inProgress":0,"done":0}
<!doctype html><html><head><meta charset="UTF-8"/><meta name="viewport" content="width=device-width,initial-scale=1.0"/><title>TaskBoard</title>
```

(`/api/health` through the Ingress returns the backend's own `{"detail":"Not Found"}`: the health endpoints live
at `/health` and `/ready` on the Service and are used by the probes; only `/api/*` is published externally.)

Probes: the **startupProbe** (`/health`, up to 2 min) covers the Alembic migration at container start; the
**readinessProbe** (`/ready`) runs a real query so a pod that lost its database leaves the Service endpoints; the
**livenessProbe** (`/health`) only restarts a hung process.

### Helm deployment

`helm/taskboard` (chart 1.1.0) renders the same objects from values: ConfigMap, Secret (or
`postgres.existingSecret`), StatefulSet + volumeClaimTemplate, Deployments with probes/resources/securityContext,
Services, Ingress, HPA, ServiceMonitor, PrometheusRule and NOTES.txt. Config/secret checksums roll the pods on change.

```bash
helm lint helm/taskboard
helm lint helm/taskboard -f helm/taskboard/values-dev.yaml
helm lint helm/taskboard -f helm/taskboard/values-prod.yaml
helm template taskboard helm/taskboard -n taskboard -f helm/taskboard/values-dev.yaml | grep -E "^kind:|^  name:" | paste - -
```

```text
Output (captured 2026-10-07)
$ helm lint helm/taskboard
==> Linting helm/taskboard
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint helm/taskboard -f helm/taskboard/values-dev.yaml
==> Linting helm/taskboard
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

$ helm lint helm/taskboard -f helm/taskboard/values-prod.yaml
==> Linting helm/taskboard
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed

kind: ConfigMap        name: taskboard-taskboard-config
kind: Deployment       name: taskboard-taskboard-backend
kind: Deployment       name: taskboard-taskboard-frontend
kind: Ingress          name: taskboard-taskboard
kind: PrometheusRule   name: taskboard-taskboard-alerts
kind: Secret           name: taskboard-taskboard-secrets
kind: Service          name: taskboard-taskboard-backend
kind: Service          name: taskboard-taskboard-frontend
kind: Service          name: taskboard-taskboard-postgres
kind: Service          name: taskboard-taskboard-postgres-headless
kind: ServiceMonitor   name: taskboard-taskboard-backend
kind: StatefulSet      name: taskboard-taskboard-postgres
```

With `values-prod.yaml` the template renders 12 objects with `storageClassName: gp3`, image tags from
`--set`, and **no** Secret (credentials come from `existingSecret`). Deploy / upgrade / rollback:

```bash
helm upgrade --install taskboard helm/taskboard -n taskboard --create-namespace -f helm/taskboard/values-dev.yaml
helm list -n taskboard
helm upgrade taskboard helm/taskboard -n taskboard -f helm/taskboard/values-dev.yaml --set backend.image.tag=<sha>
helm history taskboard -n taskboard && helm rollback taskboard 1 -n taskboard
```

```text
Output (captured 2026-10-08) - after "kubectl delete -k kubernetes/", same k3s cluster
$ helm install taskboard helm/taskboard -n taskboard --create-namespace -f helm/taskboard/values-dev.yaml \
    --set backend.image.repository=localhost:5002/taskboard-backend  --set backend.image.tag=local \
    --set frontend.image.repository=localhost:5002/taskboard-frontend --set frontend.image.tag=local \
    --set ingress.className=traefik --wait --timeout 5m
NAME: taskboard
LAST DEPLOYED: Thu Oct  8 03:01:42 2026
NAMESPACE: taskboard
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
TaskBoard 1.0.0 deployed as release "taskboard" in namespace "taskboard".
Open the app (add "127.0.0.1 taskboard.local" to /etc/hosts for a local cluster):
  http://taskboard.local/        (frontend)
  http://taskboard.local/api/tasks
$ helm list -n taskboard
NAME        NAMESPACE   REVISION   UPDATED                                STATUS     CHART             APP VERSION
taskboard   taskboard   1          2026-10-08 03:01:42.198531 +0530 IST   deployed   taskboard-1.1.0   1.0.0
$ kubectl -n taskboard get pods,svc,ingress,servicemonitor,prometheusrule
pod/taskboard-taskboard-backend-7b5746d45d-f47vl    1/1   Running   3 (32s ago)   47s
pod/taskboard-taskboard-frontend-79fdfc557c-2xknz   1/1   Running   0             47s
pod/taskboard-taskboard-postgres-0                  1/1   Running   0             47s
service/taskboard-taskboard-backend             ClusterIP   10.43.185.86   8000/TCP
service/taskboard-taskboard-frontend            ClusterIP   10.43.69.17    80/TCP
service/taskboard-taskboard-postgres            ClusterIP   10.43.18.235   5432/TCP
service/taskboard-taskboard-postgres-headless   ClusterIP   None           5432/TCP
ingress.networking.k8s.io/taskboard-taskboard   traefik   taskboard.local   192.168.5.1   80
servicemonitor.monitoring.coreos.com/taskboard-taskboard-backend
prometheusrule.monitoring.coreos.com/taskboard-taskboard-alerts
$ curl -s -H 'Host: taskboard.local' http://localhost/api/tasks/stats
{"total":0,"todo":0,"inProgress":0,"done":0}
$ helm upgrade taskboard helm/taskboard -n taskboard -f helm/taskboard/values-dev.yaml <same --set flags> --set backend.replicaCount=2 --wait
Release "taskboard" has been upgraded. Happy Helming!
REVISION: 2
$ kubectl -n taskboard get pods -l app.kubernetes.io/component=backend
taskboard-taskboard-backend-7b5746d45d-5cmjn   1/1   Running   0             5s
taskboard-taskboard-backend-7b5746d45d-f47vl   1/1   Running   3 (42s ago)   57s
$ helm history taskboard -n taskboard
REVISION   UPDATED                    STATUS       CHART             APP VERSION   DESCRIPTION
1          Thu Oct  8 03:01:42 2026   superseded   taskboard-1.1.0   1.0.0         Install complete
2          Thu Oct  8 03:02:34 2026   deployed     taskboard-1.1.0   1.0.0         Upgrade complete
$ helm rollback taskboard 1 -n taskboard --wait
Rollback was a success! Happy Helming!
$ helm history taskboard -n taskboard
1   superseded   Install complete
2   superseded   Upgrade complete
3   deployed     Rollback to 1
$ kubectl -n taskboard get pods -l app.kubernetes.io/component=backend
taskboard-taskboard-backend-7b5746d45d-5cmjn   1/1   Terminating   0   16s
taskboard-taskboard-backend-7b5746d45d-f47vl   1/1   Running       3   68s
$ helm uninstall taskboard -n taskboard
release "taskboard" uninstalled
```

The ServiceMonitor and PrometheusRule rendered because the Prometheus Operator CRDs from Task 6 were still on the
cluster; with `monitoring.*.enabled=false` the chart installs without them.

---

## Task 4: CI/CD – GitHub Actions (build, test, docker build, image push, Kubernetes deployment)

### CI/CD pipeline

`.github/workflows/ci-cd.yml` (and the identical root copy `/.github/workflows/session21-final-project.yml`,
filtered to `paths: homework/session21-final-devops-project/**` with `defaults.run.working-directory`) runs on
push and pull request to `main`:

```text
backend-lint-test  frontend-build   sast (bandit+semgrep)   sca (pip-audit+npm audit)   secret-scan (gitleaks)
        \               |                 |                        |                         /
         +--------------+-----------------+------------------------+------------------------+
                                             |  needs: all five
                                             v
                     docker-build-scan-push: build 2 images -> Trivy gate (exit 1) -> SARIF
                                             -> login GHCR -> push :<git sha> (+ :latest on main)
                                             |
                                             v   only on main, only if secrets.KUBE_CONFIG_DATA is set
                     deploy: helm lint -> helm upgrade --install --wait --set *.image.tag=<sha> -> rollout status
```

Key choices: tests run **before** any image exists (a red pytest stops the pipeline); images are tagged with the
commit SHA so production can always be traced back to a commit; pushes are skipped on pull requests; the deploy
job is a no-op with a message when no kubeconfig secret exists, because in the GitOps flow Argo CD deploys instead.

```text
Expected output (GitHub Actions run summary)
✓ Backend lint + pytest            1m 02s   12 passed
✓ Frontend build                   0m 41s
✓ SAST (bandit + semgrep)          1m 15s   0 findings
✓ SCA (pip-audit + npm audit)      0m 58s   No known vulnerabilities found
✓ Secret scan (gitleaks)           0m 20s   no leaks found
✓ Docker build + Trivy gate + push 3m 40s   taskboard-backend: 0 HIGH/CRITICAL (fixed) · pushed ghcr.io/om-malviya/taskboard-backend:3f2a9c1
✓ Helm deploy                      1m 10s   deployment "taskboard-taskboard-backend" successfully rolled out
```

---

## Task 5: DevSecOps – SAST, SCA, secret scanning, image scanning, security gates

### DevSecOps implementation

| Gate | Tool | Config | Blocks on |
|------|------|--------|-----------|
| SAST | Bandit | `security/bandit.yaml` | any MEDIUM+ finding |
| SAST | Semgrep (`p/python`, `p/owasp-top-ten`, project rules) | `security/semgrep.yml` | ERROR/WARNING |
| SCA | pip-audit `--strict`, npm audit `--audit-level=high` | - | any known CVE / HIGH+ |
| Secrets | Gitleaks over full history | `security/.gitleaks.toml` | any non-allow-listed leak |
| Image | Trivy (vuln + secret + misconfig) on both images | `security/trivy.yaml`, `.trivyignore` | HIGH/CRITICAL with a fix |

`security/SECURITY.md` explains each gate and how to run it locally. What I ran here:

```bash
bandit -c security/bandit.yaml -r application/backend/app
pip-audit -r application/backend/requirements.txt
```

```text
Output (captured 2026-10-07)
$ bandit -r app
Test results:
        No issues identified.
Code scanned:
        Total lines of code: 133
Total issues (by severity): Undefined: 0  Low: 0  Medium: 0  High: 0

$ pip-audit -r requirements.txt      # FIRST run, with the reference pins (fastapi 0.115.6 / pytest 8.3.4)
Found 8 known vulnerabilities in 2 packages
Name      Version ID              Fix Versions
--------- ------- --------------- ------------
pytest    8.3.4   PYSEC-2026-1845 9.0.3
starlette 0.41.3  PYSEC-2026-161  1.0.1
starlette 0.41.3  PYSEC-2026-249  1.3.1
starlette 0.41.3  PYSEC-2026-248  1.3.0
starlette 0.41.3  PYSEC-2026-1942 0.49.1
starlette 0.41.3  PYSEC-2026-1941 0.47.2
starlette 0.41.3  PYSEC-2026-2281 1.1.0
starlette 0.41.3  PYSEC-2026-2280 1.1.0

$ pip-audit -r requirements.txt      # after upgrading to fastapi 0.142.2 (starlette 1.7.0), pytest 9.1.1
No known vulnerabilities found
```

This is the SCA gate doing its job: the reference pins would have failed the pipeline; I upgraded the dependencies,
re-ran the 12 tests (still green) and the audit is clean. The second pass had Docker, so every remaining gate ran for real against the built images and the tree:

```bash
trivy fs --severity HIGH,CRITICAL --ignore-unfixed .                                     # SCA on requirements.txt
trivy fs --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln,secret,misconfig .     # + Dockerfile / Kubernetes / Helm misconfig
trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-backend:local
trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-frontend:local
gitleaks detect --no-git --source . -c security/.gitleaks.toml -v
semgrep scan --config security/semgrep.yml --metrics=off application/backend application/frontend/src
```

```text
Output (captured 2026-10-08) - FIRST run, before any fix (Trivy 0.75.0, Gitleaks 8.30.1, Semgrep 1.179.0)
$ trivy fs --severity HIGH,CRITICAL --ignore-unfixed .
│ application/backend/requirements.txt │ pip │ 0 │

$ trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-backend:local; echo exit=$?
taskboard-backend:local (debian 13.7)
Total: 44 (HIGH: 44, CRITICAL: 0)
│ bsdutils      │ CVE-2026-76642 │ HIGH │ affected     │ 1:2.41.5-0+deb13u1 │ (no fixed version) │ util-linux: failed external mount helper ...
│ libsystemd0   │ CVE-2026-16742 │ HIGH │ affected     │ 257.13-1~deb13u1   │ (no fixed version) │ systemd-homed: local privilege escalation ...
│ libncursesw6  │ CVE-2025-69720 │ HIGH │ affected     │ 6.5+20250216-2     │ (no fixed version) │ ncurses: buffer overflow ...
│ perl-base     │ CVE-2026-9538  │ HIGH │ fix_deferred │ 5.40.1-6+deb13u1   │ (no fixed version) │ perl-Archive-Tar: denial of service ...
  ... 40 more rows, all "affected"/"fix_deferred" with an empty Fixed Version column
exit=1

$ trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-frontend:local; echo exit=$?
taskboard-frontend:local (alpine 3.21.3)
Total: 42 (HIGH: 40, CRITICAL: 2)
│ libcrypto3   │ CVE-2026-31789 │ CRITICAL │ fixed │ 3.3.3-r0   │ 3.3.7-r0   │ openssl: heap buffer overflow ...
│ libssl3      │ CVE-2026-31789 │ CRITICAL │ fixed │ 3.3.3-r0   │ 3.3.7-r0   │
│ musl         │ CVE-2026-40200 │ HIGH     │ fixed │ 1.2.5-r9   │ 1.2.5-r11  │ musl libc: arbitrary code execution ...
│ zlib         │ CVE-2026-22184 │ HIGH     │ fixed │ 1.3.1-r2   │ 1.3.2-r0   │ zlib: buffer overflow ...
│ libxml2      │ CVE-2025-49794 │ HIGH     │ fixed │ 2.13.4-r6  │ 2.13.9-r0  │ ...
  ... c-ares, libexpat, libpng, nghttp2-libs, musl-utils
exit=1

$ trivy fs --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln,secret,misconfig . | grep -B3 "Failures:"
docker/frontend.Dockerfile                   DS-0002 (HIGH)  Specify at least 1 USER command in Dockerfile with non-root user
kubernetes/05-backend-deployment.yaml        KSV-0014 (HIGH) Container 'backend' should set securityContext.readOnlyRootFilesystem to true
kubernetes/07-frontend-deployment.yaml       KSV-0014 (HIGH) Container 'frontend' ...
kubernetes/03-postgres-statefulset.yaml      KSV-0014 (HIGH) + KSV-0118 (HIGH) container taskboard-postgres is using the default security context
helm/taskboard/templates/*.yaml              the same three findings on the rendered chart
troubleshooting/0{1,3,4,5}-*/{broken,fixed}  KSV-0014 + KSV-0118 x2 (the copies had no securityContext at all)

$ gitleaks detect --no-git --source . -c security/.gitleaks.toml -v; echo exit=$?
Finding:  DATABASE_URL: postgresql+psycopg://taskboard:changeme-demo-password@taskboard-postgres:5...
Secret:   +psycopg
RuleID:   taskboard-database-url-with-password    File: kubernetes/02-secret.yaml            Line: 15
Finding:  DATABASE_URL: postgresql+psycopg://taskboard:taskboard-local-only@postgres:5432/taskbo...
RuleID:   taskboard-database-url-with-password    File: docker/docker-compose.yml            Line: 30
Finding:  ...atabase_url: str = "postgresql+psycopg://taskboard:taskboard@localhost:5432/taskb...
RuleID:   taskboard-database-url-with-password    File: application/backend/app/config.py    Line: 12
WRN leaks found: 3
exit=1

$ semgrep scan --config security/semgrep.yml --metrics=off application/backend application/frontend/src
Ran 4 rules on 9 files: 0 findings.
```

Four gates failed on the first real run. What each failure meant and what I changed (the gates themselves were not
weakened; `.trivyignore` is still empty):

1. **Backend image, 44 HIGH.** `python:3.12-slim` was already the newest build (Debian 13.7, pulled the day before)
   and every finding has no fixed version, so `ignore-unfixed` should have dropped them. It did not, because
   `security/trivy.yaml` had `ignore-unfixed: true` at the top level, where Trivy silently ignores it - in the config
   file the key belongs under `vulnerability:`. I moved it (and left a comment); the image itself needs no change.
2. **Frontend image, 40 HIGH + 2 CRITICAL, all fixable.** `nginx-unprivileged:1.27-alpine` is a June-2025 build of
   Alpine 3.21. This is the classic "rebuild on a newer base" remedy: `docker/frontend.Dockerfile` now uses
   `1.30-alpine` (Alpine 3.24.2, nginx 1.30.5); after the rebuild the scan is clean.
3. **Misconfiguration findings** (Trivy's IaC scanner; not part of the CI image gate but real hardening gaps):
   no `USER` in the frontend Dockerfile (the base image sets uid 101 but a scanner cannot see that), no
   `readOnlyRootFilesystem` on any container, and a Postgres container without a securityContext. Fixed with
   `USER 101` in the Dockerfile and, on all three workloads, `readOnlyRootFilesystem: true` + emptyDir volumes for
   the paths that must stay writable (`/tmp` and `/etc/nginx/conf.d` for nginx-unprivileged, `/var/run/postgresql`
   and `/tmp` for Postgres, which now runs as uid/gid 70 with all capabilities dropped). The same change went into
   `kubernetes/`, the Helm chart (values + templates) and the troubleshooting manifests, and Task 3 shows it working
   on the cluster (`touch: Read-only file system`).
4. **Gitleaks, 3 "leaks".** All three are the documented demo placeholders, but the allow-list never matched.
   Root cause: the project rule used a capturing group `(\+psycopg)?`, and Gitleaks reports capture group 1 as the
   secret, so the "secret" was the string `+psycopg` and the allow-list regexes (`changeme-demo-password`, ...) were
   compared against that. Fixed by making the group non-capturing and setting `regexTarget = "line"` on the allow-list.

```text
Output (captured 2026-10-08) - SECOND run, after the fixes
$ trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-backend:local; echo exit=$?
│ taskboard-backend:local (debian 13.7)     │ debian │ 0 │      (+ 39 python-pkg targets, all 0)
exit=0
$ trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-frontend:local; echo exit=$?
│ taskboard-frontend:local (alpine 3.24.2)  │ alpine │ 0 │
exit=0
$ trivy fs --severity HIGH,CRITICAL --ignore-unfixed --scanners vuln,secret,misconfig --skip-dirs terraform .; echo exit=$?
Report Summary: 41 targets - 0 vulnerabilities, 0 secrets, 0 misconfigurations
exit=0
$ gitleaks detect --no-git --source . -c security/.gitleaks.toml -v; echo exit=$?
INF no leaks found
exit=0
```

(`--skip-dirs terraform` only because Trivy tries to download the AWS modules to evaluate them and this machine has
no network access to the Terraform registry; the Terraform code is validated separately in Task 2.) The CI gate
result for the GHCR-tagged images is therefore expected to be the same as the local one:

```text
Expected output (Trivy in GitHub Actions, backend image)
ghcr.io/om-malviya/taskboard-backend:3f2a9c1 (debian 13.7)
Total: 0 (HIGH: 0, CRITICAL: 0)
```

---

## Task 6: Monitoring & GitOps

### Monitoring

`monitoring/kube-prometheus-stack-values.yaml` installs Prometheus Operator, Grafana (sidecar auto-imports dashboards
labelled `grafana_dashboard=1`), Alertmanager, node-exporter and kube-state-metrics. `servicemonitor.yaml` scrapes
the backend Service at `/metrics` every 15 s; `prometheusrule.yaml` defines six alerts (backend down, crash loop,
not ready, 5xx ratio > 5 %, p95 > 500 ms, HPA at max); `grafana-dashboard-configmap.yaml` /
`dashboards/taskboard-dashboard.json` is a 10-panel RED dashboard (request rate, error ratio, p50/p95/p99 latency,
HPA replicas, CPU vs request, memory). PromQL is listed in `monitoring/README.md`.

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --create-namespace -f monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard-configmap.yaml
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &   # /targets, /api/v1/query, /api/v1/rules
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80 &        # admin / grafana-demo-admin
```

On the shared k3s cluster I used the namespace `monitoring-s21` (the plain `monitoring` name was in use), so the
dashboard ConfigMap - which hard-codes `namespace: monitoring` - went through a `sed` on the way in. Everything
else ran as written against the raw-manifest deployment from Task 3:

```text
Output (captured 2026-10-08)
$ helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring-s21 --create-namespace -f monitoring/kube-prometheus-stack-values.yaml --wait --timeout 10m
Release "kube-prometheus-stack" does not exist. Installing it now.
NAME: kube-prometheus-stack        NAMESPACE: monitoring-s21        STATUS: deployed        REVISION: 1     (chart 92.1.0, operator v0.94.1)
$ kubectl -n monitoring-s21 get pods
alertmanager-kube-prometheus-stack-alertmanager-0          2/2     Running
kube-prometheus-stack-grafana-7968bb55-dt9dp               3/3     Running
kube-prometheus-stack-kube-state-metrics-7757df4df-mv568   1/1     Running
kube-prometheus-stack-operator-746d485dc-28dx5             1/1     Running
kube-prometheus-stack-prometheus-node-exporter-lqd77       1/1     Running
prometheus-kube-prometheus-stack-prometheus-0              2/2     Running
$ kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml
servicemonitor.monitoring.coreos.com/taskboard-backend created
prometheusrule.monitoring.coreos.com/taskboard-alerts created
$ sed "s/namespace: monitoring$/namespace: monitoring-s21/" monitoring/grafana-dashboard-configmap.yaml | kubectl apply -f -
configmap/taskboard-grafana-dashboard created
$ kubectl -n monitoring-s21 port-forward svc/kube-prometheus-stack-prometheus 8290:9090 &
$ curl -s localhost:8290/api/v1/targets            # activeTargets filtered to scrapePool ~ taskboard
serviceMonitor/taskboard/taskboard-backend/0   taskboard-backend-6db658b5f-89gb6   UP   last scrape 2026-10-07T21:29:02
serviceMonitor/taskboard/taskboard-backend/0   taskboard-backend-6db658b5f-cql67   UP   last scrape 2026-10-07T21:29:03
$ curl -s 'localhost:8290/api/v1/query?query=up{namespace="taskboard"}'
taskboard-backend-6db658b5f-89gb6   1
taskboard-backend-6db658b5f-cql67   1
$ curl -s 'localhost:8290/api/v1/query?query=sum by (handler) (rate(http_requests_total{namespace="taskboard"}[2m]))'
/health 0.045   /ready 0.068   /api/tasks 0.033   /api/tasks/stats 0   /metrics 0.029        (req/s)
$ curl -s 'localhost:8290/api/v1/query?query=histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="taskboard"}[5m])))'
0.095                                                                                         (seconds)
$ curl -s localhost:8290/api/v1/rules               # groups taskboard.*
taskboard.availability   TaskboardBackendDown / TaskboardPodCrashLooping / TaskboardPodNotReady          state=inactive
taskboard.traffic        TaskboardHighErrorRate / TaskboardHighLatencyP95 / TaskboardHpaAtMaxReplicas    state=inactive
$ kubectl -n monitoring-s21 port-forward svc/kube-prometheus-stack-grafana 8291:80 &
$ curl -s -u admin:<GRAFANA_ADMIN_PASSWORD> "localhost:8291/api/search?query=TaskBoard"
TaskBoard - API overview -> /d/taskboard-api/taskboard-api-overview        (imported by the sidecar from the ConfigMap)
$ curl -s -u admin:<GRAFANA_ADMIN_PASSWORD> localhost:8291/api/datasources
Prometheus prometheus
Alertmanager alertmanager
$ helm uninstall kube-prometheus-stack -n monitoring-s21 && kubectl delete ns monitoring-s21
release "kube-prometheus-stack" uninstalled
namespace "monitoring-s21" deleted
```

One real debugging moment: the first `/targets` query showed the backend in *droppedTargets*. The ServiceMonitor
selects `app=taskboard-backend` on the Service, and that label had been pruned a few minutes earlier when
troubleshooting scenario 2's `fixed.yaml` (which had no `metadata.labels`) was applied. Re-applying
`kubernetes/06-backend-service.yaml` brought the target UP within one scrape interval, and the scenario manifests
now carry the same labels as the real ones.

Logs: both containers log to stdout (`kubectl logs -n taskboard deploy/taskboard-backend`); the README in
`monitoring/` shows how Loki/Promtail would be added for centralised logs with the same Grafana.

### GitOps

`gitops/argocd/application-dev.yaml` points Argo CD at `https://github.com/om-malviya/devops-heros.git`, path
`homework/session21-final-devops-project/helm/taskboard`, `values-dev.yaml`, with `automated: {prune, selfHeal}`,
`CreateNamespace=true` and `ignoreDifferences` on the backend replica count (owned by the HPA). The prod
Application uses pinned tags and no auto-prune. `gitops/install-argocd.sh` installs Argo CD and applies the app.

```bash
./gitops/install-argocd.sh
kubectl -n argocd get applications
```

```text
Output (captured 2026-10-08)
$ ./gitops/install-argocd.sh
==> Installing Argo CD v2.13.3 into namespace argocd
namespace/argocd created
  ... 59 objects created (CRDs, service accounts, RBAC, ConfigMaps, Services, Deployments, StatefulSet)
==> Waiting for the Argo CD server to become ready
Waiting for deployment "argocd-server" rollout to finish: 0 of 1 updated replicas are available...
  ... both rollouts completed (the script runs with set -e)
==> Registering the TaskBoard application
application.argoproj.io/taskboard-dev created
==> Initial admin password (change it after first login):
<redacted>
$ kubectl -n argocd get applications
NAME            SYNC STATUS   HEALTH STATUS
taskboard-dev   Unknown       Healthy
$ kubectl -n argocd get application taskboard-dev -o jsonpath='{.status.conditions}'
[{"type": "ComparisonError",
  "message": "Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = authentication required",
  "lastTransitionTime": "2026-10-07T21:34:07Z"}]
$ kubectl -n argocd get application taskboard-dev -o jsonpath='sync={.status.sync.status} source={.spec.source.repoURL}@{.spec.source.targetRevision}'
sync=Unknown source=https://github.com/om-malviya/devops-heros.git@main
$ kubectl -n argocd delete application taskboard-dev && kubectl delete -n argocd -f .../v2.13.3/manifests/install.yaml && kubectl delete ns argocd
```

This is the honest state before the first push: Argo CD installed and the Application registered, but the
repo-server cannot fetch `om-malviya/devops-heros` because the repository does not exist on GitHub yet (GitHub
answers "authentication required" for unknown repositories instead of revealing whether they are private). Nothing
was applied to the cluster, which is exactly what `ComparisonError` means. After the push the same Application goes
`OutOfSync` -> automated sync -> `Synced`/`Healthy`:

```text
Expected output (after the repository is pushed)
NAME            SYNC STATUS   HEALTH STATUS
taskboard-dev   Synced        Healthy
```

Flow: CI pushes `:<sha>`, a commit bumps `backend.image.tag`, Argo CD notices within 3 minutes, renders the chart and
applies it; a manual `kubectl edit` is reverted by selfHeal, so Git stays the only source of truth.

---

## Task 7: Final Troubleshooting Challenge

### Troubleshooting

Six faults are introduced on purpose in `troubleshooting/`; each folder has `broken.yaml`, `fixed.yaml` and a README
that follows identify -> investigate -> root cause -> fix -> verify -> document with the expected before/after output.

| # | Fault | Symptom | Key command | Root cause |
|---|-------|---------|-------------|------------|
| 1 | image tag `v9.9.9-does-not-exist` | `ImagePullBackOff` | `describe pod` -> `manifest unknown` | tag never pushed to GHCR |
| 2 | Service selector `app=taskboard-api` | `ENDPOINTS <none>`, 503 | `get endpoints`, `get pods --show-labels` | selector != pod labels |
| 3 | `secretKeyRef.key: DB_URL` | `CreateContainerConfigError` / `CrashLoopBackOff` | `describe pod`, `logs --previous` | key missing in Secret |
| 4 | readiness path `/readyz` | Running but `0/1` forever | `describe pod` -> probe 404 | wrong probe path |
| 5 | HPA on Deployment without requests | `TARGETS <unknown>/60%` | `describe hpa` -> `missing request for cpu` | no CPU request = no utilisation |
| 6 | Ingress `/api` -> port 8080 | 503/502 on `/api` | `describe ingress` -> `endpoints not found for port 8080` | Service listens on 8000 |

All six scenarios were executed on the k3s cluster against the raw-manifest deployment from Task 3 (apply
`broken.yaml`, capture the symptom, apply `fixed.yaml`, capture the recovery). Because the images on this cluster
come from `localhost:5002` and the Ingress class is Traefik, the manifests were piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#'`
before `kubectl apply -f -`. The full before/after output of every scenario is in its README; the evidence lines:

| # | Captured symptom (2026-10-08) | Captured recovery |
|---|-------------------------------|-------------------|
| 1 | `0/1 ImagePullBackOff`; event `Failed to pull image "...:v9.9.9-does-not-exist" ... 403 Forbidden` (GHCR answers 403 at the token step for an unknown repository; the message is `manifest unknown` when the repo exists but the tag does not) | `deployment "taskboard-backend" successfully rolled out`, `1/1 Running` |
| 2 | `ENDPOINTS <none>`, selector `{"app":"taskboard-api"}`, Traefik answers `HTTP/1.1 503 Service Unavailable` | `ENDPOINTS 10.42.0.189:8000`, in-cluster curl `{"status":"UP"}`, stats through the Ingress |
| 3 | `0/1 CreateContainerConfigError`; event `Error: couldn't find key DB_URL in Secret taskboard/taskboard-secrets`; Secret keys `['DATABASE_URL', 'POSTGRES_PASSWORD', 'POSTGRES_USER']` | rolled out, `1/1 Running`, uvicorn logs 200 on `/ready` |
| 4 | `0/1 Running` for the whole minute; probe line `http-get http://:http/readyz`; app log `"GET /readyz HTTP/1.1" 404 Not Found`; endpoints still only the old pod | rolled out, two endpoints `10.42.0.189:8000,10.42.0.39:8000` |
| 5 | `TARGETS cpu: <unknown>/60%`; condition `ScalingActive False FailedGetResourceMetric ... missing request for cpu in container backend`; `resources: {}`; `kubectl top` works (2-4m) | `TARGETS cpu: 2%/60%`, `ScalingActive True ValidMetricFound` |
| 6 | `describe ingress`: `/api taskboard-backend:8080 ()`; Traefik log `ERR Cannot create service error="service port not found" ingress=taskboard` | `/api taskboard-backend:8000 (10.42.0.45:8000,10.42.0.46:8000)`, stats JSON through the Ingress |

Example (scenario 2) - the before/after that proves the fix:

```bash
kubectl apply -f troubleshooting/02-service-selector-mismatch/broken.yaml
kubectl -n taskboard get endpoints taskboard-backend
kubectl apply -f troubleshooting/02-service-selector-mismatch/fixed.yaml
kubectl -n taskboard get endpoints taskboard-backend
```

```text
Output (captured 2026-10-08)
NAME                ENDPOINTS   AGE
taskboard-backend   <none>      5m59s
$ curl -si -H 'Host: taskboard.local' http://localhost/api/tasks/stats | head -1
HTTP/1.1 503 Service Unavailable
NAME                ENDPOINTS          AGE
taskboard-backend   10.42.0.189:8000   6m4s
$ curl -s -H 'Host: taskboard.local' http://localhost/api/tasks/stats
{"total":1,"todo":1,"inProgress":0,"done":0}
```

Two things the real run taught me that the write-up alone would not have: with Traefik the broken Ingress port of
scenario 6 is *masked* for end users, because Traefik drops the `/api` router and the request falls through to the
`/` rule, where the frontend's own nginx `/api/` proxy still reaches the backend (ingress-nginx returns 503 instead) -
`describe ingress` and the controller log are the reliable evidence, not the browser. And applying a "fixed" manifest
that omits `metadata.labels` prunes the labels from the live Service, which later broke the Prometheus ServiceMonitor
in Task 6; the scenario manifests are now generated from the real ones so they differ only in the intended fault.

---

## Task 8: Final deliverables, screenshots and lessons learned

### Screenshots

The terminal outputs in this README stand in for the screenshots. Captured outputs are real (Docker + k3s on
2026-10-08); the two rows marked expected need a GitHub push / an AWS account.

| Screenshot the rubric asks for | Stand-in in this README |
|--------------------------------|-------------------------|
| `pytest -v` all passing | Task 1, *Output (captured)*: 12 passed |
| Frontend built / app in browser | Task 1, Vite build output and `curl localhost:8201/` (captured HTML of the dashboard shell) |
| `docker compose up --build` | Task 1, Docker setup (captured): three containers healthy, POST/GET/stats, `/metrics` |
| `terraform plan` / apply / destroy, AWS console VPC + EKS | Task 2 (captured init+validate) and `terraform/README.md` (expected plan/apply/destroy) |
| `kubectl get pods/svc`, `helm list`, app via Ingress | Task 3 (captured): `get all,ingress,hpa,pvc`, probe lines, read-only root FS, `curl -H Host:` through Traefik, `helm list/history/rollback` |
| GitHub Actions green run, GHCR packages with SHA tags | Task 4 (expected run summary) |
| Trivy scan output | Task 5 (captured): Trivy image/fs, Gitleaks, Semgrep - first run with 4 failing gates and the clean re-run |
| `/metrics`, Prometheus targets UP, Grafana panel | Task 6 (captured): backend targets UP, PromQL rate/p95, 6 alert rules loaded, dashboard imported by the sidecar |
| Argo CD Synced/Healthy | Task 6 (captured `Unknown` + `ComparisonError: authentication required` before the push; Synced/Healthy expected after) |
| Troubleshooting before/after | Task 7 and each `troubleshooting/*/README.md` (captured) |

### Lessons learned

* **Tests before images.** Putting pytest in front of the Docker build means a broken commit never becomes an image,
  never reaches the registry and never reaches the cluster. The SQLite-backed `conftest.py` makes this cheap.
* **Security gates find real things.** pip-audit flagged 8 CVEs in the reference pins on the very first run; fixing
  them was a two-line change, but without the gate they would have shipped.
* **One image, many environments.** Templating the nginx upstream through environment variables (and reading
  backend config from a ConfigMap/Secret) is what lets the same image run in Compose, kind and EKS.
* **Running is not Ready.** Readiness probes, Service selectors and Ingress ports form a chain; `kubectl get
  endpoints` and `describe ingress` show exactly which link is broken, which is faster than reading code.
* **HPA has prerequisites.** Without resource requests (and metrics-server) it silently reports `<unknown>`.
* **Helm charts need linting too.** The reference chart's ingress pointed at a port the Service did not expose;
  `helm template` plus a quick read of the rendered YAML caught it before a cluster did.
* **GitOps changes who deploys.** With Argo CD the pipeline's job ends at "push a trusted image"; deployment becomes a
  Git commit that is reviewable, auditable and automatically reverted if someone edits the cluster by hand.
* **Infrastructure costs money even when idle.** EKS + NAT gateway is ~5-6 USD/day; `terraform destroy` and a console
  check are part of the workflow, not an afterthought.
* **A gate is only as good as its config file.** Trivy ignored `ignore-unfixed` because the key was at the wrong
  level, and Gitleaks could never match its own allow-list because of a capturing group. Both configs looked right
  and both were wrong; running the gate against real images and watching it fail is the only test that counts.
* **Base images age.** The frontend image went from 42 fixable HIGH/CRITICAL CVEs to zero by bumping one `FROM`
  line; the backend image had 44 findings with no fix anywhere, which is what `ignore-unfixed` is for.
* **Read-only root filesystems are cheap once you know the writable paths.** nginx-unprivileged needs `/tmp` and
  `/etc/nginx/conf.d`, Postgres needs `/var/run/postgresql`; two emptyDirs each and the containers run read-only.
* **`kubectl apply` prunes what you leave out.** A "fixed" Service without `metadata.labels` silently removed the
  label a ServiceMonitor selected on; copies of manifests must be generated from the originals, not retyped.
* **Startup probes do not cover processes that exit.** The backend restarted four times while Postgres was still
  initialising; an init container that waits for `pg_isready` is the next improvement.

## Deliverables

| Deliverable | Path |
|-------------|------|
| Application source (backend + frontend, 12 tests) | `application/` |
| Dockerfiles, Compose stack, .dockerignore | `docker/` |
| Raw Kubernetes manifests (namespace, ConfigMap, Secret, StatefulSet+PVC, Deployments, Services, Ingress, HPA) + kustomization | `kubernetes/` |
| Helm chart with values / values-dev / values-prod | `helm/taskboard/` |
| Terraform VPC + EKS (validated), tfvars example, README with plan/apply/destroy and cost warning | `terraform/` |
| CI/CD workflow (lint, test, build, SAST, SCA, secrets, Trivy gate, GHCR push, Helm deploy) | `.github/workflows/ci-cd.yml` and root `/.github/workflows/session21-final-project.yml` |
| Security gate configs and SECURITY.md | `security/` |
| kube-prometheus-stack values, ServiceMonitor, PrometheusRule, Grafana dashboard, PromQL README | `monitoring/` |
| Argo CD Applications, install script, README | `gitops/` |
| Six broken/fixed troubleshooting scenarios with READMEs | `troubleshooting/` |
| Project .gitignore | `.gitignore` |
