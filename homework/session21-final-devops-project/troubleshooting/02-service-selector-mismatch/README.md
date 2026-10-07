# Scenario 2: Service selector mismatch -> no endpoints

Prerequisite: the healthy stack from `kubernetes/` (or the Helm chart) is deployed in namespace `taskboard`.

On the k3s cluster used for the captured output the images come from a local registry and the Ingress class is Traefik, so every apply below was piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#' <file> | kubectl apply -f -`.

```bash
kubectl apply -f troubleshooting/02-service-selector-mismatch/broken.yaml
```

## 1. Identify the issue

Pods are `Running` and `1/1 Ready`, but `curl http://taskboard.local/api/tasks` returns `503 Service Temporarily Unavailable` from the ingress and the frontend nginx logs `connect() failed ... upstream`.

## 2. Investigate logs and resources

```bash
kubectl -n taskboard get svc taskboard-backend -o wide
kubectl -n taskboard get endpoints taskboard-backend
kubectl -n taskboard get pods --show-labels -l app=taskboard-backend
kubectl -n taskboard get svc taskboard-backend -o jsonpath='{.spec.selector}'; echo
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get svc taskboard-backend -o wide
NAME                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE     SELECTOR
taskboard-backend   ClusterIP   10.43.253.57   <none>        8000/TCP   5m59s   app=taskboard-api
$ kubectl -n taskboard get endpoints taskboard-backend
NAME                ENDPOINTS   AGE
taskboard-backend   <none>      5m59s
$ kubectl -n taskboard get pods --show-labels -l app=taskboard-backend
NAME                                READY   STATUS    RESTARTS   AGE     LABELS
taskboard-backend-6db658b5f-bw4kk   1/1     Running   4          5m57s   app=taskboard-backend,pod-template-hash=6db658b5f
$ kubectl -n taskboard get svc taskboard-backend -o jsonpath='{.spec.selector}'; echo
{"app":"taskboard-api"}
$ curl -si -H 'Host: taskboard.local' http://localhost/api/tasks/stats | head -1
HTTP/1.1 503 Service Unavailable
```

## 3. Root cause

A Service only forwards to Pods whose labels match its `spec.selector`. The selector says `app=taskboard-api` but the Pods carry `app=taskboard-backend`, so the Endpoints object is empty and every connection to the ClusterIP is refused. The ingress turns that into a 503.

## 4. Fix

```bash
kubectl -n taskboard patch svc taskboard-backend -p '{"spec":{"selector":{"app":"taskboard-backend"}}}'
# or
kubectl apply -f fixed.yaml
```

## 5. Verify

```bash
kubectl -n taskboard get endpoints taskboard-backend
kubectl -n taskboard run curl --rm -it --image=curlimages/curl --restart=Never -- curl -s http://taskboard-backend:8000/health
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get endpoints taskboard-backend
NAME                ENDPOINTS          AGE
taskboard-backend   10.42.0.189:8000   6m4s
$ kubectl -n taskboard run curl --rm -i --image=curlimages/curl --restart=Never -- curl -s http://taskboard-backend:8000/health
{"status":"UP"}
$ curl -s -H 'Host: taskboard.local' http://localhost/api/tasks/stats
{"total":1,"todo":1,"inProgress":0,"done":0}
```

Side effect I ran into: the first version of `fixed.yaml` had no `metadata.labels`, and `kubectl apply` pruned the `app` label from the live Service, which later broke the Prometheus ServiceMonitor selector. `fixed.yaml` is now identical to `kubernetes/06-backend-service.yaml`.

## 6. Document

| | |
|---|---|
| Symptom | Pods are `Running` and `1/1 Ready`, but `curl http://taskboard.local/api/...` returns 503 from the ingress controller. |
| Root cause | The Service selector (`app=taskboard-api`) does not match the pod labels (`app=taskboard-backend`), so the Endpoints object is empty. |
| Fix | `kubectl apply -f fixed.yaml` (see diff below) |
| Lesson | `kubectl get endpoints` is the fastest way to tell a networking problem from an application problem: empty endpoints = selector/label or readiness issue, never a code bug. |

```bash
diff troubleshooting/02-service-selector-mismatch/broken.yaml troubleshooting/02-service-selector-mismatch/fixed.yaml
```
