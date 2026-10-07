# Session 09 – Kubernetes Fundamentals
Student: Om Malviya | Enrollment No: 24BCS10448

Resources from `session9-k8s/Readme.md`: the Kubernetes Basics tutorial
(kubernetes.io/docs/tutorials/kubernetes-basics/), the minikube macOS arm64 install guide
(minikube.sigs.k8s.io/docs/start/), the architecture concepts page
(kubernetes.io/docs/concepts/architecture/) and github.com/Nency-Ravaliya/Kubernetes.

Honesty note on the cluster used: minikube is the documented install path (Task 1) and I kept its
commands, but on this laptop the cluster that was actually available is **k3s** (v1.35.0+k3s1)
running inside the Colima VM (Ubuntu 24.04, single arm64 node, kubectl context `colima`). Every
`kubectl` block below was really executed against that cluster, in its own namespace `s09`, and is
labelled `Output (captured 2026-10-07)` or `Output (captured 2026-10-08)`. Only the minikube-specific
commands (`brew install minikube`, `minikube start/status`, `minikube service --url`) are left as
`Expected output` from the minikube docs. The tutorial images `gcr.io/google-samples/kubernetes-bootcamp:v1`
and `jocatalin/kubernetes-bootcamp:v2` are amd64-only; they still ran on this arm64 node because the
VM has qemu-user binfmt emulation (`kubectl exec … -- uname -m` printed `x86_64`, see Module 3), so I did
not have to swap the image. `kubernetes-basics/commands.sh` replays all six modules on minikube or on
any other cluster (`NAMESPACE=s09 ./commands.sh`).

## Task 1: Install and configure Minikube

Target machine: macOS 26 on Apple Silicon (arm64). minikube needs a driver; Docker Desktop (or
Colima) is the simplest. Alternatives on arm64 are `--driver=vfkit` or `--driver=qemu`.

```bash
# 1. Install the binaries with Homebrew (arm64 builds)
brew install minikube kubectl

# 2. Make sure a container runtime is running (Docker Desktop, or: colima start)
docker version --format '{{.Server.Version}}'

# 3. Start a single-node cluster
minikube start --driver=docker

# 4. Make docker the default driver for next time
minikube config set driver docker

# 5. Versions
minikube version
kubectl version --client
```

```text
Expected output (minikube path; not run here, see the honesty note above)
==> Downloading https://ghcr.io/v2/homebrew/core/minikube/manifests/1.36.0
==> Pouring minikube--1.36.0.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/minikube/1.36.0: 10 files, 125MB
==> Pouring kubectl--1.33.1.arm64_sequoia.bottle.tar.gz
🍺  /opt/homebrew/Cellar/kubernetes-cli/1.33.1: 230 files, 59MB

28.1.1

😄  minikube v1.36.0 on Darwin 26.2 (arm64)
✨  Using the docker driver based on user configuration
📌  Using Docker Desktop driver with root privileges
👍  Starting "minikube" primary control-plane node in "minikube" cluster
🚜  Pulling base image v0.0.47 ...
🔥  Creating docker container (CPUs=2, Memory=4000MB) ...
🐳  Preparing Kubernetes v1.33.1 on Docker 28.1.1 ...
    ▪ Generating certificates and keys ...
    ▪ Booting up control plane ...
    ▪ Configuring RBAC rules ...
🔗  Configuring bridge CNI (Container Networking Interface) ...
🔎  Verifying Kubernetes components...
    ▪ Using image gcr.io/k8s-minikube/storage-provisioner:v5
🌟  Enabled addons: storage-provisioner, default_storageclass
🏄  Done! kubectl is now configured to use "minikube" cluster and "default" namespace by default

❗  These changes will take effect upon a minikube delete and then a minikube start
minikube version: v1.36.0
commit: f8f52f5de11fc6ad8244afec475fbe373a7f85cc

Client Version: v1.33.1
Kustomize Version: v5.6.0
```

What `minikube start` does: it creates one Docker container that acts as both control-plane and
worker node, bootstraps Kubernetes inside it with kubeadm, and writes the credentials into
`~/.kube/config` (context `minikube`) so `kubectl` talks to it.

What I actually have on this laptop is the equivalent single-node setup built by Colima: the
`colima start --kubernetes` flag installs k3s (a packaged Kubernetes distribution) inside the Colima
VM and writes a `colima` context into `~/.kube/config`. The `kubectl` client itself is the same
Homebrew binary:

```bash
kubectl version
kubectl config current-context
```

```text
Output (captured 2026-10-07)
Client Version: v1.37.1
Kustomize Version: v5.8.1
Server Version: v1.35.0+k3s1
Warning: version difference between client (1.37) and server (1.35) exceeds the supported minor version skew of +/-1

colima
```

The warning is kubectl's version-skew policy (client may be at most one minor version away from the
server); the two-minor gap did not break any command in this homework, but on a real cluster I would
pin `kubectl` to the server's minor version.

## Task 2: Verify Kubernetes cluster status

```bash
minikube status                       # minikube only; on k3s/Colima: colima status
kubectl cluster-info
kubectl get nodes -o wide
kubectl get pods -A
kubectl config current-context
```

```text
Expected output (minikube status only)
minikube
type: Control Plane
host: Running
kubelet: Running
apiserver: Running
kubeconfig: Configured
```

```text
Output (captured 2026-10-07)
$ kubectl cluster-info
Kubernetes control plane is running at https://127.0.0.1:58106
CoreDNS is running at https://127.0.0.1:58106/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
Metrics-server is running at https://127.0.0.1:58106/api/v1/namespaces/kube-system/services/https:metrics-server:https/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.

$ kubectl get nodes -o wide
NAME     STATUS   ROLES           AGE   VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
colima   Ready    control-plane   11m   v1.35.0+k3s1   192.168.5.1   <none>        Ubuntu 24.04.4 LTS   6.8.0-117-generic   containerd://2.1.5-k3s1

$ kubectl get pods -A
NAMESPACE     NAME                                      READY   STATUS      RESTARTS   AGE
kube-system   coredns-54bf7cdff9-hwhc7                  1/1     Running     0          11m
kube-system   helm-install-traefik-crd-vqpxz            0/1     Completed   0          11m
kube-system   helm-install-traefik-xkv2q                0/1     Completed   1          11m
kube-system   local-path-provisioner-69879d7dd7-z25wt   1/1     Running     0          11m
kube-system   metrics-server-77dbbf84b-4ptqq            1/1     Running     0          11m
kube-system   svclb-traefik-5d031198-66nzq              2/2     Running     0          10m
kube-system   svclb-web-loadbalancer-02f32f56-d9z7d     0/1     Pending     0          3m15s
kube-system   traefik-6d98778dfc-8gsvf                  1/1     Running     0          10m
s10           client                                    1/1     Running     0          4m6s
s10           web-rolling-f66497d77-c7v6z               1/1     Running     0          100s
s10           web-rolling-f66497d77-n9btg               1/1     Running     0          109s
s10           web-rolling-f66497d77-rkrs8               1/1     Running     0          97s
s10           web-rolling-f66497d77-xjm88               1/1     Running     0          105s
s11           client                                    1/1     Running     0          3m15s
s11           web-0                                     1/1     Running     0          3m15s
s11           web-1                                     1/1     Running     0          74s
s11           web-2                                     1/1     Running     0          2m44s
s11           web-clusterip-5df8dbbc74-8sjr8            1/1     Running     0          3m15s
s11           web-clusterip-5df8dbbc74-nqhkj            1/1     Running     0          3m15s
s11           web-clusterip-5df8dbbc74-vhvf7            1/1     Running     0          3m15s
s11           web-loadbalancer-68c75c5766-lztcx         1/1     Running     0          3m15s
s11           web-loadbalancer-68c75c5766-w6nbm         1/1     Running     0          3m15s
s11           web-loadbalancer-68c75c5766-xnpvp         1/1     Running     0          3m15s
s11           web-nodeport-59b6887c46-jtqzf             1/1     Running     0          3m15s
s11           web-nodeport-59b6887c46-m585t             1/1     Running     0          3m15s
s12           app1-66fbc7fcf5-fz74c                     1/1     Running     0          3m23s
s12           app1-66fbc7fcf5-lzjf2                     1/1     Running     0          3m23s
s12           app2-55f795fcd7-fwgkj                     1/1     Running     0          3m22s
s12           app2-55f795fcd7-kjmkm                     1/1     Running     0          3m22s
s12           configmap-demo                            1/1     Running     0          3m23s
s12           secret-demo                               1/1     Running     0          3m23s
s12           ts-configmap-pod                          1/1     Running     0          77s
s12           ts-secret-pod                             1/1     Running     0          78s
s14           cmd-demo                                  2/2     Running     0          21s
s14           cmd-web-5469cf8c57-blrts                  1/1     Running     0          21s
s14           cmd-web-5469cf8c57-s8qj5                  1/1     Running     0          21s

$ kubectl config current-context
colima
```

What this tells me, compared with the minikube picture: the node is `Ready`, it is the only node and
carries the `control-plane` role, its INTERNAL-IP `192.168.5.1` is the VM's address, and the runtime
is containerd (k3s does not use Docker). `kubectl get pods -A` looks different from minikube's
`kube-system` list because k3s does not run the API server, scheduler, controller-manager and etcd as
pods; they are all threads inside the single `k3s` systemd service on the node (visible in the VM
with `journalctl -u k3s`), and k3s uses SQLite instead of etcd by default. What *is* visible as pods
is the add-on layer: CoreDNS, metrics-server, the local-path storage provisioner, the Traefik
ingress controller and its `svclb-*` pods (k3s's built-in `LoadBalancer` implementation). The `s10`
to `s14` namespaces are the other Kubernetes homework sessions sharing this cluster at the same time.
In minikube the extra items would be `minikube status`, `minikube dashboard`, `minikube ip` and
`minikube ssh`; the Colima equivalents are `colima status`, `colima ssh` and the node IP above.

## Task 3: Explore Kubernetes architecture

A Kubernetes cluster is a **control plane** that stores and reconciles desired state plus one or more
**worker nodes** that run the containers. Every component talks only to the API server.

```text
                               kubectl / CI / Argo CD / dashboard
                                             │  HTTPS (REST, 6443)
┌────────────────────────────────────────────▼────────────────────────────────────────────┐
│ CONTROL PLANE (minikube: all in one node)                                                │
│                                                                                          │
│   ┌──────────────────┐     ┌────────────────┐     ┌──────────────────────────┐           │
│   │  kube-apiserver  │◀───▶│      etcd      │     │ kube-controller-manager  │           │
│   │  front door, auth│     │ key-value store│     │ Deployment/ReplicaSet/   │           │
│   │  validation, REST│     │ = cluster state│     │ Node/Job/Endpoint ctlrs  │           │
│   └───┬──────────┬───┘     └────────────────┘     └────────────▲─────────────┘           │
│       │          │                                              │ watch/update            │
│       │          │         ┌────────────────┐     ┌─────────────┴────────────┐           │
│       │          └────────▶│ kube-scheduler │     │ cloud-controller-manager │           │
│       │                    │ picks a node   │     │ LB / node / route glue   │ (not in   │
│       │                    │ for new pods   │     │ for AWS/GCP/Azure        │  minikube)│
│       │                    └────────────────┘     └──────────────────────────┘           │
└───────┼──────────────────────────────────────────────────────────────────────────────────┘
        │ watch pods assigned to me / report status
┌───────▼──────────────────────────────┐   ┌──────────────────────────────────┐
│ WORKER NODE 1                        │   │ WORKER NODE 2 …                  │
│  ┌─────────┐  ┌────────────┐         │   │                                  │
│  │ kubelet │  │ kube-proxy │         │   │   kubelet   kube-proxy           │
│  │ runs    │  │ Service →  │         │   │                                  │
│  │ pods    │  │ pod IPs    │         │   │   container runtime              │
│  └────┬────┘  │ (iptables/ │         │   │   ┌─────┐ ┌─────┐                │
│       │       │  ipvs)     │         │   │   │ Pod │ │ Pod │                │
│  ┌────▼────────────────────┐         │   │   └─────┘ └─────┘                │
│  │ container runtime (CRI) │         │   └──────────────────────────────────┘
│  │ containerd / Docker     │         │
│  │  ┌─────┐ ┌─────┐ ┌────┐ │         │   ADD-ONS (run as pods): CoreDNS (cluster DNS),
│  │  │ Pod │ │ Pod │ │Pod │ │         │   CNI plugin (pod network), metrics-server,
│  │  └─────┘ └─────┘ └────┘ │         │   ingress controller, dashboard, storage-provisioner
│  └─────────────────────────┘         │
└──────────────────────────────────────┘
```

### Control plane components

| Component | Role | How I see it in minikube |
|---|---|---|
| **kube-apiserver** | The only entry point. Validates and authenticates every request (kubectl, controllers, kubelets), persists objects to etcd, serves watches. Stateless, can be scaled horizontally. | `kube-apiserver-minikube` pod; `kubectl cluster-info` URL |
| **etcd** | Consistent, distributed key-value store (Raft). Holds *all* cluster state: every object, its spec and status. Back this up = back up the cluster. | `etcd-minikube` pod |
| **kube-scheduler** | Watches for pods with no `nodeName`, scores nodes (resources, affinity, taints/tolerations, topology) and binds the pod to the best one. It does not start containers. | `kube-scheduler-minikube` |
| **kube-controller-manager** | One binary running many control loops: Deployment, ReplicaSet, Node, Job, EndpointSlice, ServiceAccount… Each loop compares desired vs actual and acts (e.g. ReplicaSet controller creates missing pods). | `kube-controller-manager-minikube` |
| **cloud-controller-manager** | The cloud-specific loops: creates cloud load balancers for `type: LoadBalancer` services, sets node addresses, manages routes. Absent on bare metal/minikube. | not present |

### Node components

| Component | Role |
|---|---|
| **kubelet** | Agent on every node. Registers the node, watches the API for pods scheduled to it, tells the container runtime to start/stop containers, runs liveness/readiness probes, reports pod and node status. |
| **kube-proxy** | Implements Services on each node: programs iptables/IPVS rules so traffic to a Service's ClusterIP/NodePort is forwarded to one of the backing pod IPs. |
| **Container runtime** | Pulls images and runs containers through the CRI: containerd (default today), CRI-O, or Docker via cri-dockerd (what minikube's docker driver uses). |

### Add-ons

| Add-on | Role |
|---|---|
| **CoreDNS** | Cluster DNS. Every Service gets `name.namespace.svc.cluster.local`; pods use it via `/etc/resolv.conf`. |
| **CNI plugin** (bridge/kindnet/Calico/Cilium) | Gives every pod its own IP and routes pod-to-pod traffic across nodes. |
| **metrics-server** | CPU/memory metrics for `kubectl top` and the HPA (`minikube addons enable metrics-server`). |
| **Ingress controller**, **dashboard**, **storage-provisioner** | HTTP routing, UI, dynamic PersistentVolumes (minikube enables storage-provisioner by default). |

### What happens on `kubectl create deployment`

1. `kubectl` POSTs the Deployment to the **API server**, which authenticates/validates and writes it to **etcd**.
2. The Deployment controller (in **controller-manager**) sees it and creates a **ReplicaSet**; the ReplicaSet controller creates the **Pod** objects (still unscheduled).
3. The **scheduler** sees pods with no node, picks a node, and updates `spec.nodeName`.
4. The **kubelet** on that node sees a pod assigned to it, asks the **container runtime** to pull the image and start the container, and reports status back.
5. If a Service exists, **kube-proxy** on every node adds rules for the new pod IP and **CoreDNS** already resolves the Service name.
6. Everything is a loop: delete the pod and step 2 repeats within seconds (self-healing).

## Task 4: Basic Kubernetes objects and commands

| Object | What it is | One-line kubectl example |
|---|---|---|
| **Pod** | Smallest deployable unit: one or more containers sharing network namespace (one IP) and volumes. Ephemeral; normally created by a controller, not by hand. | `kubectl run nginx --image=nginx:alpine --port=80` |
| **ReplicaSet** | Keeps N identical pods running (selected by labels). Replaces pods that die. Created by Deployments. | `kubectl get rs` / `kubectl scale rs/web-abc123 --replicas=3` |
| **Deployment** | Declarative manager of ReplicaSets: rolling updates, rollbacks, scaling, revision history. The normal way to run stateless apps. | `kubectl create deployment web --image=nginx:alpine --replicas=2` |
| **Service** | Stable virtual IP + DNS name in front of a changing set of pods (selected by labels). Types: ClusterIP (internal), NodePort (node:port), LoadBalancer (cloud LB), ExternalName. | `kubectl expose deployment web --type=NodePort --port=80` |
| **Namespace** | Logical partition of the cluster for names, quotas and RBAC (`default`, `kube-system`, …). | `kubectl create namespace dev` / `kubectl get pods -n dev` |
| **ConfigMap** | Non-secret key/value configuration injected as env vars or files. | `kubectl create configmap app-config --from-literal=LOG_LEVEL=debug` |
| **Secret** | Same as ConfigMap but for sensitive data; base64-encoded at rest (encrypt etcd / use external secret stores for real security). | `kubectl create secret generic db-pass --from-literal=password=changeme-fake` |
| **Volume** | Storage attached to a pod: `emptyDir` (pod lifetime), `hostPath`, `configMap`/`secret`, or a `persistentVolumeClaim` bound to a PersistentVolume that outlives the pod. | `kubectl get pv,pvc` (declared inside the pod spec, no imperative create) |
| Node | A worker machine (VM/container in minikube). | `kubectl get nodes -o wide` |
| Labels / selectors | Key/value tags that connect Services and ReplicaSets to pods. | `kubectl get pods -l app=web` |

### Command cheat sheet

```bash
kubectl get <kind> [-n ns | -A] [-o wide|yaml|json]   # list; -A = all namespaces
kubectl describe <kind>/<name>                        # details + Events (first stop when debugging)
kubectl logs <pod> [-c container] [-f] [--previous]   # container stdout/stderr
kubectl exec -it <pod> -- sh                          # shell inside a container
kubectl apply -f file.yaml | kubectl delete -f file.yaml
kubectl create deployment NAME --image=IMG --dry-run=client -o yaml > deploy.yaml   # generate YAML
kubectl scale deployment/NAME --replicas=3
kubectl set image deployment/NAME CONTAINER=IMG:TAG
kubectl rollout status|history|undo deployment/NAME
kubectl explain deployment.spec.strategy              # built-in API docs
kubectl port-forward svc/NAME 8080:80                 # local access without a Service change
kubectl top pods|nodes                                # needs metrics-server
kubectl config get-contexts | use-context minikube
```


## Task 5: Kubernetes Basics tutorial hands-on

Image used by the tutorial: `gcr.io/google-samples/kubernetes-bootcamp:v1` (a tiny Node.js server that
prints its hostname = pod name on port 8080) and `jocatalin/kubernetes-bootcamp:v2` for the update.
Both images are published for amd64 only; they run on this arm64 node because the Colima VM
registers `qemu-x86_64` through binfmt_misc, so containerd transparently emulates them (slower, but
correct). YAML equivalents are in `kubernetes-basics/`, and `kubernetes-basics/commands.sh` runs all
six modules in order.

I ran everything in a dedicated namespace so it could not collide with the other sessions on the
shared cluster; that is why every command carries `-n s09`. On minikube the tutorial uses `default`
and the `-n` flag can simply be dropped.

### Module 1 – Create a cluster

```bash
minikube start --driver=docker      # minikube path (Expected output in Task 1)
kubectl version
kubectl get nodes
kubectl create namespace s09
kubectl get ns s09
```

```text
Output (captured 2026-10-07)
Client Version: v1.37.1
Kustomize Version: v5.8.1
Server Version: v1.35.0+k3s1

NAME     STATUS   ROLES           AGE   VERSION
colima   Ready    control-plane   11m   v1.35.0+k3s1

namespace/s09 created

NAME   STATUS   AGE
s09    Active   2m24s
```

### Module 2 – Deploy an app

```bash
kubectl -n s09 create deployment kubernetes-bootcamp --image=gcr.io/google-samples/kubernetes-bootcamp:v1
kubectl -n s09 rollout status deployment/kubernetes-bootcamp --timeout=180s
kubectl -n s09 get deployments
kubectl -n s09 get events --sort-by=.metadata.creationTimestamp | tail -n 6
kubectl -n s09 get pods
# alternative with the YAML in this folder:
kubectl -n s09 apply -f kubernetes-basics/deployment.yaml
```

```text
Output (captured 2026-10-07)
deployment.apps/kubernetes-bootcamp created

Waiting for deployment "kubernetes-bootcamp" rollout to finish: 0 out of 1 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 0 of 1 updated replicas are available...
deployment "kubernetes-bootcamp" successfully rolled out

NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   1/1     1            1           2s

2s          Normal    SuccessfulCreate    replicaset/kubernetes-bootcamp-67fbdd6b79   Created pod: kubernetes-bootcamp-67fbdd6b79-dqdp5
2s          Normal    ScalingReplicaSet   deployment/kubernetes-bootcamp              Scaled up replica set kubernetes-bootcamp-67fbdd6b79 from 0 to 1
1s          Normal    Scheduled           pod/kubernetes-bootcamp-67fbdd6b79-dqdp5    Successfully assigned s09/kubernetes-bootcamp-67fbdd6b79-dqdp5 to colima
1s          Normal    Pulled              pod/kubernetes-bootcamp-67fbdd6b79-dqdp5    Container image "gcr.io/google-samples/kubernetes-bootcamp:v1" already present on machine and can be accessed by the pod
1s          Normal    Created             pod/kubernetes-bootcamp-67fbdd6b79-dqdp5    Container created
1s          Normal    Started             pod/kubernetes-bootcamp-67fbdd6b79-dqdp5    Container started

NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running   0          2s
```

The events are the architecture in action: Deployment → ReplicaSet → Pod → Scheduled → Pulled →
Started. The whole chain took about two seconds because the image was "already present on machine":
I had pulled it a minute earlier with a throw-away `kubectl run` to check that the amd64 image starts
at all on this arm64 node (the first pull took 25 s for 84 MB).

Reaching the pod through the API server proxy (the tutorial's first access method). I used port 8011
instead of the default 8001 because other sessions on this laptop were already using 8001:

```bash
kubectl proxy --port=8011 &            # http://localhost:8011 -> API server
curl -s http://localhost:8011/version
export POD_NAME=$(kubectl -n s09 get pods -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
echo "Name of the Pod: $POD_NAME"
curl -s http://localhost:8011/api/v1/namespaces/s09/pods/$POD_NAME:8080/proxy/
kill %1
```

```text
Output (captured 2026-10-07)
{
  "major": "1",
  "minor": "35",
  "emulationMajor": "1",
  "emulationMinor": "35",
  "minCompatibilityMajor": "1",
  "minCompatibilityMinor": "34",
  "gitVersion": "v1.35.0+k3s1",
  "gitCommit": "a6c6cd15c0c42ec9fce21f8ad5f42aa74fddb4f2",
  "gitTreeState": "clean",
  "buildDate": "2025-12-23T16:12:16Z",
  "goVersion": "go1.25.5",
  "compiler": "gc",
  "platform": "linux/arm64"
}
Name of the Pod: kubernetes-bootcamp-67fbdd6b79-dqdp5
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1
```

### Module 3 – Explore the app

```bash
kubectl -n s09 get pods
kubectl -n s09 describe pod $POD_NAME
kubectl -n s09 logs $POD_NAME
kubectl -n s09 exec $POD_NAME -- env
kubectl -n s09 exec $POD_NAME -- uname -m
kubectl -n s09 exec $POD_NAME -- cat server.js | head -12     # interactive form: kubectl exec -ti $POD_NAME -- bash
kubectl -n s09 exec $POD_NAME -- curl -s localhost:8080
```

```text
Output (captured 2026-10-07)
NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running   0          4s

Name:             kubernetes-bootcamp-67fbdd6b79-dqdp5
Namespace:        s09
Priority:         0
Service Account:  default
Node:             colima/192.168.5.1
Start Time:       Wed, 07 Oct 2026 22:44:53 +0530
Labels:           app=kubernetes-bootcamp
                  pod-template-hash=67fbdd6b79
Annotations:      <none>
Status:           Running
IP:               10.42.0.56
IPs:
  IP:           10.42.0.56
Controlled By:  ReplicaSet/kubernetes-bootcamp-67fbdd6b79
Containers:
  kubernetes-bootcamp:
    Container ID:   containerd://0a455cff6f8d835fbb3e0fdd4ee25ee2f377b15fbccfd55d74d1a1aba78284a7
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image ID:       gcr.io/google-samples/kubernetes-bootcamp@sha256:0d6b8ee63bb57c5f5b6156f446b3bc3b3c143d233037f3a2f00e279c8fcc64af
    Port:           <none>
    Host Port:      <none>
    State:          Running
      Started:      Wed, 07 Oct 2026 22:44:53 +0530
    Ready:          True
    Restart Count:  0
    Environment:    <none>
    Mounts:
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-l5m9d (ro)
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
Volumes:
  kube-api-access-l5m9d:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    TokenExpirationSeconds:  3607
    ConfigMapName:           kube-root-ca.crt
    Optional:                false
    DownwardAPI:             true
QoS Class:                   BestEffort
Node-Selectors:              <none>
Tolerations:                 node.kubernetes.io/not-ready:NoExecute op=Exists for 300s
                             node.kubernetes.io/unreachable:NoExecute op=Exists for 300s
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  3s    default-scheduler  Successfully assigned s09/kubernetes-bootcamp-67fbdd6b79-dqdp5 to colima
  Normal  Pulled     3s    kubelet            spec.containers{kubernetes-bootcamp}: Container image "gcr.io/google-samples/kubernetes-bootcamp:v1" already present on machine and can be accessed by the pod
  Normal  Created    3s    kubelet            spec.containers{kubernetes-bootcamp}: Container created
  Normal  Started    3s    kubelet            spec.containers{kubernetes-bootcamp}: Container started

$ kubectl -n s09 logs kubernetes-bootcamp-67fbdd6b79-dqdp5
Kubernetes Bootcamp App Started At: 2026-10-07T17:14:53.996Z | Running On:  kubernetes-bootcamp-67fbdd6b79-dqdp5

Running On: kubernetes-bootcamp-67fbdd6b79-dqdp5 | Total Requests: 1 | App Uptime: 2.329 seconds | Log Time: 2026-10-07T17:14:56.326Z

$ kubectl -n s09 exec kubernetes-bootcamp-67fbdd6b79-dqdp5 -- env
HOME=/root
KUBERNETES_SERVICE_HOST=10.43.0.1
KUBERNETES_PORT_443_TCP_ADDR=10.43.0.1
KUBERNETES_PORT_443_TCP_PORT=443
KUBERNETES_PORT_443_TCP_PROTO=tcp
KUBERNETES_PORT_443_TCP=tcp://10.43.0.1:443
KUBERNETES_PORT=tcp://10.43.0.1:443
KUBERNETES_SERVICE_PORT_HTTPS=443
KUBERNETES_SERVICE_PORT=443
NODE_VERSION=6.3.1
NPM_CONFIG_LOGLEVEL=info
HOSTNAME=kubernetes-bootcamp-67fbdd6b79-dqdp5
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

$ kubectl -n s09 exec kubernetes-bootcamp-67fbdd6b79-dqdp5 -- uname -m
x86_64

$ kubectl -n s09 exec kubernetes-bootcamp-67fbdd6b79-dqdp5 -- cat server.js | head -12
var http = require('http');
var requests=0;
var podname= process.env.HOSTNAME;
var startTime;
var host;
var handleRequest = function(request, response) {
  response.setHeader('Content-Type', 'text/plain');
  response.writeHead(200);
  response.write("Hello Kubernetes bootcamp! | Running on: ");
  response.write(host);
  response.end(" | v=1\n");
  console.log("Running On:" ,host, "| Total Requests:", ++requests,"| App Uptime:", (new Date() - startTime)/1000 , "seconds", "| Log Time:",new Date());

$ kubectl -n s09 exec kubernetes-bootcamp-67fbdd6b79-dqdp5 -- curl -s localhost:8080
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1
```

What I learned here: `describe` shows the pod IP (`10.42.0.56`, from k3s's flannel CNI; minikube
would give `10.244.x.x`), the node it runs on with the node IP, the container ID in containerd, and
the kubelet events; `logs` shows the container's stdout, and the one request logged there is the
`curl` I made through the API proxy in Module 2; `exec` runs a process inside the container, and
the `KUBERNETES_SERVICE_HOST` env var shows every pod is told where the API server is (`10.43.0.1`,
the first IP of k3s's service CIDR). `uname -m` printing `x86_64` on an arm64 node is the qemu
emulation mentioned at the top of this task.

### Module 4 – Expose the app publicly

```bash
kubectl -n s09 get services
kubectl -n s09 expose deployment/kubernetes-bootcamp --type=NodePort --port 8080
# or: kubectl -n s09 apply -f kubernetes-basics/service.yaml
kubectl -n s09 get services
kubectl -n s09 describe services/kubernetes-bootcamp
export NODE_PORT="$(kubectl -n s09 get services/kubernetes-bootcamp -o go-template='{{(index .spec.ports 0).nodePort}}')"
echo "NODE_PORT=$NODE_PORT"
```

```text
Output (captured 2026-10-07)
No resources found in s09 namespace.

service/kubernetes-bootcamp exposed

NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kubernetes-bootcamp   NodePort   10.43.190.145   <none>        8080:31168/TCP   0s

Name:                     kubernetes-bootcamp
Namespace:                s09
Labels:                   app=kubernetes-bootcamp
Annotations:              <none>
Selector:                 app=kubernetes-bootcamp
Type:                     NodePort
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.43.190.145
IPs:                      10.43.190.145
Port:                     <unset>  8080/TCP
TargetPort:               8080/TCP
NodePort:                 <unset>  31168/TCP
Endpoints:                10.42.0.56:8080
Session Affinity:         None
External Traffic Policy:  Cluster
Internal Traffic Policy:  Cluster
Events:                   <none>
NODE_PORT=31168
```

In `default` the first `get services` would also list the `kubernetes` ClusterIP service; in my own
namespace there is nothing until I create one. The Service got a stable ClusterIP `10.43.190.145`,
the NodePort `31168` (allocated from 30000–32767) and one endpoint, the pod IP from Module 3.

Reaching it. The tutorial uses `minikube service kubernetes-bootcamp --url`; with k3s there is no
tunnel helper, so I tried the ways that exist on any cluster. My first `curl` to the NodePort,
issued in the same second the Service was created, failed with "connection refused" (kube-proxy had
not programmed the port yet, see the note after the block), so the reachability test below is from a
later re-run against the recreated Service (NodePort `32301`):

```bash
curl -s http://localhost:$NODE_PORT                        # from macOS: Colima forwards VM ports to localhost
colima ssh -- curl -s http://localhost:$NODE_PORT          # from the node itself
colima ssh -- curl -s http://192.168.5.1:$NODE_PORT        # node IP (= minikube ip)
kubectl -n s09 run client --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- http://kubernetes-bootcamp:8080   # from another pod, by DNS name
kubectl -n s09 port-forward service/kubernetes-bootcamp 18093:8080 &   # works on every cluster
curl -s http://localhost:18093
kill %1
```

```text
Output (captured 2026-10-08)
$ curl -s http://localhost:32301
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-9c9cdbbfc-wfgcw | v=2

$ colima ssh -- curl -s http://localhost:32301
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-9c9cdbbfc-7psnb | v=2

$ colima ssh -- curl -s http://192.168.5.1:32301
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-9c9cdbbfc-wfgcw | v=2

$ kubectl -n s09 run client --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- http://kubernetes-bootcamp:8080
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1      (captured 2026-10-07, before the update)
pod "client" deleted from s09 namespace

$ curl -s http://localhost:18093
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-9c9cdbbfc-wfgcw | v=2
```

Observations: (1) Colima (via Lima) forwards every port the VM listens on to `localhost` on macOS,
so `curl localhost:<NodePort>` works from the host without any `minikube service` tunnel; `curl
192.168.5.1:<NodePort>` from macOS times out because the VM network is not routed to the host. (2)
Inside the VM both `localhost` and the node IP work: a NodePort is open on every node interface.
(3) A pod reaches the Service by its DNS name `kubernetes-bootcamp` (CoreDNS expands it to
`kubernetes-bootcamp.s09.svc.cluster.local`). (4) `kubectl port-forward` is the portable fallback;
it pins to one pod, so it is not load-balanced. (5) Right after `kubectl expose` the NodePort is
not instantly reachable, kube-proxy needs a moment to write the iptables rules; `commands.sh` now
waits two seconds for that.

Labels (how the Service finds the pods):

```bash
kubectl -n s09 describe deployment kubernetes-bootcamp | grep -E '^(Labels|Selector)'
kubectl -n s09 get pods -l app=kubernetes-bootcamp
kubectl -n s09 get services -l app=kubernetes-bootcamp
kubectl -n s09 label pods $POD_NAME version=v1
kubectl -n s09 describe pods $POD_NAME | grep -A3 '^Labels'
kubectl -n s09 get pods -l version=v1
```

```text
Output (captured 2026-10-07)
Labels:                 app=kubernetes-bootcamp
Selector:               app=kubernetes-bootcamp

NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running   0          10s

NAME                  TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
kubernetes-bootcamp   NodePort   10.43.190.145   <none>        8080:31168/TCP   6s

pod/kubernetes-bootcamp-67fbdd6b79-dqdp5 labeled

Labels:           app=kubernetes-bootcamp
                  pod-template-hash=67fbdd6b79
                  version=v1
Annotations:      <none>

NAME                                   READY   STATUS    RESTARTS   AGE
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running   0          10s
```

`kubectl create deployment` put the label `app=kubernetes-bootcamp` on the Deployment, on its pod
template and in the Service selector, which is the only thing connecting the three objects. The
extra `version=v1` label I added is purely mine; the ReplicaSet still selects by `app` plus
`pod-template-hash`.

Deleting a Service (the app keeps running inside the cluster; only the external path disappears):

```bash
kubectl -n s09 delete service -l app=kubernetes-bootcamp
kubectl -n s09 get services
colima ssh -- curl -s --max-time 5 http://localhost:$NODE_PORT ; echo "(exit $?)"
kubectl -n s09 exec $POD_NAME -- curl -s localhost:8080
kubectl -n s09 expose deployment/kubernetes-bootcamp --type=NodePort --port 8080   # recreate for the next modules
```

```text
Output (captured 2026-10-07)
service "kubernetes-bootcamp" deleted from s09 namespace

No resources found in s09 namespace.

time="2026-10-07T22:45:02+05:30" level=fatal msg="exit status 7"
(exit 1)

Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1

service/kubernetes-bootcamp exposed
NODE_PORT=32301
```

curl exit status 7 is "Failed to connect": nothing listens on the old NodePort any more, but
`exec … curl localhost:8080` inside the pod still answers. Re-exposing gave a *new* random NodePort
(`32301`), which is why the YAML in `kubernetes-basics/service.yaml` is the better way to keep a port
stable.

### Module 5 – Scale the app

```bash
kubectl -n s09 get rs
kubectl -n s09 scale deployments/kubernetes-bootcamp --replicas=4
kubectl -n s09 rollout status deployment/kubernetes-bootcamp --timeout=180s
kubectl -n s09 get deployments
kubectl -n s09 get pods -o wide
kubectl -n s09 describe deployments/kubernetes-bootcamp | grep -E 'Replicas:|ScalingReplicaSet'
```

```text
Output (captured 2026-10-07)
NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-67fbdd6b79   1         1         1       10s

deployment.apps/kubernetes-bootcamp scaled

Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 of 4 updated replicas are available...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 2 of 4 updated replicas are available...
deployment "kubernetes-bootcamp" successfully rolled out

NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   4/4     4            4           12s

NAME                                   READY   STATUS    RESTARTS   AGE   IP           NODE     NOMINATED NODE   READINESS GATES
kubernetes-bootcamp-67fbdd6b79-9qr2v   1/1     Running   0          2s    10.42.0.60   colima   <none>           <none>
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running   0          12s   10.42.0.56   colima   <none>           <none>
kubernetes-bootcamp-67fbdd6b79-mxq95   1/1     Running   0          2s    10.42.0.59   colima   <none>           <none>
kubernetes-bootcamp-67fbdd6b79-wspkc   1/1     Running   0          2s    10.42.0.58   colima   <none>           <none>

Replicas:               4 desired | 4 updated | 4 total | 4 available | 0 unavailable
  Normal  ScalingReplicaSet  12s   deployment-controller  Scaled up replica set kubernetes-bootcamp-67fbdd6b79 from 0 to 1
  Normal  ScalingReplicaSet  2s    deployment-controller  Scaled up replica set kubernetes-bootcamp-67fbdd6b79 from 1 to 4
```

Scaling did not create a new ReplicaSet; the same `67fbdd6b79` ReplicaSet simply got `DESIRED=4`
and the three new pods were running two seconds later (cached image, all on the single node).

Load balancing: the Service now has four endpoints and spreads requests across them.

```bash
kubectl -n s09 describe services/kubernetes-bootcamp | grep Endpoints
kubectl -n s09 get endpointslices -l kubernetes.io/service-name=kubernetes-bootcamp
for i in 1 2 3 4 5 6; do colima ssh -- curl -s http://localhost:$NODE_PORT; done   # minikube: curl $(minikube service kubernetes-bootcamp --url)
```

```text
Output (captured 2026-10-07)
Endpoints:                10.42.0.56:8080,10.42.0.60:8080,10.42.0.59:8080 + 1 more...

NAME                        ADDRESSTYPE   PORTS   ENDPOINTS                                      AGE
kubernetes-bootcamp-npstt   IPv4          8080    10.42.0.56,10.42.0.60,10.42.0.59 + 1 more...   2s

Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-9qr2v | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-mxq95 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-dqdp5 | v=1
Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-67fbdd6b79-mxq95 | v=1
```

Six requests landed on three different pods. kube-proxy's iptables mode picks a backend at random
per connection (not strict round-robin), which is why `dqdp5` answered three times and `wspkc` not at
all in this small sample.

Scale down:

```bash
kubectl -n s09 scale deployments/kubernetes-bootcamp --replicas=2
kubectl -n s09 get deployments
kubectl -n s09 get pods -o wide
```

```text
Output (captured 2026-10-07)
deployment.apps/kubernetes-bootcamp scaled

NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   4/2     4            4           13s

NAME                                   READY   STATUS        RESTARTS   AGE   IP           NODE     NOMINATED NODE   READINESS GATES
kubernetes-bootcamp-67fbdd6b79-9qr2v   1/1     Running       0          4s    10.42.0.60   colima   <none>           <none>
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running       0          14s   10.42.0.56   colima   <none>           <none>
kubernetes-bootcamp-67fbdd6b79-mxq95   1/1     Terminating   0          4s    10.42.0.59   colima   <none>           <none>
kubernetes-bootcamp-67fbdd6b79-wspkc   1/1     Terminating   0          4s    10.42.0.58   colima   <none>           <none>
```

`READY 4/2` for a moment is the controller catching up: two pods are `Terminating` (they get a
SIGTERM and up to 30 s grace; this Node.js app ignores SIGTERM, so they stayed `Terminating` for the
full 30 s before being killed) and the Deployment reports `2/2` once they are gone.

### Module 6 – Update the app (rolling update) and roll back

```bash
kubectl -n s09 get deployments
kubectl -n s09 describe pods | grep 'Image:'
kubectl -n s09 set image deployments/kubernetes-bootcamp kubernetes-bootcamp=jocatalin/kubernetes-bootcamp:v2
kubectl -n s09 get pods
kubectl -n s09 rollout status deployments/kubernetes-bootcamp --timeout=180s
colima ssh -- curl -s http://localhost:$NODE_PORT
kubectl -n s09 describe pods | grep 'Image:'
kubectl -n s09 get rs
kubectl -n s09 rollout history deployments/kubernetes-bootcamp
```

```text
Output (captured 2026-10-07)
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
kubernetes-bootcamp   2/2     2            2           34s

    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1

deployment.apps/kubernetes-bootcamp image updated

NAME                                   READY   STATUS              RESTARTS   AGE
kubernetes-bootcamp-67fbdd6b79-9qr2v   1/1     Running             0          24s
kubernetes-bootcamp-67fbdd6b79-dqdp5   1/1     Running             0          34s
kubernetes-bootcamp-67fbdd6b79-mxq95   1/1     Terminating         0          24s
kubernetes-bootcamp-67fbdd6b79-wspkc   1/1     Terminating         0          24s
kubernetes-bootcamp-9c9cdbbfc-wfgcw    0/1     ContainerCreating   0          0s

Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 old replicas are pending termination...
deployment "kubernetes-bootcamp" successfully rolled out

Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-9c9cdbbfc-wfgcw | v=2

    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          gcr.io/google-samples/kubernetes-bootcamp:v1
    Image:          jocatalin/kubernetes-bootcamp:v2
    Image:          jocatalin/kubernetes-bootcamp:v2

NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-67fbdd6b79   0         0         0       36s
kubernetes-bootcamp-9c9cdbbfc    2         2         2       2s

deployment.apps/kubernetes-bootcamp
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

A rolling update creates a **new ReplicaSet** (`9c9cdbbfc`) and shifts pods one at a time (default
`maxUnavailable=25%`, `maxSurge=25%`, which with two replicas rounds to "one new pod up, then one old
pod down"), so the Service never has zero endpoints; the response now says `v=2`. The `describe pods |
grep Image:` lines still list the v1 pods because the two scaled-down pods from Module 5 and the two
replaced v1 pods were all still in their 30 s `Terminating` grace period; `get rs` is the clearer
view: old ReplicaSet `0/0/0`, new one `2/2/2`. The old ReplicaSet is kept (empty) so that `rollout
undo` can reuse it.

Now a broken update (tag `v10` does not exist) and a rollback. I ran this step again the next day
against the same Deployment (still at v2), so the revision numbers continue from 4; the first
attempt on 2026-10-07 behaved identically but my grep missed the pod events.

```bash
kubectl -n s09 set image deployments/kubernetes-bootcamp kubernetes-bootcamp=gcr.io/google-samples/kubernetes-bootcamp:v10
kubectl -n s09 rollout status deployments/kubernetes-bootcamp --timeout=60s
kubectl -n s09 get pods
BAD=$(kubectl -n s09 get pods --field-selector=status.phase=Pending -o jsonpath='{.items[0].metadata.name}')
kubectl -n s09 describe pod $BAD | sed -n '/^Events:/,$p'
kubectl -n s09 get rs
kubectl -n s09 rollout history deployments/kubernetes-bootcamp
```

```text
Output (captured 2026-10-08)
deployment.apps/kubernetes-bootcamp image updated

Waiting for deployment spec update to be observed...
Waiting for deployment spec update to be observed...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 0 out of 2 new replicas have been updated...
Waiting for deployment "kubernetes-bootcamp" rollout to finish: 1 out of 2 new replicas have been updated...
error: timed out waiting for the condition

NAME                                   READY   STATUS         RESTARTS   AGE
kubernetes-bootcamp-845bc89d75-tqdc7   0/1     ErrImagePull   0          60s
kubernetes-bootcamp-9c9cdbbfc-7psnb    1/1     Running        0          3h43m
kubernetes-bootcamp-9c9cdbbfc-wfgcw    1/1     Running        0          3h43m

Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  60s                default-scheduler  Successfully assigned s09/kubernetes-bootcamp-845bc89d75-tqdc7 to colima
  Normal   Pulling    18s (x3 over 59s)  kubelet            spec.containers{kubernetes-bootcamp}: Pulling image "gcr.io/google-samples/kubernetes-bootcamp:v10"
  Warning  Failed     18s (x3 over 58s)  kubelet            spec.containers{kubernetes-bootcamp}: Failed to pull image "gcr.io/google-samples/kubernetes-bootcamp:v10": rpc error: code = NotFound desc = failed to pull and unpack image "gcr.io/google-samples/kubernetes-bootcamp:v10": failed to resolve reference "gcr.io/google-samples/kubernetes-bootcamp:v10": gcr.io/google-samples/kubernetes-bootcamp:v10: not found
  Warning  Failed     18s (x3 over 58s)  kubelet            spec.containers{kubernetes-bootcamp}: Error: ErrImagePull
  Normal   BackOff    5s (x3 over 58s)   kubelet            spec.containers{kubernetes-bootcamp}: Back-off pulling image "gcr.io/google-samples/kubernetes-bootcamp:v10"
  Warning  Failed     5s (x3 over 58s)   kubelet            spec.containers{kubernetes-bootcamp}: Error: ImagePullBackOff

NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-67fbdd6b79   0         0         0       3h44m
kubernetes-bootcamp-845bc89d75   1         1         0       3h43m
kubernetes-bootcamp-9c9cdbbfc    2         2         2       3h43m

deployment.apps/kubernetes-bootcamp
REVISION  CHANGE-CAUSE
1         <none>
4         <none>
5         <none>
```

The pod alternates between `ErrImagePull` (a pull just failed: the registry answered `not found`
for tag v10) and `ImagePullBackOff` (kubelet waiting with exponential back-off before the next
attempt, `x3 over 58s`). The rollout is stuck at "1 out of 2 new replicas", but the two v2 pods are
untouched and still serving: with `maxSurge=1` the Deployment adds the new pod first and will only
remove an old pod once the new one is `Ready`, which never happens. `rollout history` shows the
rollout as revision 5; revision 2 and 3 are missing from the list because a revision number
belongs to a ReplicaSet and gets reused/renumbered when the same pod template comes back (the
v2 ReplicaSet was revision 2, then 4 after the first `undo`).

Roll back:

```bash
kubectl -n s09 rollout undo deployments/kubernetes-bootcamp
kubectl -n s09 rollout status deployments/kubernetes-bootcamp --timeout=120s
kubectl -n s09 get pods
kubectl -n s09 describe pods | grep 'Image:'
kubectl -n s09 rollout history deployments/kubernetes-bootcamp
kubectl -n s09 get rs
curl -s http://localhost:$NODE_PORT
```

```text
Output (captured 2026-10-08)
deployment.apps/kubernetes-bootcamp rolled back

deployment "kubernetes-bootcamp" successfully rolled out

NAME                                   READY   STATUS        RESTARTS   AGE
kubernetes-bootcamp-845bc89d75-tqdc7   0/1     Terminating   0          60s
kubernetes-bootcamp-9c9cdbbfc-7psnb    1/1     Running       0          3h43m
kubernetes-bootcamp-9c9cdbbfc-wfgcw    1/1     Running       0          3h43m

    Image:          jocatalin/kubernetes-bootcamp:v2
    Image:          jocatalin/kubernetes-bootcamp:v2

deployment.apps/kubernetes-bootcamp
REVISION  CHANGE-CAUSE
1         <none>
5         <none>
6         <none>

NAME                             DESIRED   CURRENT   READY   AGE
kubernetes-bootcamp-67fbdd6b79   0         0         0       3h44m
kubernetes-bootcamp-845bc89d75   0         0         0       3h43m
kubernetes-bootcamp-9c9cdbbfc    2         2         2       3h43m

Hello Kubernetes bootcamp! | Running on: kubernetes-bootcamp-9c9cdbbfc-wfgcw | v=2
```

`rollout undo` went back to the previous revision: the v10 ReplicaSet was scaled to 0 (its pod
`Terminating`), the v2 ReplicaSet stayed at 2, and the rollback itself became revision 6 (same
template as 4, so 4 disappears from the list). The Deployment kept the two healthy v2 pods serving
throughout, which is the whole point of `maxUnavailable`: a bad image never took the service down.
`CHANGE-CAUSE` is `<none>` everywhere because I did not annotate the Deployment with
`kubernetes.io/change-cause`; in real work I would (`kubectl annotate deployment/… kubernetes.io/change-cause="v2"`).

### Cleanup

```bash
kubectl -n s09 delete service kubernetes-bootcamp
kubectl -n s09 delete deployment kubernetes-bootcamp
kubectl -n s09 get all
kubectl delete namespace s09
minikube stop; minikube delete     # minikube path only, when the cluster is no longer needed
```

```text
Output (captured 2026-10-08)
service "kubernetes-bootcamp" deleted from s09 namespace
deployment.apps "kubernetes-bootcamp" deleted from s09 namespace

NAME                                      READY   STATUS        RESTARTS   AGE
pod/kubernetes-bootcamp-9c9cdbbfc-7psnb   1/1     Terminating   0          3h43m
pod/kubernetes-bootcamp-9c9cdbbfc-wfgcw   1/1     Terminating   0          3h43m

namespace "s09" deleted
```

Deleting the Deployment cascades to its ReplicaSets and pods (they go through the same 30 s
termination grace), and deleting the namespace removes anything I might have missed. The k3s
cluster itself was left running because other sessions use it.

## Short notes on Kubernetes architecture (summary for the deliverable)

- Declarative model: I tell the API server *what* I want (YAML), controllers make it true and keep it true.
- Control plane = API server (front door) + etcd (memory) + scheduler (placement) + controller-manager (reconciliation) [+ cloud-controller-manager].
- Node = kubelet (runs pods) + kube-proxy (Service networking) + container runtime; add-ons CoreDNS and CNI make pods discoverable and reachable.
- Deployment → ReplicaSet → Pod is the chain that gives scaling, self-healing and rolling updates; a Service gives a stable name/IP in front of the pods.
- minikube packs all of this into one Docker container; k3s packs it into one binary/systemd service on a VM. Both are enough to practise every command above, and the `kubectl` side is identical.

## Screenshots

| Spec item | Stand-in in this README |
|---|---|
| Minikube installation | `Expected output` block in Task 1 (`brew install`, `minikube start`) plus `Output (captured 2026-10-07)` for `kubectl version` on the k3s cluster actually used |
| Cluster status | `Output (captured 2026-10-07)` block in Task 2 (`cluster-info`, `get nodes -o wide`, `get pods -A`, `current-context`); `minikube status` as `Expected output` |
| Architecture | ASCII diagram and component tables in Task 3 |
| Tutorial modules 1–6 | `Output (captured 2026-10-07)` / `Output (captured 2026-10-08)` blocks under each module in Task 5 |

What is still `Expected output` and why: only the minikube-specific commands (`brew install minikube`,
`minikube start`, `minikube status`, `minikube service --url`, `minikube stop/delete`), because this
run used the k3s cluster inside Colima instead of minikube. Every `kubectl`/`curl` output is real.

## Deliverables

- `homework/session09-kubernetes-fundamentals/README.md` – install steps (minikube as documented, k3s/Colima as actually used), cluster verification with real output, architecture notes with diagram, object/command reference, and the six tutorial modules run for real in namespace `s09` (deploy, explore, expose, scale 4→2, rolling update to v2, broken v10 update with `ImagePullBackOff`, `rollout undo`).
- `homework/session09-kubernetes-fundamentals/kubernetes-basics/deployment.yaml` – Deployment for `gcr.io/google-samples/kubernetes-bootcamp:v1` (YAML equivalent of `kubectl create deployment`).
- `homework/session09-kubernetes-fundamentals/kubernetes-basics/service.yaml` – NodePort Service on port 8080 (YAML equivalent of `kubectl expose`).
- `homework/session09-kubernetes-fundamentals/kubernetes-basics/commands.sh` – executable script that runs modules 1–6 (deploy, explore, expose, scale, update/rollback) on minikube or on any cluster kubectl points at (`NAMESPACE=s09`, `USE_YAML=1`, `CLEANUP=1` switches; uses `kubectl port-forward` when `minikube service` is not available).
