# 02 – Blue-Green Deployment

Student: Om Malviya | Enrollment No: 24BCS10448

Two full copies of the application run side by side. The Service selector
points at exactly one of them; switching versions is a single selector patch,
and rolling back is the same patch in reverse.

```text
             +---------------------+
   users --> | Service web-bg      |   selector: app=web-bg, version=blue
             +----------+----------+
                        |
        +---------------+---------------+
        v (LIVE)                        v (IDLE, no endpoints)
 [blue][blue][blue]              [green][green][green]
 Deployment web-blue             Deployment web-green
```

## Files

| File | Purpose |
| --- | --- |
| `deployment-blue.yaml` | 3 pods, labels `app=web-bg, version=blue`, answer `blue` |
| `deployment-green.yaml` | 3 pods, labels `app=web-bg, version=green`, answer `green` |
| `service.yaml` | NodePort 30020, selector `app=web-bg, version=blue` (initial) |
| `switch-to-green.sh` | `kubectl patch svc` to flip the selector to green |
| `switch-to-blue.sh` | Same patch back to blue (rollback) |

## Step 1 – Create the Blue version

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f deployment-blue.yaml -f service.yaml
kubectl -n s10 rollout status deployment/web-blue
```

Output (captured 2026-10-08)
```text
namespace/s10 unchanged
pod/client unchanged
deployment.apps/web-blue created
service/web-bg created
Waiting for deployment "web-blue" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "web-blue" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "web-blue" rollout to finish: 2 of 3 updated replicas are available...
deployment "web-blue" successfully rolled out
```

## Step 2 – Create the Green version

```bash
kubectl apply -f deployment-green.yaml
kubectl -n s10 rollout status deployment/web-green
kubectl -n s10 get pods -l app=web-bg -L version
```

Output (captured 2026-10-08)
```text
deployment.apps/web-green created
Waiting for deployment "web-green" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "web-green" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "web-green" rollout to finish: 2 of 3 updated replicas are available...
deployment "web-green" successfully rolled out
NAME                         READY   STATUS    RESTARTS   AGE   VERSION
web-blue-869698bf69-8hxj8    1/1     Running   0          73s   blue
web-blue-869698bf69-p5dt2    1/1     Running   0          73s   blue
web-blue-869698bf69-zjwpd    1/1     Running   0          73s   blue
web-green-5747479f5f-pfk5d   1/1     Running   0          25s   green
web-green-5747479f5f-qds29   1/1     Running   0          25s   green
web-green-5747479f5f-wlgbk   1/1     Running   0          25s   green
```

Six pods are Running, but only the three blue ones are behind the Service
(the `Endpoints is deprecated` warning is kubectl 1.37 pointing at
EndpointSlices; the object still works and I keep using it because it is
the easiest to read):

```bash
kubectl -n s10 get svc web-bg -o jsonpath='{.spec.selector}'; echo
kubectl -n s10 get endpoints web-bg
kubectl -n s10 get pods -l app=web-bg,version=blue -o wide | awk '{print $1, $6}'
```

Output (captured 2026-10-08)
```text
{"app":"web-bg","version":"blue"}
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME     ENDPOINTS                                         AGE
web-bg   10.42.0.92:8080,10.42.0.93:8080,10.42.0.94:8080   73s
NAME IP
web-blue-869698bf69-8hxj8 10.42.0.93
web-blue-869698bf69-p5dt2 10.42.0.92
web-blue-869698bf69-zjwpd 10.42.0.94
```

Verify the active version from the client pod:

```bash
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 6); do wget -qO- http://web-bg; done | sort | uniq -c'
```

Output (captured 2026-10-08)
```text
      6 blue
```

## Step 3 – Switch traffic to Green

```bash
./switch-to-green.sh
```

Output (captured 2026-10-08)
```text
service/web-bg patched
Selector now:
{"app":"web-bg","version":"green"}
Endpoints now:
NAME     ENDPOINTS                                         AGE
web-bg   10.42.0.95:8080,10.42.0.96:8080,10.42.0.97:8080   75s
```

The script runs:

```bash
kubectl -n s10 patch svc web-bg -p '{"spec":{"selector":{"app":"web-bg","version":"green"}}}'
```

## Step 4 – Verify the active version

```bash
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 6); do wget -qO- http://web-bg; done | sort | uniq -c'
kubectl -n s10 describe svc web-bg | grep -E 'Selector|Endpoints'
```

Output (captured 2026-10-08)
```text
      6 green
Selector:                 app=web-bg,version=green
Endpoints:                10.42.0.95:8080,10.42.0.97:8080,10.42.0.96:8080
```

Rollback is the same operation in reverse:

```bash
./switch-to-blue.sh
kubectl -n s10 exec client -- wget -qO- http://web-bg
```

Output (captured 2026-10-08)
```text
service/web-bg patched
Selector now:
{"app":"web-bg","version":"blue"}
Endpoints now:
NAME     ENDPOINTS                                         AGE
web-bg   10.42.0.92:8080,10.42.0.93:8080,10.42.0.94:8080   75s
green
```

The very first request after the rollback still answered `green`: the
Endpoints object was already rewritten, but kube-proxy on the node had not
yet re-synced its rules (this takes well under a second). I repeated the
check 2 s later and every request answered `blue`:

```bash
sleep 2
kubectl -n s10 exec client -- sh -c 'for i in 1 2 3; do wget -qO- http://web-bg; done'
```

Output (captured 2026-10-08)
```text
blue
blue
blue
```

From macOS the same switch is visible on the NodePort,
`curl -s localhost:30020`, which answered `blue`, then `green` after
`switch-to-green.sh`, then `blue` again.

Once green is confirmed stable the old colour can be removed with
`kubectl -n s10 delete deployment web-blue`.

I also re-listed the pods after the switch and all six had the same names
and ages as before: nothing was restarted.

## What I observed

- No pod was created or deleted during the switch. Only the Service's
  `selector` changed, and the Endpoints object was rewritten immediately with
  the other set of pod IPs.
- The answers flipped from 100% `blue` to 100% `green` with no mixed window,
  which is the main difference from a rolling update. The only lag is the
  sub-second kube-proxy rule sync I caught on the rollback.
- The cost is running 2x the pods while both colours exist.

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment-blue.yaml -f deployment-green.yaml
```

## Deliverables

- `deployment-blue.yaml` / `deployment-green.yaml` – the two environments.
- `service.yaml` – NodePort 30020 Service with selector `version: blue`.
- `switch-to-green.sh` / `switch-to-blue.sh` – `kubectl patch svc` selector switch and rollback.
- `README.md` – create blue, create green, switch, verify active version.
