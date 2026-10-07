# Session 20 – Monitoring, Observability & GitOps
Student: Om Malviya | Enrollment No: 24BCS10448

This folder contains my homework for session 20. Each task has its own sub-folder with a
detailed README; this file is the index and summary.

```text
session20-monitoring-observability-gitops/
├── README.md                 <- this index
├── 01-monitoring/            Task 1: Docker Compose monitoring stack + Kubernetes variant
├── 02-observability/         Task 2: observability documentation
└── 03-gitops/                Task 3: GitOps theory + Argo CD demo
```

Environment note: I wrote the files first without a Docker daemon or cluster (those outputs were
`Expected output`), then ran everything on a Colima VM (Docker 29, 4 vCPU / 6 GB) with its
built-in single-node k3s cluster (Kubernetes v1.35, kubectl context `colima`). Every block labelled
`Output (captured 2026-10-07)` or `Output (captured 2026-10-08)` is real output from this machine; the
few blocks still labelled `Expected output` say why they could not be run here.

## Task 1: Monitoring
Learn and demonstrate: metrics, logs, alerts, CPU utilization, memory utilization, application health.

Done in [`01-monitoring/`](01-monitoring/README.md):

- `docker-compose.yml` with Prometheus, node-exporter, cAdvisor, Alertmanager, Grafana and a small python `sample-app` that exposes a counter, a histogram, a gauge and `/health`.
- `prometheus.yml` scrapes all six targets; `alert-rules.yml` defines HighCPU (>80 %), HighMemory (>85 %), InstanceDown, AppUnhealthy (`up == 0`), HighErrorRate (>5 % 5xx) and HighLatencyP95; `alertmanager.yml` routes to a placeholder webhook.
- Grafana datasource and a dashboard (CPU %, memory %, targets up, request rate, p95, error ratio, container CPU) are provisioned from files.
- README explains metrics vs logs vs alerts, lists the PromQL queries (CPU `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100`, memory, `up`, request rate, p95) and shows captured `/api/v1/targets`, `/metrics`, `/health`, logs, Grafana API and alert outputs (CPU 33 %, memory 47 %, HighLatencyP95/HighErrorRate firing under load, AppUnhealthy + InstanceDown firing after stopping the app).
- `k8s/` repeats it on the k3s cluster with `kube-prometheus-stack` (Helm, `--wait`), a `ServiceMonitor` and a `PrometheusRule`; captured: all chart pods Running, the sample-app targets `up`, the four rules loaded, per-pod CPU/memory, `kubectl top`. The pods run the public `prometheus-example-app` image because k3s cannot see locally built Docker images.

```bash
cd 01-monitoring && docker compose up -d --build && ./load.sh 120
```

## Task 2: Observability
Understand the three pillars (metrics, logs, traces) and document what each means, why observability is required, common tools, Kubernetes observability.

Done in [`02-observability/README.md`](02-observability/README.md): each pillar with concrete
examples from my sample app, monitoring vs observability, a tools table (Prometheus, Grafana,
Loki, ELK/EFK, Jaeger, Tempo, OpenTelemetry, Datadog, ...), Kubernetes observability
(metrics-server, kube-state-metrics, node-exporter, cAdvisor, `kubectl logs` -> Fluent Bit -> Loki,
traces via OpenTelemetry) and a small OTel SDK + Collector example.

## Task 3: GitOps
Learn: what is GitOps, Git as the source of truth, declarative configuration, continuous reconciliation, GitOps workflow, Kubernetes + GitOps.

Done in [`03-gitops/`](03-gitops/README.md): theory with ASCII diagrams and an Argo CD vs Flux
comparison, plus a demo: `install-argocd.sh` (captured: Argo CD v3.5.4 installed, 7 pods Running),
an Argo CD `Application` (automated sync + selfHeal + prune) pointing at
`gitops-repo/apps/demo-app` in this repository (nginx:alpine, 2 replicas, kustomize). Because my
fork is not pushed yet that Application honestly shows `ComparisonError: Repository not found`,
so a second `Application` (`application-local-demo.yaml`, same policy) points at the public
upstream course repo: captured `Synced/Healthy` in 21 s, the created pods, and self-healing after
`kubectl scale --replicas=1` (OutOfSync -> Synced in 4 s). The scale 2 -> 3 through a Git commit
stays expected until the fork is online.

```bash
cd 03-gitops && ./install-argocd.sh && kubectl apply -f argocd/application.yaml
```

## Validation I ran here

```bash
kubectl kustomize 03-gitops/gitops-repo/apps/demo-app | grep -c '^kind:'
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm template monitoring prometheus-community/kube-prometheus-stack -n monitoring -f 01-monitoring/k8s/values.yaml | grep -c '^kind:'
python3 -m py_compile 01-monitoring/sample-app/app.py && echo py-ok
bash -n 01-monitoring/load.sh 03-gitops/install-argocd.sh && echo bash-ok
```

Output (captured 2026-10-07)

```text
3
"prometheus-community" has been added to your repositories
126
py-ok
bash-ok
```

I also parsed every `.yml`/`.yaml` file with PyYAML and the dashboard JSON with `json.load`
(all 15 YAML files and the 7-panel dashboard load without errors). The container and cluster runs
themselves were done afterwards; see the captured blocks in the task READMEs.

## Screenshots

Terminal outputs replace screenshots, as listed in the `## Screenshots` section of each task README.

| Deliverable "Screenshots" | Where |
|---|---|
| Monitoring stack running, targets, metrics, alerts, logs | `01-monitoring/README.md` |
| `kubectl top`, `kubectl logs`, trace tree | `02-observability/README.md` |
| Argo CD pods, app Synced/Healthy, self-heal (captured); scale 2 -> 3 via Git (expected) | `03-gitops/README.md` |

## Deliverables

- Monitoring demo – `01-monitoring/` (compose stack, Prometheus/Alertmanager/Grafana config, sample app, k8s variant, README with PromQL and outputs).
- Observability documentation – `02-observability/README.md`.
- GitOps demo – `03-gitops/` (gitops-repo manifests, Argo CD Application, install script, README with demo steps).
- Screenshots – terminal output blocks in each task README (see table above).
- README.md – this index plus the three task READMEs.
