# Scenario 3: Wrong Secret key for DATABASE_URL -> CrashLoopBackOff

Prerequisite: the healthy stack from `kubernetes/` (or the Helm chart) is deployed in namespace `taskboard`.

On the k3s cluster used for the captured output the images come from a local registry and the Ingress class is Traefik, so every apply below was piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#' <file> | kubectl apply -f -`.

```bash
kubectl apply -f troubleshooting/03-wrong-secret-key/broken.yaml
```

## 1. Identify the issue

The backend pod flips between `CreateContainerConfigError` (if the key is missing) or `CrashLoopBackOff` (if the value is wrong); `READY 0/1`, `RESTARTS` climbing.

## 2. Investigate logs and resources

```bash
kubectl -n taskboard get pods -l app=taskboard-backend
kubectl -n taskboard describe pod -l app=taskboard-backend | grep -A3 -i "warning\|error"
kubectl -n taskboard get secret taskboard-secrets -o jsonpath='{.data}' | python3 -c 'import sys,json;print(list(json.load(sys.stdin)))'
kubectl -n taskboard logs deploy/taskboard-backend --previous --tail=20
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get pods -l app=taskboard-backend
NAME                                 READY   STATUS                       RESTARTS   AGE
taskboard-backend-6db658b5f-bw4kk    1/1     Running                      4          9m33s   <- old pod still serving (maxUnavailable: 0)
taskboard-backend-8444b74d4d-m59kk   0/1     CreateContainerConfigError   0          30s
taskboard-backend-8444b74d4d-r9ttx   0/1     CreateContainerConfigError   0          18s
$ kubectl -n taskboard get events --field-selector reason=Failed --sort-by=.lastTimestamp | grep -i secret | tail -2
3s   Warning   Failed   pod/taskboard-backend-8444b74d4d-r9ttx   Error: couldn't find key DB_URL in Secret taskboard/taskboard-secrets
2s   Warning   Failed   pod/taskboard-backend-8444b74d4d-m59kk   Error: couldn't find key DB_URL in Secret taskboard/taskboard-secrets
$ kubectl -n taskboard get secret taskboard-secrets -o jsonpath='{.data}' | python3 -c 'import sys,json;print(sorted(json.load(sys.stdin)))'
['DATABASE_URL', 'POSTGRES_PASSWORD', 'POSTGRES_USER']

# the wrong-*value* variant (CrashLoopBackOff) was observed for free on the first deploy, when the backend
# started before Postgres accepted connections (kubectl logs --previous):
sqlalchemy.exc.OperationalError: (psycopg.OperationalError) connection failed: connection to server at "10.43.112.131", port 5432 failed: Connection refused
```

## 3. Root cause

The container asks for `secretKeyRef.key: DB_URL` but the Secret only has `DATABASE_URL`. The kubelet cannot build the container environment, so the container never starts (`CreateContainerConfigError`). With a wrong value instead of a wrong key the container starts, `alembic upgrade head` cannot connect, the process exits non-zero and Kubernetes restarts it with back-off (`CrashLoopBackOff`).

## 4. Fix

```bash
kubectl apply -f fixed.yaml      # secretKeyRef.key: DATABASE_URL
```
If the *value* is wrong, fix the Secret and restart the pods so they pick it up:
```bash
kubectl -n taskboard create secret generic taskboard-secrets --from-literal=DATABASE_URL='postgresql+psycopg://taskboard:<pw>@taskboard-postgres:5432/taskboard' \
  --from-literal=POSTGRES_USER=taskboard --from-literal=POSTGRES_PASSWORD='<pw>' --dry-run=client -o yaml | kubectl apply -f -
kubectl -n taskboard rollout restart deployment/taskboard-backend
```

## 5. Verify

```bash
kubectl -n taskboard get pods -l app=taskboard-backend
kubectl -n taskboard logs deploy/taskboard-backend --tail=5
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard rollout status deployment/taskboard-backend --timeout=180s
deployment "taskboard-backend" successfully rolled out
$ kubectl -n taskboard get pods -l app=taskboard-backend
NAME                                READY   STATUS    RESTARTS   AGE
taskboard-backend-6db658b5f-bw4kk   1/1     Running   4          9m53s
taskboard-backend-6db658b5f-fwwnp   1/1     Running   0          8s
$ kubectl -n taskboard logs deploy/taskboard-backend --tail=3
INFO:     10.42.0.1:34184 - "GET /ready HTTP/1.1" 200 OK
INFO:     10.42.0.1:34186 - "GET /health HTTP/1.1" 200 OK
INFO:     10.42.0.1:44750 - "GET /ready HTTP/1.1" 200 OK
```

## 6. Document

| | |
|---|---|
| Symptom | The backend pod flips between `CreateContainerConfigError` (if the key is missing) or `CrashLoopBackOff` (if the value is wrong); `READY 0/1`, `RESTARTS` climbing. |
| Root cause | The container asks for `secretKeyRef. |
| Fix | `kubectl apply -f fixed.yaml` (see diff below) |
| Lesson | `describe pod` events tell you *why* a container did not start; `logs --previous` tells you why it *crashed*. Check both before touching code. |

```bash
diff troubleshooting/03-wrong-secret-key/broken.yaml troubleshooting/03-wrong-secret-key/fixed.yaml
```
