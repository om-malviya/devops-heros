# 01 – Rolling Update

Student: Om Malviya | Enrollment No: 24BCS10448

RollingUpdate is the default Deployment strategy. Kubernetes creates new pods a
few at a time and only removes an old pod once a new one is Ready, so the
Service never has zero endpoints.

```text
replicas=4, maxSurge=1, maxUnavailable=0

[v1][v1][v1][v1]            4 ready, 0 updated
[v1][v1][v1][v1][v2]        surge pod created (5 pods), wait for Ready
[v1][v1][v1]    [v2]        one v1 terminated -> back to 4
[v1][v1][v1]    [v2][v2]    next surge ...
...
                [v2][v2][v2][v2]   done
```

## Files

| File | Purpose |
| --- | --- |
| `deployment-v1.yaml` | 4 replicas of `hashicorp/http-echo` answering `v1`, `maxSurge: 1`, `maxUnavailable: 0` |
| `deployment-v2.yaml` | Same Deployment name, pod template answers `v2` |
| `service.yaml` | NodePort 30010 -> container 8080, selector `app=web-rolling` |

All objects live in namespace `s10` (`../namespace.yaml`). The in-cluster
client pod is `../client-pod.yaml`.

## Step 1 – Create the Deployment

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f ../client-pod.yaml
kubectl apply -f deployment-v1.yaml
kubectl apply -f service.yaml
kubectl -n s10 rollout status deployment/web-rolling
```

Output (captured 2026-10-08)
```text
namespace/s10 created
pod/client created
deployment.apps/web-rolling created
service/web-rolling created
Waiting for deployment "web-rolling" rollout to finish: 0 of 4 updated replicas are available...
Waiting for deployment "web-rolling" rollout to finish: 1 of 4 updated replicas are available...
Waiting for deployment "web-rolling" rollout to finish: 2 of 4 updated replicas are available...
Waiting for deployment "web-rolling" rollout to finish: 3 of 4 updated replicas are available...
deployment "web-rolling" successfully rolled out
```

```bash
kubectl -n s10 get pods -l app=web-rolling --show-labels
```

Output (captured 2026-10-08)
```text
NAME                           READY   STATUS    RESTARTS   AGE   LABELS
web-rolling-7b85bb48cf-9q8jt   1/1     Running   0          30s   app=web-rolling,pod-template-hash=7b85bb48cf,version=v1
web-rolling-7b85bb48cf-btgzm   1/1     Running   0          30s   app=web-rolling,pod-template-hash=7b85bb48cf,version=v1
web-rolling-7b85bb48cf-d8ht9   1/1     Running   0          30s   app=web-rolling,pod-template-hash=7b85bb48cf,version=v1
web-rolling-7b85bb48cf-z9rdf   1/1     Running   0          30s   app=web-rolling,pod-template-hash=7b85bb48cf,version=v1
```

## Step 2 – Configure the rolling update

The strategy is declared in the manifest:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # up to 1 extra pod (5 total) during the rollout
    maxUnavailable: 0  # never fewer than 4 Ready pods
```

Confirm what the API server stored:

```bash
kubectl -n s10 get deployment web-rolling -o jsonpath='{.spec.strategy}'; echo
```

Output (captured 2026-10-08)
```text
{"rollingUpdate":{"maxSurge":1,"maxUnavailable":0},"type":"RollingUpdate"}
```

Baseline check from inside the cluster:

```bash
kubectl -n s10 exec client -- sh -c 'for i in 1 2 3 4; do wget -qO- http://web-rolling; done'
```

Output (captured 2026-10-08)
```text
v1
v1
v1
v1
```

## Step 3 – Perform the update

Start a watch in a second terminal first:

```bash
kubectl -n s10 get pods -l app=web-rolling -w
```

Then apply v2 (the pod template changes: `-text=v2`, label `version=v2`):

```bash
kubectl apply -f deployment-v2.yaml
kubectl -n s10 rollout status deployment/web-rolling
```

Output (captured 2026-10-08) (repeated progress lines removed)
```text
deployment.apps/web-rolling configured
Waiting for deployment "web-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "web-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "web-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "web-rolling" rollout to finish: 2 old replicas are pending termination...
Waiting for deployment "web-rolling" rollout to finish: 1 old replicas are pending termination...
deployment "web-rolling" successfully rolled out
```

An equivalent way to trigger a rollout is `kubectl set image`. It is the
normal way when only the image tag changes:

```bash
kubectl -n s10 set image deployment/web-rolling web=hashicorp/http-echo:1.0.0
```

In this lab the version text lives in `args`, not in the image tag, so I use
`kubectl apply -f deployment-v2.yaml`; both commands produce the same
RollingUpdate behaviour because both change the pod template.

## Step 4 – Verify old and new pods

Watch output (terminal 2). Old pods are from ReplicaSet `7b85bb48cf`, new
pods from `f66497d77`. Note there are never fewer than 4 Ready pods and never
more than 5 pods in total. The old pods show `Error` instead of a clean
`0/1 Terminating` because `http-echo` exits with a non-zero code when it
receives SIGTERM; that is just how this tiny image shuts down, the rollout
itself is unaffected:

Output (captured 2026-10-08) (duplicate watch lines for an unchanged state removed)
```text
NAME                           READY   STATUS    RESTARTS   AGE
web-rolling-7b85bb48cf-9q8jt   1/1     Running   0          90s
web-rolling-7b85bb48cf-btgzm   1/1     Running   0          90s
web-rolling-7b85bb48cf-d8ht9   1/1     Running   0          90s
web-rolling-7b85bb48cf-z9rdf   1/1     Running   0          90s
web-rolling-f66497d77-j2976    0/1     Pending   0          0s     <- v2 surge pod, 5 pods now
web-rolling-f66497d77-j2976    0/1     ContainerCreating   0          0s
web-rolling-f66497d77-j2976    0/1     Running             0          1s     <- running, not Ready yet
web-rolling-f66497d77-j2976    1/1     Running             0          2s     <- readiness passed
web-rolling-7b85bb48cf-btgzm   1/1     Terminating         0          95s    <- first v1 pod removed
web-rolling-f66497d77-v99x4    0/1     Pending             0          0s
web-rolling-f66497d77-v99x4    0/1     ContainerCreating   0          0s
web-rolling-7b85bb48cf-btgzm   0/1     Error               0          95s    <- http-echo exits non-zero on SIGTERM
web-rolling-f66497d77-v99x4    0/1     Running             0          1s
web-rolling-f66497d77-v99x4    1/1     Running             0          2s
web-rolling-7b85bb48cf-d8ht9   1/1     Terminating         0          97s
web-rolling-f66497d77-mdx8h    0/1     Pending             0          0s
web-rolling-f66497d77-mdx8h    0/1     ContainerCreating   0          0s
web-rolling-7b85bb48cf-d8ht9   0/1     Error               0          97s
web-rolling-f66497d77-mdx8h    0/1     Running             0          1s
web-rolling-f66497d77-mdx8h    1/1     Running             0          2s
web-rolling-7b85bb48cf-z9rdf   1/1     Terminating         0          99s
web-rolling-f66497d77-f4svf    0/1     Pending             0          0s
web-rolling-f66497d77-f4svf    0/1     ContainerCreating   0          0s
web-rolling-7b85bb48cf-z9rdf   0/1     Error               0          99s
web-rolling-f66497d77-f4svf    0/1     Running             0          1s
web-rolling-f66497d77-f4svf    1/1     Running             0          2s
web-rolling-7b85bb48cf-9q8jt   1/1     Terminating         0          101s   <- last v1 pod
web-rolling-7b85bb48cf-9q8jt   0/1     Error               0          101s
```

While the rollout runs, a request loop from the client pod shows the answers
shifting from `v1` to `v2` with no failures (the rollout took about 10 s, so
the mix is short):

```bash
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 12); do wget -qO- http://web-rolling || echo FAIL; sleep 1; done'
```

Output (captured 2026-10-08)
```text
v1
v1
v1
v1
v1
v1
v1
v1
v1
v2
v2
v2
```

After the rollout both ReplicaSets still exist; the old one is scaled to 0:

```bash
kubectl -n s10 get rs -l app=web-rolling
kubectl -n s10 get pods -l app=web-rolling -L version
```

Output (captured 2026-10-08)
```text
NAME                     DESIRED   CURRENT   READY   AGE
web-rolling-7b85bb48cf   0         0         0       2m58s
web-rolling-f66497d77    4         4         4       85s

NAME                          READY   STATUS    RESTARTS   AGE   VERSION
web-rolling-f66497d77-f4svf   1/1     Running   0          79s   v2
web-rolling-f66497d77-j2976   1/1     Running   0          85s   v2
web-rolling-f66497d77-mdx8h   1/1     Running   0          81s   v2
web-rolling-f66497d77-v99x4   1/1     Running   0          83s   v2
```

## Step 5 – Rollout history and rollback

```bash
kubectl -n s10 rollout history deployment/web-rolling
```

Output (captured 2026-10-08)
```text
deployment.apps/web-rolling
REVISION  CHANGE-CAUSE
1         deploy v1
2         deploy v2
```

(The CHANGE-CAUSE column comes from the `kubernetes.io/change-cause`
annotation in each manifest.)

```bash
kubectl -n s10 rollout undo deployment/web-rolling
kubectl -n s10 rollout status deployment/web-rolling
kubectl -n s10 exec client -- wget -qO- http://web-rolling
kubectl -n s10 rollout history deployment/web-rolling
```

Output (captured 2026-10-08) (repeated progress lines removed)
```text
Warning: resource deployments/web-rolling was previously managed with 'kubectl apply'. Rolling back will not update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected behavior on future 'kubectl apply' operations. Consider using 'kubectl apply' with your previous configuration file instead.
deployment.apps/web-rolling rolled back
Waiting for deployment "web-rolling" rollout to finish: 1 out of 4 new replicas have been updated...
Waiting for deployment "web-rolling" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "web-rolling" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "web-rolling" rollout to finish: 1 old replicas are pending termination...
deployment "web-rolling" successfully rolled out
v1
deployment.apps/web-rolling
REVISION  CHANGE-CAUSE
2         deploy v2
3         deploy v1
```

The undo is itself a rolling update in the other direction (revision 1 is
re-used as revision 3). The warning about `last-applied-configuration` is
kubectl reminding me that the live object no longer matches
`deployment-v2.yaml`; the next `kubectl apply` would simply roll forward
again.

## What I observed

- The Deployment never touched pods directly: it created a second ReplicaSet
  and moved the replica count from the old RS to the new one, one pod at a
  time because `maxSurge: 1`.
- The readiness probe is what gates the rollout. Each surge pod sat at `0/1
  Running` for about a second (`initialDelaySeconds: 2`), and only after it
  became `1/1` did the next v1 pod start Terminating.
- With `maxUnavailable: 0` capacity never dropped below 4 Ready pods, so the
  request loop had no failures, only a shift from `v1` to `v2`.
- From macOS the NodePort was reachable as `http://localhost:30010` (colima
  forwards the VM's ports to localhost); the node IP `192.168.5.1` itself is
  not routable from the host.

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment-v2.yaml
```

(Deleting the Deployment removes both ReplicaSets and their pods.)

## Deliverables

- `deployment-v1.yaml` – 4-replica Deployment, RollingUpdate with `maxSurge: 1`, `maxUnavailable: 0`.
- `deployment-v2.yaml` – same Deployment with the v2 pod template.
- `service.yaml` – NodePort 30010 Service selecting `app=web-rolling`.
- `README.md` – create, configure, update, verify old/new pods, rollout history and undo.
