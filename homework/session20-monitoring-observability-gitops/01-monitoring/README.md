# Session 20 – Task 1: Monitoring demo
Student: Om Malviya | Enrollment No: 24BCS10448

## Task 1: Monitoring
Learn and demonstrate: metrics, logs, alerts, CPU utilization, memory utilization, application health.

I built a small Docker Compose stack that covers every bullet:

```text
                 +-------------+        +--------------+
  scrape /metrics|  Prometheus |------->| Alertmanager |---> webhook (placeholder)
   +------------>|  :9090      | alerts |  :9093       |
   |             +------+------+        +--------------+
   |                    | PromQL
   |                    v
   |             +-------------+
   |             |   Grafana   |  provisioned datasource + dashboard
   |             |   :3000     |
   |             +-------------+
   |
   +-- node-exporter :9100  (host CPU, memory, disk)
   +-- cadvisor      :8081  (per-container CPU / memory)
   +-- sample-app    :8000  (python prometheus_client: counter, histogram, gauge, /health)
   +-- prometheus / alertmanager themselves
```

| Spec bullet | Where it is demonstrated |
|---|---|
| Metrics | `sample-app` exposes `/metrics`; node-exporter and cAdvisor expose host/container metrics; Prometheus scrapes all of them |
| Logs | `docker compose logs sample-app` (one log line per request) |
| Alerts | `alert-rules.yml` (HighCPU, HighMemory, InstanceDown, AppUnhealthy, HighErrorRate, HighLatencyP95) routed to Alertmanager |
| CPU utilization | PromQL on `node_cpu_seconds_total`, Grafana panel, HighCPU alert |
| Memory utilization | PromQL on `node_memory_*`, Grafana panel, HighMemory alert |
| Application health | `/health` endpoint, `up{job="sample-app"}`, AppUnhealthy alert, Grafana stat panel |

### Files

```text
01-monitoring/
├── docker-compose.yml          prometheus, node-exporter, cadvisor, alertmanager, grafana, sample-app
├── prometheus.yml              scrape config for all six targets + alertmanager + rule_files
├── alert-rules.yml             alert rules
├── alertmanager.yml            route -> webhook placeholder receiver
├── load.sh                     traffic generator (~10% requests hit /error on purpose)
├── sample-app/
│   ├── app.py                  stdlib http.server + prometheus_client
│   ├── Dockerfile              python:3.12-slim, non-root, HEALTHCHECK on /health
│   └── requirements.txt
├── grafana/
│   ├── provisioning/datasources/prometheus.yml
│   ├── provisioning/dashboards/dashboards.yml
│   └── dashboards/session20.json   CPU %, memory %, targets up, request rate, p95, error ratio, container CPU
└── k8s/                        kube-prometheus-stack guide + ServiceMonitor + PrometheusRule (see k8s/README.md)
```

## Metrics vs logs vs alerts (in my words)

- **Metric**: a number sampled over time with labels, e.g. `app_requests_total{status="500"} 7`. Cheap to store, easy to aggregate, great for dashboards and thresholds. Prometheus pulls them from `/metrics`.
- **Log**: a line of text describing one event, e.g. `2026-10-07T22:29:13 INFO 127.0.0.1 "GET /error HTTP/1.1" 500 -`. It tells me *what* happened to *that* request; it cannot tell me "7 per second" without processing.
- **Alert**: a *rule* on top of metrics: `expr` + `for` duration. When the expression is true long enough, Prometheus fires the alert to Alertmanager, which groups/deduplicates and sends it somewhere (webhook, Slack, PagerDuty). Alerts are how monitoring tells a human "something is wrong" instead of waiting for someone to look at a dashboard.

The sample app shows the three Prometheus metric types:

| Type | Metric | Why |
|---|---|---|
| Counter | `app_requests_total{method,path,status}` | only goes up; `rate()` gives requests/second and error rate |
| Histogram | `app_request_duration_seconds{path}` | buckets of latency; `histogram_quantile()` gives p50/p95 |
| Gauge | `app_in_progress_requests`, `app_start_time_seconds` | a value that can go up and down |

## How to run

```bash
cd homework/session20-monitoring-observability-gitops/01-monitoring
docker compose up -d --build
docker compose ps
```

Output (captured 2026-10-07, Colima Docker 29.5 / Compose 5.6; the `[::]` port column trimmed)

```text
NAME                      IMAGE                              COMMAND                  SERVICE         CREATED          STATUS                    PORTS
session20-alertmanager    prom/alertmanager:v0.28.1          "/bin/alertmanager -…"   alertmanager    32 seconds ago   Up 31 seconds             0.0.0.0:9093->9093/tcp
session20-cadvisor        gcr.io/cadvisor/cadvisor:v0.52.1   "/usr/bin/cadvisor -…"   cadvisor        32 seconds ago   Up 31 seconds (healthy)   0.0.0.0:8081->8080/tcp
session20-grafana         grafana/grafana:12.1.1             "/run.sh"                grafana         32 seconds ago   Up 31 seconds             0.0.0.0:3000->3000/tcp
session20-node-exporter   prom/node-exporter:v1.9.1          "/bin/node_exporter …"   node-exporter   32 seconds ago   Up 31 seconds             0.0.0.0:9100->9100/tcp
session20-prometheus      prom/prometheus:v3.5.0             "/bin/prometheus --c…"   prometheus      32 seconds ago   Up 31 seconds             0.0.0.0:9090->9090/tcp
session20-sample-app      session20-sample-app:1.0           "python app.py"          sample-app      32 seconds ago   Up 31 seconds (healthy)   0.0.0.0:8000->8000/tcp
```

The `docker compose up -d --build` step built `session20-sample-app:1.0` from `sample-app/Dockerfile` and pulled the five public images (about 2 minutes on this connection).

Generate some traffic so the graphs are not flat:

```bash
./load.sh 120
```

UIs: Prometheus http://localhost:9090, Alertmanager http://localhost:9093, Grafana http://localhost:3000 (admin/admin, lab only), cAdvisor http://localhost:8081.

Note for macOS: node-exporter and cAdvisor report the metrics of the Docker Desktop/Colima Linux VM, not the Mac itself. That is expected.

## Application health and metrics

With the stack running (and `./load.sh` sending traffic in the background) I checked the two endpoints of the container:

```bash
curl -si localhost:8000/health
```

Output (captured 2026-10-07)

```text
HTTP/1.0 200 OK
Server: BaseHTTP/0.6 Python/3.12.15
Date: Wed, 07 Oct 2026 17:09:42 GMT
Content-Type: application/json
Content-Length: 16

{"status": "ok"}
```

```bash
curl -s localhost:8000/metrics | head -20
```

Output (captured 2026-10-07; the python client adds its own process/GC metrics before mine)

```text
# HELP python_gc_objects_collected_total Objects collected during gc
# TYPE python_gc_objects_collected_total counter
python_gc_objects_collected_total{generation="0"} 301.0
python_gc_objects_collected_total{generation="1"} 28.0
python_gc_objects_collected_total{generation="2"} 0.0
# HELP python_gc_objects_uncollectable_total Uncollectable objects found during GC
# TYPE python_gc_objects_uncollectable_total counter
python_gc_objects_uncollectable_total{generation="0"} 0.0
python_gc_objects_uncollectable_total{generation="1"} 0.0
python_gc_objects_uncollectable_total{generation="2"} 0.0
# HELP python_gc_collections_total Number of times this generation was collected
# TYPE python_gc_collections_total counter
python_gc_collections_total{generation="0"} 31.0
python_gc_collections_total{generation="1"} 2.0
python_gc_collections_total{generation="2"} 0.0
# HELP python_info Python platform information
# TYPE python_info gauge
python_info{implementation="CPython",major="3",minor="12",patchlevel="15",version="3.12.15"} 1.0
# HELP process_virtual_memory_bytes Virtual memory size in bytes.
# TYPE process_virtual_memory_bytes gauge
```

```bash
curl -s localhost:8000/metrics | grep -E '^(# (HELP|TYPE) app_|app_requests_total|app_in_progress|app_start_time|app_request_duration_seconds_(count|sum))'
```

Output (captured 2026-10-07, a few seconds into the load run; histogram buckets filtered out for readability)

```text
# HELP app_requests_total Total HTTP requests handled by the sample app
# TYPE app_requests_total counter
app_requests_total{method="GET",path="/health",status="200"} 6.0
app_requests_total{method="GET",path="/",status="200"} 14.0
app_requests_total{method="GET",path="/slow",status="200"} 13.0
app_requests_total{method="GET",path="/error",status="500"} 4.0
# HELP app_request_duration_seconds Request latency in seconds
# TYPE app_request_duration_seconds histogram
app_request_duration_seconds_count{path="/health"} 6.0
app_request_duration_seconds_sum{path="/health"} 0.0015113079999764523
app_request_duration_seconds_count{path="/"} 14.0
app_request_duration_seconds_sum{path="/"} 0.0013465270001233876
app_request_duration_seconds_count{path="/slow"} 13.0
app_request_duration_seconds_sum{path="/slow"} 7.499952428000256
app_request_duration_seconds_count{path="/error"} 4.0
app_request_duration_seconds_sum{path="/error"} 0.00035951499978637
# HELP app_in_progress_requests Number of requests currently being handled
# TYPE app_in_progress_requests gauge
app_in_progress_requests 1.0
# HELP app_start_time_seconds Unix timestamp at which the sample app started
# TYPE app_start_time_seconds gauge
app_start_time_seconds 1.7913929309090238e+09
```

The `/health` requests in the counter come from the Dockerfile `HEALTHCHECK` (every 10 s), which is also why `docker compose ps` shows `(healthy)`.

### Logs

```bash
docker compose logs --no-log-prefix sample-app | head -12
```

Output (captured 2026-10-07, first lines after start: 172.18.0.6 is Prometheus scraping every 5 s, 127.0.0.1 is the Docker HEALTHCHECK every 10 s)

```text
sample-app listening on :8000 (metrics at /metrics)
2026-10-07T17:08:58 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:00 INFO 127.0.0.1 "GET /health HTTP/1.1" 200 -
2026-10-07T17:09:03 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:08 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:10 INFO 127.0.0.1 "GET /health HTTP/1.1" 200 -
2026-10-07T17:09:13 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:18 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:21 INFO 127.0.0.1 "GET /health HTTP/1.1" 200 -
2026-10-07T17:09:23 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:28 INFO 172.18.0.6 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:09:31 INFO 127.0.0.1 "GET /health HTTP/1.1" 200 -
```

```bash
docker compose logs --no-log-prefix sample-app | grep -E 'GET /(slow|error) HTTP|GET / HTTP' | head -6
docker compose logs --no-log-prefix sample-app | grep -c 'GET /error'
```

Output (captured 2026-10-08, after two `load.sh` runs; 172.18.0.1 is the host running `load.sh`)

```text
2026-10-07T17:09:32 INFO 172.18.0.1 "GET / HTTP/1.1" 200 -
2026-10-07T17:09:32 INFO 172.18.0.1 "GET /slow HTTP/1.1" 200 -
2026-10-07T17:09:33 INFO 172.18.0.1 "GET / HTTP/1.1" 200 -
2026-10-07T17:09:33 INFO 172.18.0.1 "GET /slow HTTP/1.1" 200 -
2026-10-07T17:09:33 INFO 172.18.0.1 "GET / HTTP/1.1" 200 -
2026-10-07T17:09:34 INFO 172.18.0.1 "GET /slow HTTP/1.1" 200 -
51
```

I observed that the same `/error` requests appear once per request as a log line with status `500` (an event) and in aggregate as `app_requests_total{path="/error",status="500"}` (a number). That is the metrics vs logs difference in one picture: the log answers "what happened to that request", the counter answers "how many / how fast".

## Prometheus targets

```bash
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.scrapeUrl)\t\(.health)"'
```

Output (captured 2026-10-07, about 40 s after `docker compose up`)

```text
alertmanager   http://alertmanager:9093/metrics   up
cadvisor       http://cadvisor:8080/metrics       up
node-exporter  http://node-exporter:9100/metrics  up
prometheus     http://prometheus:9090/metrics     up
sample-app     http://sample-app:8000/metrics     up
```

The compact form `curl -s localhost:9090/api/v1/targets | jq -c '.data.activeTargets[] | {job: .labels.job, health}'` gives:

Output (captured 2026-10-07)

```text
{"job":"alertmanager","health":"up"}
{"job":"cadvisor","health":"up"}
{"job":"node-exporter","health":"up"}
{"job":"prometheus","health":"up"}
{"job":"sample-app","health":"up"}
```

Raw shape of the sample-app entry (`curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="sample-app")'`):

Output (captured 2026-10-07, `discoveredLabels` trimmed to two keys)

```text
{
  "discoveredLabels": {
    "__address__": "sample-app:8000",
    "job": "sample-app"
  },
  "labels": {
    "app": "sample-app",
    "instance": "sample-app:8000",
    "job": "sample-app"
  },
  "scrapePool": "sample-app",
  "scrapeUrl": "http://sample-app:8000/metrics",
  "lastError": "",
  "lastScrape": "2026-10-07T17:09:38.429942768Z",
  "lastScrapeDuration": 0.001488181,
  "health": "up",
  "scrapeInterval": "5s",
  "scrapeTimeout": "5s"
}
```

## PromQL queries I use

| Goal | Query |
|---|---|
| CPU utilization % (whole host) | `100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| CPU utilization % per instance | `100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Memory utilization % | `(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100` |
| Application health (1 up, 0 down) | `up{job="sample-app"}` |
| All targets health | `up` |
| Request rate (req/s) | `sum(rate(app_requests_total[1m]))` |
| Request rate per status | `sum by (status) (rate(app_requests_total[1m]))` |
| Error ratio (5xx) | `sum(rate(app_requests_total{status=~"5.."}[5m])) / sum(rate(app_requests_total[5m]))` |
| p95 latency | `histogram_quantile(0.95, sum by (le) (rate(app_request_duration_seconds_bucket[5m])))` |
| Container CPU % (cAdvisor) | `sum by (name) (rate(container_cpu_usage_seconds_total{name=~"session20.*"}[1m])) * 100` |
| Container memory (cAdvisor) | `container_memory_working_set_bytes{name=~"session20.*"}` |

I ran the queries through the HTTP API (same result as typing them into the Prometheus UI):

```bash
P=localhost:9090/api/v1/query
curl -s $P --data-urlencode 'query=100 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))*100' | jq -c '.data.result[0].value'
curl -s $P --data-urlencode 'query=100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100' | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
curl -s $P --data-urlencode 'query=(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100' | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
curl -s $P --data-urlencode 'query=node_memory_MemTotal_bytes' | jq -r '.data.result[0].value[1]'
curl -s $P --data-urlencode 'query=up' | jq -r '.data.result[] | "\(.metric.job) \(.value[1])"'
```

Output (captured 2026-10-08, while `load.sh` was running; the VM has 4 vCPUs and 6 GB)

```text
[1791406649.941,"32.9771186440678"]
node-exporter:9100 32.9771186440678
node-exporter:9100 47.364163301454695
6197370880
alertmanager 1
cadvisor 1
sample-app 1
node-exporter 1
prometheus 1
```

So CPU utilization of the VM was about 33 % and memory utilization about 47 % (of 6197370880 bytes = 5.8 GiB), and all five targets report `up = 1`.

```bash
curl -s $P --data-urlencode 'query=sum(rate(app_requests_total[1m]))' | jq -c '.data.result[0].value'
curl -s $P --data-urlencode 'query=sum by (status) (rate(app_requests_total[1m]))' | jq -r '.data.result[] | "\(.metric.status) \(.value[1])"'
curl -s $P --data-urlencode 'query=sum(rate(app_requests_total{status=~"5.."}[5m])) / sum(rate(app_requests_total[5m]))' | jq -r '.data.result[0].value[1]'
curl -s $P --data-urlencode 'query=histogram_quantile(0.95, sum by (le) (rate(app_request_duration_seconds_bucket[5m])))' | jq -r '.data.result[0].value[1]'
curl -s $P --data-urlencode 'query=histogram_quantile(0.95, sum by (path, le) (rate(app_request_duration_seconds_bucket[5m])))' | jq -r '.data.result[] | "\(.metric.path) \(.value[1])"'
```

Output (captured 2026-10-08, right after a 160 s `load.sh` run)

```text
[1791406821.518,"1.5090634715732443"]
200 1.4363375211359795
500 0.07272595043726478
0.05088495575221239
0.9088709677419353
/slow 0.9596774193548386
/error 0.00475
/health 0.00475
/ 0.00475
```

Reading this: about 1.5 requests/s, 5.1 % of them 5xx (load.sh sends roughly every 10th request to `/error`), overall p95 latency 0.91 s because `/slow` sleeps 0.5-1 s, while the other paths answer in under 5 ms (the lowest histogram bucket).

### Per-container metrics from cAdvisor (limitation on this host)

The queries `sum by (name) (rate(container_cpu_usage_seconds_total{name=~"session20.*"}[1m]))` and `container_memory_working_set_bytes{name=~"session20.*"}` returned an **empty result** here. The reason is in the cAdvisor log:

```bash
docker logs session20-cadvisor 2>&1 | grep 'Failed to create existing container' | head -1 | cut -c1-230
```

Output (captured 2026-10-07)

```text
E1007 17:08:50.858812       1 manager.go:1116] Failed to create existing container: /docker/ce669b0fef3e5e1fbdf0443ccceea7aeab62b1d308ad222a1ee1d517c51cb0b0: failed to identify the read-write layer ID for container "ce669b0fef3e5e..." - open /rootfs/va...
```

Docker 29 on this machine stores images in containerd (no `/var/lib/docker/image/overlay2/layerdb`), so cAdvisor v0.52 cannot attach to the Docker containers and only exports raw cgroup series without a `name` label (the k3s pods on the same VM show up as `/kubepods.slice/...` ids). The cAdvisor target itself is `up`, the Grafana "Container CPU" panel is just empty on this host. On a Docker host with the classic overlay2 store (or on Kubernetes, where the kubelet's cAdvisor labels by pod/container) the same queries work; the Kubernetes variant in `k8s/` is where I show per-pod CPU/memory instead.

## Alerts

Rules (`alert-rules.yml`):

| Alert | Expression (short) | for | severity |
|---|---|---|---|
| HighCPU | CPU utilization > 80 % | 2m | warning |
| HighMemory | memory utilization > 85 % | 2m | warning |
| InstanceDown | `up == 0` | 1m | critical |
| AppUnhealthy | `up{job="sample-app"} == 0` | 30s | critical |
| HighErrorRate | 5xx ratio > 5 % | 2m | warning |
| HighLatencyP95 | p95 > 0.5 s | 2m | warning |

State of every rule right after the load run (nothing stopped yet):

```bash
curl -s localhost:9090/api/v1/rules | jq -r '.data.groups[].rules[] | "\(.name)\t\(.state)\t\(.health)"'
curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname)\t\(.labels.severity)\t\(.state)\t\(.annotations.description)"'
curl -s localhost:9093/api/v2/alerts | jq -r '.[] | "\(.labels.alertname)\t\(.status.state)\t\(.startsAt)\t\(.receivers[0].name)"'
```

Output (captured 2026-10-08)

```text
HighCPU         inactive  ok
HighMemory      inactive  ok
InstanceDown    inactive  ok
AppUnhealthy    inactive  ok
HighErrorRate   pending   ok
HighLatencyP95  firing    ok

HighErrorRate   warning   pending   5.088% of requests returned 5xx in the last 5 minutes.
HighLatencyP95  warning   firing    p95 latency is 0.909s.

HighLatencyP95  active   2026-10-07T20:59:22.220Z   webhook-placeholder
```

`HighLatencyP95` fires because `/slow` pushes p95 above 0.5 s; `HighErrorRate` is `pending` (yellow in the UI): the 5.09 % ratio is above the 5 % threshold but had not yet been true for the full `for: 2m`. Only firing alerts reach Alertmanager, which is why it lists one.

Then I triggered the health alerts on purpose by stopping the app:

```bash
docker compose stop sample-app
sleep 95
curl -s localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)\t\(.lastError)"'
curl -s localhost:9090/api/v1/query --data-urlencode 'query=up{job="sample-app"}' | jq -c '.data.result[0].value'
curl -s localhost:9090/api/v1/alerts | jq -r '.data.alerts[] | "\(.labels.alertname)\t\(.labels.severity)\t\(.state)"'
curl -s localhost:9093/api/v2/alerts | jq -r '.[] | "\(.labels.alertname)\t\(.status.state)\t\(.startsAt)"'
```

Output (captured 2026-10-08)

```text
alertmanager   up
cadvisor       up
node-exporter  up
prometheus     up
sample-app     down   Get "http://sample-app:8000/metrics": dial tcp: lookup sample-app on 127.0.0.11:53: no such host

[1791406963.987,"0"]

InstanceDown    critical  firing
AppUnhealthy    critical  firing
HighErrorRate   warning   firing
HighLatencyP95  warning   firing

AppUnhealthy    active  2026-10-07T21:01:37.220Z
HighErrorRate   active  2026-10-07T21:01:52.220Z
InstanceDown    active  2026-10-07T21:02:07.543Z
HighLatencyP95  active  2026-10-07T20:59:22.220Z
```

The timestamps show the `for` durations working: the app was stopped at 21:00:50, `AppUnhealthy` (`for: 30s`) started at 21:01:37 and `InstanceDown` (`for: 1m`) at 21:02:07. `HighErrorRate` turned from pending to firing at 21:01:52, two minutes after the error ratio crossed 5 %. One alert as Alertmanager stores it:

```bash
curl -s localhost:9093/api/v2/alerts | jq '.[] | select(.labels.alertname=="AppUnhealthy") | {labels, annotations, startsAt, status, receivers}'
```

Output (captured 2026-10-08)

```text
{
  "labels": {
    "alertname": "AppUnhealthy",
    "app": "sample-app",
    "instance": "sample-app:8000",
    "job": "sample-app",
    "severity": "critical"
  },
  "annotations": {
    "description": "The /metrics endpoint of sample-app is not responding (up == 0).",
    "summary": "sample-app is unhealthy"
  },
  "startsAt": "2026-10-07T21:01:37.220Z",
  "status": {
    "inhibitedBy": [],
    "mutedBy": [],
    "silencedBy": [],
    "state": "active"
  },
  "receivers": [
    {
      "name": "webhook-placeholder"
    }
  ]
}
```

Alertmanager tries to POST every group to the placeholder webhook URL and nothing listens there:

```bash
docker compose logs --no-log-prefix alertmanager | grep 'Notify for alerts failed' | tail -1
```

Output (captured 2026-10-08, trimmed)

```text
time=2026-10-07T21:00:05.689Z level=ERROR source=dispatch.go:360 msg="Notify for alerts failed" component=dispatcher num_alerts=1 err="webhook-placeholder/webhook[0]: notify retry canceled due to unrecoverable error after 1 attempts: unexpected status code 404
```

Swapping that URL for a Slack/Teams/PagerDuty webhook is the only change needed to get paged. After `docker compose start sample-app`, `up{job="sample-app"}` went back to `1` within one scrape (captured `[1791406984.260,"1"]`), and the alerts resolve after their next evaluation.

## Grafana

Login at http://localhost:3000 (admin / admin). The Prometheus datasource and the dashboard "Session 20 - Monitoring" (folder "Session 20") are provisioned automatically, no clicking needed. Panels:

1. Targets up (stat, green = 1)
2. CPU utilization % (threshold line at 80)
3. Memory utilization % (threshold at 85)
4. App request rate by status
5. App p50 / p95 latency
6. App 5xx error ratio (threshold at 5 %)
7. Container CPU from cAdvisor

```bash
curl -s localhost:3000/api/health
curl -s -u admin:admin 'localhost:3000/api/search?query=Session' | jq -r '.[] | "\(.title)\t\(.uid)\t\(.type)\t\(.folderTitle)"'
curl -s -u admin:admin localhost:3000/api/datasources | jq -r '.[] | "\(.name)\t\(.type)\t\(.url)\t\(.isDefault)"'
```

Output (captured 2026-10-07)

```text
{
  "database": "ok",
  "version": "12.1.1",
  "commit": "df5de8219b41d1e639e003bf5f3a85913761d167"
}
Session 20                 cg0j1eg2rq22oa          dash-folder   null
Session 20 - Monitoring    session20-monitoring    dash-db       Session 20
Prometheus    prometheus    http://prometheus:9090    true
```

Both the folder and the dashboard were created by the provisioning files at start-up, and the Prometheus datasource is the default one, so the dashboard panels query it without any manual setup.

## Kubernetes variant

`k8s/README.md` shows the same thing on a cluster with `kube-prometheus-stack` (Prometheus Operator, Grafana, node-exporter, kube-state-metrics, Alertmanager via Helm) plus a `ServiceMonitor` and `PrometheusRule` for the sample app.

## Stop

```bash
docker compose down -v
```

Output (captured 2026-10-08)

```text
 Container session20-cadvisor Stopping
 Container session20-node-exporter Stopping
 Container session20-grafana Stopping
 Container session20-node-exporter Stopped
 Container session20-node-exporter Removing
 Container session20-cadvisor Stopped
 Container session20-cadvisor Removing
 Container session20-node-exporter Removed
 Container session20-grafana Stopped
 Container session20-grafana Removing
 Container session20-cadvisor Removed
 Container session20-grafana Removed
 Container session20-prometheus Stopping
 Container session20-prometheus Stopped
 Container session20-prometheus Removing
 Container session20-prometheus Removed
 Container session20-sample-app Stopping
 Container session20-alertmanager Stopping
 Container session20-alertmanager Stopped
 Container session20-alertmanager Removing
 Container session20-alertmanager Removed
 Container session20-sample-app Stopped
 Container session20-sample-app Removing
 Container session20-sample-app Removed
 Volume 01-monitoring_grafana-data Removing
 Volume 01-monitoring_prometheus-data Removing
 Network 01-monitoring_default Removing
 Volume 01-monitoring_grafana-data Removed
 Volume 01-monitoring_prometheus-data Removed
 Network 01-monitoring_default Removed
```

## Screenshots

| Screenshot asked for | Stands in |
|---|---|
| Containers running | captured `docker compose ps` output above |
| /health and /metrics | captured curl outputs above |
| Prometheus targets page | captured `/api/v1/targets` outputs (all up, then sample-app down) |
| CPU / memory graphs | captured PromQL results (CPU 33 %, memory 47 %) + Grafana dashboard JSON (`grafana/dashboards/session20.json`) and the captured Grafana API output |
| Alerts firing | captured `/api/v1/rules`, `/api/v1/alerts` and Alertmanager `/api/v2/alerts` outputs |
| Application logs | captured `sample-app` log blocks |

## Deliverables

- `docker-compose.yml` – full monitoring stack (Prometheus, node-exporter, cAdvisor, Alertmanager, Grafana, sample app).
- `prometheus.yml`, `alert-rules.yml`, `alertmanager.yml` – scrape config, 6 alert rules, placeholder webhook receiver.
- `sample-app/` – python app with counter, histogram, gauge and `/health`; Dockerfile.
- `grafana/` – provisioned datasource and dashboard JSON (CPU, memory, request rate, p95, errors).
- `load.sh` – traffic generator.
- `k8s/` – kube-prometheus-stack install guide, values, ServiceMonitor, PrometheusRule, sample-app manifests.
- `README.md` – this file: how to run, PromQL, captured outputs, metrics vs logs vs alerts.
