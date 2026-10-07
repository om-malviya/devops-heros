# Session 20 – Task 2: Observability documentation
Student: Om Malviya | Enrollment No: 24BCS10448

## Task 2: Observability
Understand the three major pillars (metrics, logs, traces) and document: what each pillar means, why observability is required, common tools, Kubernetes observability.

## The three pillars

```text
Metrics = numbers      -> HOW MUCH / HOW OFTEN?
Logs    = events       -> WHAT happened?
Traces  = journey      -> WHERE did the request spend its time?
```

### 1. Metrics

A metric is a numeric measurement with a name, labels and a timestamp, stored as a time series.
Metrics are cheap (one number per sample), easy to aggregate (`sum`, `avg`, `rate`) and are what
dashboards and alerts are built on. They answer "how much?" and "how often?" but not "why?".

Example from my sample app in `../01-monitoring`:

```text
app_requests_total{method="GET",path="/error",status="500"} 7
app_request_duration_seconds_bucket{le="0.5",path="/slow"} 12
node_memory_MemAvailable_bytes{instance="node-exporter:9100"} 2.1e+09
```

Types: counter (only increases), gauge (up and down), histogram (buckets, used for percentiles), summary.

### 2. Logs

A log is a timestamped record of a single event, usually text or JSON. Logs carry the detail
metrics lose: which user, which request id, what the stack trace was. They are expensive at scale
(every request writes a line) and need indexing/parsing to be searched.

```text
2026-10-07T22:29:13 INFO 127.0.0.1 "GET /error HTTP/1.1" 500 -
{"ts":"2026-10-07T22:29:13Z","level":"error","msg":"db timeout","trace_id":"4bf92f3577b34da6","user":"u-1042","duration_ms":1203}
```

The second line is a *structured* log. Putting `trace_id` in it is what links logs to traces.

### 3. Traces

A trace follows one request through all services it touches. It is a tree of **spans**; each span
has a name, start time, duration and parent. Traces answer "where did the 2 seconds go?" in a
microservice system where no single service's metrics show the problem.

```text
trace_id 4bf92f3577b34da6                 total 1 420 ms
└── frontend  GET /checkout               1 420 ms
    ├── api-gateway  POST /orders            1 350 ms
    │   ├── order-service  createOrder         1 300 ms
    │   │   ├── SELECT inventory                   40 ms
    │   │   └── payment-service  charge          1 200 ms   <-- the slow part
    │   │       └── INSERT payments               1 180 ms  <-- lock wait
    │   └── notification-service  enqueue           20 ms
    └── static assets                              30 ms
```

### Comparison

| | Metrics | Logs | Traces |
|---|---|---|---|
| Unit | number per time | event line | span tree per request |
| Good for | dashboards, alerts, trends | debugging one event, audit | latency breakdown across services |
| Cardinality / cost | low | high | medium (usually sampled) |
| Question | is something wrong? how much? | what exactly happened? | where in the request path? |
| Tools | Prometheus, Grafana | Loki, Elasticsearch | Jaeger, Tempo |

They work best together: an alert on a metric (error ratio > 5 %), then the logs for those
minutes, then the trace id from a log to see which downstream call failed.

## Why observability is required (vs monitoring)

Monitoring (Task 1) watches *known* failure signals: CPU > 80 %, `up == 0`, error ratio > 5 %.
I decide in advance what to measure and what threshold means trouble. That is excellent for
problems I already know about.

Observability is the property of a system that lets me ask *new* questions about it from the
outside, without shipping new code. It is needed because:

1. **Unknown unknowns.** Users say "checkout is slow for some people". No dashboard was built for
   that. With traces and structured logs I can filter by user, region, version and find the pattern.
2. **Distributed systems.** One request may cross 10 services and 3 queues. Each service looks
   healthy on its own dashboard; only a trace shows the end-to-end latency.
3. **Ephemeral infrastructure.** In Kubernetes pods come and go in seconds. SSH-ing into a box to
   read `/var/log` does not work; logs and metrics must be shipped out centrally.
4. **Faster root cause, less guessing.** Monitoring tells me *that* and *when*; observability
   tells me *why*. This directly reduces MTTR.
5. **Correlation.** The same labels (service, pod, namespace, trace_id) across metrics, logs and
   traces let me jump from a spike on a graph to the exact requests behind it.

| Monitoring | Observability |
|---|---|
| Is something wrong? | Why is it wrong? |
| Pre-defined dashboards and alerts | Explore arbitrary questions |
| Known failure modes | Unknown failure modes |
| Mostly metrics | Metrics + logs + traces, correlated |
| An activity I do | A property the system has |

Monitoring is a subset of observability: an observable system is easy to monitor, but a monitored
system is not automatically observable.

## Common tools

| Tool | Pillar | What it does | Notes |
|---|---|---|---|
| Prometheus | metrics | pull-based scraping, TSDB, PromQL, alert rules | CNCF, de-facto standard on Kubernetes |
| Alertmanager | metrics (alerts) | groups, silences and routes Prometheus alerts | ships with Prometheus |
| Grafana | all (visualization) | dashboards over Prometheus, Loki, Tempo, Elasticsearch, ... | open source + cloud |
| Loki | logs | log aggregation indexed only by labels ("Prometheus for logs"), LogQL | cheap, pairs with Grafana |
| Promtail / Grafana Alloy / Fluent Bit / Fluentd | logs (shipping) | agents that tail container logs and ship them to Loki/Elasticsearch | Fluent Bit is lightweight, common as a DaemonSet |
| ELK / EFK | logs | Elasticsearch + Logstash (or Fluentd) + Kibana; full-text indexed logs | powerful search, heavier to run |
| Jaeger | traces | distributed tracing backend and UI | CNCF, OTLP compatible |
| Zipkin | traces | older tracing backend | simple, still common |
| Grafana Tempo | traces | trace storage in object storage, queried from Grafana | scales cheaply, links to Loki/Prometheus |
| OpenTelemetry (OTel) | all (instrumentation) | vendor-neutral SDKs, auto-instrumentation and Collector for metrics/logs/traces | standard way to produce signals; backend-agnostic |
| kube-prometheus-stack | metrics | Helm chart: Prometheus Operator + Grafana + exporters + default alerts | used in `../01-monitoring/k8s` |
| Datadog | all (SaaS) | agents + hosted metrics, logs, APM, dashboards | commercial, easy, per-host pricing |
| New Relic / Dynatrace / Splunk / Elastic Observability | all (SaaS) | hosted full-stack observability and APM | commercial |
| AWS CloudWatch / X-Ray | all (cloud) | cloud-native metrics, logs and traces for AWS workloads | tied to AWS |

A typical open-source stack: OpenTelemetry SDK in the app -> OTel Collector -> Prometheus (metrics),
Loki (logs), Tempo or Jaeger (traces) -> Grafana for one UI over all three.

## Kubernetes observability

```text
+----------------------------------- Kubernetes node -----------------------------------+
|  kubelet ---- cAdvisor (built in): container CPU / memory / network / fs              |
|  node-exporter (DaemonSet): host CPU / memory / disk                                   |
|  Fluent Bit / Promtail (DaemonSet): tails /var/log/containers/*.log                    |
|  OTel Collector (DaemonSet or sidecar): receives OTLP from apps                        |
|  app pods: /metrics endpoint, stdout logs, OTel SDK spans                              |
+----------------------------------------------------------------------------------------+
        | metrics (scrape)         | logs (push)              | traces (push)
        v                          v                          v
   Prometheus  <-- kube-state-metrics (object state: deployments, pods, replicas)
   metrics-server (kubectl top, HPA)
        v                          v                          v
   Grafana  <--------------------- Loki <--------------------- Tempo / Jaeger
```

### Metrics

| Component | What it gives | How I use it |
|---|---|---|
| metrics-server | current CPU/memory per pod and node (not stored) | `kubectl top pods/nodes`, HorizontalPodAutoscaler |
| kube-state-metrics | state of API objects as metrics: `kube_deployment_status_replicas_available`, `kube_pod_status_phase`, `kube_pod_container_status_restarts_total` | alert on "fewer replicas than desired", CrashLoopBackOff |
| node-exporter | host-level metrics from each node | CPU %, memory %, disk full alerts |
| cAdvisor (inside kubelet, `/metrics/cadvisor`) | per-container CPU, memory, network | `container_cpu_usage_seconds_total`, `container_memory_working_set_bytes` |
| Application `/metrics` + ServiceMonitor | business metrics (requests, latency, errors) | see `../01-monitoring/k8s/servicemonitor.yaml` |
| kubelet, apiserver, etcd, coredns `/metrics` | control-plane health | default dashboards in kube-prometheus-stack |

```bash
kubectl top node
kubectl top pods -n s20-sample-app
```

Output (captured 2026-10-08, during the kube-prometheus-stack run described in `../01-monitoring/k8s/README.md`; the node was busy pulling images)

```text
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
colima   3352m        83%      4197Mi          71%

NAME                          CPU(cores)   MEMORY(bytes)
sample-app-5cc6bd7cd9-6gbcf   5m           19Mi
sample-app-5cc6bd7cd9-vh6ss   3m           20Mi
```

### Logs

Containers write to stdout/stderr; the container runtime stores them under
`/var/log/pods/` and `/var/log/containers/` on the node. Options from simple to production:

```bash
kubectl logs deployment/sample-app -n s20-sample-app --tail=5          # one deployment
kubectl logs -n s20-sample-app -l app=sample-app --all-containers -f   # all pods of a label, follow
kubectl logs sample-app-5cc6bd7cd9-6gbcf -n s20-sample-app --previous  # the crashed previous container
```

Expected output (I did not capture `kubectl logs` during the cluster run, where the pods ran the public example app; the format below is what my python sample app prints, captured from its container in `../01-monitoring/README.md`)

```text
sample-app listening on :8000 (metrics at /metrics)
2026-10-07T17:10:01 INFO 10.244.0.1 "GET /health HTTP/1.1" 200 -
2026-10-07T17:10:03 INFO 10.244.0.5 "GET /metrics HTTP/1.1" 200 -
2026-10-07T17:10:06 INFO 10.244.0.1 "GET /health HTTP/1.1" 200 -
2026-10-07T17:10:08 INFO 10.244.0.5 "GET /metrics HTTP/1.1" 200 -
```

`kubectl logs` is lost when the pod is deleted and does not search across pods. So a log agent
runs as a DaemonSet on every node, adds Kubernetes metadata (namespace, pod, container, labels)
and ships lines to a central store:

```text
pod stdout -> /var/log/containers/*.log -> Fluent Bit (DaemonSet) -> Loki  -> Grafana (LogQL)
                                                                   -> Elasticsearch -> Kibana (EFK)
```

LogQL example in Grafana: `{namespace="sample-app"} |= "500"` shows every 5xx line from any pod.

### Traces

Kubernetes does not trace anything by itself. The app (or a service mesh / auto-instrumentation)
creates spans with the OpenTelemetry SDK and sends them over OTLP to an OTel Collector, which
exports to Jaeger or Tempo. The Collector is usually a DaemonSet (one per node) or a Deployment
(gateway). Context propagation uses the W3C `traceparent` HTTP header so spans from different
services join one trace.

```text
sample-app (OTel SDK) --OTLP/gRPC 4317--> otel-collector --> Tempo / Jaeger --> Grafana / Jaeger UI
```

### Small OpenTelemetry example

Python instrumentation (would be added to `../01-monitoring/sample-app/app.py`;
pip packages `opentelemetry-sdk opentelemetry-exporter-otlp`):

```python
from opentelemetry import trace
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter

provider = TracerProvider(resource=Resource.create({"service.name": "sample-app"}))
provider.add_span_processor(BatchSpanProcessor(
    OTLPSpanExporter(endpoint="otel-collector.observability:4317", insecure=True)))
trace.set_tracer_provider(provider)
tracer = trace.get_tracer("sample-app")

def handle_checkout(order_id):
    with tracer.start_as_current_span("checkout") as span:       # parent span
        span.set_attribute("order.id", order_id)
        with tracer.start_as_current_span("db.insert_order"):    # child span
            insert_order(order_id)
        with tracer.start_as_current_span("payment.charge"):     # child span
            charge_card(order_id)
```

Minimal OTel Collector config that receives OTLP and fans out to the three backends:

```yaml
receivers:
  otlp:
    protocols:
      grpc: { endpoint: 0.0.0.0:4317 }
      http: { endpoint: 0.0.0.0:4318 }
processors:
  batch: {}
  k8sattributes: {}          # adds k8s.namespace.name, k8s.pod.name, ... to every signal
exporters:
  otlp/tempo:
    endpoint: tempo.observability:4317
    tls: { insecure: true }
  prometheus:
    endpoint: 0.0.0.0:8889   # Prometheus scrapes the collector here
  loki:
    endpoint: http://loki.observability:3100/loki/api/v1/push
service:
  pipelines:
    traces:  { receivers: [otlp], processors: [k8sattributes, batch], exporters: [otlp/tempo] }
    metrics: { receivers: [otlp], processors: [k8sattributes, batch], exporters: [prometheus] }
    logs:    { receivers: [otlp], processors: [k8sattributes, batch], exporters: [loki] }
```

What I take away: the OTel SDK and Collector are the plumbing; Prometheus, Loki and Tempo are the
storage; Grafana is the single pane. On Kubernetes the `k8sattributes` processor is what makes
all three signals carry the same `namespace`/`pod` labels so I can jump between them.

## Screenshots

| Screenshot asked for | Stands in |
|---|---|
| `kubectl top` | expected output block above |
| `kubectl logs` | expected output block above |
| Trace view | ASCII span tree above |

## Deliverables

- `README.md` – this document: three pillars with examples, why observability, tools table, Kubernetes observability (metrics-server, kube-state-metrics, node-exporter, cAdvisor, logs via kubectl/Fluent Bit/Loki, traces via OpenTelemetry) and an OTel code + Collector snippet.
