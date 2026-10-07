# Pod Lifecycle Lab

Student: Om Malviya | Enrollment No: 24BCS10448

Twelve small Pods, each engineered to land in one lifecycle situation. All of
them are in namespace `s10` and carry the label `lab=pod-lifecycle`.

```text
Official Pod phases:        Pending -> Running -> Succeeded
                                    \         \-> Failed
                                     \-> (Unknown: node unreachable)

Container states:           Waiting -> Running -> Terminated
                            (reason: ContainerCreating, CrashLoopBackOff,
                             ImagePullBackOff, Completed, Error ...)
```

`kubectl get pods` prints a STATUS column that mixes the phase with the
container-state *reason*, which is why you see values such as
`ContainerCreating`, `CrashLoopBackOff`, `Completed` or `Init:0/1` that are
not phases.

## How to run

```bash
kubectl apply -f ../namespace.yaml
kubectl -n s10 get pods -w          # terminal 1: live watch
kubectl apply -f 01-running.yaml    # terminal 2: apply one example at a time
```

Or run the whole lab unattended:

```bash
./run-all.sh      # applies each file, waits, prints status + state + events
./cleanup.sh      # deletes all lab pods
```

The three commands used for every example:

```bash
kubectl -n s10 get pod <name>
kubectl -n s10 describe pod <name>
kubectl -n s10 logs <name> [-c <container>] [--previous]
```

---

## 1. Running – `01-running.yaml`

```bash
kubectl apply -f 01-running.yaml
sleep 5
kubectl -n s10 get pod lifecycle-running
```

Output (captured 2026-10-08)
```text
pod/lifecycle-running created
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-running   1/1     Running   0          5s
```

```bash
kubectl -n s10 describe pod lifecycle-running | sed -n '/^Status:/p;/^Containers:/,/Restart Count/p;/^Events:/,$p'
```

Output (captured 2026-10-08) (key lines; Container ID / Image ID lines removed)
```text
Status:           Running
Containers:
  nginx:
    Image:          nginx:alpine
    Port:           80/TCP
    State:          Running
      Started:      Thu, 08 Oct 2026 02:33:06 +0530
    Ready:          True
    Restart Count:  0
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  5s    default-scheduler  Successfully assigned s10/lifecycle-running to colima
  Normal  Pulled     5s    kubelet            spec.containers{nginx}: Container image "nginx:alpine" already present on machine and can be accessed by the pod
  Normal  Created    5s    kubelet            spec.containers{nginx}: Container created
  Normal  Started    5s    kubelet            spec.containers{nginx}: Container started
```

What I observed: the Pod went `Pending -> ContainerCreating -> Running` in
about a second. Phase is `Running`, the single container is in state
`Running` and, because there is no readiness probe, Kubernetes marks it
Ready the moment it starts (`1/1`). There is no `Pulling` event because
`nginx:alpine` was already cached on the node from Session 11; a first run
on a clean node would show `Pulling`/`Pulled` and take a few seconds longer.

## 2. Pending – `02-pending.yaml`

```bash
kubectl apply -f 02-pending.yaml
kubectl -n s10 get pod lifecycle-pending
```

Output (captured 2026-10-08)
```text
pod/lifecycle-pending created
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-pending   0/1     Pending   0          8s
```

```bash
kubectl -n s10 describe pod lifecycle-pending | sed -n '/^Status:/p;/^Node:/p;/^Events:/,$p'
```

Output (captured 2026-10-08) (key lines)
```text
Node:             <none>
Status:           Pending
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  8s    default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.
```

What I observed: the Pod asks for 64 CPUs and 512Gi, so the scheduler finds
no node and never assigns one (`Node: <none>`). It stays `Pending` forever;
no image is pulled and no container exists. This is the same status you see
when a cluster is simply full.

## 3. Succeeded – `03-succeeded.yaml`

```bash
kubectl apply -f 03-succeeded.yaml
sleep 12
kubectl -n s10 get pod lifecycle-succeeded
kubectl -n s10 logs lifecycle-succeeded
kubectl -n s10 get pod lifecycle-succeeded -o jsonpath='{.status.phase}'; echo
```

Output (captured 2026-10-08)
```text
pod/lifecycle-succeeded created
NAME                  READY   STATUS      RESTARTS   AGE
lifecycle-succeeded   0/1     Completed   0          12s
Task started
Task completed successfully
Succeeded
```

```bash
kubectl -n s10 describe pod lifecycle-succeeded | sed -n '/^Status:/p;/State:/,/Restart Count/p'
```

Output (captured 2026-10-08) (key lines)
```text
Status:           Succeeded
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Thu, 08 Oct 2026 02:33:20 +0530
      Finished:     Thu, 08 Oct 2026 02:33:25 +0530
    Ready:          False
    Restart Count:  0
```

What I observed: with `restartPolicy: Never` a clean `exit 0` moves the Pod
to phase `Succeeded`. `kubectl get` shows `Completed` (the container reason)
and READY is `0/1` because a terminated container is never Ready. This is how
Job pods look when they finish.

## 4. Failed – `04-failed.yaml`

```bash
kubectl apply -f 04-failed.yaml
sleep 12
kubectl -n s10 get pod lifecycle-failed
kubectl -n s10 logs lifecycle-failed
kubectl -n s10 get pod lifecycle-failed -o jsonpath='{.status.phase}'; echo
```

Output (captured 2026-10-08)
```text
pod/lifecycle-failed created
NAME               READY   STATUS   RESTARTS   AGE
lifecycle-failed   0/1     Error    0          12s
Task started
Task failed
Failed
```

```bash
kubectl -n s10 describe pod lifecycle-failed | sed -n '/^Status:/p;/State:/,/Restart Count/p'
```

Output (captured 2026-10-08) (key lines)
```text
Status:           Failed
    State:          Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Thu, 08 Oct 2026 02:33:32 +0530
      Finished:     Thu, 08 Oct 2026 02:33:37 +0530
    Ready:          False
    Restart Count:  0
```

What I observed: identical to the previous Pod except for `exit 1`. The
non-zero exit code gives reason `Error` and phase `Failed`. Because the
restart policy is `Never`, the kubelet does not retry.

## 5. CrashLoopBackOff – `05-crashloopbackoff.yaml`

```bash
kubectl apply -f 05-crashloopbackoff.yaml
kubectl -n s10 get pod lifecycle-crashloop -w
```

Output (captured 2026-10-08) (watched for 70 s)
```text
pod/lifecycle-crashloop created
NAME                  READY   STATUS              RESTARTS   AGE
lifecycle-crashloop   0/1     ContainerCreating   0          0s
lifecycle-crashloop   1/1     Running             0          1s
lifecycle-crashloop   0/1     Error               0          4s
lifecycle-crashloop   1/1     Running             1 (2s ago)   5s
lifecycle-crashloop   0/1     Error               1 (5s ago)   8s
lifecycle-crashloop   0/1     CrashLoopBackOff    1 (13s ago)   20s
lifecycle-crashloop   1/1     Running             2 (13s ago)   20s
lifecycle-crashloop   0/1     Error               2 (16s ago)   23s
lifecycle-crashloop   0/1     CrashLoopBackOff    2 (27s ago)   50s
lifecycle-crashloop   1/1     Running             3 (27s ago)   50s
lifecycle-crashloop   0/1     Error               3 (30s ago)   53s
```

```bash
kubectl -n s10 describe pod lifecycle-crashloop | sed -n '/State:/,/Restart Count/p;/^Events:/,$p'
kubectl -n s10 logs lifecycle-crashloop --previous
```

Output (captured 2026-10-08) (key lines; first `describe` caught the pod in the `Error` state just after a crash, before the back-off started)
```text
    State:          Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Thu, 08 Oct 2026 02:34:34 +0530
      Finished:     Thu, 08 Oct 2026 02:34:37 +0530
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Thu, 08 Oct 2026 02:34:04 +0530
      Finished:     Thu, 08 Oct 2026 02:34:07 +0530
    Ready:          False
    Restart Count:  3
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  70s                default-scheduler  Successfully assigned s10/lifecycle-crashloop to colima
  Normal   Pulled     20s (x4 over 70s)  kubelet            spec.containers{crashing-app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    20s (x4 over 70s)  kubelet            spec.containers{crashing-app}: Container created
  Normal   Started    20s (x4 over 70s)  kubelet            spec.containers{crashing-app}: Container started
  Warning  BackOff    17s (x3 over 62s)  kubelet            spec.containers{crashing-app}: Back-off restarting failed container crashing-app in pod lifecycle-crashloop_s10(4553422c-8fe0-4b50-84e3-a9f3240d34da)
unable to retrieve container logs for containerd://d9a02830e935412fb17f774955794fe22cab20cf3544176a9c1f197048ed8ea4
```

What I observed: the phase stays `Running` the whole time (the Pod is
scheduled and has a container that was running), but the container keeps
exiting 1. The default `restartPolicy: Always` makes the kubelet restart it
with growing delays (the restarts happened at 5 s, 20 s and 50 s, i.e. gaps
of roughly 1 s, 12 s and 27 s, doubling towards the 5-minute cap), and
during each delay the container state is `Waiting / CrashLoopBackOff`.
`RESTARTS` climbs. My first `describe` happened to land in the short
`Terminated / Error` moment right after a crash, and at that instant
`logs --previous` failed because the kubelet was still rotating the
containers; a few seconds later, with the pod `Running` again at
`RESTARTS 3`, it returned the crashed instance's output:

```bash
kubectl -n s10 get pod lifecycle-crashloop
kubectl -n s10 logs lifecycle-crashloop --previous
```

Output (captured 2026-10-08)
```text
NAME                  READY   STATUS    RESTARTS      AGE
lifecycle-crashloop   1/1     Running   3 (27s ago)   50s
Application started
Application crashed
```

## 6. ImagePullBackOff – `06-imagepullbackoff.yaml`

```bash
kubectl apply -f 06-imagepullbackoff.yaml
sleep 20
kubectl -n s10 get pod lifecycle-image-error
```

Output (captured 2026-10-08)
```text
pod/lifecycle-image-error created
NAME                    READY   STATUS             RESTARTS   AGE
lifecycle-image-error   0/1     ImagePullBackOff   0          20s
```

```bash
kubectl -n s10 describe pod lifecycle-image-error | sed -n '/^Status:/p;/State:/,/Ready:/p;/^Events:/,$p'
```

Output (captured 2026-10-08) (key lines)
```text
Status:           Pending
    State:          Waiting
      Reason:       ImagePullBackOff
    Ready:          False
Events:
  Type     Reason     Age               From               Message
  ----     ------     ----              ----               -------
  Normal   Scheduled  20s               default-scheduler  Successfully assigned s10/lifecycle-image-error to colima
  Normal   BackOff    19s               kubelet            spec.containers{broken-image}: Back-off pulling image "registry.example.invalid/does-not-exist:v0.0.0"
  Warning  Failed     19s               kubelet            spec.containers{broken-image}: Error: ImagePullBackOff
  Normal   Pulling    3s (x2 over 20s)  kubelet            spec.containers{broken-image}: Pulling image "registry.example.invalid/does-not-exist:v0.0.0"
  Warning  Failed     3s (x2 over 20s)  kubelet            spec.containers{broken-image}: Failed to pull image "registry.example.invalid/does-not-exist:v0.0.0": failed to pull and unpack image "registry.example.invalid/does-not-exist:v0.0.0": failed to resolve reference "registry.example.invalid/does-not-exist:v0.0.0": failed to do request: Head "https://registry.example.invalid/v2/does-not-exist/manifests/v0.0.0": dial tcp: lookup registry.example.invalid: no such host
  Warning  Failed     3s (x2 over 20s)  kubelet            spec.containers{broken-image}: Error: ErrImagePull
```

What I observed: the Pod *was* scheduled (it has a node) but the phase is
still `Pending` because no container has ever started. The first attempt
fails with `ErrImagePull`; the kubelet then backs off and reports
`ImagePullBackOff`. Typical real causes: typo in the tag, private registry
without `imagePullSecrets`, or no network from the node.

## 7. Readiness probe – `07-readiness.yaml`

```bash
kubectl apply -f 07-readiness.yaml
kubectl -n s10 get pod lifecycle-readiness -w
```

Output (captured 2026-10-08)
```text
pod/lifecycle-readiness created
NAME                  READY   STATUS    RESTARTS   AGE
lifecycle-readiness   0/1     Pending   0          0s
lifecycle-readiness   0/1     ContainerCreating   0          0s
lifecycle-readiness   0/1     Running             0          2s     <- running but NOT ready
lifecycle-readiness   1/1     Running             0          13s    <- first probe at 10s passed
```

```bash
kubectl -n s10 describe pod lifecycle-readiness | sed -n '/Readiness:/p;/^Conditions:/,/PodScheduled/p'
```

Output (captured 2026-10-08) (key lines, taken at 5 s)
```text
    Readiness:      http-get http://:80/ delay=10s timeout=1s period=5s successThreshold=1 failureThreshold=3
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       False
  ContainersReady             False
  PodScheduled                True
```

What I observed: the container was `Running` at 2 s but READY stayed `0/1`
until the first probe at 10 s succeeded (the watch shows `1/1` at 13 s).
The `PodReadyToStartContainers` condition is new in recent Kubernetes
versions and just means the sandbox/network was set up. `Running` answers "is the process
up?"; `Ready` answers "should this Pod receive Service traffic?". A Service
only adds a Pod to its Endpoints when Ready is True, and removes it again if
the probe later fails, without restarting anything.

## 8. Liveness probe – `08-liveness.yaml`

```bash
kubectl apply -f 08-liveness.yaml
kubectl -n s10 get pod lifecycle-liveness -w
```

Output (captured 2026-10-08) (watched for 80 s)
```text
pod/lifecycle-liveness created
NAME                 READY   STATUS    RESTARTS   AGE
lifecycle-liveness   0/1     Pending   0          1s
lifecycle-liveness   0/1     ContainerCreating   0          1s
lifecycle-liveness   1/1     Running             0          2s
lifecycle-liveness   1/1     Running             1 (5s ago)   67s   <- restarted after 2 failed probes + 30 s grace
```

```bash
kubectl -n s10 describe pod lifecycle-liveness | sed -n '/Liveness:/p;/Last State:/,/Restart Count/p;/^Events:/,$p'
```

Output (captured 2026-10-08) (key lines)
```text
    Last State:     Terminated
      Reason:       Error
      Exit Code:    137
      Started:      Thu, 08 Oct 2026 02:35:36 +0530
      Finished:     Thu, 08 Oct 2026 02:36:36 +0530
    Ready:          True
    Restart Count:  1
    Liveness:       exec [sh -c test -f /tmp/healthy] delay=5s timeout=1s period=5s successThreshold=1 failureThreshold=2
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  80s                default-scheduler  Successfully assigned s10/lifecycle-liveness to colima
  Warning  Unhealthy  50s (x2 over 55s)  kubelet            spec.containers{app}: Liveness probe failed:
  Normal   Killing    50s                kubelet            spec.containers{app}: Container app failed liveness probe, will be restarted
  Normal   Pulled     18s (x2 over 79s)  kubelet            spec.containers{app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    17s (x2 over 79s)  kubelet            spec.containers{app}: Container created
  Normal   Started    16s (x2 over 79s)  kubelet            spec.containers{app}: Container started
```

What I observed: the process never crashes on its own, but after 20 s it
deletes `/tmp/healthy`. Two consecutive probe failures (`failureThreshold: 2`,
`period 5s`, at 25 s and 30 s) made the kubelet decide to kill the container
(`Killing` event at 30 s). The restart only showed up at 67 s, not ~35 s as I
first expected: `sh -c` does not forward SIGTERM to its `sleep` child, so the
container ignored SIGTERM and the kubelet waited the full 30 s
`terminationGracePeriodSeconds` before sending SIGKILL (exit code 137,
`Finished` exactly 60 s after `Started`). So the cycle is ~65 s per restart
here; with an app that exits on SIGTERM it would be ~35 s. The Pod object
and its IP stay the same; only the container is replaced. Liveness is for
"stuck" processes, not for startup time.

## 9. Startup probe – `09-startup.yaml`

```bash
kubectl apply -f 09-startup.yaml
kubectl -n s10 get pod lifecycle-startup -w
```

Output (captured 2026-10-08)
```text
pod/lifecycle-startup created
NAME                READY   STATUS    RESTARTS   AGE
lifecycle-startup   0/1     Pending   0          0s
lifecycle-startup   0/1     ContainerCreating   0          1s
lifecycle-startup   0/1     Running             0          7s
lifecycle-startup   1/1     Running             0          36s    <- startup probe passed, 0 restarts
```

```bash
kubectl -n s10 describe pod lifecycle-startup | sed -n '/Startup:/p;/Liveness:/p;/^Events:/,$p'
```

Output (captured 2026-10-08) (key lines)
```text
    Liveness:       exec [sh -c test -f /tmp/started] delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=1
    Startup:        exec [sh -c test -f /tmp/started] delay=0s timeout=1s period=5s successThreshold=1 failureThreshold=10
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  44s                default-scheduler  Successfully assigned s10/lifecycle-startup to colima
  Normal   Pulled     42s                kubelet            spec.containers{slow-app}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal   Created    41s                kubelet            spec.containers{slow-app}: Container created
  Normal   Started    40s                kubelet            spec.containers{slow-app}: Container started
  Warning  Unhealthy  14s (x6 over 38s)  kubelet            spec.containers{slow-app}: Startup probe failed:
```

What I observed: the app needs 30 s to start. The liveness probe here has
`failureThreshold: 1`, so without the startup probe it would kill the
container every 5 s and the Pod would crash-loop forever. With the startup
probe, liveness and readiness are *disabled* until the startup probe succeeds
(up to 10 x 5 s = 50 s), so the Pod showed `0/1 Running` until 36 s and then
`1/1` with `RESTARTS 0`, after six `Startup probe failed` warnings. The "Unhealthy: Startup probe failed" warnings are
expected and harmless.

## 10. Init container – `10-init-container.yaml`

```bash
kubectl apply -f 10-init-container.yaml
kubectl -n s10 get pod lifecycle-init -w
```

Output (captured 2026-10-08)
```text
pod/lifecycle-init created
NAME             READY   STATUS    RESTARTS   AGE
lifecycle-init   0/1     Pending   0          0s
lifecycle-init   0/1     Init:0/1   0          0s
lifecycle-init   0/1     PodInitializing   0          13s
lifecycle-init   1/1     Running           0          14s
```

```bash
kubectl -n s10 logs lifecycle-init -c setup
kubectl -n s10 describe pod lifecycle-init | sed -n '/^Init Containers:/,/^Containers:/p' | grep -E 'setup:|State|Reason|Exit Code'
kubectl -n s10 describe pod lifecycle-init | sed -n '/^Events:/,$p'
```

Output (captured 2026-10-08) (key lines)
```text
Init container running
Init complete
  setup:
    State:          Terminated
      Reason:       Completed
      Exit Code:    0
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  20s   default-scheduler  Successfully assigned s10/lifecycle-init to colima
  Normal  Pulled     18s   kubelet            spec.initContainers{setup}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal  Created    17s   kubelet            spec.initContainers{setup}: Container created
  Normal  Started    17s   kubelet            spec.initContainers{setup}: Container started
  Normal  Pulled     7s    kubelet            spec.containers{app}: Container image "nginx:alpine" already present on machine and can be accessed by the pod
  Normal  Created    7s    kubelet            spec.containers{app}: Container created
  Normal  Started    7s    kubelet            spec.containers{app}: Container started
```

What I observed: `Init:0/1` means 0 of 1 init containers has finished. The
`app` container was not even created until `setup` exited 0 (the `Created`
events are 10 s apart, matching the `sleep 10`). Init containers run strictly in order, each to completion, before any
app container starts; if one fails the Pod restarts it according to the
restart policy and the app never starts. Useful for waiting on a database,
fetching config, or fixing volume permissions.

## 11. Multi-container Pod – `11-multi-container.yaml`

```bash
kubectl apply -f 11-multi-container.yaml
sleep 15
kubectl -n s10 get pod lifecycle-multi-container
kubectl -n s10 logs lifecycle-multi-container -c sidecar | tail -n 2
kubectl -n s10 logs lifecycle-multi-container -c app | tail -n 1
```

Output (captured 2026-10-08)
```text
pod/lifecycle-multi-container created
NAME                        READY   STATUS    RESTARTS   AGE
lifecycle-multi-container   2/2     Running   0          15s
Sidecar: nginx says <!DOCTYPE html>...
Sidecar: nginx says <!DOCTYPE html>...
127.0.0.1 - - [07/Oct/2026:21:08:12 +0000] "GET / HTTP/1.1" 200 896 "-" "Wget" "-"
```

```bash
kubectl -n s10 describe pod lifecycle-multi-container | grep -E '^  (app|sidecar):|State:|^IP:'
```

Output (captured 2026-10-08) (key lines)
```text
IP:               10.42.0.194
  app:
    State:          Running
  sidecar:
    State:          Running
```

What I observed: READY reads `2/2`, one Pod IP is shared by both containers,
and the sidecar reaches nginx on `127.0.0.1` because they share the network
namespace. `kubectl logs` needs `-c` to choose a container. If either
container dies the Pod shows `1/2` and the Pod is not Ready as a whole; both
containers are scheduled, scaled and deleted together.

## 12. Graceful termination – `12-termination.yaml`

```bash
kubectl apply -f 12-termination.yaml
kubectl -n s10 wait --for=condition=Ready pod/lifecycle-termination
kubectl -n s10 logs -f lifecycle-termination &      # keep following logs
time kubectl -n s10 delete pod lifecycle-termination
```

On my colima VM `kubectl logs -f` died right after the first line with
`failed to create fsnotify watcher: too many open files` (the VM's inotify
limit), and `time kubectl delete` reported `16.7s total`. To still capture
the shutdown messages I re-ran it polling `kubectl logs` once a second until
the pod was gone, keeping the last successful read:

```bash
kubectl apply -f 12-termination.yaml
kubectl -n s10 wait --for=condition=Ready pod/lifecycle-termination
START=$(date +%s); kubectl -n s10 delete pod lifecycle-termination --wait=false
while L=$(kubectl -n s10 logs lifecycle-termination 2>/dev/null); do LAST=$L; sleep 1; done
echo "$LAST"; echo "pod gone after $(( $(date +%s) - START ))s"
```

Output (captured 2026-10-08)
```text
pod/lifecycle-termination created
pod/lifecycle-termination condition met
pod "lifecycle-termination" deleted from s10 namespace
Application running
SIGTERM received; cleaning up...
Cleanup complete
pod gone after 17s
```

In a second terminal during the delete:

```bash
kubectl -n s10 get pod lifecycle-termination -w
```

Output (captured 2026-10-08) (duplicate watch lines removed)
```text
NAME                    READY   STATUS    RESTARTS   AGE
lifecycle-termination   1/1     Running   0          1s
lifecycle-termination   1/1     Terminating   0          3s
lifecycle-termination   0/1     Completed     0          19s
```

`kubectl describe` in kubectl 1.37 no longer prints the grace period or the
lifecycle hooks, so I read them from the spec instead:

```bash
kubectl -n s10 get pod lifecycle-termination -o jsonpath='grace={.spec.terminationGracePeriodSeconds}{"\n"}preStop={.spec.containers[0].lifecycle.preStop.exec.command}{"\n"}'
```

Output (captured 2026-10-08) (before deleting)
```text
grace=30
preStop=["sh","-c","echo 'preStop: draining connections'; sleep 5"]
```

What I observed: the delete took 16-17 s rather than returning instantly.
The order was: Pod marked `Terminating` and removed from Service endpoints,
the `preStop` hook ran (5 s), then SIGTERM was sent and my `trap` handler
did 10 s of cleanup and exited 0, which is why the watch ends with
`0/1 Completed` (exit code 0) before the object disappears. Because
5 + 10 < `terminationGracePeriodSeconds: 30`, no SIGKILL was needed. One
thing I had wrong in my first draft: the `echo` inside the `preStop` hook is
not part of the container's stdout, so it never appears in `kubectl logs`;
only the handler's own lines do. If I set the grace period to 8 s the kubelet would
SIGKILL the process mid-cleanup and the last log line would never appear.
`kubectl delete --grace-period=0 --force` skips all of this.

---

## Summary table

| # | File | `kubectl get` STATUS | Phase | Why |
| --- | --- | --- | --- | --- |
| 1 | 01-running | `Running 1/1` | Running | normal start |
| 2 | 02-pending | `Pending 0/1` | Pending | unschedulable resource request |
| 3 | 03-succeeded | `Completed 0/1` | Succeeded | exit 0, restartPolicy Never |
| 4 | 04-failed | `Error 0/1` | Failed | exit 1, restartPolicy Never |
| 5 | 05-crashloopbackoff | `CrashLoopBackOff` | Running | exit 1, restartPolicy Always, backoff |
| 6 | 06-imagepullbackoff | `ImagePullBackOff` | Pending | image cannot be pulled |
| 7 | 07-readiness | `Running 0/1` then `1/1` | Running | readiness gates Ready/endpoints |
| 8 | 08-liveness | `Running`, RESTARTS 1,2,... (every ~65 s here) | Running | liveness restarts container |
| 9 | 09-startup | `Running 0/1` 30s then `1/1` | Running | startup probe delays liveness |
| 10 | 10-init-container | `Init:0/1`, `PodInitializing`, `Running` | Pending then Running | init runs first |
| 11 | 11-multi-container | `Running 2/2` | Running | two containers, one Pod |
| 12 | 12-termination | `Terminating` ~16s, then `Completed` | Running then gone | preStop + SIGTERM + grace period |

## Cleanup

```bash
./cleanup.sh
# or
kubectl -n s10 delete pod -l lab=pod-lifecycle
```

Output (captured 2026-10-08)
```text
pod "lifecycle-crashloop" deleted from s10 namespace
pod "lifecycle-failed" deleted from s10 namespace
pod "lifecycle-image-error" deleted from s10 namespace
pod "lifecycle-init" deleted from s10 namespace
pod "lifecycle-liveness" deleted from s10 namespace
pod "lifecycle-multi-container" deleted from s10 namespace
pod "lifecycle-pending" deleted from s10 namespace
pod "lifecycle-readiness" deleted from s10 namespace
pod "lifecycle-running" deleted from s10 namespace
pod "lifecycle-startup" deleted from s10 namespace
pod "lifecycle-succeeded" deleted from s10 namespace
No resources found in s10 namespace.
```

## Deliverables

- `01-running.yaml` … `12-termination.yaml` – one Pod per lifecycle situation, namespace `s10`.
- `run-all.sh` – applies each file with sleeps and prints status, container state and events.
- `cleanup.sh` – deletes all lab Pods by label.
- `README.md` – per-file apply command, expected `get pod` status, `describe pod` key lines and explanation.
