# Task 3: Mini Project – Kubernetes Troubleshooting Challenge

Student: Om Malviya | Enrollment No: 24BCS10448

## Problem statement

An nginx application (`troubleshooting-app`, 2 replicas) is exposed through the ClusterIP Service `troubleshooting-service` in namespace `s14`. The team reports two problems:

1. A Pod that was added to the namespace (`project-broken-pod`) never becomes Ready.
2. After a Service change, the application is no longer reachable through `troubleshooting-service`, even though the application Pods are Running.

My job is to follow the course flow (**Deploy → Observe → Break → Investigate → Find root cause → Fix → Verify**) and document it. I must not edit YAML before I have proven the root cause with `kubectl`.

Files:

| File | Purpose |
|---|---|
| `deployment.yaml` | 2 x `nginx:alpine` with a readiness probe |
| `service.yaml` | correct Service (selector `app: troubleshooting-app`) |
| `client-pod.yaml` | busybox client to test DNS + HTTP from inside the cluster |
| `broken-pod.yaml` / `fixed-pod.yaml` | image problem and its fix |
| `broken-service.yaml` | Service with selector `app: wrong-app` |
| `run.sh` | runs all the steps below in order and echoes each command |

All outputs below are from one run of `./run.sh` on a single-node k3s cluster (Kubernetes v1.35, node `colima`), trimmed where noted.

---

## 1. Deploy the application

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f deployment.yaml -f service.yaml -f client-pod.yaml
kubectl rollout status deployment/troubleshooting-app -n s14 --timeout=120s
kubectl get pods -n s14
kubectl get service -n s14
```

Output (captured 2026-10-08)

```text
namespace/s14 unchanged
deployment.apps/troubleshooting-app created
service/troubleshooting-service created
pod/client created
Waiting for deployment "troubleshooting-app" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "troubleshooting-app" rollout to finish: 1 of 2 updated replicas are available...
deployment "troubleshooting-app" successfully rolled out
NAME                                   READY   STATUS    RESTARTS   AGE   IP            NODE     NOMINATED NODE   READINESS GATES
client                                 1/1     Running   0          3s    10.42.0.121   colima   <none>           <none>
troubleshooting-app-79c8b7545d-96kds   1/1     Running   0          3s    10.42.0.120   colima   <none>           <none>
troubleshooting-app-79c8b7545d-qcw6j   1/1     Running   0          3s    10.42.0.119   colima   <none>           <none>
NAME                      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
troubleshooting-service   ClusterIP   10.43.92.5   <none>        80/TCP    3s
```

## 2. Check the application (Observe)

```bash
kubectl get pods -n s14 -o wide
kubectl describe pod troubleshooting-app-79c8b7545d-96kds -n s14
kubectl logs troubleshooting-app-79c8b7545d-96kds -n s14 --tail=5
kubectl exec troubleshooting-app-79c8b7545d-96kds -n s14 -- wget -qO- localhost | head -4   # nginx:alpine has sh, not bash
```

Output (captured 2026-10-08; describe trimmed)

```text
Name:             troubleshooting-app-79c8b7545d-96kds
Namespace:        s14
Node:             colima/192.168.5.1
Labels:           app=troubleshooting-app
                  pod-template-hash=79c8b7545d
Status:           Running
IP:               10.42.0.120
Controlled By:  ReplicaSet/troubleshooting-app-79c8b7545d
Containers:
  app:
    Image:          nginx:alpine
    Port:           80/TCP
    State:          Running
      Started:      Thu, 08 Oct 2026 03:07:21 +0530
    Ready:          True
    Restart Count:  0
    Readiness:      http-get http://:80/ delay=2s timeout=1s period=5s successThreshold=1 failureThreshold=3
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  2s    default-scheduler  Successfully assigned s14/troubleshooting-app-79c8b7545d-96kds to colima
  Normal  Pulled     2s    kubelet            spec.containers{app}: Container image "nginx:alpine" already present on machine and can be accessed by the pod
  Normal  Created    2s    kubelet            spec.containers{app}: Container created
  Normal  Started    2s    kubelet            spec.containers{app}: Container started

2026/10/07 21:37:21 [notice] 1#1: start worker process 31
2026/10/07 21:37:21 [notice] 1#1: start worker process 32
2026/10/07 21:37:21 [notice] 1#1: start worker process 33
2026/10/07 21:37:21 [notice] 1#1: start worker process 34
10.42.0.1 - - [07/Oct/2026:21:37:23 +0000] "GET / HTTP/1.1" 200 896 "-" "kube-probe/1.35" "-"

<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

The application itself works: `localhost` answers from inside the container, and the last log line is the readiness probe (`kube-probe/1.35`) getting a 200.

## 3. Check the Service

```bash
kubectl get service troubleshooting-service -n s14
kubectl describe service troubleshooting-service -n s14
```

Output (captured 2026-10-08)

```text
NAME                      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
troubleshooting-service   ClusterIP   10.43.92.5   <none>        80/TCP    3s
Name:                     troubleshooting-service
Namespace:                s14
Selector:                 app=troubleshooting-app
Type:                     ClusterIP
IP:                       10.43.92.5
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
Endpoints:                10.42.0.120:80,10.42.0.119:80
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

The three things I check: **Selector** = `app=troubleshooting-app` (same as the Pod label), **TargetPort** = 80 (the port nginx listens on), **Endpoints** = both Pod IPs.

## 4. Check endpoints and test from a client Pod

```bash
kubectl get endpoints troubleshooting-service -n s14
kubectl exec client -n s14 -- nslookup troubleshooting-service
kubectl exec client -n s14 -- wget -qO- --timeout=3 http://troubleshooting-service | head -4
```

Output (captured 2026-10-08)

```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                      ENDPOINTS                       AGE
troubleshooting-service   10.42.0.119:80,10.42.0.120:80   3s
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	troubleshooting-service.s14.svc.cluster.local
Address: 10.43.92.5

** server can't find troubleshooting-service.svc.cluster.local: NXDOMAIN
** server can't find troubleshooting-service.cluster.local: NXDOMAIN
command terminated with exit code 1
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

This is my healthy baseline ("before" state). (busybox's `nslookup` prints the answer from the first search domain and then still reports NXDOMAIN for the remaining search domains and exits 1; the `Name:`/`Address:` lines are what matter.)

## 5. Create the broken Pod (Break)

```bash
kubectl apply -f broken-pod.yaml
kubectl get pod project-broken-pod -n s14      # 20 s later
```

Output (captured 2026-10-08)

```text
pod/project-broken-pod created
NAME                 READY   STATUS             RESTARTS   AGE
project-broken-pod   0/1     ImagePullBackOff   0          20s
```

## 6. Troubleshoot it (Investigate – no YAML changes yet)

```bash
kubectl get pod project-broken-pod -n s14
kubectl describe pod project-broken-pod -n s14
kubectl logs project-broken-pod -n s14
```

Output (captured 2026-10-08; describe trimmed)

```text
Name:             project-broken-pod
Namespace:        s14
Status:           Pending
IP:               10.42.0.122
Containers:
  app:
    Container ID:
    Image:          nginx:this-tag-does-not-exist
    Image ID:
    State:          Waiting
      Reason:       ImagePullBackOff
    Ready:          False
    Restart Count:  0
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned s14/project-broken-pod to colima
  Normal   BackOff    18s               kubelet            spec.containers{app}: Back-off pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     18s               kubelet            spec.containers{app}: Error: ImagePullBackOff
  Normal   Pulling    3s (x2 over 20s)  kubelet            spec.containers{app}: Pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     2s (x2 over 19s)  kubelet            spec.containers{app}: Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:this-tag-does-not-exist": failed to resolve reference "docker.io/library/nginx:this-tag-does-not-exist": docker.io/library/nginx:this-tag-does-not-exist: not found
  Warning  Failed     2s (x2 over 19s)  kubelet            spec.containers{app}: Error: ErrImagePull

Error from server (BadRequest): container "app" in pod "project-broken-pod" is waiting to start: trying and failing to pull image
```

## 7. Answers

**Q1: What is the Pod status?**
`ImagePullBackOff` (briefly `ErrImagePull` right after each failed attempt). READY is `0/1`, phase is still `Pending` because no container has started (`Container ID` is empty).

**Q2: What is the actual error?**
`Failed to pull image "nginx:this-tag-does-not-exist": ... docker.io/library/nginx:this-tag-does-not-exist: not found`.

**Q3: Which command helped you find the reason?**
`kubectl describe pod project-broken-pod -n s14` – the Events section. `kubectl logs` was useless here because the container never started (it just says `waiting to start: trying and failing to pull image`).

**Q4: What is wrong with the image?**
The repository `nginx` is fine, but the tag `this-tag-does-not-exist` does not exist in Docker Hub, so the registry answers `not found`.

**Q5: How would you fix it?**
Use a valid tag. `image` is a mutable field, so I can simply apply `fixed-pod.yaml` (image `nginx:alpine`); kubelet pulls the new image on the next retry.

```bash
kubectl apply -f fixed-pod.yaml
kubectl wait pod/project-broken-pod -n s14 --for=condition=Ready --timeout=120s
kubectl get pod project-broken-pod -n s14
```

Output (captured 2026-10-08, after)

```text
pod/project-broken-pod configured
pod/project-broken-pod condition met
NAME                 READY   STATUS    RESTARTS   AGE
project-broken-pod   1/1     Running   0          20s
```

Same Pod (AGE 20s, no recreation), now Running.

## 8. Service troubleshooting challenge (Break)

Change the selector to `app: wrong-app` (`broken-service.yaml`) and apply it:

```bash
kubectl apply -f broken-service.yaml
kubectl get endpoints troubleshooting-service -n s14
kubectl exec client -n s14 -- wget -qO- --timeout=3 http://troubleshooting-service
```

Output (captured 2026-10-08, before fix)

```text
service/troubleshooting-service configured
NAME                      ENDPOINTS   AGE
troubleshooting-service   <none>      28s
wget: can't connect to remote host (10.43.92.5): Connection refused
command terminated with exit code 1
```

The Service still exists with the same ClusterIP and DNS still resolves (wget got as far as the IP `10.43.92.5`), but it has no endpoints, so the connection is refused.

## 9. Find the root cause

```bash
kubectl get pods -n s14 --show-labels
kubectl describe service troubleshooting-service -n s14 | grep -E 'Selector|Endpoints'
kubectl get pods -n s14 -l app=wrong-app
```

Output (captured 2026-10-08)

```text
NAME                                   READY   STATUS    RESTARTS   AGE   LABELS
client                                 1/1     Running   0          29s   <none>
project-broken-pod                     1/1     Running   0          24s   <none>
troubleshooting-app-79c8b7545d-96kds   1/1     Running   0          29s   app=troubleshooting-app,pod-template-hash=79c8b7545d
troubleshooting-app-79c8b7545d-qcw6j   1/1     Running   0          29s   app=troubleshooting-app,pod-template-hash=79c8b7545d
Selector:                 app=wrong-app
Endpoints:
No resources found in s14 namespace.
```

Root cause: the Service selector `app=wrong-app` matches no Pod; the Pods are labelled `app=troubleshooting-app`. Querying Pods with the Service's own selector returns nothing, which confirms it.

Fix and verify:

```bash
kubectl apply -f service.yaml
kubectl get endpoints troubleshooting-service -n s14
kubectl exec client -n s14 -- wget -qO- --timeout=3 http://troubleshooting-service | head -4
```

Output (captured 2026-10-08, after)

```text
service/troubleshooting-service configured
NAME                      ENDPOINTS                       AGE
troubleshooting-service   10.42.0.119:80,10.42.0.120:80   32s
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

Final state from `run.sh`:

```text
$ kubectl get all -n s14 -l app=troubleshooting-app
NAME                                       READY   STATUS    RESTARTS   AGE
pod/troubleshooting-app-79c8b7545d-96kds   1/1     Running   0          33s
pod/troubleshooting-app-79c8b7545d-qcw6j   1/1     Running   0          33s

NAME                                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/troubleshooting-app   2/2     2            2           33s

NAME                                             DESIRED   CURRENT   READY   AGE
replicaset.apps/troubleshooting-app-79c8b7545d   2         2         2       33s

$ kubectl get events -n s14 --field-selector type=Warning --sort-by=.lastTimestamp
...                                                                        <- older Warnings from the Task 2 scenarios in the same namespace
26s         Warning   Failed   pod/project-broken-pod   Error: ImagePullBackOff
10s         Warning   Failed   pod/project-broken-pod   Error: ErrImagePull
10s         Warning   Failed   pod/project-broken-pod   Failed to pull image "nginx:this-tag-does-not-exist": ... not found
```

The only Warnings produced by this project are the three image-pull events of `project-broken-pod`; the whole run (deploy, two breaks, two fixes) took about 35 seconds of cluster time. Clean-up afterwards:

```text
$ kubectl delete -f deployment.yaml -f service.yaml -f client-pod.yaml -f fixed-pod.yaml
deployment.apps "troubleshooting-app" deleted from s14 namespace
service "troubleshooting-service" deleted from s14 namespace
pod "client" deleted from s14 namespace
pod "project-broken-pod" deleted from s14 namespace
```

## 10. Final troubleshooting checklist

Before saying "it is not working" I run, in this order:

```bash
kubectl get pods -n s14
kubectl describe pod <pod> -n s14
kubectl logs <pod> -n s14
kubectl exec -it <pod> -n s14 -- sh
kubectl get events -n s14 --sort-by=.lastTimestamp
# Service problems
kubectl describe service <svc> -n s14
kubectl get endpoints <svc> -n s14
kubectl exec client -n s14 -- nslookup <svc>
```

## 11. Troubleshooting table

| Problem | What I saw | Command I used | Root cause | Fix |
|---|---|---|---|---|
| **Broken Pod** | `0/1 ImagePullBackOff`, phase `Pending`, no logs | `kubectl get pod`, `kubectl describe pod` (Events) | Image tag `this-tag-does-not-exist` not in registry | Apply `fixed-pod.yaml` with `nginx:alpine` |
| **Service Problem** | DNS resolves, `Connection refused`, `Endpoints: <none>` | `kubectl get endpoints`, `kubectl describe service`, `kubectl get pods --show-labels` | Selector `app=wrong-app` != label `app=troubleshooting-app` | Re-apply `service.yaml` with the right selector |
| **Image Problem** | Events: `Failed to pull image ... not found`, then `BackOff` | `kubectl describe pod`, `kubectl get events --field-selector type=Warning` | Registry has no such tag (typo / never pushed) | Correct tag; for private images add `imagePullSecrets` |

## 12. README questions

1. **What does `kubectl get` tell us?** The current state of resources in one line each: name, READY count, STATUS/phase, RESTARTS, AGE (and IP/node with `-o wide`). It tells me *that* something is wrong, not *why*.
2. **Difference between `get` and `describe`?** `get` is a summary table for many objects; `describe` is the full story of one object: spec, container states with exit codes, conditions, volumes and the Events. I use `get` to find the sick object and `describe` to diagnose it.
3. **Why do we use `kubectl logs`?** To read what the application wrote to stdout/stderr. For a crashing app the logs (especially `--previous`) usually contain the real error message.
4. **When would you use `kubectl exec`?** When the container is running and I need to check from the inside: is the process listening (`netstat`), does `localhost` answer, what does `/etc/resolv.conf` say, can it reach another Service (`wget`, `nslookup`).
5. **What does `CrashLoopBackOff` mean?** The container starts, exits with an error, kubelet restarts it, and after repeated failures waits with an increasing back-off between restarts. It is a symptom; the cause is in the logs/exit code.
6. **What does `ImagePullBackOff` mean?** kubelet could not pull the image (wrong name/tag, no credentials, registry unreachable) and is now backing off between retries. The container never started, so only Events help.
7. **Why can a Pod remain `Pending`?** The scheduler found no suitable node: not enough CPU/memory, a nodeSelector/affinity nobody matches, untolerated taints, a missing or unbound PVC, or no Ready nodes at all. `describe` shows `FailedScheduling` with the exact reason.
8. **Why can a Service have no endpoints?** Its selector matches no Pod labels, or the matching Pods are not Ready (failing readiness probe), or the Pods are in another namespace.
9. **Relationship between a Service selector and Pod labels?** The Service continuously selects Pods whose labels contain all the key/value pairs of its selector and writes their IPs into the Endpoints/EndpointSlice objects. Labels and selector must match exactly or no traffic is routed.
10. **What is Kubernetes DNS?** CoreDNS, running in `kube-system` behind the `kube-dns` Service (`10.43.0.10` on this cluster), gives every Service a name `<svc>.<ns>.svc.cluster.local` (and Pods a name too). Each Pod's `/etc/resolv.conf` points to it with search domains so that a short name works inside the same namespace.

## 13. Final architecture

```text
                       namespace s14
                            │
                            ▼
              ┌───────────────────────────┐
              │  troubleshooting-service  │  ClusterIP 10.43.92.5:80
              └─────────────┬─────────────┘
                            │ selector app=troubleshooting-app
              ┌─────────────┴─────────────┐
              ▼                           ▼
   troubleshooting-app-...-96kds   troubleshooting-app-...-qcw6j
        10.42.0.120:80                  10.42.0.119:80
              │                           │
              └──────── nginx:alpine ─────┘

   client (busybox) ── nslookup / wget ──► troubleshooting-service
```

## 14. What I can now do

`kubectl get`, `describe`, `logs`, `exec`, `events`, and troubleshoot `CrashLoopBackOff`, `ImagePullBackOff`, `Pending`, Service and DNS problems by following GET → DESCRIBE → EVENTS → LOGS → EXEC → TEST → FIX → VERIFY instead of guessing.

## Screenshots

| Screenshot requested | Stands in for it |
|---|---|
| Healthy deployment | Section 1 and 2 outputs (`get pods -o wide`, `describe`, `exec wget`) |
| Service with endpoints | Section 3 / 4 outputs |
| Broken Pod | Section 5 / 6 outputs (`ImagePullBackOff` + Events) |
| Fixed Pod | Section 7 "after" output |
| Service with `<none>` endpoints | Section 8 output |
| Fixed Service | Section 9 "after" output |

## Deliverables

* `deployment.yaml`, `service.yaml`, `client-pod.yaml` – the application and a test client.
* `broken-pod.yaml` / `fixed-pod.yaml` – image problem and fix.
* `broken-service.yaml` – selector problem (fix = `service.yaml`).
* `run.sh` – reproduces every step and prints each command and output.
* `README.md` – problem statement, investigation steps, root causes, solutions, captured before/after output, answers.
