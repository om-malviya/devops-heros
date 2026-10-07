# Issue: Configuration (bad env var reference -> CreateContainerConfigError)

Student: Om Malviya | Enrollment No: 24BCS10448

When a container's environment references a ConfigMap key or Secret that does not exist, kubelet cannot even build the container configuration. The Pod is scheduled and the image is pulled, but the status is `CreateContainerConfigError` and it never starts. This is different from `ContainerCreating` (volume problem) and from `CrashLoopBackOff` (the app started and crashed).

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pod config-demo -n s14
```

Output (captured 2026-10-08, before)

```text
configmap/app-config created
pod/config-demo created
NAME          READY   STATUS                       RESTARTS   AGE
config-demo   0/1     CreateContainerConfigError   0          58s
```

## 2. Investigate

```bash
kubectl describe pod config-demo -n s14 | sed -n '/Environment:/,/Mounts:/p;/Events:/,$p'
kubectl get configmap app-config -n s14 -o jsonpath='{.data}{"\n"}'
kubectl get secret app-secret -n s14
```

Output (captured 2026-10-08)

```text
    Environment:
      DB_HOST:  <set to the key 'DB_HOST' of config map 'app-config'>  Optional: false
      DB_PORT:  <set to the key 'DB_PORT' of config map 'app-config'>  Optional: false
      DB_USER:  <set to the key 'username' in secret 'app-secret'>     Optional: false
    Mounts:
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  58s               default-scheduler  Successfully assigned s14/config-demo to colima
  Normal   Pulled     2s (x6 over 56s)  kubelet            spec.containers{app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Warning  Failed     2s (x6 over 55s)  kubelet            spec.containers{app}: Error: couldn't find key DB_PORT in ConfigMap s14/app-config

{"DB_HOST":"db.s14.svc.cluster.local"}
Error from server (NotFound): secrets "app-secret" not found
```

## 3. Root cause

* The event says it plainly: `couldn't find key DB_PORT in ConfigMap s14/app-config`. The ConfigMap only has `DB_HOST`.
* Kubelet stops at the first error, so the second problem (`secret "app-secret" not found`) only appears **after** the first one is fixed. I checked the Secret proactively so I would not have to loop twice.

## 4. Fix

Add the missing key and create the Secret (placeholder values only - never real credentials in Git).

```diff
 data:
   DB_HOST: "db.s14.svc.cluster.local"
+  DB_PORT: "5432"
+---
+apiVersion: v1
+kind: Secret
+metadata:
+  name: app-secret
+  namespace: s14
+type: Opaque
+stringData:
+  username: "app_user"
+  password: "fake-password-change-me"
```

```bash
kubectl apply -f fixed.yaml      # kubelet retries automatically; no need to delete the Pod
```

Output (captured 2026-10-08)

```text
configmap/app-config configured
secret/app-secret created
pod/config-demo unchanged
```

`pod/config-demo unchanged` is the nice part: the Pod spec was correct all along, only the objects it referenced were incomplete, so no Pod recreation was needed.

## 5. Verify

```bash
kubectl get pod config-demo -n s14
kubectl logs config-demo -n s14
kubectl exec config-demo -n s14 -- env | grep DB_
```

Output (captured 2026-10-08, after)

```text
NAME          READY   STATUS    RESTARTS   AGE
config-demo   1/1     Running   0          2m47s
DB=db.s14.svc.cluster.local:5432 user=app_user
DB_PORT=5432
DB_USER=app_user
DB_HOST=db.s14.svc.cluster.local
```

The AGE (2m47s) is the age of the original Pod: kubelet's next retry simply succeeded once the key and the Secret existed.

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| CreateContainerConfigError | `couldn't find key DB_PORT in ConfigMap` | `kubectl describe pod` (Events + Environment), `kubectl get cm -o jsonpath`, `kubectl get secret` | Missing ConfigMap key and missing Secret | Add key, create Secret; kubelet retries by itself |

Related configuration symptoms: a wrong value (e.g. `DB_PORT=abc`) does **not** give this error - the container starts and the app crashes (`CrashLoopBackOff`), so logs are the place to look; a ConfigMap mounted as a volume that is missing gives `ContainerCreating` + `FailedMount` instead (see `../containercreating/`).

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
