# Scenario 4: Readiness probe on a wrong path -> pod never Ready

Prerequisite: the healthy stack from `kubernetes/` (or the Helm chart) is deployed in namespace `taskboard`.

On the k3s cluster used for the captured output the images come from a local registry and the Ingress class is Traefik, so every apply below was piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#' <file> | kubectl apply -f -`.

```bash
kubectl apply -f troubleshooting/04-readiness-probe-wrong-path/broken.yaml
```

## 1. Identify the issue

Pod is `Running` but stays `0/1 READY` forever, the Deployment rollout never completes, Service has no endpoints, ingress returns 503. Logs show the app started fine.

## 2. Investigate logs and resources

```bash
kubectl -n taskboard get pods -l app=taskboard-backend
kubectl -n taskboard describe pod -l app=taskboard-backend | grep -A2 "Readiness\|Unhealthy"
kubectl -n taskboard logs deploy/taskboard-backend --tail=5
kubectl -n taskboard port-forward deploy/taskboard-backend 8000:8000 & curl -s -o /dev/null -w "%{http_code}\n" localhost:8000/readyz; curl -s localhost:8000/ready
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get pods -l app=taskboard-backend            # 60 s after the apply
NAME                                 READY   STATUS    RESTARTS   AGE
taskboard-backend-5bf4674575-tkbqb   0/1     Running   0          60s
taskboard-backend-5bf4674575-w754f   0/1     Running   0          53s
taskboard-backend-6db658b5f-bw4kk    1/1     Running   4          10m     <- old pod, still the only endpoint
$ kubectl -n taskboard describe pod -l app=taskboard-backend | grep -E 'Readiness:' | sort | uniq -c
   2     Readiness:  http-get http://:http/readyz delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
   1     Readiness:  http-get http://:http/ready delay=0s timeout=1s period=10s successThreshold=1 failureThreshold=3
$ kubectl -n taskboard logs -l app=taskboard-backend --tail=200 | grep readyz | tail -2
INFO:     10.42.0.1:59744 - "GET /readyz HTTP/1.1" 404 Not Found
INFO:     10.42.0.1:37596 - "GET /readyz HTTP/1.1" 404 Not Found
$ kubectl -n taskboard get endpoints taskboard-backend
NAME                ENDPOINTS          AGE
taskboard-backend   10.42.0.189:8000   10m
```

## 3. Root cause

The application exposes `/ready` but the probe asks for `/readyz`, so every probe gets a 404 and the kubelet never marks the container Ready. Kubernetes deliberately keeps a not-ready pod out of the Service endpoints, which is correct behaviour - the probe definition is what is wrong.

## 4. Fix

```bash
kubectl apply -f fixed.yaml      # readinessProbe.httpGet.path: /ready
```

## 5. Verify

```bash
kubectl -n taskboard rollout status deployment/taskboard-backend
kubectl -n taskboard get pods -l app=taskboard-backend
kubectl -n taskboard get endpoints taskboard-backend
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard rollout status deployment/taskboard-backend --timeout=180s
deployment "taskboard-backend" successfully rolled out
$ kubectl -n taskboard get pods -l app=taskboard-backend
NAME                                 READY   STATUS        RESTARTS   AGE
taskboard-backend-5bf4674575-tkbqb   0/1     Terminating   0          76s
taskboard-backend-5bf4674575-w754f   0/1     Terminating   0          69s
taskboard-backend-6db658b5f-5bvsw    1/1     Running       0          9s
taskboard-backend-6db658b5f-bw4kk    1/1     Running       4          11m
$ kubectl -n taskboard get endpoints taskboard-backend
NAME                ENDPOINTS                          AGE
taskboard-backend   10.42.0.189:8000,10.42.0.39:8000   11m
```

## 6. Document

| | |
|---|---|
| Symptom | Pod is `Running` but stays `0/1 READY` forever, the Deployment rollout never completes, Service has no endpoints, ingress returns 503. |
| Root cause | The application exposes `/ready` but the probe asks for `/readyz`, so every probe gets a 404 and the kubelet never marks the container Ready. |
| Fix | `kubectl apply -f fixed.yaml` (see diff below) |
| Lesson | `Running` is not `Ready`. A 404 on a probe path is a configuration bug, not an outage of the app - compare the probe path in `describe pod` with the routes in the code (`/docs`). |

```bash
diff troubleshooting/04-readiness-probe-wrong-path/broken.yaml troubleshooting/04-readiness-probe-wrong-path/fixed.yaml
```
