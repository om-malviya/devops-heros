# 04 – Recreate Deployment

Student: Om Malviya | Enrollment No: 24BCS10448

With `strategy.type: Recreate` the Deployment scales the old ReplicaSet to 0
and waits until every old pod is gone before scaling the new ReplicaSet up.
Two versions never run together, so there is a downtime window.

```text
[v1][v1][v1]                     Running
      | apply v2
[Terminating][Terminating][Terminating]
      |
[            no pods            ]   <- downtime, Service has 0 endpoints
      |
[ContainerCreating] x3
      |
[v2][v2][v2]                     Running
```

## Files

| File | Purpose |
| --- | --- |
| `deployment-v1.yaml` | 3 replicas, `strategy.type: Recreate`, answer `v1` |
| `deployment-v2.yaml` | Same Deployment, answer `v2` |
| `service.yaml` | NodePort 30040, selector `app=web-recreate` |

## Step 1 – Deploy the application

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f deployment-v1.yaml -f service.yaml
kubectl -n s10 rollout status deployment/web-recreate
kubectl -n s10 get pods -l app=web-recreate
kubectl -n s10 get deployment web-recreate -o jsonpath='{.spec.strategy.type}'; echo
```

Output (captured 2026-10-08)
```text
namespace/s10 unchanged
pod/client unchanged
deployment.apps/web-recreate created
service/web-recreate created
Waiting for deployment "web-recreate" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "web-recreate" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "web-recreate" rollout to finish: 2 of 3 updated replicas are available...
deployment "web-recreate" successfully rolled out
NAME                            READY   STATUS    RESTARTS   AGE
web-recreate-695c848bbf-4j2b9   1/1     Running   0          23s
web-recreate-695c848bbf-6h2d6   1/1     Running   0          23s
web-recreate-695c848bbf-dn9p7   1/1     Running   0          23s
Recreate
```

## Step 2 – Update the application

Terminal 1 (watch):

```bash
kubectl -n s10 get pods -l app=web-recreate -w
```

Terminal 2 (request loop, 2 per second):

```bash
kubectl -n s10 exec client -- sh -c 'while true; do wget -qO- -T 1 http://web-recreate 2>/dev/null || echo "[OUTAGE] no endpoint"; sleep 0.5; done'
```

Terminal 3 (apply the new version):

```bash
kubectl apply -f deployment-v2.yaml
kubectl -n s10 rollout status deployment/web-recreate
```

Output (captured 2026-10-08) (repeated progress lines removed)
```text
deployment.apps/web-recreate configured
Waiting for deployment "web-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "web-recreate" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "web-recreate" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "web-recreate" rollout to finish: 2 of 3 updated replicas are available...
deployment "web-recreate" successfully rolled out
```

## Step 3 – Observe old pods terminating before new ones are created

Terminal 1 Output (captured 2026-10-08) (duplicate watch lines removed)
```text
NAME                            READY   STATUS    RESTARTS   AGE
web-recreate-695c848bbf-4j2b9   1/1     Running   0          113s
web-recreate-695c848bbf-6h2d6   1/1     Running   0          113s
web-recreate-695c848bbf-dn9p7   1/1     Running   0          113s
web-recreate-695c848bbf-4j2b9   1/1     Terminating   0          116s   <- all three at once
web-recreate-695c848bbf-6h2d6   1/1     Terminating   0          116s
web-recreate-695c848bbf-dn9p7   1/1     Terminating   0          116s
web-recreate-695c848bbf-6h2d6   0/1     Error         0          117s   <- http-echo exits non-zero on SIGTERM
web-recreate-695c848bbf-dn9p7   0/1     Error         0          117s
web-recreate-695c848bbf-4j2b9   0/1     Error         0          117s
web-recreate-55945577ff-cd4jx   0/1     Pending       0          0s     <- v2 only starts now
web-recreate-55945577ff-4xfvs   0/1     Pending       0          0s
web-recreate-55945577ff-thsmr   0/1     Pending       0          0s
web-recreate-55945577ff-cd4jx   0/1     ContainerCreating   0          0s
web-recreate-55945577ff-thsmr   0/1     ContainerCreating   0          1s
web-recreate-55945577ff-4xfvs   0/1     ContainerCreating   0          1s
web-recreate-695c848bbf-6h2d6   0/1     Error               0          118s   <- old pod objects removed
web-recreate-695c848bbf-4j2b9   0/1     Error               0          118s
web-recreate-695c848bbf-dn9p7   0/1     Error               0          118s
web-recreate-55945577ff-4xfvs   0/1     Running             0          2s
web-recreate-55945577ff-cd4jx   0/1     Running             0          2s
web-recreate-55945577ff-thsmr   0/1     Running             0          2s
web-recreate-55945577ff-cd4jx   1/1     Running             0          3s
web-recreate-55945577ff-thsmr   1/1     Running             0          3s
web-recreate-55945577ff-4xfvs   1/1     Running             0          3s
```

Terminal 2 Output (captured 2026-10-08) (loop bounded to 50 requests; trailing `v2` lines removed)
```text
v1
v1
v1
v1
v1
v1
v1
[OUTAGE] no endpoint
[OUTAGE] no endpoint
[OUTAGE] no endpoint
[OUTAGE] no endpoint
v2
v2
v2
```

The Endpoints object is empty during the gap. Because the gap is only a few
seconds long I polled it from a loop instead of typing the command by hand:

```bash
for i in $(seq 1 40); do echo "$(date +%T) $(kubectl -n s10 get endpoints web-recreate --no-headers)"; sleep 0.5; done
```

Output (captured 2026-10-08) (polled every 0.5 s during the update)
```text
02:31:59 web-recreate   10.42.0.133:8080,10.42.0.134:8080,10.42.0.135:8080   116s
02:31:59 web-recreate   <none>                                                117s   <- all v1 pods Terminating
02:32:00 web-recreate   <none>                                                117s
02:32:01 web-recreate   <none>                                                118s
02:32:02 web-recreate   <none>                                                119s
02:32:03 web-recreate                                                         2m     <- v2 pods exist, none Ready
02:32:03 web-recreate   10.42.0.140:8080,10.42.0.141:8080,10.42.0.142:8080   2m1s
```

Compare the ReplicaSets after the update:

```bash
kubectl -n s10 get rs -l app=web-recreate
kubectl -n s10 rollout history deployment/web-recreate
```

Output (captured 2026-10-08)
```text
NAME                      DESIRED   CURRENT   READY   AGE
web-recreate-55945577ff   3         3         3       61s
web-recreate-695c848bbf   0         0         0       2m58s
deployment.apps/web-recreate
REVISION  CHANGE-CAUSE
1         deploy v1
2         deploy v2
```

Rollback also uses Recreate, so it has the same gap:

```bash
kubectl -n s10 rollout undo deployment/web-recreate
kubectl -n s10 exec client -- wget -qO- http://web-recreate
```

Output (captured 2026-10-08) (repeated progress lines removed)
```text
deployment.apps/web-recreate rolled back
Waiting for deployment "web-recreate" rollout to finish: 0 out of 3 new replicas have been updated...
Waiting for deployment "web-recreate" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "web-recreate" rollout to finish: 2 of 3 updated replicas are available...
deployment "web-recreate" successfully rolled out
v1
```

## What I observed

- All three v1 pods entered `Terminating` at the same moment and no v2 pod
  was created until the last v1 pod had disappeared from the API.
- During that gap `kubectl get endpoints` showed `<none>` and the request
  loop printed `[OUTAGE]` four times, i.e. about 4 s (http-echo exits
  immediately on SIGTERM, the image was cached, and the readiness probe
  passed on its first try at 2 s). With a slower-stopping app or an image
  pull it would be much longer.
- The old pods show `Error` rather than a clean `Terminating 0/1` because
  `http-echo` returns a non-zero exit code on SIGTERM; it is cosmetic.
- The `rollout status` line `0 out of 3 new replicas have been updated`
  repeated for a few seconds: that is the controller waiting for the old
  ReplicaSet to reach 0 before it creates the new one.
- This is acceptable when the two versions cannot coexist (schema change,
  single-writer volume, licence lock) but not for a public web service.

## Strategy comparison

| Strategy | Downtime | Extra capacity | Mixed versions | Rollback |
| --- | --- | --- | --- | --- |
| RollingUpdate | none | +maxSurge | yes, briefly | `rollout undo` |
| Blue-Green | none | 2x | no | patch selector back |
| Canary | none | +canary pods | yes, controlled | scale canary to 0 |
| Recreate | yes | none | no | `rollout undo` (also with gap) |

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment-v2.yaml
```

## Deliverables

- `deployment-v1.yaml` / `deployment-v2.yaml` – Deployment with `strategy.type: Recreate`.
- `service.yaml` – NodePort 30040 Service.
- `README.md` – deploy, update, watch all old pods terminate before new ones start.
