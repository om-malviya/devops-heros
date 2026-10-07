# Issue: Pending

Student: Om Malviya | Enrollment No: 24BCS10448

`Pending` means the Pod exists in the API but **no node has accepted it yet**. `NODE` is `<none>` in `-o wide`. Kubelet has not even started, so there are no container events, no logs - only the scheduler's `FailedScheduling` events.

`broken.yaml` creates two Pods with the two most common causes: unsatisfiable resource requests and a `nodeSelector` that matches no node.

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pods -n s14 -l 'app in (pending-cpu,pending-selector)' -o wide
```

Output (captured 2026-10-08, before)

```text
pod/pending-cpu created
pod/pending-selector created
NAME               READY   STATUS    RESTARTS   AGE    IP       NODE     NOMINATED NODE   READINESS GATES
pending-cpu        0/1     Pending   0          102s   <none>   <none>   <none>           <none>
pending-selector   0/1     Pending   0          102s   <none>   <none>   <none>           <none>
```

## 2. Investigate

```bash
kubectl describe pod pending-cpu -n s14 | sed -n '/Conditions:/,$p'
kubectl describe pod pending-selector -n s14 | sed -n '/Events:/,$p'
kubectl get nodes --show-labels
kubectl describe node colima | sed -n '/Allocatable:/,/System Info/p'
```

Output (captured 2026-10-08; Volumes/Tolerations lines removed)

```text
Conditions:
  Type           Status
  PodScheduled   False
QoS Class:                   Burstable
Node-Selectors:              <none>
Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  102s  default-scheduler  0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.

Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  102s  default-scheduler  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. no new claims to deallocate, preemption: 0/1 nodes are available: 1 Preemption is not helpful for scheduling.

NAME     STATUS   ROLES           AGE    VERSION        LABELS
colima   Ready    control-plane   4h2m   v1.35.0+k3s1   beta.kubernetes.io/arch=arm64,beta.kubernetes.io/instance-type=k3s,beta.kubernetes.io/os=linux,kubernetes.io/arch=arm64,kubernetes.io/hostname=colima,kubernetes.io/os=linux,node-role.kubernetes.io/control-plane=true,node.kubernetes.io/instance-type=k3s

Allocatable:
  cpu:                4
  ephemeral-storage:  18698430040
  hugepages-1Gi:      0
  hugepages-2Mi:      0
  hugepages-32Mi:     0
  hugepages-64Ki:     0
  memory:             6052120Ki
  pods:               110
System Info:
```

The only Condition present is `PodScheduled: False`; `Initialized`, `Ready` etc. do not even exist yet because the Pod never reached a kubelet.

## 3. Root cause

* `pending-cpu` requests `cpu: 64` and `memory: 512Gi`; the only node has 4 CPUs and ~5.8 GiB allocatable. The scheduler message says `Insufficient cpu, Insufficient memory`.
* `pending-selector` has `nodeSelector: disktype: nvme-does-not-exist`; `kubectl get nodes --show-labels` shows no node carries a `disktype` label at all, hence `didn't match Pod's node affinity/selector`.

Both are **scheduling constraints**, not application bugs.

## 4. Fix

```diff
       resources:
         requests:
-          cpu: "64"
-          memory: "512Gi"
+          cpu: "50m"
+          memory: "32Mi"
```

```diff
 spec:
-  nodeSelector:
-    disktype: nvme-does-not-exist
   containers:
```

(The alternative for the selector case is to label a node: `kubectl label node colima disktype=nvme-does-not-exist`.)

Requests and nodeSelector are immutable on a running Pod, so I recreate them:

```bash
kubectl delete -f broken.yaml
kubectl apply -f fixed.yaml
```

Output (captured 2026-10-08)

```text
pod "pending-cpu" deleted from s14 namespace
pod "pending-selector" deleted from s14 namespace
pod/pending-cpu created
pod/pending-selector created
```

## 5. Verify

```bash
kubectl get pods -n s14 -l 'app in (pending-cpu,pending-selector)' -o wide
```

Output (captured 2026-10-08, after)

```text
NAME               READY   STATUS    RESTARTS   AGE   IP            NODE     NOMINATED NODE   READINESS GATES
pending-cpu        1/1     Running   0          57s   10.42.0.182   colima   <none>           <none>
pending-selector   1/1     Running   0          57s   10.42.0.181   colima   <none>           <none>
```

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| Pending (resources) | `NODE <none>`, `Insufficient cpu/memory` | `kubectl describe pod` (Events), `kubectl describe node` (Allocatable) | Requests larger than any node | Realistic requests |
| Pending (selector) | `didn't match Pod's node affinity/selector` | `kubectl get nodes --show-labels` | nodeSelector label does not exist | Remove selector or label a node |

Other `Pending` causes I keep in mind: taints without tolerations (`had untolerated taint`), a PVC that does not exist or is unbound (I hit `persistentvolumeclaim "data-missing" not found` while building the ContainerCreating scenario, see `../containercreating/README.md`), too many pods on the node (`Too many pods`), or a node that is `NotReady`.

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
