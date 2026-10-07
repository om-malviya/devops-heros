# Probes – liveness, readiness, startup

Student: Om Malviya | Enrollment No: 24BCS10448

A Pod can be `Running` while the application inside is broken. Probes let the kubelet ask the app
three questions. Examples adapted from the course (`nginx:alpine`, namespace `s13`).

| Probe | Question | On failure | File |
| --- | --- | --- | --- |
| **startupProbe** | "Have you finished starting?" | container restarted after `failureThreshold`; liveness/readiness are paused until it succeeds once | `startup.yaml` |
| **readinessProbe** | "Can you take traffic?" | Pod marked `NotReady`, removed from Service endpoints; **no restart** | `readiness.yaml` |
| **livenessProbe** | "Are you still alive?" | container restarted (`RESTARTS` increments) | `liveness.yaml` |

Probe mechanisms: `httpGet` (2xx/3xx = success), `tcpSocket`, `exec` (exit 0 = success), `grpc`.
Tuning fields: `initialDelaySeconds`, `periodSeconds`, `timeoutSeconds`, `failureThreshold`, `successThreshold`.

## Apply and inspect

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f liveness.yaml -f readiness.yaml -f startup.yaml
kubectl get pods -n s13 -l '!app' -o wide
kubectl describe pod startup-demo -n s13 | grep -E 'Liveness|Readiness|Startup'
```

Output (captured 2026-10-07; the volume demo pods from `../01-kubernetes-volumes` were still running
in the same namespace and have no `app` label either, so they show up in the list):

```text
pod/liveness-demo created
pod/readiness-demo created
service/readiness-service created
pod/startup-demo created
NAME               READY   STATUS    RESTARTS   AGE     IP            NODE     NOMINATED NODE   READINESS GATES
dynamic-pvc-demo   1/1     Running   0          3m50s   10.42.0.84    colima   <none>           <none>
emptydir-demo      2/2     Running   0          5m8s    10.42.0.71    colima   <none>           <none>
hostpath-demo      1/1     Running   0          4m31s   10.42.0.76    colima   <none>           <none>
liveness-demo      1/1     Running   0          8s      10.42.0.101   colima   <none>           <none>
startup-demo       1/1     Running   0          8s      10.42.0.103   colima   <none>           <none>
    Liveness:       http-get http://:80/ delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=3
    Readiness:      http-get http://:80/ delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=3
    Startup:        http-get http://:80/ delay=0s timeout=1s period=2s successThreshold=1 failureThreshold=30
```

`startup-demo` became `Ready` within the first 2-second startup-probe period because nginx starts
instantly; the point of the probe is the 60 s budget it *would* have given a slow application.

`readiness-demo` has label `app=readiness-demo`, so check it with its Service:

```bash
kubectl get pod readiness-demo -n s13
kubectl get endpoints readiness-service -n s13
```

Output (captured 2026-10-07):

```text
NAME             READY   STATUS    RESTARTS   AGE
readiness-demo   1/1     Running   0          8s
NAME                ENDPOINTS        AGE
readiness-service   10.42.0.102:80   8s
```

## Break readiness (no restart, traffic removed)

```bash
sed 's|path: / .*|path: /wrong-path|' readiness.yaml | kubectl replace --force -f -
sleep 20
kubectl get pod readiness-demo -n s13
kubectl get endpoints readiness-service -n s13
kubectl describe pod readiness-demo -n s13 | tail -3
```

Output (captured 2026-10-08):

```text
pod "readiness-demo" deleted from s13 namespace
service "readiness-service" deleted from s13 namespace
pod/readiness-demo replaced
service/readiness-service replaced
NAME             READY   STATUS    RESTARTS   AGE
readiness-demo   0/1     Running   0          26s
NAME                ENDPOINTS   AGE
readiness-service               26s
  Normal   Created    25s               kubelet            spec.containers{nginx}: Container created
  Normal   Started    25s               kubelet            spec.containers{nginx}: Container started
  Warning  Unhealthy  2s (x4 over 17s)  kubelet            spec.containers{nginx}: Readiness probe failed: HTTP probe failed with statuscode: 404
```

I observed `STATUS Running` but `READY 0/1`, `RESTARTS` still 0, and the Service's ENDPOINTS column
is empty: the Pod is quarantined, not killed. (The Service was recreated too because it is in the
same file; its endpoints would have gone empty either way.)

## Break liveness (restart loop)

```bash
sed 's|path: / .*|path: /wrong-path|' liveness.yaml | kubectl replace --force -f -
kubectl get pod liveness-demo -n s13 -w
```

Output (captured 2026-10-08, watch over 75 s; one restart every ~20 s = 5 s initial delay + 3 failures x 5 s):

```text
pod "liveness-demo" deleted from s13 namespace
pod/liveness-demo replaced
NAME            READY   STATUS              RESTARTS   AGE
liveness-demo   0/1     ContainerCreating   0          0s
liveness-demo   1/1     Running             0          2s
liveness-demo   1/1     Running             1 (1s ago)   21s
liveness-demo   1/1     Running             2 (1s ago)   41s
liveness-demo   1/1     Running             3 (2s ago)   62s
```

```bash
kubectl get events -n s13 --field-selector involvedObject.name=liveness-demo --sort-by=.lastTimestamp | tail -3
```

Output (captured 2026-10-08):

```text
14s         Normal    Created     pod/liveness-demo   Container created
14s         Normal    Started     pod/liveness-demo   Container started
5s          Warning   Unhealthy   pod/liveness-demo   Liveness probe failed: HTTP probe failed with statuscode: 404
```

(The `Killing ... will be restarted` event is also there, a few lines higher; `tail -3` only shows the
last restart cycle.) The pod keeps going `Running` -> killed -> `Running`; after enough restarts the
kubelet starts backing off and the STATUS becomes `CrashLoopBackOff` between attempts.

Probe fields on a Pod are immutable, which is why `replace --force` (delete + recreate) is used instead
of `apply`. I restored both afterwards:

```bash
kubectl replace --force -f readiness.yaml -f liveness.yaml
kubectl get pod liveness-demo readiness-demo startup-demo -n s13
kubectl get endpoints readiness-service -n s13
```

Output (captured 2026-10-08):

```text
pod "readiness-demo" deleted from s13 namespace
service "readiness-service" deleted from s13 namespace
pod "liveness-demo" deleted from s13 namespace
pod/readiness-demo replaced
service/readiness-service replaced
pod/liveness-demo replaced
NAME             READY   STATUS    RESTARTS   AGE
liveness-demo    1/1     Running   0          7s
readiness-demo   1/1     Running   0          7s
startup-demo     1/1     Running   0          3h42m
NAME                ENDPOINTS        AGE
readiness-service   10.42.0.147:80   7s
```

## Why the startup probe exists

With `failureThreshold: 30` x `periodSeconds: 2`, `startup-demo` may take up to 60 s to answer before
it is restarted, and during that time the 5-second liveness probe is not running. Without it, a slow
JVM or a database doing recovery would be killed by liveness before it ever became healthy.

## Cleanup

```bash
kubectl delete -f liveness.yaml -f readiness.yaml -f startup.yaml
```

## Deliverables

- `liveness.yaml`, `readiness.yaml`, `startup.yaml` – probe examples.
- This README – what each probe asks, what happens on failure, break-and-observe experiments.
