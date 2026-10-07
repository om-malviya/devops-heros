# Session 13 – Kubernetes Storage, HPA & Probes

Student: Om Malviya | Enrollment No: 24BCS10448

Parts 01-03 live in namespace `s13`; the mini project uses the namespace the course defines,
`production-webapp`. Target cluster is k3s (default StorageClass `local-path`, metrics-server bundled);
minikube differences (`standard` StorageClass, `minikube addons enable metrics-server`) are noted in
each part. I ran everything on a single-node k3s v1.35 cluster (4 CPU / 6 GB Colima VM on macOS,
node `colima`, shared with other namespaces), so every cluster output is labelled
`Output (captured <date>)`; the only remaining `Expected output` block is the minikube StorageClass
listing in part 01, which I could not run because I only had k3s.

```text
session13-storage-hpa-probes/
├── namespace.yaml               # Namespace s13
├── deploy-all.sh / cleanup.sh   # everything below, in order
├── 01-kubernetes-volumes/       # Task 1: README.md + emptyDir / hostPath / PV / PVC / StorageClass examples
├── 02-hpa/                      # Task 2: deployment, service, hpa.yaml, load-generator.yaml, load_generator.sh, README.md
├── 03-probes/                   # liveness / readiness / startup examples + README.md
└── mini-project/                # Task 3: namespace, pvc, deployment, service, hpa, load-generator, scripts, README.md
```

Quick start:

```bash
./deploy-all.sh
./02-hpa/load_generator.sh          # then: kubectl get hpa -n s13 -w
./02-hpa/load_generator.sh --stop
./cleanup.sh
```

For the captures I applied the manifests step by step as each part's README describes (so that the
intermediate states such as `PV Available` and `PVC Pending` could be shown) instead of running
`deploy-all.sh`; `cleanup.sh` was run at the end (see Cleanup below).

## Task 1: Kubernetes Volumes

`01-kubernetes-volumes/README.md` documents, each with a runnable YAML next to it and expected output:

- **emptyDir** – `emptydir-pod.yaml`: a writer container and an nginx container share `/data`; the
  directory disappears with the Pod.
- **hostPath** – `hostpath-pod.yaml`: node directory `/tmp/s13-hostpath-data`; survives Pod deletion
  but is tied to the node.
- **PersistentVolume** – `pv.yaml`: static, hostPath-backed, 1Gi, RWO, `Retain`.
- **PersistentVolumeClaim** – `pvc-static.yaml` + `pod-static-pvc.yaml`: claim binds to the PV,
  data survives `kubectl delete pod`.
- **StorageClass** – `kubectl get/describe storageclass` on k3s (`local-path`) and minikube (`standard`);
  provisioner, reclaim policy, binding mode, default class.
- **Dynamic provisioning** – `pvc-dynamic.yaml` + `pod-dynamic-pvc.yaml`: no PV written by hand, the
  provisioner creates `pvc-...`; `WaitForFirstConsumer` behaviour explained.
- Plus access modes, reclaim policies and the PV/PVC binding lifecycle.

```bash
kubectl get pv
kubectl get pvc -n s13
```

Output (captured 2026-10-07):

```text
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM             STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-d50c9a25-c120-45e1-824a-ea8e6c73c5f9   500Mi      RWO            Delete           Bound    s13/dynamic-pvc   local-path     <unset>                          2s
s13-static-pv                              1Gi        RWO            Retain           Bound    s13/static-pvc    manual         <unset>                          44s
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
dynamic-pvc   Bound    pvc-d50c9a25-c120-45e1-824a-ea8e6c73c5f9   500Mi      RWO            local-path     <unset>                 7s
static-pvc    Bound    s13-static-pv                              1Gi        RWO            manual         <unset>                 44s
```

Both binding styles worked: the static PV was `Available` until the claim appeared and the dynamic PV
was created by `rancher.io/local-path` only when the first Pod was scheduled (`WaitForFirstConsumer`).

## Task 2: HPA Hands-on

`02-hpa/README.md` performs the nine steps with `hpa.yaml` (autoscaling/v2, 50% CPU, 1-5 replicas):

1. Deploy the application – `deployment.yaml` (CPU-burning python:3.12-alpine server with
   `resources.requests.cpu: 100m`; `registry.k8s.io/hpa-example` avoided because it is amd64-only) + `service.yaml`.
2. Configure HPA – `kubectl apply -f hpa.yaml`.
3. Verify HPA – `kubectl get hpa`, `kubectl describe hpa` (`ScalingActive True / ValidMetricFound`).
4. Deploy a load generator – `load_generator.sh` / `load-generator.yaml` (busybox wget loop).
5. Increase application load – `./load_generator.sh 6` (not needed: 3 loops already gave ~300 %).
6. Observe CPU utilization – `kubectl top pods`, `kubectl get hpa -w`.
7. Observe Pod scaling – `kubectl get pods` 1 -> 5 in one step, `describe hpa` events `SuccessfulRescale`.
8. Capture the output – scale-up and scale-down traces.
9. Output in README – Steps 3, 6, 7, 8 of `02-hpa/README.md`.

```bash
kubectl get hpa -n s13 -w
```

Output (captured 2026-10-08, condensed from the two watches in `02-hpa/README.md`; the HPA object was
a few hours old by then, hence the AGE column):

```text
NAME          REFERENCE            TARGETS         MINPODS   MAXPODS   REPLICAS   AGE
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         1          3h36m
cpu-app-hpa   Deployment/cpu-app   cpu: 283%/50%   1         5         1          3h36m      <- load started
cpu-app-hpa   Deployment/cpu-app   cpu: 499%/50%   1         5         5          3h36m      <- 1 -> 5 in one step
cpu-app-hpa   Deployment/cpu-app   cpu: 309%/50%   1         5         5          3h37m
cpu-app-hpa   Deployment/cpu-app   cpu: 293%/50%   1         5         5          3h39m      <- load stopped
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         5          3h40m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         4          3h41m      <- after the 60 s window
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         3          3h41m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         2          3h42m
cpu-app-hpa   Deployment/cpu-app   cpu: 3%/50%     1         5         1          3h42m
```

```bash
kubectl top pods -n s13 -l app=cpu-app
```

Output (captured 2026-10-08, under load after the scale-out):

```text
NAME                       CPU(cores)   MEMORY(bytes)
cpu-app-55f8dd8876-bqslx   296m         11Mi
cpu-app-55f8dd8876-dq5jc   337m         11Mi
cpu-app-55f8dd8876-mvfgk   296m         11Mi
cpu-app-55f8dd8876-pbqfj   263m         11Mi
cpu-app-55f8dd8876-t9w9f   276m         11Mi
```

Probes (`03-probes/`) are included because they are part of the session: liveness restarts (I watched
`RESTARTS` go 0 -> 1 -> 2 -> 3 every ~20 s with a wrong path), readiness removes the Pod from the
Service endpoints without restarting it (`READY 0/1`, `ENDPOINTS` empty), startup protects slow
starters; see `03-probes/README.md`.

## Task 3: Mini Project

`mini-project/` implements the course mini project exactly as specified (namespace
`production-webapp`, PVC `web-data` 500Mi RWO, Deployment `web-app` with 2 replicas, three probes,
requests/limits and `/data` mount, Service `web-service`, HPA `web-app-hpa` 2-5 at 50% CPU) and
`mini-project/README.md` documents deploy, the three verification tasks (persistence across Pod
deletion, Service via port-forward, HPA scale-out/scale-in), troubleshooting and the bonus challenges.
One change came out of running it: 4 `wget` loops only pushed static nginx to ~47 % of its 100m
request, just under the target, so `load-generator.yaml` now uses 8 replicas.

```bash
./mini-project/deploy.sh
kubectl get pvc,pods,svc,hpa -n production-webapp
```

Output (captured 2026-10-08, the `kubectl get` printed by `deploy.sh`; the HPA line was taken a minute
later once metrics had arrived):

```text
namespace/production-webapp created
persistentvolumeclaim/web-data created
deployment.apps/web-app created
service/web-service created
deployment "web-app" successfully rolled out
horizontalpodautoscaler.autoscaling/web-app-hpa created

NAME                             STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/web-data   Bound    pvc-372be0b5-d22b-4285-9353-5d0867d135bb   500Mi      RWO            local-path     <unset>                 16s

NAME                          READY   STATUS    RESTARTS   AGE
pod/web-app-d69479c4c-742wl   1/1     Running   0          14s
pod/web-app-d69479c4c-lj2xm   1/1     Running   0          13s

NAME                  TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/web-service   ClusterIP   10.43.48.237   <none>        80/TCP    14s

NAME                                              REFERENCE            TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/web-app-hpa   Deployment/web-app   cpu: 1%/50%   2         5         2          2m45s
```

Persistence (`/data/student.txt` survived a Pod deletion), the Service (`port-forward` + `curl`
returned the nginx welcome page) and the HPA (2 -> 4 under load, back to 2 after the 5-minute
stabilization window) are all captured in `mini-project/README.md`.

## Screenshots

| Screenshot required for | Stand-in |
| --- | --- |
| Volume behaviour | `01-kubernetes-volumes/README.md` sections 1-8 (`get pv/pvc`, `exec cat` before/after Pod deletion) |
| HPA output | `02-hpa/README.md` Steps 3, 6, 7, 8 (`get hpa -w`, `top pods`, `describe hpa`, `get pods`) |
| Mini project | `mini-project/README.md` Deploy 5.1-5.4 and Verification Tasks 1-3 |

## Cleanup

```bash
./cleanup.sh
kubectl get namespace s13 production-webapp
kubectl get pv
```

Output (captured 2026-10-08):

```text
horizontalpodautoscaler.autoscaling "web-app-hpa" deleted from production-webapp namespace
service "web-service" deleted from production-webapp namespace
deployment.apps "web-app" deleted from production-webapp namespace
persistentvolumeclaim "web-data" deleted from production-webapp namespace
namespace "production-webapp" deleted
Done.
pod "liveness-demo" deleted from s13 namespace
pod "readiness-demo" deleted from s13 namespace
service "readiness-service" deleted from s13 namespace
pod "startup-demo" deleted from s13 namespace
horizontalpodautoscaler.autoscaling "cpu-app-hpa" deleted from s13 namespace
service "cpu-app" deleted from s13 namespace
deployment.apps "cpu-app" deleted from s13 namespace
pod "dynamic-pvc-demo" deleted from s13 namespace
persistentvolumeclaim "dynamic-pvc" deleted from s13 namespace
pod "hostpath-demo" deleted from s13 namespace
pod "emptydir-demo" deleted from s13 namespace
namespace "s13" deleted
persistentvolume "s13-static-pv" deleted
Done. hostPath data left on the node under /tmp/s13-hostpath-data and /tmp/s13-static-pv (remove by hand if needed).
Error from server (NotFound): namespaces "s13" not found
Error from server (NotFound): namespaces "production-webapp" not found
No resources found
```

(`static-pvc` and `static-pvc-demo` do not appear because I had already deleted them in part 01
section 8 to demonstrate the `Retain` policy; `cleanup.sh` uses `--ignore-not-found`.)

## Deliverables

- Volume documentation – `01-kubernetes-volumes/README.md` + example YAMLs.
- HPA YAML – `02-hpa/hpa.yaml` (+ `deployment.yaml`, `service.yaml`).
- Load generator – `02-hpa/load-generator.yaml`, `02-hpa/load_generator.sh`.
- HPA output – `02-hpa/README.md` Steps 3-8.
- Screenshots – output blocks listed above.
- Mini-project implementation – `mini-project/` manifests, scripts and README.
- README documentation – this file plus the per-part READMEs; `deploy-all.sh`, `cleanup.sh`, `namespace.yaml`.
