# Kubernetes Object Comparison

Student: Om Malviya | Enrollment No: 24BCS10448

This is Task 2 of Session 11. Commands reference the objects from Session 10
(`namespace s10`) and this session (`namespace s11`).

## Task 2: Kubernetes Object Comparison

### 1. Deployment vs ReplicaSet

| Aspect | ReplicaSet | Deployment |
| --- | --- | --- |
| Purpose | Keep exactly N identical pods running at all times | Describe the *desired* application version and manage ReplicaSets to get there safely |
| Pod management | Creates/deletes pods directly to match `replicas`; selects them by label | Never touches pods directly; creates one ReplicaSet per pod-template revision and owns them |
| Scaling | `kubectl scale rs/<name> --replicas=N` works, but a Deployment will revert it | `kubectl scale deployment/<name>` (or HPA); the Deployment copies the number to the current ReplicaSet |
| Rolling updates | None. Changing the template only affects *new* pods; existing pods stay as they are | Yes. New template -> new ReplicaSet, scaled up while the old one is scaled down (`RollingUpdate`) or after it hits 0 (`Recreate`); history, pause, undo |
| Relationship | Child, owned by a Deployment via `ownerReferences` (or standalone, rarely) | Parent. `Deployment -> ReplicaSet(s) -> Pods` |

**Purpose.** A ReplicaSet is a reconciliation loop with one job: count the
pods matching its selector and add or remove pods until the count equals
`spec.replicas`. A Deployment adds the "how do I get from version A to
version B without downtime" layer on top, plus a revision history.

**Pod management.** The ReplicaSet owns the pods. The Deployment owns the
ReplicaSets. You can see both links with `ownerReferences`:

```bash
kubectl -n s10 get rs -l app=web-rolling
kubectl -n s10 get pod -l app=web-rolling -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}'; echo
kubectl -n s10 get rs -l app=web-rolling -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}/{.items[0].metadata.ownerReferences[0].name}'; echo
```

Output (captured 2026-10-08)
```text
NAME                     DESIRED   CURRENT   READY   AGE
web-rolling-7b85bb48cf   4         4         4       3h53m
web-rolling-f66497d77    0         0         0       3h52m
ReplicaSet/web-rolling-7b85bb48cf
Deployment/web-rolling
```

The hash suffix (`7b85bb48cf`) is the `pod-template-hash` label the
Deployment adds to the ReplicaSet and to its pods so that two ReplicaSets of
the same Deployment never select each other's pods. (When I captured this
the Deployment had just been rolled back to v1 in Session 10, so the v1
ReplicaSet `7b85bb48cf` is the live one and the v2 ReplicaSet `f66497d77`
is kept at 0.)

**Scaling.** Both can be scaled, but the Deployment is the source of truth:

```bash
kubectl -n s10 scale rs web-rolling-7b85bb48cf --replicas=1   # fights the Deployment
kubectl -n s10 get rs web-rolling-7b85bb48cf                   # a second later
```

Output (captured 2026-10-08)
```text
replicaset.apps/web-rolling-7b85bb48cf scaled
NAME                     DESIRED   CURRENT   READY   AGE
web-rolling-7b85bb48cf   4         4         1       3h53m
```

The Deployment controller had already put `DESIRED` back to 4 one second
later, but my `scale` had killed three pods in the meantime (`READY 1`); the
ReplicaSet then recreated them and 15 s later it showed `4 4 4` again. So
scaling a managed ReplicaSet by hand is not just pointless, it causes a
short outage.

**Rolling updates.** Editing a ReplicaSet's template does nothing to its
running pods; they would only change if deleted and recreated. A Deployment
performs the replacement:

```text
Deployment web-rolling (template v2)
 ├── ReplicaSet web-rolling-7b85bb48cf (v1)   replicas 4 -> 3 -> 2 -> 1 -> 0
 └── ReplicaSet web-rolling-f66497d77  (v2)   replicas 0 -> 1 -> 2 -> 3 -> 4
```

Old ReplicaSets are kept at 0 replicas (`revisionHistoryLimit`) so
`kubectl rollout undo` can scale one back up.

**Minimal manifests.** A standalone ReplicaSet looks like a Deployment with
`kind` changed and no `strategy`:

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: web-rs
spec:
  replicas: 3
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: nginx:alpine
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate: { maxSurge: 1, maxUnavailable: 0 }
  selector:
    matchLabels: { app: web }
  template:
    metadata:
      labels: { app: web }
    spec:
      containers:
        - name: web
          image: nginx:alpine
```

In practice nobody writes ReplicaSets by hand; Deployments create them.

### 2. Deployment vs DaemonSet vs StatefulSet

| Aspect | Deployment | DaemonSet | StatefulSet |
| --- | --- | --- | --- |
| Use cases | Stateless, interchangeable replicas: web servers, APIs, workers | Exactly one pod per (matching) node: log shippers, node-exporter, CNI/kube-proxy, storage agents | Stateful, non-interchangeable replicas: databases, Kafka, ZooKeeper, etcd, Redis cluster |
| Pod creation | Via ReplicaSet; random names `web-7f9b4c6d58-x2pnl`; any order, in parallel | Directly by the DaemonSet controller; one pod per node, name `agent-k4t2p`; a new node gets a pod automatically | Directly by the StatefulSet controller; ordinal names `db-0`, `db-1`, `db-2`; created in order, each waits for the previous to be Ready |
| Scaling | `replicas: N`, up or down, any pod can be removed | No `replicas` field; count = number of nodes matching `nodeSelector`/tolerations | `replicas: N`; scale-down removes the highest ordinal first (`db-2` before `db-1`) |
| Networking | Pods reached through a normal Service (ClusterIP VIP); pod IPs and names are random | Usually `hostNetwork` or `hostPort` so the node itself is the address; often no Service | Headless Service gives each pod a stable DNS name `db-0.db.ns.svc.cluster.local` that survives rescheduling |
| Storage | Shared or none; a PVC in the template is mounted by *all* replicas (needs RWX) or you use emptyDir | Usually hostPath (the node's own filesystem, e.g. `/var/log`) | `volumeClaimTemplates`: one PVC per pod (`data-db-0`, `data-db-1`), re-attached to the same ordinal after restart; PVCs are not deleted on scale-down |
| Update strategy | RollingUpdate (surge) or Recreate | RollingUpdate (`maxUnavailable`) or OnDelete | RollingUpdate in reverse ordinal order, `partition` for canaries, or OnDelete |
| Examples | `web-rolling` (Session 10), nginx frontends, REST APIs | `node-exporter`, `fluent-bit`, `kube-proxy`, k3s `svclb-*` (one per node, see below) | `web` headless demo (this session), MySQL/PostgreSQL, Kafka, Cassandra |

**Minimal manifests.**

```yaml
# DaemonSet: one node-agent on every node, reading the node's logs
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-agent
spec:
  selector:
    matchLabels: { app: node-agent }
  template:
    metadata:
      labels: { app: node-agent }
    spec:
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: agent
          image: busybox:1.36
          command: ["sh", "-c", "tail -F /host/var/log/syslog"]
          volumeMounts:
            - { name: varlog, mountPath: /host/var/log, readOnly: true }
      volumes:
        - name: varlog
          hostPath: { path: /var/log }
```

```yaml
# StatefulSet: three database pods, each with its own 1Gi volume and DNS name
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: db
spec:
  serviceName: db               # headless Service "db" must exist
  replicas: 3
  selector:
    matchLabels: { app: db }
  template:
    metadata:
      labels: { app: db }
    spec:
      containers:
        - name: db
          image: mysql:8
          env:
            - { name: MYSQL_ROOT_PASSWORD, value: "changeme-placeholder" }
          volumeMounts:
            - { name: data, mountPath: /var/lib/mysql }
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 1Gi
```

What the three look like once running:

```bash
kubectl get deploy,ds,sts -A | grep -E 'NAME|web-rolling|svclb|^s11.*web'
```

Output (captured 2026-10-08)
```text
NAMESPACE           NAME                                                  READY   UP-TO-DATE   AVAILABLE   AGE
s10                 deployment.apps/web-rolling                           4/4     4            4           3h54m
s11                 deployment.apps/web-clusterip                         3/3     3            3           3h57m
s11                 deployment.apps/web-loadbalancer                      3/3     3            3           3h57m
s11                 deployment.apps/web-nodeport                          2/2     2            2           3h57m
NAMESPACE     NAME                                                 DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
kube-system   daemonset.apps/svclb-traefik-5d031198                1         1         1       1            1           <none>                   4h5m
kube-system   daemonset.apps/svclb-web-loadbalancer-02f32f56       1         1         1       1            1           <none>                   3h57m
NAMESPACE    NAME                                                                    READY   AGE
s11          statefulset.apps/web                                                    3/3     3h57m
```

### 3. ReplicaSet vs Service

| Aspect | ReplicaSet | Service |
| --- | --- | --- |
| Responsibility | Pod **lifecycle**: keep N copies alive, replace crashed/evicted pods | Pod **access**: give a set of pods one stable address and spread traffic across the ready ones |
| Owns pods? | Yes (`ownerReferences`) | No; it only *selects* them by label |
| Reacts to | Pod count drifting from `replicas` | Pods becoming Ready/NotReady, appearing or disappearing (updates Endpoints/EndpointSlice) |
| Identity it provides | None; pods get random names and IPs | Stable ClusterIP + DNS name `svc.ns.svc.cluster.local` |
| Can exist without the other? | Yes, but nobody can reliably reach the pods | Yes, but with no pods it has empty Endpoints |

**ReplicaSet responsibility.** Keep the pods *existing*. If a node dies, the
ReplicaSet creates replacement pods elsewhere. It knows nothing about
traffic.

**Service responsibility.** Keep the pods *reachable*. It watches the pods
that match its selector and maintains the list of `IP:port` pairs that are
currently Ready (the Endpoints / EndpointSlice objects). kube-proxy turns
that list into forwarding rules on every node.

**Why a Service is required.** Pod IPs are ephemeral. Every pod the
ReplicaSet (re)creates gets a new IP, and a Deployment rollout replaces all
of them. A client that stored a pod IP would break at the first restart.
The Service's ClusterIP and DNS name are allocated once and never change
while the Service exists, so clients bind to the name, not to pods. The
Service also removes pods that fail their readiness probe, which the
ReplicaSet does not care about (it only restarts on liveness failures or
crashes).

```bash
kubectl -n s10 get endpoints web-rolling
kubectl -n s10 delete pod -l app=web-rolling --wait=false   # ReplicaSet recreates them
sleep 10
kubectl -n s10 get endpoints web-rolling
kubectl -n s10 get svc web-rolling -o jsonpath='{.spec.clusterIP}'; echo
```

Output (captured 2026-10-08)
```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME          ENDPOINTS                                                        AGE
web-rolling   10.42.0.197:8080,10.42.0.198:8080,10.42.0.199:8080 + 1 more...   3h58m
pod "web-rolling-7b85bb48cf-bb9p9" deleted from s10 namespace
pod "web-rolling-7b85bb48cf-ksthz" deleted from s10 namespace
pod "web-rolling-7b85bb48cf-tnd92" deleted from s10 namespace
pod "web-rolling-7b85bb48cf-v9v5p" deleted from s10 namespace
NAME          ENDPOINTS                                                        AGE
web-rolling   10.42.0.200:8080,10.42.0.201:8080,10.42.0.202:8080 + 1 more...   3h58m
10.43.34.175
```

All four pod IPs changed (`.197-.199` became `.200-.202` plus one more);
the ClusterIP `10.43.34.175` did not.

**How traffic reaches pods.**

```text
 1. client resolves "web-rolling" -> CoreDNS -> 10.43.34.175 (ClusterIP)
 2. client sends TCP SYN to 10.43.34.175:80
 3. on the client's node, kube-proxy's iptables/IPVS rules match the VIP
    and DNAT the packet to one Endpoint, e.g. 10.42.0.201:8080
    (random pick in iptables mode, round-robin/least-conn in IPVS mode)
 4. the CNI routes 10.42.0.201 to the right node and into the pod
 5. reply is un-NATed on the way back so the client sees 10.43.34.175

                 Service (VIP 10.43.34.175:80)
                            │
                 EndpointSlice: [10.42.0.200, .201, .202, .203]:8080
                            │        ▲ maintained by the endpoints controller
                            │        │ from pods with label app=web-rolling AND Ready=True
          ┌─────────────────┼─────────────────┐
          ▼                 ▼                 ▼
      pod .200           pod .201          pod .202 ...
          ▲                 ▲                 ▲
          └── created and replaced by ReplicaSet web-rolling-7b85bb48cf ──┘
```

The two objects are joined only by labels: the ReplicaSet's
`spec.selector.matchLabels` and the Service's `spec.selector` both say
`app=web-rolling`. If they disagree the pods run fine but the Service has
`<none>` endpoints, which is the most common "my service does not work"
bug.

## Deliverables

- `README.md` – this document: Deployment vs ReplicaSet (purpose, pod management, scaling, rolling updates, relationship); Deployment vs DaemonSet vs StatefulSet (use cases, pod creation, scaling, networking, storage, examples, manifests); ReplicaSet vs Service (responsibilities, why a Service is required, traffic path).
