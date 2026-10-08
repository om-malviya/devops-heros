# monitoring/

| File | Purpose |
|------|---------|
| `kube-prometheus-stack-values.yaml` | Helm values for Prometheus Operator + Grafana + Alertmanager + node-exporter + kube-state-metrics |
| `servicemonitor.yaml` | tells Prometheus to scrape `taskboard-backend` Service port `http` at `/metrics` every 15 s |
| `prometheusrule.yaml` | 6 alerts: backend down, crash loop, not ready, 5xx ratio > 5 %, p95 > 500 ms, HPA at max |
| `grafana-dashboard-configmap.yaml` | ConfigMap with label `grafana_dashboard=1`; the Grafana sidecar imports it automatically |
| `dashboards/taskboard-dashboard.json` | the same dashboard for manual import (10 panels: rate, errors, latency, HPA, CPU, memory) |

## Install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace -f monitoring/kube-prometheus-stack-values.yaml
kubectl apply -f monitoring/servicemonitor.yaml -f monitoring/prometheusrule.yaml -f monitoring/grafana-dashboard-configmap.yaml

kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090   # http://localhost:9090/targets
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80       # admin / grafana-demo-admin
```

```text
Output (captured 2026-10-08, k3s; namespace monitoring-s21 because "monitoring" was taken on the shared cluster,
so grafana-dashboard-configmap.yaml was applied through sed "s/namespace: monitoring$/namespace: monitoring-s21/")
$ helm upgrade --install kube-prometheus-stack ... -n monitoring-s21 --create-namespace -f monitoring/kube-prometheus-stack-values.yaml --wait
NAME: kube-prometheus-stack   STATUS: deployed   REVISION: 1   (chart 92.1.0, Prometheus Operator v0.94.1)
$ kubectl -n monitoring-s21 get pods
alertmanager-kube-prometheus-stack-alertmanager-0          2/2   Running
kube-prometheus-stack-grafana-7968bb55-dt9dp               3/3   Running
kube-prometheus-stack-kube-state-metrics-7757df4df-mv568   1/1   Running
kube-prometheus-stack-operator-746d485dc-28dx5             1/1   Running
kube-prometheus-stack-prometheus-node-exporter-lqd77       1/1   Running
prometheus-kube-prometheus-stack-prometheus-0              2/2   Running
$ curl -s localhost:8290/api/v1/targets        # port-forward of svc/kube-prometheus-stack-prometheus, filtered to taskboard
serviceMonitor/taskboard/taskboard-backend/0   taskboard-backend-6db658b5f-89gb6   UP   last scrape 2026-10-07T21:29:02
serviceMonitor/taskboard/taskboard-backend/0   taskboard-backend-6db658b5f-cql67   UP   last scrape 2026-10-07T21:29:03
$ curl -s 'localhost:8290/api/v1/query?query=sum by (handler) (rate(http_requests_total{namespace="taskboard"}[2m]))'
/health 0.045   /ready 0.068   /api/tasks 0.033   /api/tasks/stats 0   /metrics 0.029   (req/s)
$ curl -s 'localhost:8290/api/v1/query?query=histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="taskboard"}[5m])))'
0.095
$ curl -s localhost:8290/api/v1/rules | <groups taskboard.*>
taskboard.availability  TaskboardBackendDown, TaskboardPodCrashLooping, TaskboardPodNotReady      state=inactive
taskboard.traffic       TaskboardHighErrorRate, TaskboardHighLatencyP95, TaskboardHpaAtMaxReplicas  state=inactive
$ curl -s -u admin:<GRAFANA_ADMIN_PASSWORD> "localhost:8291/api/search?query=TaskBoard"   # port-forward of the Grafana svc
TaskBoard - API overview -> /d/taskboard-api/taskboard-api-overview
```

Gotcha I hit: the ServiceMonitor selects the Service by `app=taskboard-backend`. If that label is missing (it had
been pruned by a `kubectl apply` of a manifest without labels), Prometheus lists the pods under *droppedTargets*
and `up{namespace="taskboard"}` is empty - check `get svc --show-labels` before suspecting the operator.

## Metrics exposed by the backend

`prometheus-fastapi-instrumentator` adds to `GET /metrics`:

| Metric | Type | Labels |
|--------|------|--------|
| `http_requests_total` | counter | `handler`, `method`, `status` |
| `http_request_duration_seconds` | histogram (`_bucket/_sum/_count`) | `handler`, `method` |
| `http_request_size_bytes`, `http_response_size_bytes` | summary | `handler` |
| `http_requests_inprogress` | gauge | `handler`, `method` |
| `process_*`, `python_gc_*` | default client metrics | |

## PromQL used on the dashboard / alerts

```promql
# request rate per endpoint (RED: Rate)
sum by (handler) (rate(http_requests_total{namespace="taskboard"}[1m]))

# error ratio (RED: Errors)
sum(rate(http_requests_total{namespace="taskboard",status=~"5.."}[5m]))
  / sum(rate(http_requests_total{namespace="taskboard"}[5m]))

# p95 latency (RED: Duration)
histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{namespace="taskboard"}[5m])))

# slowest endpoint
topk(3, histogram_quantile(0.95, sum by (le, handler) (rate(http_request_duration_seconds_bucket[5m]))))

# scrape health
up{namespace="taskboard"}

# HPA behaviour
kube_horizontalpodautoscaler_status_current_replicas{namespace="taskboard"}
sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="taskboard",container="backend"}[2m]))
```

## Logs

Container logs go to stdout (uvicorn access log, nginx access log) and are read with
`kubectl logs -n taskboard deploy/taskboard-backend -f`. For centralised logs the same stack is extended with
Loki + Promtail (`grafana/loki-stack`); Grafana then queries `{namespace="taskboard", container="backend"} |= "ERROR"`.
