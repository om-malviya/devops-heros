# Scenario 6: Ingress points to the wrong Service port -> 502/503 on /api

Prerequisite: the healthy stack from `kubernetes/` (or the Helm chart) is deployed in namespace `taskboard`.

On the k3s cluster used for the captured output the images come from a local registry and the Ingress class is Traefik, so every apply below was piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#' <file> | kubectl apply -f -`.

```bash
kubectl apply -f troubleshooting/06-ingress-wrong-backend-port/broken.yaml
```

## 1. Identify the issue

`http://taskboard.local/` loads the UI but it shows 'Backend unavailable'; `curl http://taskboard.local/api/tasks` returns `503 Service Temporarily Unavailable` (or `502 Bad Gateway`) from nginx while the backend pods are healthy.

## 2. Investigate logs and resources

```bash
curl -si http://taskboard.local/api/tasks | head -3
kubectl -n taskboard describe ingress taskboard
kubectl -n taskboard get svc taskboard-backend
kubectl -n ingress-nginx logs deploy/ingress-nginx-controller --tail=5 | grep -i "api\|error"
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard describe ingress taskboard | sed -n '/^Rules/,/^Annotations/p'
Rules:
  Host             Path  Backends
  ----             ----  --------
  taskboard.local
                   /api   taskboard-backend:8080 ()
                   /      taskboard-frontend:80 (10.42.0.190:8080,10.42.0.193:8080)
$ kubectl -n taskboard get svc taskboard-backend
NAME                TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)    AGE
taskboard-backend   ClusterIP   10.43.253.57   <none>        8000/TCP   14m
$ kubectl -n kube-system logs deploy/traefik --tail=200 | grep -i taskboard | tail -1      # Traefik on k3s instead of ingress-nginx
2026-10-07T21:21:48Z ERR Cannot create service error="service port not found" ingress=taskboard namespace=taskboard providerName=kubernetes
$ curl -si -H 'Host: taskboard.local' http://localhost/api/tasks | head -1
HTTP/1.1 200 OK        <- see note below: Traefik dropped the /api router and the request fell through to the frontend
```

Note on the captured run: with Traefik the browser symptom is *masked*. Traefik refuses to build the `/api` router (`service port not found`) and the request falls through to the `/` rule, where the frontend's own nginx `/api/` proxy still reaches the backend Service on 8000 - hence the `200 OK`. With ingress-nginx the same fault answers `503 Service Temporarily Unavailable`. The reliable evidence is `describe ingress` (empty endpoints next to the path) and the controller log, not the HTTP status.

## 3. Root cause

The Ingress backend references Service port `8080`, but the backend Service only defines port `8000`. The ingress controller resolves backends by Service port -> endpoints; for a port that does not exist it finds no endpoints and answers 503 itself (502 when it reaches a pod on a closed port). This was a real bug in the reference Helm chart (`port: 8080` in `ingress.yaml` while the Service used 8000) that I fixed in `helm/taskboard/templates/ingress.yaml` by templating both from `.Values.backend.port`.

## 4. Fix

```bash
kubectl apply -f fixed.yaml      # /api -> taskboard-backend:8000
```

## 5. Verify

```bash
kubectl -n taskboard describe ingress taskboard | sed -n '/Rules/,/Annotations/p'
curl -s http://taskboard.local/api/tasks/stats
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard describe ingress taskboard | sed -n '/^Rules/,/^Annotations/p'
                   /api   taskboard-backend:8000 (10.42.0.45:8000,10.42.0.46:8000)
                   /      taskboard-frontend:80 (10.42.0.190:8080,10.42.0.193:8080)
$ curl -s -H 'Host: taskboard.local' http://localhost/api/tasks/stats
{"total":1,"todo":1,"inProgress":0,"done":0}
```

## 6. Document

| | |
|---|---|
| Symptom | `describe ingress` shows `taskboard-backend:8080 ()` with no endpoints for `/api`; ingress-nginx answers 503, Traefik logs `service port not found`. |
| Root cause | The Ingress backend references Service port `8080`, but the backend Service only defines port `8000`. |
| Fix | `kubectl apply -f fixed.yaml` (see diff below) |
| Lesson | Follow the chain Ingress -> Service port -> targetPort -> containerPort; `describe ingress` prints the resolved endpoints next to each path, so the broken hop is visible immediately. |

```bash
diff troubleshooting/06-ingress-wrong-backend-port/broken.yaml troubleshooting/06-ingress-wrong-backend-port/fixed.yaml
```
