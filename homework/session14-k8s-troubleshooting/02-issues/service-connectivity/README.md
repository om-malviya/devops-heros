# Issue: Service connectivity (selector mismatch, no endpoints)

Student: Om Malviya | Enrollment No: 24BCS10448

The Pods are healthy, the Service exists, but requests to the Service fail. In my experience this is almost always a mismatch between the Service `selector` and the Pod labels, which shows up as an empty endpoint list.

```text
Pod labels  --(must match)-->  Service selector  -->  Endpoints  -->  traffic
```

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pods,svc -n s14 -l 'app in (web)'
kubectl exec client -n s14 -- wget -qO- --timeout=3 http://web-svc
```

Output (captured 2026-10-08, before)

```text
deployment.apps/web created
service/web-svc created
pod/client created

NAME                      READY   STATUS    RESTARTS   AGE
pod/web-6bbcc66bc-gwh2k   1/1     Running   0          119s
pod/web-6bbcc66bc-tzqrv   1/1     Running   0          119s

wget: can't connect to remote host (10.43.144.157): Connection refused
command terminated with exit code 1
```

The Pods are `Running` and `1/1`, yet the Service refuses connections. (The label filter `-l app in (web)` only lists the Pods: the Service itself carries no labels, which is a first hint that labels and selectors are two different things.)

## 2. Investigate

```bash
kubectl get endpoints web-svc -n s14
kubectl describe service web-svc -n s14
kubectl get pods -n s14 -l app=web --show-labels
kubectl get pods -n s14 -l app=web-frontend
```

Output (captured 2026-10-08)

```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME      ENDPOINTS   AGE
web-svc   <none>      2m

Name:                     web-svc
Namespace:                s14
Selector:                 app=web-frontend
Type:                     ClusterIP
IP:                       10.43.144.157
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
Endpoints:
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>

NAME                  READY   STATUS    RESTARTS   AGE   LABELS
web-6bbcc66bc-gwh2k   1/1     Running   0          2m    app=web,pod-template-hash=6bbcc66bc
web-6bbcc66bc-tzqrv   1/1     Running   0          2m    app=web,pod-template-hash=6bbcc66bc

No resources found in s14 namespace.
```

## 3. Root cause

`Endpoints: <none>` (shown as an empty line by `describe`). The Service selects `app=web-frontend`, the Pods are labelled `app=web`. Running `kubectl get pods -l app=web-frontend` with the Service's own selector returns nothing, which proves the mismatch. kube-proxy has no backends to forward to, so it refuses the connection.

Side note: `kubectl get endpoints` still works but warns that the `Endpoints` API is deprecated since 1.33; the modern equivalent is `kubectl get endpointslices -l kubernetes.io/service-name=web-svc`.

## 4. Fix

```diff
   selector:
-    app: web-frontend
+    app: web
```

```bash
kubectl apply -f fixed.yaml
```

Output (captured 2026-10-08)

```text
deployment.apps/web unchanged
service/web-svc configured
pod/client unchanged
```

Only the Service changed; a Service selector is mutable, so no Pod was touched.

## 5. Verify

```bash
kubectl get endpoints web-svc -n s14
kubectl get endpointslices -n s14 -l kubernetes.io/service-name=web-svc
kubectl exec client -n s14 -- wget -qO- --timeout=3 http://web-svc | head -4
```

Output (captured 2026-10-08, after)

```text
NAME      ENDPOINTS                       AGE
web-svc   10.42.0.216:80,10.42.0.218:80   2m49s

NAME            ADDRESSTYPE   PORTS   ENDPOINTS                 AGE
web-svc-ft9pm   IPv4          80      10.42.0.218,10.42.0.216   2m49s

<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| Service unreachable | Pods Running but `Connection refused` via Service; `Endpoints: <none>` | `kubectl get endpoints`, `kubectl describe svc`, `kubectl get pods --show-labels`, `kubectl get pods -l <service selector>` | Selector `app=web-frontend` != label `app=web` | Correct the selector (`kubectl apply`, no restart needed) |

Endpoints can also be empty when the Pods are **not Ready** (failing readiness probe): then the labels match but the Pod IP is only listed under `NotReadyAddresses` in `kubectl describe endpoints`.

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
