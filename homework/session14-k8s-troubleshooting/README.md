# Session 14 – Kubernetes Troubleshooting
Student: Om Malviya | Enrollment No: 24BCS10448

Everything in this folder runs in the namespace `s14` (`namespace.yaml`). I ran all of it on a single-node k3s cluster (`colima`, Kubernetes v1.35.0+k3s1, arm64, 4 CPU / 6 GB, metrics-server and Traefik included), so the terminal blocks are labelled **Output (captured 2026-10-08)** and trimmed where noted; the manifests and scripts also work on kind/minikube (`kubectl apply -f namespace.yaml` first). Pod IPs are `10.42.x.x` and Service IPs `10.43.x.x` because that is the k3s default.

```text
session14-k8s-troubleshooting/
  namespace.yaml
  01-commands/        Task 1 – every kubectl troubleshooting command with a demo Pod/Deployment
  02-issues/          Task 2 – nine broken/fixed scenarios + triage.sh health report
  mini-project/       Task 3 – the troubleshooting challenge (image problem + Service selector problem)
```

## Task 1: Kubernetes Commands

Hands-on practice of all troubleshooting commands, documented with captured output in [01-commands/README.md](01-commands/README.md):

* `kubectl get` (incl. `--show-labels`, `-l`, `-w`, `-o yaml`, `-o jsonpath`, `-o custom-columns`)
* `kubectl describe` (pod, deployment, service)
* `kubectl logs` (`-f`, `--previous`, `-c`, `--tail`, `--since`, `-l`)
* `kubectl exec` (interactive `sh`, one-shot commands, `-c`)
* `kubectl events` and `kubectl get events --sort-by=.lastTimestamp` / `--field-selector type=Warning`
* `kubectl explain pod.spec.containers` (and `--recursive`)
* `kubectl top` (nodes, pods, `--containers`, what happens without metrics-server)
* `kubectl get -o wide`

Demo manifests: `01-commands/pod.yaml` (two-container Pod) and `01-commands/deployment.yaml` (Deployment + Service).

## Task 2: Troubleshoot Common Issues

One folder per issue under [02-issues/](02-issues/README.md), each with `broken.yaml`, `fixed.yaml` and a README following the six steps **identify → investigate → root cause → fix → verify → document**, plus before/after output:

| Issue | Folder |
|---|---|
| CrashLoopBackOff | `02-issues/crashloopbackoff/` |
| ImagePullBackOff | `02-issues/imagepullbackoff/` |
| ErrImagePull | `02-issues/errimagepull/` |
| Pending | `02-issues/pending/` |
| ContainerCreating | `02-issues/containercreating/` |
| Service connectivity issues | `02-issues/service-connectivity/` |
| DNS issues | `02-issues/dns/` |
| Pod networking issues | `02-issues/pod-networking/` |
| Configuration issues | `02-issues/configuration/` |

`02-issues/triage.sh [namespace]` prints a quick health report (unhealthy Pods, waiting reasons, Services without endpoints, Warning events, nodes, CoreDNS) and can apply/fix/clean all scenarios at once (`--fix-all` falls back to `kubectl replace --force` for immutable Pod fields).

Things I had to change after running the scenarios for real: the ContainerCreating scenario now uses a missing ConfigMap + Secret (a missing PVC keeps the Pod `Pending`), the DNS client is `busybox:1.36` (the `dnsutils:1.3` image no longer exists), and the pod-networking README documents that k3s **does** enforce NetworkPolicy but rejects instead of dropping, so the symptom is `Connection refused`, not a timeout.

## Task 3: Mini Project

[mini-project/README.md](mini-project/README.md) implements the course challenge end to end: deploy nginx + Service, observe with get/describe/logs/exec, break it with a bad image tag and a wrong Service selector, investigate without touching YAML, find the root causes, fix, verify, and answer the project questions. Deliverables there: commands, problem statement, investigation steps, root cause, solution, before/after output, screenshot substitutes, README.

---

## Troubleshooting decision tree

```text
                              kubectl get pods -n <ns>
                                        │
          ┌───────────────┬─────────────┼──────────────┬────────────────────┐
          ▼               ▼             ▼              ▼                    ▼
       Pending     ContainerCreating  ErrImagePull  CrashLoopBackOff   Running 1/1
      NODE <none>    (stuck > 1 min)  ImagePullBackOff   / Error       but "not working"
          │               │             │              │                    │
   describe pod     describe pod   describe pod   logs --previous     describe svc
   -> Events        -> Events      -> Events      describe pod        get endpoints
   FailedScheduling FailedMount    Failed: pull   -> Last State            │
          │               │             │          Exit Code          ┌─────┴──────┐
   ┌──────┼──────┐   ┌────┴────┐   ┌────┴─────┐        │              ▼            ▼
   ▼      ▼      ▼   ▼         ▼   ▼          ▼   ┌────┼─────┐   Endpoints     Endpoints
Insuff. node   taint cm/secret PVC  "not     403/401  ▼    ▼     ▼   <none>        present
cpu/mem selector    missing  unbound found"  auth  exit1 137  probe   │            │
   │      │      │    │        │     │        │     │    OOM  Unhealthy│     ┌──────┴───────┐
 lower  label   add  create  create fix tag  add    │    │    │  labels !=   ▼              ▼
requests node  tolera- cm/   PVC/   /name  pullSecret app  raise fix  selector  "Connection   "timed out"
 /scale        tion  secret  SC            │        cfg  limit probe or not   refused"       │
 nodes                                     │        env       │     Ready       │        NetworkPolicy
                                           │     (logs!)      │                 │        CNI / firewall
                                           │                  │          targetPort !=
                                           │                  │          containerPort
                                           └──────────────────┴──────────────────────────────┐
                                                                                             ▼
                     CreateContainerConfigError ──► describe pod -> "couldn't find key"   FIX -> VERIFY
                                                   -> add ConfigMap key / create Secret

   Name does not resolve ("bad address", NXDOMAIN)
        └─► nslookup <svc> / <svc>.<ns>   -> wrong name or namespace?
            nslookup kubernetes.default  -> fails? check CoreDNS pods + logs in kube-system
```

## One-page cheat sheet

| Symptom (`kubectl get pods`) | First command | What to look for | Typical root cause | Typical fix |
|---|---|---|---|---|
| `Pending`, NODE `<none>` | `kubectl describe pod` | `FailedScheduling: Insufficient cpu/memory`, `didn't match ... selector`, `untolerated taint`, `persistentvolumeclaim "x" not found` / `unbound PersistentVolumeClaims` | requests too big, nodeSelector/affinity, taints, PVC | lower requests / add nodes, fix selector or label node, add toleration, create PVC/StorageClass |
| `ContainerCreating` for > 1 min | `kubectl describe pod` | `FailedMount ... configmap/secret "x" not found`, `FailedCreatePodSandBox` (CNI) | ConfigMap/Secret volume missing, CNI down | create ConfigMap/Secret, check CNI pods (a missing/unbound PVC shows as `Pending` instead) |
| `ErrImagePull` / `ImagePullBackOff` | `kubectl describe pod` (Events) | `not found`, `401/403`, `toomanyrequests`, `no match for platform` | wrong name/tag, private registry, rate limit, arch | fix name/tag, `imagePullSecrets`, mirror, multi-arch image |
| `CreateContainerConfigError` | `kubectl describe pod` | `couldn't find key X in ConfigMap`, `secret "x" not found` | env `valueFrom` points at missing key/object | add key / create Secret |
| `CrashLoopBackOff` / `Error` | `kubectl logs --previous` | app error message; `describe`: `Exit Code`, `Reason: OOMKilled`, `Unhealthy` probe events | missing config/env, bad command, OOM (137), failing liveness probe | fix config/command, raise memory limit, fix probe |
| `Running` but `0/1` READY | `kubectl describe pod` | `Readiness probe failed` events | wrong probe path/port, app slow to start | fix probe, add `initialDelaySeconds` |
| Service: `Connection refused` | `kubectl get endpoints <svc>` | `<none>` → `describe svc` Selector vs `get pods --show-labels` | selector mismatch, or `targetPort` != listening port | fix selector / `targetPort` (`netstat -tlnp` in pod) |
| Service: `timed out` (or `Connection refused` on the right port, e.g. k3s) | `kubectl get networkpolicy` | default-deny policy, CNI/firewall | NetworkPolicy blocks ingress/egress | add allow policy (CNI must support NetworkPolicy) |
| `bad address` / `NXDOMAIN` | `kubectl exec <pod> -- nslookup <svc>` | short name vs `<svc>.<ns>.svc.cluster.local`; `kubernetes.default` must resolve | wrong Service name/namespace; CoreDNS down | fix name/namespace; `kubectl get pods -n kube-system -l k8s-app=kube-dns`, CoreDNS logs |
| Anything, no idea yet | `kubectl get events -n <ns> --field-selector type=Warning --sort-by=.lastTimestamp` | newest Warning at the bottom | – | follow the Warning |
| Node/pod resource usage | `kubectl top nodes` / `kubectl top pods --containers` | CPU/memory near limits | OOM / CPU throttling | adjust requests/limits (needs metrics-server) |

Golden order: **GET → DESCRIBE → EVENTS → LOGS → EXEC → TEST → FIX → VERIFY**.

## Screenshots

Every screenshot the spec asks for is replaced by a captured terminal-output block:

| Screenshot | Where |
|---|---|
| Each kubectl command output (Task 1) | `01-commands/README.md`, one block per command |
| Before/after of each issue (Task 2) | `02-issues/<issue>/README.md`, sections 1 and 5 |
| triage report | `02-issues/README.md` |
| Mini project before/after | `mini-project/README.md`, sections 1-9 and the Screenshots table there |

## Deliverables

* `namespace.yaml` – the `s14` namespace used by everything.
* `01-commands/README.md` + `pod.yaml` + `deployment.yaml` – Task 1 commands with captured output.
* `02-issues/README.md`, `02-issues/triage.sh`, nine `<issue>/{broken.yaml,fixed.yaml,README.md}` – Task 2.
* `mini-project/README.md` + manifests + `run.sh` – Task 3 mini project.
* This `README.md` – task overview, decision tree, cheat sheet, screenshot map.
