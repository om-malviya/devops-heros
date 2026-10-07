# Task 5 – Troubleshooting

Student: Om Malviya | Enrollment No: 24BCS10448

I built three deliberately broken manifests, each reproducing a mistake that the course's
`troubleshooting/` material and the lab warn about, and worked through them with the same loop every
time: **identify the symptom -> run troubleshooting commands -> find the root cause -> fix -> compare
before/after**.

| # | File (broken -> fixed) | Mistake | Symptom |
| --- | --- | --- | --- |
| 1 | `broken-01-secret-key-mismatch.yaml` -> `fixed-01-...` | `secretKeyRef.key: DB_PASS`, Secret has `DB_PASSWORD` | `CreateContainerConfigError` |
| 2 | `broken-02-configmap-missing.yaml` -> `fixed-02-...` | `configMapRef.name: app-confg` (typo) | `CreateContainerConfigError` |
| 3 | `broken-03-ingress-wrong-backend.yaml` -> `fixed-03-...` | Ingress backend `app1-svc:8080`, real Service is `app1:80` | Ingress created, but curl `/app1` returns 404 |

Prerequisite: namespace `s12` and the Task 1/3 resources exist (`../deploy-all.sh`), because scenario 2
needs ConfigMap `app-config` and scenario 3 needs Services `app1`/`app2`.

Commands I used throughout:

```bash
kubectl get pods -n s12
kubectl describe pod <pod> -n s12
kubectl logs <pod> -n s12
kubectl get events -n s12 --sort-by=.lastTimestamp
kubectl get endpoints -n s12
kubectl describe ingress <ingress> -n s12
```

---

## Scenario 1 – Secret key name mismatch

### 1. Identify the problem

```bash
kubectl apply -f broken-01-secret-key-mismatch.yaml
kubectl get pods -n s12 -l scenario=1
```

Before (Output, captured 2026-10-07):

```text
secret/ts-db-secret created
pod/ts-secret-pod created
NAME            READY   STATUS                       RESTARTS   AGE
ts-secret-pod   0/1     CreateContainerConfigError   0          1s
```

The container never starts. `CreateContainerConfigError` means the kubelet could not build the
container's configuration (env vars / volumes), so this is not an application bug.

### 2. Run troubleshooting commands

```bash
kubectl describe pod ts-secret-pod -n s12 | sed -n '/^Events/,$p'
```

Output (captured 2026-10-07):

```text
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  12s                default-scheduler  Successfully assigned s12/ts-secret-pod to colima
  Normal   Pulled     12s (x2 over 12s)  kubelet            spec.containers{app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Warning  Failed     12s (x2 over 12s)  kubelet            spec.containers{app}: Error: couldn't find key DB_PASS in Secret s12/ts-db-secret
```

```bash
kubectl get events -n s12 --sort-by=.lastTimestamp | tail -3
kubectl logs ts-secret-pod -n s12
```

Output (captured 2026-10-07; scenario 2 was applied at the same time, so its event is visible too):

```text
12s         Warning   Failed              pod/ts-configmap-pod         Error: configmap "app-confg" not found
12s         Normal    Pulled              pod/ts-secret-pod            Container image "busybox:1.36" already present on machine and can be accessed by the pod
12s         Warning   Failed              pod/ts-secret-pod            Error: couldn't find key DB_PASS in Secret s12/ts-db-secret
Error from server (BadRequest): container "app" in pod "ts-secret-pod" is waiting to start: CreateContainerConfigError
```

There are no logs because the container never ran; the events hold the real message.

### 3. Root cause

Compare what the Pod asks for with what the Secret contains:

```bash
kubectl get secret ts-db-secret -n s12 -o jsonpath='{.data}' ; echo
kubectl get pod ts-secret-pod -n s12 -o jsonpath='{.spec.containers[0].env[*].valueFrom.secretKeyRef.key}' ; echo
```

Output (captured 2026-10-07):

```text
{"DB_PASSWORD":"ZmFrZS1wYXNzd29yZC0xMjM=","DB_USER":"ZGVtb191c2Vy"}
DB_USER DB_PASS
```

The Secret has `DB_PASSWORD`, the Pod references `DB_PASS`. Key names are case- and
spelling-sensitive and are validated by the kubelet at container-creation time, not by `kubectl apply`.

### 4. Fix

```bash
diff broken-01-secret-key-mismatch.yaml fixed-01-secret-key-mismatch.yaml
kubectl apply -f fixed-01-secret-key-mismatch.yaml          # first attempt: rejected for the Pod
kubectl replace --force -f fixed-01-secret-key-mismatch.yaml
```

Output (captured 2026-10-07):

```text
1,2c1
< # SCENARIO 1 (BROKEN): the Pod asks for Secret key "DB_PASS", but the Secret only has "DB_PASSWORD".
< # Symptom: Pod stuck in CreateContainerConfigError.
---
> # SCENARIO 1 (FIXED): secretKeyRef.key now matches the key that really exists in the Secret.
35c34
<               key: DB_PASS        # <-- BUG: key does not exist in the Secret
---
>               key: DB_PASSWORD    # FIX: correct key name
secret/ts-db-secret configured
The Pod "ts-secret-pod" is invalid: spec: Forbidden: pod updates may not change fields other than `spec.containers[*].image`,`spec.initContainers[*].image`,`spec.activeDeadlineSeconds`,`spec.tolerations` (only additions to existing tolerations),`spec.terminationGracePeriodSeconds` (allow it to be set to 1 if it was previously negative)
@@ -127,7 +127,7 @@
       "ConfigMapKeyRef": null,
       "SecretKeyRef": {
        "Name": "ts-db-secret",
-       "Key": "DB_PASS",
+       "Key": "DB_PASSWORD",
        "Optional": null
       },
       "FileKeyRef": null

secret "ts-db-secret" deleted from s12 namespace
pod "ts-secret-pod" deleted from s12 namespace
secret/ts-db-secret replaced
pod/ts-secret-pod replaced
```

I tried a plain `kubectl apply` first on purpose: the Secret part was accepted (`configured`) but the
Pod was rejected because a Pod's `env` list is immutable. `replace --force` (delete + create) is the
way out for a bare Pod; for a Deployment, `kubectl apply` would simply roll out new Pods.

### 5. After

```bash
kubectl get pods -n s12 -l scenario=1
kubectl logs ts-secret-pod -n s12
```

Output (captured 2026-10-07):

```text
NAME            READY   STATUS    RESTARTS   AGE
ts-secret-pod   1/1     Running   0          1s
user=demo_user pass_len=17
```

---

## Scenario 2 – ConfigMap does not exist

### 1. Identify the problem

```bash
kubectl apply -f broken-02-configmap-missing.yaml
kubectl get pods -n s12 -l scenario=2
```

Before (Output, captured 2026-10-07):

```text
pod/ts-configmap-pod created
NAME               READY   STATUS                       RESTARTS   AGE
ts-configmap-pod   0/1     CreateContainerConfigError   0          2s
```

### 2. Run troubleshooting commands

```bash
kubectl describe pod ts-configmap-pod -n s12 | sed -n '/^Events/,$p'
kubectl get events -n s12 --field-selector involvedObject.name=ts-configmap-pod --sort-by=.lastTimestamp
```

Output (captured 2026-10-07):

```text
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  14s                default-scheduler  Successfully assigned s12/ts-configmap-pod to colima
  Normal   Pulled     14s (x2 over 14s)  kubelet            spec.containers{app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Warning  Failed     14s (x2 over 14s)  kubelet            spec.containers{app}: Error: configmap "app-confg" not found

LAST SEEN   TYPE      REASON      OBJECT                 MESSAGE
14s         Normal    Scheduled   pod/ts-configmap-pod   Successfully assigned s12/ts-configmap-pod to colima
14s         Normal    Pulled      pod/ts-configmap-pod   Container image "busybox:1.36" already present on machine and can be accessed by the pod
14s         Warning   Failed      pod/ts-configmap-pod   Error: configmap "app-confg" not found
```

### 3. Root cause

```bash
kubectl get configmap -n s12
```

Output (captured 2026-10-07):

```text
NAME               DATA   AGE
app-config         5      2m5s
kube-root-ca.crt   1      2m5s
```

The Pod references `app-confg`; the cluster has `app-config`. Same class of bug as scenario 1, one
level up: the whole object is missing instead of one key. The same symptom appears when the ConfigMap
lives in a different namespace (references never cross namespaces) or is applied after the Pod.

### 4. Fix

Three valid fixes; I chose the first:

1. correct the name in the Pod (`fixed-02-configmap-missing.yaml`);
2. create the missing ConfigMap with the name the Pod expects;
3. mark the reference `optional: true` if the app can run without it (the Pod then starts with no
   env vars, which hides the bug, so I would only do this for genuinely optional config).

```bash
kubectl replace --force -f fixed-02-configmap-missing.yaml
```

Output (captured 2026-10-07):

```text
pod "ts-configmap-pod" deleted from s12 namespace
pod/ts-configmap-pod replaced
```

### 5. After

```bash
kubectl get pods -n s12 -l scenario=2
kubectl logs ts-configmap-pod -n s12
```

Output (captured 2026-10-07):

```text
NAME               READY   STATUS    RESTARTS   AGE
ts-configmap-pod   1/1     Running   0          0s
APP_ENV=production LOG_LEVEL=DEBUG
```

(`LOG_LEVEL=DEBUG` rather than `INFO` because I had patched `app-config` in Task 1 Step 4 a few
minutes earlier; it is a nice proof that a freshly created container picks up the current ConfigMap.)

Side note: if the fix had been option 2 (creating the missing ConfigMap) the broken Pod would not need
to be touched at all; the kubelet retries `CreateContainerConfigError` pods automatically and starts
the container on the next sync once the ConfigMap exists.

---

## Scenario 3 – Ingress points to the wrong Service name and port

### 1. Identify the problem

```bash
kubectl apply -f broken-03-ingress-wrong-backend.yaml
kubectl get ingress -n s12 ts-ingress
INGRESS=http://localhost       # Colima forwards the VM's port 80; see ../03-ingress/README.md Step 4
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: ts.demo.local' $INGRESS/app1
curl -sS -H 'Host: ts.demo.local' $INGRESS/app1
curl -sS -H 'Host: ts.demo.local' $INGRESS/app2
```

Before (Output, captured 2026-10-08):

```text
ingress.networking.k8s.io/ts-ingress configured
NAME         CLASS     HOSTS           ADDRESS       PORTS   AGE
ts-ingress   traefik   ts.demo.local   192.168.5.1   80      3h44m
404
404 page not found
Hello from app2
```

(`configured`/`3h44m` because I re-applied the broken file for this capture after the scenario had
already been run once on 2026-10-07; the first run printed `created`.)

Important lesson: `kubectl apply` succeeded and the Ingress even got an ADDRESS. The API server does
**not** check that the backend Service exists. `/app2` works, `/app1` returns an error from the
controller. I had expected a `503` from Traefik, but this Traefik version simply does not create a
router for a rule whose Service it cannot resolve, so the request falls through to the plain-text
`404 page not found` that Traefik returns when nothing matches (ingress-nginx answers `503` or `404`
depending on version).

### 2. Run troubleshooting commands

```bash
kubectl describe ingress ts-ingress -n s12
```

Output (captured 2026-10-07):

```text
Name:             ts-ingress
Labels:           scenario=3
Namespace:        s12
Address:          192.168.5.1
Ingress Class:    traefik
Default backend:  <default>
Rules:
  Host           Path  Backends
  ----           ----  --------
  ts.demo.local
                 /app1   app1-svc:8080 (<error: services "app1-svc" not found>)
                 /app2   app2:80 (10.42.0.25:5678,10.42.0.24:5678)
Annotations:     <none>
Events:          <none>
```

`describe ingress` resolves each backend to endpoints; the `/app1` line shows the error inline while
`/app2` shows real pod IPs.

```bash
kubectl get svc,endpoints -n s12
kubectl logs -n kube-system deploy/traefik --tail=200 | grep ts-ingress | tail -2     # controller logs
```

Output (captured 2026-10-07; Traefik's colour codes removed):

```text
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/app1   ClusterIP   10.43.157.16   <none>        80/TCP    2m19s
service/app2   ClusterIP   10.43.36.136   <none>        80/TCP    2m18s

NAME             ENDPOINTS                         AGE
endpoints/app1   10.42.0.22:5678,10.42.0.23:5678   2m19s
endpoints/app2   10.42.0.24:5678,10.42.0.25:5678   2m18s

2026-10-07T17:13:39Z ERR Cannot create service error="service not found" ingress=ts-ingress namespace=s12 providerName=kubernetes serviceName=app1-svc servicePort=&ServiceBackendPort{Name:,Number:8080,}
2026-10-07T17:13:41Z ERR Cannot create service error="service not found" ingress=ts-ingress namespace=s12 providerName=kubernetes serviceName=app1-svc servicePort=&ServiceBackendPort{Name:,Number:8080,}
```

The controller log repeats the error on every resync (every couple of seconds), which is the clearest
"who is to blame" signal: the Ingress object is fine, the controller cannot build a route from it.

### 3. Root cause

Two mismatches between the Ingress backend and the real Service:

| Ingress says | Cluster has |
| --- | --- |
| `service.name: app1-svc` | Service `app1` |
| `service.port.number: 8080` | Service port `80` (targetPort 5678) |

Either one alone breaks the route. A wrong name gives `service not found`; a wrong port would give
`describe ingress` output like `app1:8080 (<error: endpoints "app1" not found>)` / `<none>` endpoints,
because the controller looks up endpoints by port.

### 4. Fix

```bash
diff broken-03-ingress-wrong-backend.yaml fixed-03-ingress-wrong-backend.yaml
kubectl apply -f fixed-03-ingress-wrong-backend.yaml
```

Output (captured 2026-10-07):

```text
1,4c1
< # SCENARIO 3 (BROKEN): Ingress points at a Service name that does not exist ("app1-svc", the real
< # Service is "app1") and at port 8080 (the real Service port is 80).
< # Symptom: Ingress is accepted by the API server, but curl returns 503/404 and
< # `kubectl describe ingress` shows  <error: services "app1-svc" not found>.
---
> # SCENARIO 3 (FIXED): backend service name and port match `kubectl get svc -n s12`.
21c18
<                 name: app1-svc     # <-- BUG 1: Service is called "app1"
---
>                 name: app1         # FIX: real Service name
23c20
<                   number: 8080     # <-- BUG 2: Service listens on port 80
---
>                   number: 80       # FIX: real Service port
ingress.networking.k8s.io/ts-ingress configured
```

### 5. After

```bash
kubectl describe ingress ts-ingress -n s12 | sed -n '/^Rules/,/^Annotations/p'
curl -sS -H 'Host: ts.demo.local' $INGRESS/app1
curl -sS -H 'Host: ts.demo.local' $INGRESS/app2
```

Output (captured 2026-10-08, a few seconds after the apply; no restart of anything was needed):

```text
Rules:
  Host           Path  Backends
  ----           ----  --------
  ts.demo.local
                 /app1   app1:80 (10.42.0.23:5678,10.42.0.22:5678)
                 /app2   app2:80 (10.42.0.25:5678,10.42.0.24:5678)
Annotations:     <none>
Hello from app1
Hello from app2
```

---

## Generic checklist I ended up with

| Symptom | First command | Usual cause |
| --- | --- | --- |
| `CreateContainerConfigError` | `kubectl describe pod` (Events) | missing ConfigMap/Secret or wrong key name |
| `CrashLoopBackOff` | `kubectl logs --previous` | app error, bad command, wrong env value (e.g. password with trailing `\n` from `echo` without `-n`) |
| Ingress has no ADDRESS | `kubectl get ingressclass`, controller pods | no Ingress Controller / wrong `ingressClassName` |
| Ingress 404 (or 503) on one path | `kubectl describe ingress`, `kubectl get endpoints`, controller logs | wrong Service name/port, Service selector matches no pods |
| Secret decodes to a different length | `kubectl get secret -o jsonpath | base64 -d | xxd` | base64 made with `echo` instead of `echo -n` |

## Cleanup

```bash
kubectl delete -f fixed-01-secret-key-mismatch.yaml -f fixed-02-configmap-missing.yaml -f fixed-03-ingress-wrong-backend.yaml
```

## Screenshots

Terminal output blocks above stand in for screenshots:

- Scenario 1 before: `kubectl get pods` showing `CreateContainerConfigError`; after: `Running` + log line.
- Scenario 2 before: event `configmap "app-confg" not found`; after: `Running` + log line.
- Scenario 3 before: `describe ingress` with `<error: services "app1-svc" not found>` and `404`; after: both paths return text.

## Deliverables

- `broken-0{1,2,3}-*.yaml` – reproducible broken scenarios.
- `fixed-0{1,2,3}-*.yaml` – corrected manifests.
- This README – troubleshooting documentation with commands, root causes and before/after output.
