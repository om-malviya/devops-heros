# Task 2: Troubleshoot Common Issues

Student: Om Malviya | Enrollment No: 24BCS10448

One folder per issue. Every folder contains `broken.yaml`, `fixed.yaml` and a `README.md` that follows the same six steps from the spec: **identify, investigate, root cause, fix, verify, document**, with captured before/after output from a single-node k3s cluster (Kubernetes v1.35, arm64).

| # | Folder | Pod status / symptom | Root cause practised |
|---|---|---|---|
| 1 | [crashloopbackoff/](crashloopbackoff/README.md) | `CrashLoopBackOff` / `Error`, restarts growing | app exits 1 because env var missing |
| 2 | [imagepullbackoff/](imagepullbackoff/README.md) | `ImagePullBackOff` | image tag does not exist |
| 3 | [errimagepull/](errimagepull/README.md) | `ErrImagePull` | private registry, no `imagePullSecrets` |
| 4 | [pending/](pending/README.md) | `Pending`, `NODE <none>` | requests too large, nodeSelector mismatch |
| 5 | [containercreating/](containercreating/README.md) | stuck `ContainerCreating` | missing ConfigMap + Secret volumes (a missing PVC gives `Pending` instead, documented there) |
| 6 | [service-connectivity/](service-connectivity/README.md) | Service `Connection refused`, `Endpoints: <none>` | selector != pod labels |
| 7 | [dns/](dns/README.md) | `bad address`, `NXDOMAIN` | wrong Service name / namespace, CoreDNS check |
| 8 | [pod-networking/](pod-networking/README.md) | `Connection refused` (k3s rejects; `timed out` on dropping CNIs) | wrong `targetPort`, NetworkPolicy deny |
| 9 | [configuration/](configuration/README.md) | `CreateContainerConfigError` | missing ConfigMap key / Secret |

All manifests use namespace `s14` (`kubectl apply -f ../namespace.yaml` first). Things I changed after running them for real:

* `containercreating/`: the missing-PVC variant never reached `ContainerCreating` (scheduler blocks it as `Pending`), so the scenario now uses a missing ConfigMap and a missing Secret; its ConfigMap is called `cc-config` so it does not collide with `configuration/`'s `app-config` when all fixes are applied together.
* `dns/`: the `dnsutils:1.3` test image no longer exists on `registry.k8s.io`; the client is `busybox:1.36`.
* Pods are almost completely immutable, so for every fix that changes `env`, `args`, `resources`, `nodeSelector` or `volumes` the READMEs use delete + apply (or `kubectl replace --force`); only the image tag (`imagepullbackoff`), the Service selector and the referenced ConfigMap/Secret objects could be fixed with a plain `kubectl apply`.

## triage.sh – quick health report

I adapted the course's `scenarios/triage_all.sh` (which only applied the broken Pods) into a script that prints a health report for a namespace: unhealthy Pods, waiting reasons and exit codes, Services without endpoints, unbound PVCs, NetworkPolicies, the last Warning events, node status and CoreDNS.

```bash
./triage.sh                 # report for namespace s14
./triage.sh s14 --apply-all # deploy every broken.yaml first, then report
./triage.sh s14 --fix-all   # apply every fixed.yaml (replace --force where a Pod field is immutable), then report
./triage.sh s14 --clean     # remove everything again
```

### `--apply-all`

Output (captured 2026-10-08; the apply lines, then the report ~80 s later, trimmed)

```text
==================================================================
  Deploying all broken scenarios into namespace s14
==================================================================
--> .../02-issues/configuration/broken.yaml
configmap/app-config created
pod/config-demo created
--> .../02-issues/containercreating/broken.yaml
pod/cc-demo created
--> .../02-issues/crashloopbackoff/broken.yaml
pod/crash-demo created
--> .../02-issues/dns/broken.yaml
deployment.apps/api created
service/api-svc created
pod/dns-client created
--> .../02-issues/errimagepull/broken.yaml
pod/registry-demo created
--> .../02-issues/imagepullbackoff/broken.yaml
pod/image-demo created
--> .../02-issues/pending/broken.yaml
pod/pending-cpu created
pod/pending-selector created
--> .../02-issues/pod-networking/broken.yaml
deployment.apps/echo created
service/echo-svc created
networkpolicy.networking.k8s.io/deny-all-ingress created
pod/net-client created
--> .../02-issues/service-connectivity/broken.yaml
deployment.apps/web created
service/web-svc created
pod/client created
Sleeping 20s so the states can settle...

==================================================================
  TRIAGE REPORT  namespace=s14  2026-10-08 02:53:54
==================================================================

==================================================================
  1. Pods that are not Running/Succeeded
==================================================================
NAME               READY   STATUS                       RESTARTS   AGE
cc-demo            0/1     ContainerCreating            0          81s
config-demo        0/1     CreateContainerConfigError   0          81s
image-demo         0/1     ImagePullBackOff             0          80s
pending-cpu        0/1     Pending                      0          80s
pending-selector   0/1     Pending                      0          80s
registry-demo      0/1     ImagePullBackOff             0          81s

==================================================================
  2. Container waiting reasons (CrashLoopBackOff, ImagePullBackOff, ...)
==================================================================
NAME                   READY    RESTARTS   WAITING                      LAST_EXIT
cc-demo                false    0          ContainerCreating            <none>
config-demo            false    0          CreateContainerConfigError   <none>
crash-demo             false    4          <none>                       1
image-demo             false    0          ImagePullBackOff             <none>
registry-demo          false    0          ImagePullBackOff             <none>

==================================================================
  3. Services with no endpoints
==================================================================
SERVICE    ENDPOINTS
web-svc    <none>

==================================================================
  4. PersistentVolumeClaims not Bound
==================================================================

==================================================================
  5. NetworkPolicies in the namespace
==================================================================
NAME               POD-SELECTOR   AGE
deny-all-ingress   <none>         81s

==================================================================
  6. Last 20 Warning events
==================================================================
42s         Warning   Failed             pod/registry-demo      Failed to pull image "ghcr.io/om-malviya-example/private-api:1.0.0": ... 403 Forbidden
42s         Warning   Failed             pod/registry-demo      Error: ErrImagePull
36s         Warning   Failed             pod/image-demo         Error: ErrImagePull
36s         Warning   Failed             pod/image-demo         Failed to pull image "nginx:this-tag-does-not-exist": ... not found
18s         Warning   FailedMount        pod/cc-demo            MountVolume.SetUp failed for volume "config" : configmap "cc-config-missing" not found
18s         Warning   FailedMount        pod/cc-demo            MountVolume.SetUp failed for volume "creds" : secret "cc-secret-missing" not found
10s         Warning   Failed             pod/config-demo        Error: couldn't find key DB_PORT in ConfigMap s14/app-config
6s          Warning   Failed             pod/image-demo         Error: ImagePullBackOff
2s          Warning   Failed             pod/registry-demo      Error: ImagePullBackOff
1s          Warning   BackOff            pod/crash-demo         Back-off restarting failed container app in pod crash-demo_s14(20484889-...)

==================================================================
  7. Node status
==================================================================
NAME     STATUS   ROLES           AGE     VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
colima   Ready    control-plane   4h20m   v1.35.0+k3s1   192.168.5.1   <none>        Ubuntu 24.04.4 LTS   6.8.0-117-generic   containerd://2.1.5-k3s1
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
colima   1221m        30%      3656Mi          61%

==================================================================
  8. CoreDNS
==================================================================
NAME                       READY   STATUS    RESTARTS   AGE
coredns-54bf7cdff9-hwhc7   1/1     Running   0          4h20m

==================================================================
Next step for anything listed above: kubectl describe pod <name> -n s14  ->  Events
==================================================================
```

What I noticed in the report:

* `crash-demo` is missing from section 1 because its phase is `Running` (the container exists, it just keeps dying). Section 2 catches it through `RESTARTS=4` and `LAST_EXIT=1`; at that instant its state was `Terminated` rather than `Waiting`, hence `WAITING=<none>`. Both sections are needed.
* The `FailedScheduling` events of the two Pending Pods are older than the 20 newest Warnings (the scheduler only re-logs them every few minutes), so they were not in the tail of section 6 - section 1 is where Pending shows up.
* Section 6 also contained ~10 older Warning lines from my earlier manual runs of the same scenarios (events live for an hour); I trimmed those.

### `--fix-all`

Output (captured 2026-10-08, trimmed - the interesting part is the fallback)

```text
--> .../02-issues/configuration/fixed.yaml
configmap/app-config configured
secret/app-secret created
pod/config-demo unchanged
--> .../02-issues/containercreating/fixed.yaml
configmap/cc-config created
secret/cc-secret created
The Pod "cc-demo" is invalid: spec: Forbidden: pod updates may not change fields other than `spec.containers[*].image`, ...
    apply rejected (immutable Pod field) -> kubectl replace --force
configmap "cc-config" deleted from s14 namespace
secret "cc-secret" deleted from s14 namespace
pod "cc-demo" deleted from s14 namespace
configmap/cc-config replaced
secret/cc-secret replaced
pod/cc-demo replaced
--> .../02-issues/crashloopbackoff/fixed.yaml
The Pod "crash-demo" is invalid: ...
    apply rejected (immutable Pod field) -> kubectl replace --force
pod "crash-demo" deleted from s14 namespace
pod/crash-demo replaced
--> .../02-issues/dns/fixed.yaml
    apply rejected (immutable Pod field) -> kubectl replace --force
deployment.apps/api replaced
service/api-svc replaced
pod/dns-client replaced
--> .../02-issues/errimagepull/fixed.yaml
    apply rejected (immutable Pod field) -> kubectl replace --force
pod/registry-demo replaced
--> .../02-issues/imagepullbackoff/fixed.yaml
pod/image-demo configured
--> .../02-issues/pending/fixed.yaml
    apply rejected (immutable Pod field) -> kubectl replace --force
pod/pending-cpu replaced
pod/pending-selector replaced
--> .../02-issues/pod-networking/fixed.yaml
deployment.apps/echo configured
service/echo-svc configured
networkpolicy.networking.k8s.io/deny-all-ingress unchanged
networkpolicy.networking.k8s.io/allow-client-to-echo created
pod/net-client unchanged
--> .../02-issues/service-connectivity/fixed.yaml
deployment.apps/web unchanged
service/web-svc configured
pod/client unchanged
Sleeping 20s so the states can settle...
```

The first version of the script only ran `kubectl apply`, which aborted on the first immutable Pod (`set -e`). The fallback to `kubectl replace --force` is what made `--fix-all` work end to end. The report afterwards:

```text
==================================================================
  TRIAGE REPORT  namespace=s14  2026-10-08 02:55:34
==================================================================

==================================================================
  1. Pods that are not Running/Succeeded
==================================================================

==================================================================
  2. Container waiting reasons (CrashLoopBackOff, ImagePullBackOff, ...)
==================================================================
NAME                    READY   RESTARTS   WAITING   LAST_EXIT

==================================================================
  3. Services with no endpoints
==================================================================
SERVICE    ENDPOINTS

==================================================================
  4. PersistentVolumeClaims not Bound
==================================================================

==================================================================
  5. NetworkPolicies in the namespace
==================================================================
NAME                   POD-SELECTOR   AGE
allow-client-to-echo   app=echo       61s
deny-all-ingress       <none>         3m
(sections 6-8 as before: only stale Warnings older than the fix, node Ready, CoreDNS Running)
```

Sections 1, 2 and 3 are empty: every Pod is Running and every Service has endpoints.

### `--clean`

```text
==================================================================
  Deleting all scenario resources from namespace s14
==================================================================
done
```

## Deliverables

* `<issue>/broken.yaml`, `<issue>/fixed.yaml`, `<issue>/README.md` for the nine issues listed above.
* `triage.sh` – namespace health report with `--apply-all`, `--fix-all`, `--clean` helpers.
