# Monitoring on Kubernetes with kube-prometheus-stack
Student: Om Malviya | Enrollment No: 24BCS10448

The Docker Compose stack in the parent folder is good for learning. On a cluster the
same components come as one Helm chart, `kube-prometheus-stack`, which installs the
Prometheus Operator, Prometheus, Alertmanager, Grafana, node-exporter and kube-state-metrics,
and lets me describe scrape targets and alert rules as Kubernetes objects
(`ServiceMonitor`, `PrometheusRule`).

I ran this on the single-node k3s cluster that comes with Colima (kubectl context `colima`,
Kubernetes v1.35, 4 vCPU / 6 GB shared with Docker). Any cluster works; with kind it would be
`kind create cluster --name session20` first.

## 1. Install

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values.yaml --wait --timeout 10m

helm list -n monitoring
kubectl get pods -n monitoring
```

Output (captured 2026-10-08; `--wait` returned after about 3 minutes, most of it image pulls. NOTES text trimmed)

```text
NAME: monitoring
LAST DEPLOYED: Thu Oct  8 02:33:29 2026
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=monitoring"
...

NAME      	NAMESPACE 	REVISION	UPDATED                             	STATUS  	CHART                       	APP VERSION
monitoring	monitoring	1       	2026-10-08 02:33:29.748982 +0530 IST	deployed	kube-prometheus-stack-92.1.0	v0.94.1

NAME                                                     READY   STATUS    RESTARTS   AGE
alertmanager-monitoring-kube-prometheus-alertmanager-0   2/2     Running   0          80s
monitoring-grafana-7b64dc69c9-xb9zg                      3/3     Running   0          2m23s
monitoring-kube-prometheus-operator-6ffc467f59-m2kg4     1/1     Running   0          2m23s
monitoring-kube-state-metrics-6d8ffd8867-fh7z8           1/1     Running   0          2m23s
monitoring-prometheus-node-exporter-4wtpw                1/1     Running   0          2m23s
prometheus-monitoring-kube-prometheus-prometheus-0       2/2     Running   0          79s
```

While waiting I saw the Grafana pod in `ErrImagePull` for about a minute: the `quay.io/kiwigrid/k8s-sidecar:2.13.1` pull failed once with a transient registry error (`httpReadSeeker: failed open`), the kubelet retried and the pod became `3/3`. The operator, kube-state-metrics and node-exporter were `Running` first; Prometheus and Alertmanager are StatefulSets that the operator creates only after it is up, which is why their AGE is shorter.

`values.yaml` only changes a few things: a lab Grafana password, 2 days retention, and
`*SelectorNilUsesHelmValues: false` so that Prometheus picks up `ServiceMonitor`/`PrometheusRule`
objects from every namespace (by default it only watches objects labelled with the release name).

## 2. Deploy the sample app and tell Prometheus about it

Image note: k3s uses its own containerd, so an image built by the local Docker daemon is not
visible to the cluster (I checked: a pod with `imagePullPolicy: Never` stays in
`ErrImageNeverPull`) and there is no registry on this machine. `kind load docker-image`
would solve that on kind. On this cluster `sample-app.yaml` therefore runs the public
`quay.io/brancz/prometheus-example-app:v0.5.0` (a tiny Go app made for exactly this kind of
ServiceMonitor demo) instead of my python image. It serves `/metrics` on port 8080 with the same
shape of data: `http_requests_total{code,method}` counter, `http_request_duration_seconds`
histogram, `version` gauge. `prometheusrule.yaml` uses those metric names; the comments in both
files say what to change to run my own image on kind.

```bash
kubectl apply -f sample-app.yaml
kubectl apply -f servicemonitor.yaml
kubectl apply -f prometheusrule.yaml
kubectl rollout status deployment/sample-app -n s20-sample-app --timeout=180s

kubectl get pods,svc,servicemonitor,prometheusrule -n s20-sample-app
kubectl get servicemonitor,prometheusrule -A | grep -E 'NAMESPACE|s20-sample-app'
```

Output (captured 2026-10-08)

```text
namespace/s20-sample-app created
deployment.apps/sample-app created
service/sample-app created
servicemonitor.monitoring.coreos.com/sample-app created
prometheusrule.monitoring.coreos.com/sample-app-rules created
Waiting for deployment "sample-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "sample-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "sample-app" successfully rolled out

NAME                              READY   STATUS    RESTARTS   AGE
pod/sample-app-5cc6bd7cd9-6gbcf   1/1     Running   0          19s
pod/sample-app-5cc6bd7cd9-vh6ss   1/1     Running   0          19s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
service/sample-app   ClusterIP   10.43.172.135   <none>        8080/TCP   19s

NAME                                              AGE
servicemonitor.monitoring.coreos.com/sample-app   18s

NAME                                                    AGE
prometheusrule.monitoring.coreos.com/sample-app-rules   16s

NAMESPACE        NAME                                                                                      AGE
s20-sample-app   servicemonitor.monitoring.coreos.com/sample-app                                           40s

NAMESPACE        NAME                                                                                                   AGE
s20-sample-app   prometheusrule.monitoring.coreos.com/sample-app-rules                                                  38s
```

The full `kubectl get servicemonitor,prometheusrule -A` list is long: the chart itself ships 14
ServiceMonitors (apiserver, kubelet, coredns, kube-state-metrics, node-exporter, grafana, ...) and
about 30 PrometheusRule objects in `monitoring`; mine are the only ones in `s20-sample-app`.

How the pieces connect:

```text
Service sample-app (label app=sample-app, port name "http")
        ^
        | selector.matchLabels app=sample-app, endpoints[0].port=http
ServiceMonitor sample-app
        ^
        | operator watches ServiceMonitors -> writes prometheus.yml -> reloads Prometheus
Prometheus (CR "monitoring-kube-prometheus-prometheus")
        ^
        | ruleSelector -> PrometheusRule sample-app-rules -> alert rules
```

## 3. Check in Prometheus and Grafana

I port-forwarded Prometheus to a free local port and sent a few requests through a second
port-forward to the Service so the counters are not zero:

```bash
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 19090:9090 &
kubectl port-forward -n s20-sample-app svc/sample-app 18080:8080 &
for i in $(seq 1 60); do curl -s -o /dev/null localhost:18080/; curl -s -o /dev/null localhost:18080/err; done

curl -s localhost:19090/api/v1/targets | jq -c '.data.activeTargets[] | select(.labels.job=="sample-app") | {job: .labels.job, pod: .labels.pod, health}'
curl -s localhost:19090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job=="sample-app") | "\(.labels.namespace)\t\(.labels.pod)\t\(.scrapeUrl)\t\(.health)\t\(.lastScrapeDuration)"'
curl -s localhost:19090/api/v1/targets | jq -r '.data.activeTargets[] | "\(.labels.job)\t\(.health)"' | sort | uniq -c
```

Output (captured 2026-10-08; the targets appeared about 20 s after the ServiceMonitor was created, first as `unknown` (not scraped yet) and `up` from the next scrape on)

```text
{"job":"sample-app","pod":"sample-app-5cc6bd7cd9-6gbcf","health":"up"}
{"job":"sample-app","pod":"sample-app-5cc6bd7cd9-vh6ss","health":"up"}

s20-sample-app	sample-app-5cc6bd7cd9-6gbcf	http://10.42.0.174:8080/metrics	up	0.004984496
s20-sample-app	sample-app-5cc6bd7cd9-vh6ss	http://10.42.0.175:8080/metrics	up	0.019999049

   1 apiserver	up
   1 coredns	up
   1 kube-state-metrics	up
   3 kubelet	up
   1 monitoring-grafana	up
   2 monitoring-kube-prometheus-alertmanager	up
   1 monitoring-kube-prometheus-operator	up
   2 monitoring-kube-prometheus-prometheus	up
   1 node-exporter	up
   2 sample-app	up
```

I observed that I never edited a `prometheus.yml` here: the operator turned my `ServiceMonitor`
into a scrape job named after the Service (`job="sample-app"`) with one target per pod endpoint.
Three `kubelet` targets are the kubelet itself, its cAdvisor endpoint and the probes endpoint.

```bash
curl -s localhost:19090/api/v1/rules | jq -r '.data.groups[] | select(.name=="sample-app") | .rules[] | "\(.name)\t\(.state)\t\(.health)"'
curl -s localhost:19090/api/v1/rules | jq '.data.groups | length'
kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Output (captured 2026-10-08)

```text
AppUnhealthy	inactive	ok
HighErrorRate	inactive	ok
HighLatencyP95	inactive	ok
SampleAppPodNotReady	inactive	ok
36
admin-lab-password
```

My four rules are loaded (`health: ok`, all `inactive` because both pods are up and the example
app is fast) next to the 35 rule groups the chart ships (node, kubelet, etcd, Alertmanager, ...).

Queries through the same port-forward (`P=localhost:19090/api/v1/query; curl -s $P --data-urlencode 'query=...'`):

```bash
curl -s $P --data-urlencode 'query=up{job="sample-app"}' | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'
curl -s $P --data-urlencode 'query=sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="s20-sample-app",container!=""}[5m]))' | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'
curl -s $P --data-urlencode 'query=sum by (pod) (container_memory_working_set_bytes{namespace="s20-sample-app",container!=""})' | jq -r '.data.result[] | "\(.metric.pod) \(.value[1])"'
curl -s $P --data-urlencode 'query=100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100' | jq -r '.data.result[] | "\(.metric.instance) \(.value[1])"'
curl -s $P --data-urlencode 'query=kube_deployment_status_replicas_available{deployment="sample-app"}' | jq -r '.data.result[] | "\(.metric.namespace) \(.value[1])"'
curl -s $P --data-urlencode 'query=sum by (code) (http_requests_total{job="sample-app"})' | jq -r '.data.result[] | "\(.metric.code) \(.value[1])"'
```

Output (captured 2026-10-08)

```text
sample-app-5cc6bd7cd9-vh6ss 1
sample-app-5cc6bd7cd9-6gbcf 1
sample-app-5cc6bd7cd9-6gbcf 0.0006697515009610769
sample-app-5cc6bd7cd9-vh6ss 0.0008335400000000001
sample-app-5cc6bd7cd9-6gbcf 16793600
sample-app-5cc6bd7cd9-vh6ss 16879616
192.168.5.1:9100 95.91468380555547
s20-sample-app 2
200 48
```

So on Kubernetes the per-pod CPU (about 0.7 millicores) and memory (about 16 MiB working set) come
from the kubelet's built-in cAdvisor, labelled by `namespace`/`pod`/`container`, which is the part
that did not work with the standalone cAdvisor container in the Compose stack. Node CPU was 96 %
at that moment because the image pulls and the Prometheus start-up were still running on the
4-vCPU VM. `kubectl top` agrees with the same numbers:

```bash
kubectl top pods -n monitoring
kubectl top pods -n s20-sample-app
kubectl top node
```

Output (captured 2026-10-08)

```text
NAME                                                     CPU(cores)   MEMORY(bytes)
alertmanager-monitoring-kube-prometheus-alertmanager-0   5m           29Mi
monitoring-grafana-7b64dc69c9-xb9zg                      20m          655Mi
monitoring-kube-prometheus-operator-6ffc467f59-m2kg4     5m           22Mi
monitoring-kube-state-metrics-6d8ffd8867-fh7z8           5m           18Mi
monitoring-prometheus-node-exporter-4wtpw                4m           14Mi
prometheus-monitoring-kube-prometheus-prometheus-0       44m          467Mi
NAME                          CPU(cores)   MEMORY(bytes)
sample-app-5cc6bd7cd9-6gbcf   5m           19Mi
sample-app-5cc6bd7cd9-vh6ss   3m           20Mi
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
colima   3352m        83%      4197Mi          71%
```

Grafana (`kubectl port-forward -n monitoring svc/monitoring-grafana 3000:80`, user `admin`, password from the secret above) was reachable with the chart's built-in dashboards; I did not add screenshots, the API outputs above are the evidence.

Grafana already ships with dashboards for nodes, pods and the cluster (CPU, memory per
namespace/pod from cAdvisor via the kubelet, and desired vs available replicas from
kube-state-metrics). I can import `../grafana/dashboards/session20.json` for the app panels;
the queries are identical because the metric names are the same.

Useful Kubernetes-specific queries:

| Goal | Query |
|---|---|
| Pod CPU (cores) | `sum by (pod) (rate(container_cpu_usage_seconds_total{namespace="s20-sample-app",container!=""}[5m]))` |
| Pod memory | `sum by (pod) (container_memory_working_set_bytes{namespace="s20-sample-app",container!=""})` |
| Node CPU % | `100 - avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100` |
| Replicas desired vs available | `kube_deployment_spec_replicas{deployment="sample-app"}` / `kube_deployment_status_replicas_available{deployment="sample-app"}` |
| Pods not running | `kube_pod_status_phase{phase!="Running",namespace="s20-sample-app"} == 1` |

## 4. Offline check

Before having a cluster I rendered the chart to be sure the values file is accepted:

```bash
helm template monitoring prometheus-community/kube-prometheus-stack -n monitoring -f values.yaml | grep -c '^kind:'
```

See the session README for the result of this command.

## Cleanup

The VM has 6 GB in total, so I removed the stack right after the captures:

```bash
kubectl delete -f prometheusrule.yaml -f servicemonitor.yaml -f sample-app.yaml
helm uninstall monitoring -n monitoring
kubectl delete ns monitoring
kubectl delete crd -l app.kubernetes.io/name=kube-prometheus-stack   # the chart leaves its CRDs behind on purpose
```


Output (captured 2026-10-08)

```text
prometheusrule.monitoring.coreos.com "sample-app-rules" deleted from s20-sample-app namespace
servicemonitor.monitoring.coreos.com "sample-app" deleted from s20-sample-app namespace
namespace "s20-sample-app" deleted
deployment.apps "sample-app" deleted from s20-sample-app namespace
service "sample-app" deleted from s20-sample-app namespace
release "monitoring" uninstalled
namespace "monitoring" deleted
No resources found
```

`helm uninstall` leaves the `monitoring.coreos.com` CRDs in place (Helm never deletes CRDs) and
they do not carry the label I tried, so I removed them by name afterwards:

```bash
kubectl get crd -o name | grep monitoring.coreos.com | xargs kubectl delete
```

Output (captured 2026-10-08)

```text
customresourcedefinition.apiextensions.k8s.io "alertmanagerconfigs.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "alertmanagers.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "podmonitors.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "probes.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "prometheusagents.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "prometheuses.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "prometheusrules.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "scrapeconfigs.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "servicemonitors.monitoring.coreos.com" deleted
customresourcedefinition.apiextensions.k8s.io "thanosrulers.monitoring.coreos.com" deleted
```
