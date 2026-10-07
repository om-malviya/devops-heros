# Task 3 – Mini Project: Production-Ready Kubernetes Web App

Student: Om Malviya | Enrollment No: 24BCS10448

Implementation of the Session 13 mini project (`session-13-storage-hpa-probes/mini-project/README.md`):
a web app in namespace `production-webapp` that combines

1. **State persistence** – PVC `web-data` (500Mi, RWO) mounted at `/data`, data outlives Pod deletion.
2. **Elastic scaling** – HPA `web-app-hpa`, CPU 50%, 2-5 replicas.
3. **Health diagnostics** – startup, readiness and liveness probes, CPU/memory requests and limits.

```text
                 [ Service: web-service ]  (ClusterIP :80)
                           |
          +----------------+----------------+
          v                v                v
   [ web-app-1 ]    [ web-app-2 ]  ...  [ web-app-5 ]      <-- HPA web-app-hpa (50% CPU, 2..5)
   probes: startup / readiness / liveness                     ^
   requests: cpu 100m, mem 64Mi                               | metrics-server
   mount: /data  --> PVC web-data (500Mi RWO) --> StorageClass local-path (k3s) / standard (minikube)
```

```text
mini-project/
├── namespace.yaml        # production-webapp
├── pvc.yaml              # web-data, 500Mi, ReadWriteOnce, default StorageClass
├── deployment.yaml       # web-app, 2 replicas, nginx:alpine, 3 probes, resources, /data mount
├── service.yaml          # web-service ClusterIP :80
├── hpa.yaml              # web-app-hpa, 2..5, 50% CPU
├── load-generator.yaml   # busybox wget loop (8 replicas) for the scaling test
├── deploy.sh / cleanup.sh
└── README.md
```

Changes from the course skeleton and why: `nginx:alpine` instead of `nginx:1.27` (smaller, multi-arch);
no `storageClassName` in the PVC so it works on k3s (`local-path`) and minikube (`standard`) without
edits; the load generator is a Deployment so I can scale it, because static nginx needs several
parallel loops before 2 x 100m pods exceed 50 % (I started with 4 loops, which only reached 47 %, and
ended up with 8; see Verification Task 3).

## Prerequisites

```bash
kubectl get storageclass
kubectl top nodes
```

Output (captured 2026-10-08 / 2026-10-07, k3s):

```text
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  3h56m
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
colima   1408m        35%      2601Mi          44%
```

Minikube: `minikube addons enable metrics-server` (and `default-storageclass` is on by default).

## Deploy

Either `./deploy.sh` or step by step:

### 5.1 Namespace

```bash
kubectl apply -f namespace.yaml
```

Output (captured 2026-10-08):

```text
namespace/production-webapp created
```

### 5.2 PersistentVolumeClaim

```bash
kubectl apply -f pvc.yaml
kubectl get pvc -n production-webapp
```

Output (captured 2026-10-08, k3s; `WaitForFirstConsumer` keeps it `Pending` until a Pod uses it, on
minikube it would be `Bound` immediately):

```text
persistentvolumeclaim/web-data created
NAME       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
web-data   Pending                                      local-path     <unset>                 2s
```

### 5.3 Deployment and Service

```bash
kubectl apply -f deployment.yaml -f service.yaml
kubectl rollout status deployment/web-app -n production-webapp
kubectl get pvc,pods,svc -n production-webapp
```

Output (captured 2026-10-08):

```text
deployment.apps/web-app created
service/web-service created
Waiting for deployment "web-app" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "web-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "web-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "web-app" successfully rolled out
NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/web-data   Bound    pvc-372be0b5-d22b-4285-9353-5d0867d135bb   500Mi      RWO            local-path     <unset>                 16s

NAME                          READY   STATUS    RESTARTS   AGE
pod/web-app-d69479c4c-742wl   1/1     Running   0          14s
pod/web-app-d69479c4c-lj2xm   1/1     Running   0          13s

NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/web-service   ClusterIP   10.43.48.237   <none>        80/TCP    14s
```

The PVC became `Bound` the moment the first Pod was scheduled (dynamic provisioning). Both replicas
share the RWO volume because they run on the same node.

### 5.4 HPA

```bash
kubectl apply -f hpa.yaml
kubectl get hpa -n production-webapp          # right away: no metrics yet
sleep 60
kubectl get hpa -n production-webapp
```

Output (captured 2026-10-08):

```text
horizontalpodautoscaler.autoscaling/web-app-hpa created
NAME          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   cpu: <unknown>/50%   2         5         0          14s
NAME          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2         5         2          2m45s
```

The `<unknown>` phase lasted about a minute here (the HPA even logged a one-off
`FailedGetResourceMetric ... did not receive metrics for targeted pods` event), then settled at 1 %.

## Verification

### Task 1 – Storage persistence

```bash
POD_NAME=$(kubectl get pods -n production-webapp -l app=web-app -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n production-webapp "$POD_NAME" -- sh -c 'echo "Student: Om Malviya" > /data/student.txt'
kubectl exec -n production-webapp "$POD_NAME" -- cat /data/student.txt
kubectl delete pod -n production-webapp "$POD_NAME"
kubectl rollout status deployment/web-app -n production-webapp
NEW_POD=$(kubectl get pods -n production-webapp -l app=web-app -o jsonpath='{.items[0].metadata.name}')
echo "old=$POD_NAME new=$NEW_POD"
kubectl exec -n production-webapp "$NEW_POD" -- cat /data/student.txt
```

Output (captured 2026-10-08):

```text
Student: Om Malviya
pod "web-app-d69479c4c-742wl" deleted from production-webapp namespace
Waiting for deployment "web-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "web-app" successfully rolled out
old=web-app-d69479c4c-742wl new=web-app-d69479c4c-7cp9n
Student: Om Malviya
```

The Pod was replaced but the file survived on the PersistentVolume. Because both replicas mount the
same PVC, the other replica sees it too:

```bash
kubectl exec -n production-webapp deploy/web-app -- cat /data/student.txt
```

Output (captured 2026-10-08):

```text
Student: Om Malviya
```

### Task 2 – Service verification

```bash
kubectl port-forward -n production-webapp svc/web-service 18081:80 &    # 8080 was taken on my machine
sleep 3
curl -s http://localhost:18081 | head -5
kill %1
```

Output (captured 2026-10-08):

```text
Forwarding from 127.0.0.1:18081 -> 80
Forwarding from [::1]:18081 -> 80
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
```

### Task 3 – HPA elastic scaling

```bash
kubectl apply -f load-generator.yaml
kubectl get hpa -n production-webapp -w
```

Output (captured 2026-10-08; load generator applied at 03:09:24 IST, removed at 03:13:35, watch kept
running until the scale-down):

```text
NAME          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   cpu: 1%/50%   2         5         2          38m
web-app-hpa   Deployment/web-app   cpu: 15%/50%   2         5         2          39m      <- load applied (8 loops)
web-app-hpa   Deployment/web-app   cpu: 82%/50%   2         5         2          39m      <- 2 -> 4 in one step
web-app-hpa   Deployment/web-app   cpu: 23%/50%   2         5         4          39m
web-app-hpa   Deployment/web-app   cpu: 2%/50%    2         5         4          39m
web-app-hpa   Deployment/web-app   cpu: 11%/50%   2         5         4          40m
web-app-hpa   Deployment/web-app   cpu: 21%/50%   2         5         4          40m
web-app-hpa   Deployment/web-app   cpu: 5%/50%    2         5         4          40m
web-app-hpa   Deployment/web-app   cpu: 2%/50%    2         5         4          40m
web-app-hpa   Deployment/web-app   cpu: 16%/50%   2         5         4          41m
web-app-hpa   Deployment/web-app   cpu: 6%/50%    2         5         4          41m
web-app-hpa   Deployment/web-app   cpu: 16%/50%   2         5         4          41m
web-app-hpa   Deployment/web-app   cpu: 7%/50%    2         5         4          41m
web-app-hpa   Deployment/web-app   cpu: 11%/50%   2         5         4          42m
web-app-hpa   Deployment/web-app   cpu: 19%/50%   2         5         4          42m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         4          42m
web-app-hpa   Deployment/web-app   cpu: 11%/50%   2         5         4          42m
web-app-hpa   Deployment/web-app   cpu: 17%/50%   2         5         4          43m
web-app-hpa   Deployment/web-app   cpu: 12%/50%   2         5         4          43m
web-app-hpa   Deployment/web-app   cpu: 4%/50%    2         5         4          43m
web-app-hpa   Deployment/web-app   cpu: 11%/50%   2         5         4          43m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         4          44m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         4          44m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         2          44m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         2          48m
```

What I observed:

- My first attempt used the 4 `wget` loops I had planned. Two nginx pods then sat at 44-49 %, a hair
  under the 50 % target, and the HPA correctly did nothing (its tolerance is 10 %, so anything between
  45 % and 55 % counts as "on target"). I scaled the load generator to 8 and changed
  `load-generator.yaml` accordingly; the trace above is the clean re-run with 8 loops.
- The first sample under load was 82 %; desired = ceil(2 x 82 / 50) = 4, and the HPA went 2 -> 4 in
  one step. With 4 pods the average fell to 2-23 %, so it never needed the 5th replica. This is the
  textbook behaviour, unlike the CPU-burning app in `../02-hpa` where closed-loop clients kept every
  new pod saturated.
- The percentages are bursty after the scale-out (1-23 %) because eight tight `wget` loops spend most
  of their time in DNS lookups of `web-service` (CoreDNS went to ~100m in `kubectl top pods -n
  kube-system`) rather than in nginx. In a real load test I would resolve the Service once or use its
  ClusterIP so the DNS server is not the thing being benchmarked.
- The scale-down to 2 happened at 03:15:09, about 5 minutes after the *last recommendation above 2*
  (the 82 % sample at ~03:10), not 5 minutes after I removed the load: the default
  `stabilizationWindowSeconds: 300` keeps the highest recommendation of the past 5 minutes.

```bash
kubectl top pods -n production-webapp -l app=web-app
kubectl get pods -n production-webapp -l app=web-app
```

Output (captured 2026-10-08, 4 minutes into the load with 4 replicas):

```text
NAME                      CPU(cores)   MEMORY(bytes)
web-app-d69479c4c-6j4fm   21m          4Mi
web-app-d69479c4c-7cp9n   19m          4Mi
web-app-d69479c4c-8lpph   14m          4Mi
web-app-d69479c4c-lj2xm   17m          4Mi
NAME                      READY   STATUS    RESTARTS   AGE
web-app-d69479c4c-6j4fm   1/1     Running   0          3m41s
web-app-d69479c4c-7cp9n   1/1     Running   0          42m
web-app-d69479c4c-8lpph   1/1     Running   0          3m41s
web-app-d69479c4c-lj2xm   1/1     Running   0          43m
```

Stop the load and watch the scale-down (default 5-minute stabilization window):

```bash
kubectl delete -f load-generator.yaml
kubectl get hpa -n production-webapp -w
```

Output (captured 2026-10-08; the tail of the same watch as above):

```text
deployment.apps "load-generator" deleted from production-webapp namespace
NAME          REFERENCE            TARGETS        MINPODS   MAXPODS   REPLICAS   AGE
web-app-hpa   Deployment/web-app   cpu: 11%/50%   2         5         4          43m
web-app-hpa   Deployment/web-app   cpu: 4%/50%    2         5         4          43m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         4          44m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         2          44m
web-app-hpa   Deployment/web-app   cpu: 1%/50%    2         5         2          48m
```

```bash
kubectl describe hpa web-app-hpa -n production-webapp | sed -n '/^Events/,$p'
```

Output (captured 2026-10-08; the event list covers the whole afternoon, including my first attempt and
a run that I had to abort, which is why the `New size: 4` event has `x3` and `New size: 2` has `x2`.
The `New size: 4/3 ... All metrics below target` pair at 40m is the HPA restoring its recommendation
after I accidentally reset the Deployment with `deploy.sh`, see Troubleshooting):

```text
Events:
  Type     Reason                        Age                  From                       Message
  ----     ------                        ----                 ----                       -------
  Warning  FailedGetResourceMetric       51m                  horizontal-pod-autoscaler  failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
  Warning  FailedComputeMetricsReplicas  51m                  horizontal-pod-autoscaler  invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: failed to get cpu utilization: did not receive metrics for targeted pods (pods might be unready)
  Normal   SuccessfulRescale             40m                  horizontal-pod-autoscaler  New size: 4; reason: All metrics below target
  Normal   SuccessfulRescale             40m                  horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal   SuccessfulRescale             12m (x3 over 45m)    horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale             7m22s (x2 over 34m)  horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
```

Final state after the run:

```bash
kubectl get pods -n production-webapp -l app=web-app
```

Output (captured 2026-10-08):

```text
NAME                      READY   STATUS    RESTARTS   AGE
web-app-d69479c4c-7cp9n   1/1     Running   0          51m
web-app-d69479c4c-lj2xm   1/1     Running   0          52m
```

## Probe diagnostics reference

| Probe | Question | Action on failure | Settings used |
| --- | --- | --- | --- |
| Startup | Has the process initialised? | restart container; other probes disabled until it passes | 30 x 2 s = 60 s grace |
| Readiness | Can the Pod receive traffic? | Pod IP removed from endpoints, **no restart** | every 5 s, 2 failures |
| Liveness | Is the container alive? | kubelet restarts the container | every 5 s, 3 failures |

```bash
kubectl describe pod -n production-webapp -l app=web-app | grep -E 'Liveness|Readiness|Startup' | head -3
```

Output (captured 2026-10-08):

```text
    Liveness:     http-get http://:80/ delay=5s timeout=2s period=5s successThreshold=1 failureThreshold=3
    Readiness:    http-get http://:80/ delay=5s timeout=2s period=5s successThreshold=1 failureThreshold=2
    Startup:      http-get http://:80/ delay=0s timeout=1s period=2s successThreshold=1 failureThreshold=30
```

## Troubleshooting

| Issue | Check | Root cause | Fix |
| --- | --- | --- | --- |
| PVC `Pending` for more than a minute with pods also Pending | `kubectl describe pvc web-data -n production-webapp` | no default StorageClass | `kubectl get sc`; minikube: `minikube addons enable default-storageclass storage-provisioner`; or set `storageClassName` explicitly |
| PVC `Pending` but pods Running | normal `WaitForFirstConsumer` on k3s before the first Pod; afterwards it is Bound | | |
| HPA `TARGETS <unknown>/50%` | `kubectl top pods -n production-webapp` | metrics-server missing or no `resources.requests.cpu` | enable metrics-server; keep `cpu: 100m` request |
| `CrashLoopBackOff` | `kubectl describe pod <pod> -n production-webapp` (Events) | liveness path/port wrong | probe must hit an endpoint returning 200-399 |
| second replica stuck `ContainerCreating` on multi-node cluster | `describe pod`: `Multi-Attach error` | RWO volume on a different node | use RWX storage or pin pods to one node |
| replicas drop to 2 right after a `kubectl apply -f deployment.yaml` / `./deploy.sh` while the HPA is at 4 | `kubectl get pods` shows two pods `Terminating` with no `SuccessfulRescale` event | `spec.replicas: 2` in the manifest overrides the HPA's value on every apply (I hit this myself: re-running `deploy.sh` during the scale-down test reset the Deployment to 2 and I had to redo the load test) | leave `replicas` out of the Deployment once an HPA owns it, or only re-apply the files that changed |

## Bonus challenges

These are described, not run, to keep the shared cluster quiet; items 2 and 3 are exactly the
experiments I did run on the standalone probe pods in `../03-probes/README.md`.

1. **Target tuning** – `sed -i 's/averageUtilization: 50/averageUtilization: 30/' hpa.yaml && kubectl apply -f hpa.yaml`:
   with the 78 % sample I measured, desired = ceil(2 x 78 / 30) = 6, capped to 5, so the HPA would
   jump straight to 5 replicas instead of stopping at 4.
2. **Readiness gating** – change `readinessProbe.httpGet.path` to `/does-not-exist`, apply, then
   `kubectl get endpoints -n production-webapp web-service`: pods stay `Running` with `READY 0/1` and
   `ENDPOINTS <none>` (observed on `readiness-demo` in `../03-probes`).
3. **Liveness restart loop** – change `livenessProbe.httpGet.path` to `/crash`, apply, then
   `kubectl get pods -n production-webapp -w`: `RESTARTS` increases every ~20 s (5 s initial delay +
   3 failures x 5 s; observed on `liveness-demo` in `../03-probes`).

## Cleanup

```bash
./cleanup.sh          # or: kubectl delete namespace production-webapp
```

Output (captured 2026-10-08, as part of `../cleanup.sh`; the load generator had already been removed):

```text
horizontalpodautoscaler.autoscaling "web-app-hpa" deleted from production-webapp namespace
service "web-service" deleted from production-webapp namespace
deployment.apps "web-app" deleted from production-webapp namespace
persistentvolumeclaim "web-data" deleted from production-webapp namespace
namespace "production-webapp" deleted
Done.
```

`kubectl get pv` afterwards printed `No resources found`: the dynamically provisioned PV went away
with the PVC.

Deleting the PVC also deletes the dynamically provisioned PV (`reclaimPolicy: Delete` of `local-path`).

## Deliverables

- `namespace.yaml`, `pvc.yaml`, `deployment.yaml`, `service.yaml`, `hpa.yaml` – the mini-project implementation.
- `load-generator.yaml`, `deploy.sh`, `cleanup.sh` – helpers for the scaling test and lifecycle.
- This README – deploy, verify (persistence, service, HPA), troubleshooting, bonus challenges, cleanup.
