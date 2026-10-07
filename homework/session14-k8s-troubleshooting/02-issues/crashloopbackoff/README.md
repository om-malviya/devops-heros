# Issue: CrashLoopBackOff

Student: Om Malviya | Enrollment No: 24BCS10448

`CrashLoopBackOff` is a **symptom**: the container starts, exits with an error, kubelet restarts it, it exits again, and kubelet waits longer and longer between restarts (10s, 20s, 40s ... up to 5 minutes).

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pod crash-demo -n s14
```

Output (captured 2026-10-08, before)

```text
pod/crash-demo created
NAME         READY   STATUS   RESTARTS      AGE
crash-demo   0/1     Error    4 (65s ago)   101s
```

READY `0/1`, RESTARTS climbing, STATUS alternating between `Error` (the current container has just exited) and `CrashLoopBackOff` (kubelet is waiting before the next restart). A little later:

```text
NAME         READY   STATUS             RESTARTS      AGE
crash-demo   0/1     CrashLoopBackOff   5 (88s ago)   4m31s
```

## 2. Investigate

```bash
kubectl describe pod crash-demo -n s14
kubectl logs crash-demo -n s14
kubectl logs crash-demo -n s14 --previous
kubectl get events -n s14 --field-selector involvedObject.name=crash-demo --sort-by=.lastTimestamp
```

Output (captured 2026-10-08; describe trimmed to the container state and Events)

```text
Containers:
  app:
    State:          Waiting
      Reason:       CrashLoopBackOff
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Thu, 08 Oct 2026 02:41:50 +0530
      Finished:     Thu, 08 Oct 2026 02:41:50 +0530
    Ready:          False
    Restart Count:  5
    Environment:    <none>
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  101s               default-scheduler  Successfully assigned s14/crash-demo to colima
  Normal   Pulled     7s (x5 over 100s)  kubelet            spec.containers{app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    7s (x5 over 100s)  kubelet            spec.containers{app}: Container created
  Normal   Started    7s (x5 over 100s)  kubelet            spec.containers{app}: Container started
  Warning  BackOff    6s (x4 over 99s)   kubelet            spec.containers{app}: Back-off restarting failed container app in pod crash-demo_s14(19f67037-d961-4036-a3db-670077e83733)

Application starting...
FATAL: DB_HOST environment variable is missing

Application starting...
FATAL: DB_HOST environment variable is missing

LAST SEEN   TYPE      REASON      OBJECT           MESSAGE
101s        Normal    Scheduled   pod/crash-demo   Successfully assigned s14/crash-demo to colima
7s          Normal    Pulled      pod/crash-demo   Container image "busybox:1.36" already present on machine and can be accessed by the pod
7s          Normal    Created     pod/crash-demo   Container created
7s          Normal    Started     pod/crash-demo   Container started
6s          Warning   BackOff     pod/crash-demo   Back-off restarting failed container app in pod crash-demo_s14(19f67037-d961-4036-a3db-670077e83733)
```

Something I only learned by doing it: `logs --previous` failed the first two times I ran it, with

```text
unable to retrieve container logs for containerd://43b90bd8790108485eeaa1617048abf56b8b54e31d8d99d9c90fd6bf9d8150cf
```

Both times the Pod was showing `Error` (State: Terminated) rather than `CrashLoopBackOff` (State: Waiting). In the `Error` moment there are two dead containers (the one that just exited and the "previous" one) and the kubelet garbage-collects all but one dead container per container, so the previous one is already gone. Once the Pod was in `CrashLoopBackOff` the command worked (output above). On this cluster the plain `kubectl logs` of the just-exited container showed the same message anyway, which is the important part.

## 3. Root cause

The `Last State` shows `Exit Code: 1`, and the logs (current and `--previous`) say `DB_HOST environment variable is missing`. The start-up script checks for `DB_HOST` and exits with code 1 when it is empty. The manifest never sets that variable (`Environment: <none>` in describe). Kubernetes is doing exactly what it should: restart a failed container with back-off.

## 4. Fix

Add the missing environment variable (in a real app this would normally come from a ConfigMap/Secret).

```diff
     - name: app
       image: busybox:1.36
+      env:
+        - name: DB_HOST
+          value: "db.s14.svc.cluster.local"
```

`env` is immutable on a running Pod (`kubectl apply` is rejected with `Forbidden: pod updates may not change fields other than spec.containers[*].image ...`), so I recreate it:

```bash
kubectl delete pod crash-demo -n s14
kubectl apply -f fixed.yaml
```

Output (captured 2026-10-08)

```text
pod "crash-demo" deleted from s14 namespace
pod/crash-demo created
```

(`kubectl replace --force -f fixed.yaml` does the same in one command; `triage.sh --fix-all` uses that.)

## 5. Verify

```bash
kubectl get pod crash-demo -n s14
kubectl logs crash-demo -n s14
```

Output (captured 2026-10-08, after)

```text
NAME         READY   STATUS    RESTARTS   AGE
crash-demo   1/1     Running   0          63s
Application starting...
Connected to db.s14.svc.cluster.local
Application is healthy
Application is healthy
Application is healthy
```

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| CrashLoopBackOff | `0/1`, RESTARTS growing, STATUS `Error`/`CrashLoopBackOff`, `Exit Code: 1`, `BackOff` events | `kubectl logs` / `logs --previous`, `kubectl describe pod` | Required env var `DB_HOST` not set, app exits 1 | Add `env: DB_HOST` (fixed.yaml), recreate the Pod |

Other causes that produce the same symptom: wrong `command`/`args`, failing liveness probe (`Unhealthy` events), `OOMKilled` (`Exit Code: 137`, `Reason: OOMKilled` – check `kubectl top` and raise memory limit), missing file or permission problem. The exit code and the previous logs separate these cases.

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
