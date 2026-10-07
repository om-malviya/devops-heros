# 03 – Canary Deployment

Student: Om Malviya | Enrollment No: 24BCS10448

A small number of pods run the new version alongside the stable version. One
Service selects both sets, so the share of traffic the canary receives equals
its share of the endpoints.

```text
                    Service web  (selector: app=web)
                              |
      kube-proxy distributes across all 10 endpoints
                              |
   +----+----+----+----+----+----+----+----+----+-----+
   v    v    v    v    v    v    v    v    v    v
 [s1] [s1] [s1] [s1] [s1] [s1] [s1] [s1] [s1]  [c2]
   web-stable x9  (track=stable)                web-canary x1 (track=canary)
          ~90% of requests                      ~10% of requests
```

| stable | canary | canary share |
| --- | --- | --- |
| 9 | 1 | 10% |
| 7 | 3 | 30% |
| 5 | 5 | 50% |
| 0 | 10 | 100% (promoted) |

## Files

| File | Purpose |
| --- | --- |
| `deployment-stable.yaml` | 9 replicas, labels `app=web, track=stable`, answer `stable-v1` |
| `deployment-canary.yaml` | 1 replica, labels `app=web, track=canary`, answer `canary-v2` |
| `service.yaml` | NodePort 30030, selector **only** `app=web` so both tracks are endpoints |

## Step 1 – Deploy the stable version

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f deployment-stable.yaml -f service.yaml
kubectl -n s10 rollout status deployment/web-stable
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 20); do wget -qO- http://web; done | sort | uniq -c'
```

Output (captured 2026-10-08) (repeated progress lines removed)
```text
namespace/s10 unchanged
pod/client unchanged
deployment.apps/web-stable created
service/web created
Waiting for deployment "web-stable" rollout to finish: 0 of 9 updated replicas are available...
Waiting for deployment "web-stable" rollout to finish: 4 of 9 updated replicas are available...
Waiting for deployment "web-stable" rollout to finish: 8 of 9 updated replicas are available...
deployment "web-stable" successfully rolled out
     20 stable-v1
```

## Step 2 – Deploy the canary version

```bash
kubectl apply -f deployment-canary.yaml
kubectl -n s10 rollout status deployment/web-canary
kubectl -n s10 get pods -l app=web -L track,version
```

Output (captured 2026-10-08)
```text
deployment.apps/web-canary created
Waiting for deployment "web-canary" rollout to finish: 0 of 1 updated replicas are available...
deployment "web-canary" successfully rolled out
NAME                          READY   STATUS    RESTARTS   AGE   TRACK    VERSION
web-canary-85c7d745c7-mx2zw   1/1     Running   0          19s   canary   v2
web-stable-6d8bf949d5-46n5q   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-8kkqn   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-b599x   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-fm5kh   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-jz8gc   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-k8xnf   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-ntcjj   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-nvfrg   1/1     Running   0          84s   stable   v1
web-stable-6d8bf949d5-pmk6m   1/1     Running   0          84s   stable   v1
```

## Step 3 – Route a small percentage of traffic to the canary

Nothing extra to configure: the Service already selects `app=web`, so the
new pod is added to the endpoints automatically.

```bash
kubectl -n s10 get endpoints web
```

Output (captured 2026-10-08)
```text
NAME   ENDPOINTS                                                        AGE
web    10.42.0.120:8080,10.42.0.121:8080,10.42.0.122:8080 + 7 more...   84s
```

```bash
kubectl -n s10 get endpointslices -l kubernetes.io/service-name=web -o jsonpath='{range .items[0].endpoints[*]}{.targetRef.name}{"\n"}{end}' | sort
```

Output (captured 2026-10-08)
```text
web-canary-85c7d745c7-mx2zw
web-stable-6d8bf949d5-46n5q
web-stable-6d8bf949d5-8kkqn
web-stable-6d8bf949d5-b599x
web-stable-6d8bf949d5-fm5kh
web-stable-6d8bf949d5-jz8gc
web-stable-6d8bf949d5-k8xnf
web-stable-6d8bf949d5-ntcjj
web-stable-6d8bf949d5-nvfrg
web-stable-6d8bf949d5-pmk6m
```

## Step 4 – Verify both versions

```bash
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 20); do wget -qO- http://web; done | sort | uniq -c'
```

Output (captured 2026-10-08)
```text
      3 canary-v2
     17 stable-v1
```

With 100 requests the split is close to the 9:1 ratio:

```bash
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 100); do wget -qO- http://web; done | sort | uniq -c'
```

Output (captured 2026-10-08)
```text
      7 canary-v2
     93 stable-v1
```

Increase the canary share to 30% and re-test (I waited ~15 s for the new
pods to pass their readiness probe; `kubectl get pods -l app=web -L track`
then listed 3 canary and 7 stable pods):

```bash
kubectl -n s10 scale deployment web-canary --replicas=3
kubectl -n s10 scale deployment web-stable --replicas=7
kubectl -n s10 exec client -- sh -c 'for i in $(seq 1 20); do wget -qO- http://web; done | sort | uniq -c'
```

Output (captured 2026-10-08)
```text
deployment.apps/web-canary scaled
deployment.apps/web-stable scaled
      7 canary-v2
     13 stable-v1
```

Promote (canary healthy) or roll back (canary broken):

```bash
# promote
kubectl -n s10 scale deployment web-canary --replicas=10
kubectl -n s10 scale deployment web-stable --replicas=0
# rollback
kubectl -n s10 scale deployment web-canary --replicas=0
kubectl -n s10 scale deployment web-stable --replicas=9
```

## What I observed

- The `track` label is only for humans; the Service ignores it. Because the
  selector is just `app=web`, both Deployments feed the same endpoint list.
- The traffic split is approximate. kube-proxy picks endpoints randomly (in
  iptables mode) so 20 requests gave 3 canary hits (15%), 100 requests gave 7
  (7%), and at 3:7 pods 20 requests gave 7 (35%). The ratio converges on the
  pod ratio but is never exact per request. The same mix was visible from
  macOS on the NodePort (`curl localhost:30030` five times: 2 canary, 3
  stable).
- Exact weights (e.g. 5%) need something above the Service: an Ingress with
  canary weight annotations, a service mesh, or Argo Rollouts / Flagger.

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment-canary.yaml -f deployment-stable.yaml
```

## Deliverables

- `deployment-stable.yaml` – 9 replicas (`track=stable`).
- `deployment-canary.yaml` – 1 replica (`track=canary`).
- `service.yaml` – NodePort 30030 Service selecting only `app=web`.
- `README.md` – deploy stable, deploy canary, ~10% routing, verify distribution.
