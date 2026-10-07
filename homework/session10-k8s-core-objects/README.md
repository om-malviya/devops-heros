# Session 10 – Kubernetes Pods, ReplicaSets & Deployments

Student: Om Malviya | Enrollment No: 24BCS10448

Everything in this session runs in the namespace `s10` so it can be created
and removed as one unit. Every output block labelled **Output (captured
2026-10-08)** was produced by running the commands on a single-node k3s
cluster (`v1.35.0+k3s1`, node `colima`, 4 CPU / 6 GB, macOS arm64 host via
colima; kubectl client `v1.37.1`). Two environment details show up in the
outputs: kubectl 1.37 prints `Warning: v1 Endpoints is deprecated in v1.33+`
whenever I `get endpoints` (harmless), and from macOS the NodePorts are
reached as `http://localhost:<nodePort>` because colima forwards the VM's
ports; the node IP `192.168.5.1` is not routable from the host.

```bash
kubectl apply -f namespace.yaml      # once
kubectl apply -f client-pod.yaml     # busybox pod used to wget the Services
...
kubectl delete namespace s10         # removes everything from this session
```

Images used: `hashicorp/http-echo:1.0` (returns the text given in `-text`, so
`wget -qO-` prints the version), `nginx:alpine`, `busybox:1.36`. All are small
and multi-arch.

## How the objects relate

```text
Deployment  ──creates/owns──>  ReplicaSet (one per pod-template revision)
                                   │
                                   └──creates/owns──>  Pod  Pod  Pod
                                                        ▲
Service  ──selects by label────────────────────────────┘   (traffic, not ownership)
```

## Pod phase diagram

```text
 kubectl apply
      │
      ▼
 ┌─────────┐  scheduled, images pulled,  ┌─────────┐
 │ Pending │ ─────────────────────────▶  │ Running │ ◀──┐ container restarts
 └─────────┘  init containers done       └────┬────┘    │ (restartPolicy Always/OnFailure)
      │                                       │          │   STATUS: CrashLoopBackOff
      │ never leaves Pending when:            │          │
      │  - unschedulable (resources,          │ all containers exit     container exits
      │    taints, affinity)                  │                          non-zero
      │  - ImagePullBackOff                   ▼                            │
      │                              ┌──────────────┐   exit 0     ┌───────┴────┐
      │                              │  Succeeded   │ ◀────────────│ Terminated │
      │                              │ (Completed)  │              │ (container)│
      │                              └──────────────┘              └───────┬────┘
      │                              ┌──────────────┐   exit != 0          │
      │                              │   Failed     │ ◀────────────────────┘
      │                              │   (Error)    │   (restartPolicy Never)
      │                              └──────────────┘
      │
      └── Unknown: node stopped reporting (kubelet down / network partition)

 kubectl delete at any point ──▶ STATUS Terminating ──▶ preStop ──▶ SIGTERM ──▶ (grace period) ──▶ SIGKILL
```

Container states inside a Pod are `Waiting` (reason: ContainerCreating,
CrashLoopBackOff, ImagePullBackOff, PodInitializing), `Running` and
`Terminated` (reason: Completed, Error, OOMKilled). `kubectl get pods` shows
the most informative of phase / reason in the STATUS column.

## Task 1: Deployment Strategies

Implemented all four strategies; each folder has its manifests and a README
with commands and expected output.

| # | Strategy | Folder | Mechanism | Downtime |
| --- | --- | --- | --- | --- |
| 01 | Rolling Update | [`01-rolling-update/`](01-rolling-update/README.md) | `strategy.type: RollingUpdate`, `maxSurge: 1`, `maxUnavailable: 0`; new ReplicaSet scaled up as old scaled down | none |
| 02 | Blue-Green | [`02-blue-green/`](02-blue-green/README.md) | two Deployments, Service selector `version: blue` patched to `green` (`switch-to-green.sh`) | none, instant cut-over |
| 03 | Canary | [`03-canary/`](03-canary/README.md) | 9 stable + 1 canary pods under one Service selector `app=web`, ~10% traffic | none |
| 04 | Recreate | [`04-recreate/`](04-recreate/README.md) | `strategy.type: Recreate`; all old pods Terminating before new ones are created | yes |

Spec bullets and where they are covered:

- 01 Rolling Update: create Deployment (Step 1), configure rolling update
  (Step 2), perform an application update (Step 3, `kubectl apply` of v2 /
  `kubectl set image`), verify old and new Pods (Step 4, `get pods -w`,
  `get rs`, `rollout history`).
- 02 Blue-Green: create Blue (Step 1), create Green (Step 2), switch traffic
  (Step 3, `kubectl patch svc`), verify active version (Step 4, wget loop and
  `get endpoints`).
- 03 Canary: deploy stable (Step 1), deploy canary (Step 2), route a small
  percentage (Step 3, shared selector, 1 of 10 endpoints), verify both
  versions (Step 4, `sort | uniq -c` distribution).
- 04 Recreate: deploy (Step 1), update (Step 2), observe old Pods terminated
  before new Pods created (Step 3, watch transcript + outage loop + empty
  endpoints).

Quick run of all four (after `kubectl apply -f namespace.yaml -f client-pod.yaml`):

```bash
for d in 01-rolling-update 02-blue-green 03-canary 04-recreate; do
  kubectl apply -f $d/
done
kubectl -n s10 get deploy,rs,svc
```

Output (captured 2026-10-08) (state after following each folder's README in turn)
```text
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web-blue       3/3     3            3           3h53m
deployment.apps/web-canary     3/3     3            3           12m
deployment.apps/web-green      3/3     3            3           3h52m
deployment.apps/web-recreate   3/3     3            3           11m
deployment.apps/web-rolling    4/4     4            4           3h56m
deployment.apps/web-stable     7/7     7            7           13m

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/web-blue-869698bf69       3         3         3       3h53m
replicaset.apps/web-canary-85c7d745c7     3         3         3       12m
replicaset.apps/web-green-5747479f5f      3         3         3       3h52m
replicaset.apps/web-recreate-55945577ff   0         0         0       9m44s
replicaset.apps/web-recreate-695c848bbf   3         3         3       11m
replicaset.apps/web-rolling-7b85bb48cf    4         4         4       3h56m
replicaset.apps/web-rolling-f66497d77     0         0         0       3h54m
replicaset.apps/web-stable-6d8bf949d5     7         7         7       13m

NAME                   TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/web            NodePort   10.43.50.79     <none>        80:30030/TCP   13m
service/web-bg         NodePort   10.43.62.29     <none>        80:30020/TCP   3h53m
service/web-recreate   NodePort   10.43.163.202   <none>        80:30040/TCP   11m
service/web-rolling    NodePort   10.43.34.175    <none>        80:30010/TCP   4h
```

(Applying a folder in one go applies both v1 and v2 of the same Deployment;
the last file wins, so `web-rolling` and `web-recreate` would end up on v2.
The listing above was taken after I had followed each folder's README step
by step instead, which is why `web-rolling` and `web-recreate` are back on
their v1 ReplicaSets after `rollout undo`, and the canary pair is at the 3:7
split from the last canary step.)

## Task 2: Pod Lifecycle

Folder: [`pod-lifecycle/`](pod-lifecycle/README.md). Twelve YAMLs adapted
into namespace `s10`, each covered in the README with: the apply command,
`kubectl get pod` expected status, `kubectl describe pod` key lines, and what
I observed.

| # | File | Demonstrates |
| --- | --- | --- |
| 01 | `01-running.yaml` | normal Running / Ready |
| 02 | `02-pending.yaml` | Pending, FailedScheduling (impossible requests) |
| 03 | `03-succeeded.yaml` | Succeeded / Completed (exit 0, Never) |
| 04 | `04-failed.yaml` | Failed / Error (exit 1, Never) |
| 05 | `05-crashloopbackoff.yaml` | CrashLoopBackOff, exponential backoff, `logs --previous` |
| 06 | `06-imagepullbackoff.yaml` | ErrImagePull -> ImagePullBackOff, phase Pending |
| 07 | `07-readiness.yaml` | readiness gating: Running but 0/1 |
| 08 | `08-liveness.yaml` | liveness failures restart the container, RESTARTS increments |
| 09 | `09-startup.yaml` | startup probe protects a slow starter from liveness |
| 10 | `10-init-container.yaml` | Init:0/1 -> PodInitializing -> Running ordering |
| 11 | `11-multi-container.yaml` | 2/2, shared network namespace, `logs -c` |
| 12 | `12-termination.yaml` | Terminating, preStop, SIGTERM trap, terminationGracePeriodSeconds |

Scripts: `pod-lifecycle/run-all.sh` applies each file with sleeps and prints
status, container state and events; `pod-lifecycle/cleanup.sh` deletes all
lab pods by label. I ran `run-all.sh` end to end (about 5 minutes, exit
code 0); its final listing was:

Output (captured 2026-10-08)
```text
== Final state of all lab pods
NAME                        READY   STATUS         RESTARTS       AGE
lifecycle-crashloop         0/1     Error          5 (2m3s ago)   3m55s
lifecycle-failed            0/1     Error          0              4m10s
lifecycle-image-error       0/1     ErrImagePull   0              3m9s
lifecycle-init              1/1     Running        0              53s
lifecycle-liveness          1/1     Running        2 (18s ago)    2m18s
lifecycle-multi-container   2/2     Running        0              34s
lifecycle-pending           0/1     Pending        0              4m31s
lifecycle-readiness         1/1     Running        0              2m38s
lifecycle-running           1/1     Running        0              4m41s
lifecycle-startup           1/1     Running        0              93s
lifecycle-succeeded         0/1     Completed      0              4m25s
```

(`lifecycle-crashloop` and `lifecycle-image-error` alternate between
`Error`/`CrashLoopBackOff` and `ErrImagePull`/`ImagePullBackOff` depending
on the instant you look; the per-file sections show both states.)

## Screenshots

Terminal output captured from the k3s cluster stands in for the screenshots
the spec asks for:

| Spec screenshot | Substitute block |
| --- | --- |
| Rolling update old/new pods | `01-rolling-update/README.md` Step 4 `kubectl get pods -w` transcript and `get rs` |
| Blue-Green active version | `02-blue-green/README.md` Steps 2–4 `get endpoints`, `uniq -c` outputs |
| Canary traffic split | `03-canary/README.md` Step 4 `sort | uniq -c` (20 and 100 requests) |
| Recreate termination order | `04-recreate/README.md` Step 3 watch transcript and `[OUTAGE]` loop |
| Pod status for each lifecycle YAML | `pod-lifecycle/README.md` sections 1–12, `kubectl get pod` blocks |
| Pod details for each lifecycle YAML | `pod-lifecycle/README.md` sections 1–12, `kubectl describe pod` key lines |

## Deliverables

- `namespace.yaml` – Namespace `s10` used by every manifest in this session.
- `client-pod.yaml` – busybox client Pod for in-cluster `wget`/`nslookup` tests.
- `01-rolling-update/` – `deployment-v1.yaml`, `deployment-v2.yaml`, `service.yaml`, `README.md` (RollingUpdate with maxSurge/maxUnavailable, rollout status/history/undo).
- `02-blue-green/` – `deployment-blue.yaml`, `deployment-green.yaml`, `service.yaml`, `switch-to-green.sh`, `switch-to-blue.sh`, `README.md` (selector switch and verification).
- `03-canary/` – `deployment-stable.yaml` (9), `deployment-canary.yaml` (1), `service.yaml`, `README.md` (10% split and distribution loop).
- `04-recreate/` – `deployment-v1.yaml`, `deployment-v2.yaml`, `service.yaml`, `README.md` (all old pods terminate before new ones start).
- `pod-lifecycle/` – 12 YAMLs `01-running.yaml` … `12-termination.yaml`, `README.md` (commands, expected output, explanations), `run-all.sh`, `cleanup.sh`.
- `README.md` – this file: session overview, pod-phase diagram, Task 1 and Task 2 index, screenshot substitutes.
