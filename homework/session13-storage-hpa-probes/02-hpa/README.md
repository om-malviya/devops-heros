# Task 2 – HPA Hands-on

Student: Om Malviya | Enrollment No: 24BCS10448

The HorizontalPodAutoscaler watches the average CPU of a Deployment's pods (via metrics-server) and
changes `replicas` to keep it near a target. Here: target 50% of the requested 100m, between 1 and 5
pods.

```text
load-generator pods --wget loop--> Service cpu-app --> cpu-app pods (CPU rises)
                                                            |
                                   metrics-server <--- kubelet /metrics/resource
                                        |
                                   HPA cpu-app-hpa: avg CPU / request vs 50%  --> scales Deployment cpu-app
```

| File | Purpose |
| --- | --- |
| `deployment.yaml` | `cpu-app`, python:3.12-alpine HTTP server that burns CPU per request; `resources.requests.cpu: 100m` (required for HPA) |
| `service.yaml` | ClusterIP `cpu-app` 80 -> 8080 |
| `hpa.yaml` | `autoscaling/v2`, CPU `averageUtilization: 50`, `minReplicas: 1`, `maxReplicas: 5`, 60 s scale-down window |
| `load-generator.yaml` | 3 busybox pods running `wget` in a loop against the Service |
| `load_generator.sh` | start / `--stop` wrapper around the load generator (adapted from the course `hpa/load_generator.sh`) |

### Why this image and not `registry.k8s.io/hpa-example`

The upstream walkthrough image is published for amd64 only; on an arm64 k3s node (Apple Silicon VM,
Raspberry Pi) the pod fails with `exec format error`. `python:3.12-alpine` is multi-arch and the inline
server does a short integer loop per request (about 20-40 ms of CPU), which is what makes utilisation
climb. Plain nginx would barely move above a few percent under a wget loop, so the HPA would never
trigger with a 100m request.

### Why `resources.requests.cpu` is mandatory

Utilisation = (actual CPU usage) / (CPU request). Without a request the HPA has nothing to divide by,
reports `TARGETS <unknown>/50%` and does nothing.

## Prerequisite: metrics-server

```bash
kubectl top nodes
kubectl get deployment metrics-server -n kube-system
```

Output (captured 2026-10-07, k3s ships metrics-server; the node was shared with other workloads):

```text
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
colima   1408m        35%      2601Mi          44%
NAME             READY   UP-TO-DATE   AVAILABLE   AGE
metrics-server   1/1     1            1           14m
```

If you see `error: Metrics API not available`: on minikube run `minikube addons enable metrics-server`;
on other clusters `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml`
(add `--kubelet-insecure-tls` for self-signed kubelets) and wait a minute.

## Step 1 – Deploy the application

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f deployment.yaml -f service.yaml
kubectl rollout status deployment/cpu-app -n s13
kubectl get pods,svc -n s13 -l app=cpu-app
```

Output (captured 2026-10-07; the first rollout took ~2.5 min because `python:3.12-alpine` had to be pulled):

```text
namespace/s13 created
deployment.apps/cpu-app created
service/cpu-app created
Waiting for deployment "cpu-app" rollout to finish: 0 of 1 updated replicas are available...
deployment "cpu-app" successfully rolled out
NAME                           READY   STATUS    RESTARTS   AGE
pod/cpu-app-55f8dd8876-mvfgk   1/1     Running   0          2m44s

NAME              TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/cpu-app   ClusterIP   10.43.67.102   <none>        80/TCP    2m44s
```

Sanity check from inside the cluster:

```bash
kubectl run -n s13 curl --rm -it --restart=Never --image=busybox:1.36 -- wget -qO- http://cpu-app/
```

Output (captured 2026-10-07):

```text
OK x=599998
pod "curl" deleted from s13 namespace
```

## Step 2 – Configure HPA

```bash
kubectl apply -f hpa.yaml
```

Output (captured 2026-10-07):

```text
horizontalpodautoscaler.autoscaling/cpu-app-hpa created
```

## Step 3 – Verify HPA

```bash
kubectl get hpa -n s13
```

Output (captured 2026-10-07, immediately after the apply; the first 15-30 s show `<unknown>` until
metrics-server has a sample, and `REPLICAS 0` until the HPA has read the Deployment's scale once):

```text
NAME          REFERENCE            TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
cpu-app-hpa   Deployment/cpu-app   cpu: <unknown>/50%   1         5         0          0s
```

```bash
sleep 30; kubectl get hpa -n s13
kubectl describe hpa cpu-app-hpa -n s13
```

Output (captured 2026-10-08; the HPA had been idle for a few hours by then, hence the AGE. The idle
app sits at 3-4% because the readiness probe hits it every 5 s):

```text
NAME          REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
cpu-app-hpa   Deployment/cpu-app   cpu: 4%/50%   1         5         1          3h35m

Name:                                                  cpu-app-hpa
Namespace:                                             s13
Labels:                                                <none>
Annotations:                                           <none>
CreationTimestamp:                                     Wed, 07 Oct 2026 22:51:05 +0530
Reference:                                             Deployment/cpu-app
Metrics:                                               ( current / target )
  resource cpu on pods  (as a percentage of request):  4% (4m) / 50%
Min replicas:                                          1
Max replicas:                                          5
Behavior:
  Scale Up:
    Stabilization Window: 0 seconds
    Select Policy: Max
    Policies:
      - Type: Pods     Value: 4    Period: 15 seconds
      - Type: Percent  Value: 100  Period: 15 seconds
  Scale Down:
    Stabilization Window: 60 seconds
    Select Policy: Max
    Policies:
      - Type: Pods  Value: 1  Period: 30 seconds
Deployment pods:    1 current / 1 desired
Conditions:
  Type            Status  Reason              Message
  ----            ------  ------              -------
  AbleToScale     True    ReadyForNewScale    recommended size matches current size
  ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  False   DesiredWithinRange  the desired count is within the acceptable range
Events:
  Type     Reason          Age   From                       Message
  ----     ------          ----  ----                       -------
  Warning  FailedGetScale  58m   horizontal-pod-autoscaler  Unauthorized
```

`ScalingActive True / ValidMetricFound` is the confirmation that metrics flow and the request is set.
The `Scale Up` block shows the defaults I did not override (max of +4 pods or +100 % per 15 s), the
`Scale Down` block shows my 60 s window and 1 pod per 30 s. The single `FailedGetScale ... Unauthorized`
warning happened once while the cluster was idle (a controller token refresh); it did not recur.

## Step 4 – Deploy a load generator

```bash
./load_generator.sh           # same as: kubectl apply -f load-generator.yaml
```

Output (captured 2026-10-08):

```text
==================================================
      KUBERNETES HPA TRAFFIC LOAD GENERATOR
==================================================
[load] target: http://cpu-app.s13.svc.cluster.local/  (replicas: 3)
deployment.apps/load-generator created
deployment.apps/load-generator scaled
Waiting for deployment "load-generator" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "load-generator" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "load-generator" rollout to finish: 2 of 3 updated replicas are available...
deployment "load-generator" successfully rolled out
[load] traffic active. In other terminals run:
         kubectl get hpa -n s13 -w
         kubectl get pods -n s13 -l app=cpu-app -w
         kubectl top pods -n s13
[load] stop with:  ./load_generator.sh --stop
```

The course's one-liner works as well: `kubectl run load-generator -n s13 --image=busybox:1.36 --restart=Never -- /bin/sh -c "while true; do wget -q -O- http://cpu-app; done"`.

## Step 5 – Increase application load

More load = more wget loops:

```bash
./load_generator.sh 6         # or: kubectl scale -n s13 deploy/load-generator --replicas=6
```

I did not need this step: the 3 default loops already drove the app to about 300 % of its request
(see Step 6), so I left the load at 3 replicas to stay well inside the 4-CPU node that other
namespaces were sharing.

## Step 6 – Observe CPU utilization

```bash
kubectl top pods -n s13
```

Output (captured 2026-10-08, about 90 s after the load started; by then the HPA had already scaled
to 5 pods, each of which is still at ~300m):

```text
NAME                              CPU(cores)   MEMORY(bytes)
cpu-app-55f8dd8876-bqslx          289m         11Mi
cpu-app-55f8dd8876-dq5jc          304m         11Mi
cpu-app-55f8dd8876-mvfgk          294m         11Mi
cpu-app-55f8dd8876-pbqfj          273m         11Mi
cpu-app-55f8dd8876-t9w9f          311m         11Mi
load-generator-767f7c854c-42gkx   32m          0Mi
load-generator-767f7c854c-mz6hm   30m          0Mi
load-generator-767f7c854c-rvbkp   32m          0Mi
```

About 300m used against a 100m request = ~300 % utilisation per pod, far above the 50 % target. The
load generators themselves use almost nothing (~30m each); the CPU goes into the integer loop in
`cpu-app`. Since each `cpu-app` pod is capped by `limits.cpu: 500m`, the whole Deployment burns at
most 2.5 CPU on the 4-CPU node.

```bash
kubectl get hpa -n s13 -w
```

Output (captured 2026-10-08, watch over 4 minutes from the moment the load started; the HPA
samples every 15 s and the watch prints a line whenever the object changes):

```text
NAME          REFERENCE            TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         1          3h36m
cpu-app-hpa   Deployment/cpu-app   cpu: 283%/50%   1         5         1          3h36m
cpu-app-hpa   Deployment/cpu-app   cpu: 499%/50%   1         5         5          3h36m
cpu-app-hpa   Deployment/cpu-app   cpu: 322%/50%   1         5         5          3h36m
cpu-app-hpa   Deployment/cpu-app   cpu: 309%/50%   1         5         5          3h37m
cpu-app-hpa   Deployment/cpu-app   cpu: 307%/50%   1         5         5          3h37m
cpu-app-hpa   Deployment/cpu-app   cpu: 294%/50%   1         5         5          3h37m
cpu-app-hpa   Deployment/cpu-app   cpu: 314%/50%   1         5         5          3h37m
cpu-app-hpa   Deployment/cpu-app   cpu: 309%/50%   1         5         5          3h38m
cpu-app-hpa   Deployment/cpu-app   cpu: 316%/50%   1         5         5          3h38m
cpu-app-hpa   Deployment/cpu-app   cpu: 319%/50%   1         5         5          3h38m
cpu-app-hpa   Deployment/cpu-app   cpu: 308%/50%   1         5         5          3h38m
cpu-app-hpa   Deployment/cpu-app   cpu: 293%/50%   1         5         5          3h39m
```

What I observed, and how it differs from what I had expected:

- The first sample under load was already 283 %, the next one 499 % (the single pod hit its 500m
  limit). Desired replicas = ceil(1 x 499 / 50) = 10, capped to `maxReplicas` 5.
- I had expected 1 -> 4 -> 5 in two rounds, but it went **1 -> 5 in one step**: the default scale-up
  policies are "+4 pods per 15 s" and "+100 % per 15 s" with `selectPolicy: Max`, and from 1 pod the
  Pods policy (1 + 4 = 5) wins, which is exactly the maximum.
- Utilisation stayed around 300 % even with 5 pods, because the three `wget` loops are closed-loop
  clients: every time a response comes back faster they immediately send the next request, so the
  extra pods were simply used up by more requests. With a fixed request rate the percentage would
  have dropped as replicas increased.

## Step 7 – Observe Pod scaling

```bash
kubectl get pods -n s13 -l app=cpu-app
kubectl get deployment cpu-app -n s13
```

Output (captured 2026-10-08; the four new pods are all the same age because they were created in one step):

```text
NAME                       READY   STATUS    RESTARTS   AGE
cpu-app-55f8dd8876-bqslx   1/1     Running   0          2m45s
cpu-app-55f8dd8876-dq5jc   1/1     Running   0          2m45s
cpu-app-55f8dd8876-mvfgk   1/1     Running   0          3h41m
cpu-app-55f8dd8876-pbqfj   1/1     Running   0          2m45s
cpu-app-55f8dd8876-t9w9f   1/1     Running   0          2m45s
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
cpu-app   5/5     5            5           3h41m
```

```bash
kubectl describe hpa cpu-app-hpa -n s13 | sed -n '/^Conditions/,$p'
```

Output (captured 2026-10-08):

```text
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooManyReplicas   the desired replica count is more than the maximum replica count
Events:
  Type    Reason             Age    From                       Message
  ----    ------             ----   ----                       -------
  Normal  SuccessfulRescale  2m45s  horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
```

`ScalingLimited True / TooManyReplicas` tells me the HPA would like more than 5 pods: the load is
larger than the max. That is useful capacity information, not an error.

## Step 8 – Capture the output after stopping the load (scale-down)

```bash
./load_generator.sh --stop
kubectl get hpa -n s13 -w
```

Output (captured 2026-10-08; the load was stopped at 02:30:08 IST, the watch ran for 5.5 minutes):

```text
[load] stopping load generator
deployment.apps "load-generator" deleted from s13 namespace
[load] watch the scale-down with:  kubectl get hpa -n s13 -w
NAME          REFERENCE            TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
cpu-app-hpa   Deployment/cpu-app   cpu: 293%/50%   1         5         5          3h39m
cpu-app-hpa   Deployment/cpu-app   cpu: 303%/50%   1         5         5          3h39m
cpu-app-hpa   Deployment/cpu-app   cpu: 304%/50%   1         5         5          3h39m
cpu-app-hpa   Deployment/cpu-app   cpu: 214%/50%   1         5         5          3h39m
cpu-app-hpa   Deployment/cpu-app   cpu: 7%/50%     1         5         5          3h40m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         5          3h40m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         5          3h40m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         4          3h41m
cpu-app-hpa   Deployment/cpu-app   cpu: 5%/50%     1         5         4          3h41m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         3          3h41m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         3          3h41m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         2          3h42m
cpu-app-hpa   Deployment/cpu-app   cpu: 4%/50%     1         5         2          3h42m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         1          3h42m
cpu-app-hpa   Deployment/cpu-app   cpu: 4%/50%     1         5         1          3h42m
```

The utilisation fell to 3 % within about 30 s (metrics-server lag), then nothing happened for the 60 s
stabilization window, and then one pod was removed every 30 s as configured: 5 -> 4 -> 3 -> 2 -> 1 in
two minutes. With the default 300 s window the first scale-down step alone would have waited 5 minutes.

```bash
kubectl get pods -n s13 -l app=cpu-app
kubectl describe hpa cpu-app-hpa -n s13 | sed -n '/^Events/,$p'
```

Output (captured 2026-10-08):

```text
NAME                       READY   STATUS    RESTARTS   AGE
cpu-app-55f8dd8876-mvfgk   1/1     Running   0          3h46m
Events:
  Type    Reason             Age    From                       Message
  ----    ------             ----   ----                       -------
  Normal  SuccessfulRescale  7m1s   horizontal-pod-autoscaler  New size: 5; reason: cpu resource utilization (percentage of request) above target
  Normal  SuccessfulRescale  2m31s  horizontal-pod-autoscaler  New size: 4; reason: All metrics below target
  Normal  SuccessfulRescale  2m1s   horizontal-pod-autoscaler  New size: 3; reason: All metrics below target
  Normal  SuccessfulRescale  91s    horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
  Normal  SuccessfulRescale  61s    horizontal-pod-autoscaler  New size: 1; reason: All metrics below target
```

The original pod (`mvfgk`) survived: the Deployment controller removes the youngest pods first. The
event timestamps confirm the 30 s cadence of the scale-down policy.

## Step 9 – Output / screenshots

The captured output blocks in Steps 3, 6, 7 and 8 (`kubectl get hpa -w`, `kubectl top pods`,
`kubectl describe hpa`, `kubectl get pods`) are the captures for this task and are referenced from the
session README's Screenshots section. Timeline of the run on 2026-10-08 (IST): load started 02:27:04,
5 replicas at 02:27:40, load stopped 02:30:08, back to 1 replica at 02:33:20.

## Troubleshooting notes

| Symptom | Cause / fix |
| --- | --- |
| `TARGETS <unknown>/50%` for more than a minute | metrics-server missing (`kubectl top pods` fails) or no `resources.requests.cpu` on the container |
| `FailedGetResourceMetric ... missing request for cpu` in `describe hpa` | add `resources.requests.cpu` to every container in the pod |
| utilisation stays low under load | app is not CPU-bound (that is why this demo uses a CPU-burning handler) or load generator too small: `./load_generator.sh 6` |
| utilisation does not drop after scale-out | closed-loop load generator (tight `wget` loop) grows with capacity; this is what I saw, see Step 6 |
| replicas stuck at max | expected, see `ScalingLimited True / TooManyReplicas`; raise `maxReplicas` or reduce load |
| pods `exec format error` | amd64-only image on arm64 node; use multi-arch images |

## Cleanup

```bash
./load_generator.sh --stop
kubectl delete -f hpa.yaml -f service.yaml -f deployment.yaml
```

## Deliverables

- `hpa.yaml` – HPA YAML (autoscaling/v2, 50% CPU, 1-5 replicas).
- `deployment.yaml`, `service.yaml` – application with CPU requests.
- `load-generator.yaml`, `load_generator.sh` – load generator.
- This README – the nine steps with HPA output (`get hpa -w`, `top pods`, `describe hpa`, `get pods`).
