# Task 1 – Kubernetes Volumes

Student: Om Malviya | Enrollment No: 24BCS10448

What I learned about storage in Kubernetes, with runnable examples. All examples use namespace
`s13` (`kubectl apply -f ../namespace.yaml` first) and small multi-arch images (`busybox:1.36`,
`nginx:alpine`). Cluster: single-node k3s v1.35 in a Colima VM (default StorageClass `local-path`);
minikube notes where it differs. All outputs below were captured on that cluster.

| File | Demonstrates |
| --- | --- |
| `emptydir-pod.yaml` | `emptyDir` shared by two containers of one Pod |
| `hostpath-pod.yaml` | `hostPath` directory from the node |
| `pv.yaml` | static `PersistentVolume` (hostPath-backed, `Retain`) |
| `pvc-static.yaml`, `pod-static-pvc.yaml` | `PersistentVolumeClaim` bound to that PV, Pod using it |
| `pvc-dynamic.yaml`, `pod-dynamic-pvc.yaml` | dynamic provisioning through a `StorageClass` |

## Why volumes?

A container's writable layer disappears when the container is recreated. A volume is a directory
that is mounted into one or more containers and whose lifetime is defined by something other than the
container: the Pod (`emptyDir`), the node (`hostPath`) or an independent storage object (`PersistentVolume`).

```text
lifetime:   container  <  Pod (emptyDir)  <  node (hostPath)  <  cluster/external (PV, PVC, StorageClass)
```

## 1. emptyDir

An empty directory created when the Pod is scheduled to a node. Every container in the Pod can mount
it; the data is deleted when the Pod is removed (restarting a *container* keeps it).
Typical use: scratch space, caches, sharing files between a main container and a sidecar.

```yaml
# emptydir-pod.yaml (excerpt): writer appends to /data/log.txt, nginx serves the same directory
volumes:
  - name: shared
    emptyDir: {}      # options: sizeLimit: 100Mi, medium: Memory (tmpfs)
```

```bash
kubectl apply -f emptydir-pod.yaml
kubectl get pod emptydir-demo -n s13
sleep 15
kubectl exec -n s13 emptydir-demo -c reader -- cat /usr/share/nginx/html/log.txt
kubectl exec -n s13 emptydir-demo -c reader -- wget -qO- http://localhost/log.txt | tail -1
```

Output (captured 2026-10-07):

```text
pod/emptydir-demo created
NAME            READY   STATUS    RESTARTS   AGE
emptydir-demo   2/2     Running   0          1s
Wed Oct  7 17:15:20 UTC 2026 written by writer container
Wed Oct  7 17:15:25 UTC 2026 written by writer container
Wed Oct  7 17:15:30 UTC 2026 written by writer container
Wed Oct  7 17:15:35 UTC 2026 written by writer container
Wed Oct  7 17:15:35 UTC 2026 written by writer container
```

Both containers see the same files although they have different images. Now delete and recreate the Pod:

```bash
kubectl delete pod emptydir-demo -n s13
kubectl apply -f emptydir-pod.yaml
sleep 6
kubectl exec -n s13 emptydir-demo -c reader -- cat /usr/share/nginx/html/log.txt
```

Output (captured 2026-10-07):

```text
pod "emptydir-demo" deleted from s13 namespace
pod/emptydir-demo created
Wed Oct  7 17:16:06 UTC 2026 written by writer container
```

Only one fresh line: the old `emptyDir` died with the old Pod.

## 2. hostPath

Mounts a path from the **node's** filesystem. The data survives Pod deletion, but only on that node:
if the Pod is rescheduled elsewhere the data is "gone". Needs privileges on real clusters and is
mostly for single-node labs, node agents (log collectors) and CSI drivers themselves.

```yaml
# hostpath-pod.yaml (excerpt)
volumes:
  - name: host-storage
    hostPath:
      path: /tmp/s13-hostpath-data
      type: DirectoryOrCreate
```

```bash
kubectl apply -f hostpath-pod.yaml
kubectl exec -n s13 hostpath-demo -- sh -c 'echo "hello from hostPath" > /data/note.txt'
kubectl delete pod hostpath-demo -n s13
kubectl apply -f hostpath-pod.yaml
kubectl exec -n s13 hostpath-demo -- cat /data/note.txt
```

Output (captured 2026-10-07):

```text
pod/hostpath-demo created
pod "hostpath-demo" deleted from s13 namespace
pod/hostpath-demo created
hello from hostPath
```

The file survived because it lives in `/tmp/s13-hostpath-data` on the node (check with
`sudo ls /tmp/s13-hostpath-data` on the k3s host, `colima ssh -- ls /tmp/s13-hostpath-data` on Colima,
or `minikube ssh -- ls /tmp/s13-hostpath-data`; I did not ssh into the shared VM).

## 3. PersistentVolume (PV)

A cluster-scoped object that represents a piece of storage: capacity, access modes, reclaim policy
and the backend (hostPath, NFS, a cloud disk, a CSI driver). Created by an administrator (static
provisioning) or by a provisioner (dynamic provisioning).

```yaml
# pv.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: s13-static-pv
spec:
  storageClassName: manual
  capacity:
    storage: 1Gi
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /tmp/s13-static-pv
    type: DirectoryOrCreate
```

```bash
kubectl apply -f pv.yaml
kubectl get pv s13-static-pv
```

Output (captured 2026-10-07):

```text
persistentvolume/s13-static-pv created
NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-static-pv   1Gi        RWO            Retain           Available           manual         <unset>                          0s
```

(The `VOLUMEATTRIBUTESCLASS` column is new in Kubernetes 1.31+; `<unset>` just means no
VolumeAttributesClass is used.)

`Available` = exists, nobody has claimed it yet.

## 4. PersistentVolumeClaim (PVC)

A namespaced **request** for storage by a developer: "I need 500Mi, ReadWriteOnce, class manual".
Kubernetes binds it to a PV that satisfies the request (same class, access mode included, capacity
>= requested). The Pod references the claim, never the PV, which decouples the app from the storage
implementation.

```bash
kubectl apply -f pvc-static.yaml
kubectl get pvc static-pvc -n s13
kubectl get pv s13-static-pv
```

Output (captured 2026-10-07):

```text
persistentvolumeclaim/static-pvc created
NAME         STATUS   VOLUME          CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
static-pvc   Bound    s13-static-pv   1Gi        RWO            manual         <unset>                 3s

NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM            STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-static-pv   1Gi        RWO            Retain           Bound    s13/static-pvc   manual         <unset>                          3s
```

Note the PVC shows capacity `1Gi` (the PV's size) even though it asked for 500Mi: binding is 1:1 and
the whole PV is taken.

Use it from a Pod and prove the data outlives the Pod:

```bash
kubectl apply -f pod-static-pvc.yaml
kubectl exec -n s13 static-pvc-demo -- sh -c 'echo "Kubernetes Storage" > /data/message.txt'
kubectl delete pod static-pvc-demo -n s13
kubectl apply -f pod-static-pvc.yaml
kubectl exec -n s13 static-pvc-demo -- cat /data/message.txt
```

Output (captured 2026-10-07):

```text
pod/static-pvc-demo created
pod "static-pvc-demo" deleted from s13 namespace
pod/static-pvc-demo created
Kubernetes Storage
```

```text
Pod  --(claimName)-->  PVC  --(bound)-->  PV  -->  /tmp/s13-static-pv on the node
```

## 5. StorageClass

Describes a *type* of storage and which provisioner creates it. With a StorageClass nobody has to
pre-create PVs: the claim names the class and the provisioner makes a PV to fit.

```bash
kubectl get storageclass
kubectl describe storageclass local-path
```

Output (captured 2026-10-07, k3s; the long `objectset.rio.cattle.io/...` annotations that k3s adds are
cut from the Annotations line):

```text
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ALLOWVOLUMEEXPANSION   AGE
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   false                  13m

Name:                  local-path
IsDefaultClass:        Yes
Annotations:           defaultVolumeType=local,objectset.rio.cattle.io/...,storageclass.kubernetes.io/is-default-class=true
Provisioner:           rancher.io/local-path
Parameters:            <none>
AllowVolumeExpansion:  <unset>
MountOptions:          <none>
ReclaimPolicy:         Delete
VolumeBindingMode:     WaitForFirstConsumer
Events:                <none>
```

Expected output (minikube; not run, I only had the k3s cluster):

```text
NAME                 PROVISIONER                RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
standard (default)   k8s.io/minikube-hostpath   Delete          Immediate           false                  1h
```

Key fields: `provisioner` (who creates the PV), `reclaimPolicy` (what happens to the PV after the
PVC is deleted), `volumeBindingMode` (`Immediate` = PV created as soon as the PVC exists;
`WaitForFirstConsumer` = wait until a Pod needs it, so the volume is created on the node where the Pod
is scheduled), and the `is-default-class` annotation (used when a PVC has no `storageClassName`).

## 6. Dynamic provisioning

```yaml
# pvc-dynamic.yaml (excerpt)
spec:
  storageClassName: local-path     # minikube: standard; or omit to use the default class
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 500Mi
```

```bash
kubectl apply -f pvc-dynamic.yaml
kubectl get pvc dynamic-pvc -n s13
```

Output (captured 2026-10-07, k3s, `WaitForFirstConsumer`):

```text
persistentvolumeclaim/dynamic-pvc created
NAME          STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
dynamic-pvc   Pending                                      local-path     <unset>                 3s
```

`Pending` is normal here, the describe output says why:

```bash
kubectl describe pvc dynamic-pvc -n s13 | tail -3
```

Output (captured 2026-10-07):

```text
Events:
  Type    Reason                Age   From                         Message
  ----    ------                ----  ----                         -------
  Normal  WaitForFirstConsumer  3s    persistentvolume-controller  waiting for first consumer to be created before binding
```

(On minikube the class is `Immediate`, so the PVC is `Bound` right away.) Create the consumer:

```bash
kubectl apply -f pod-dynamic-pvc.yaml
sleep 10
kubectl get pvc dynamic-pvc -n s13
kubectl get pv
```

Output (captured 2026-10-07):

```text
pod/dynamic-pvc-demo created
NAME          STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
dynamic-pvc   Bound    pvc-d50c9a25-c120-45e1-824a-ea8e6c73c5f9   500Mi      RWO            local-path     <unset>                 7s

NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM             STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
pvc-d50c9a25-c120-45e1-824a-ea8e6c73c5f9   500Mi      RWO            Delete           Bound    s13/dynamic-pvc   local-path     <unset>                          2s
s13-static-pv                              1Gi        RWO            Retain           Bound    s13/static-pvc    manual         <unset>                          44s
```

I never wrote a PV for `dynamic-pvc`; the `local-path` provisioner created `pvc-d50c9a25-...` with
exactly 500Mi, reclaim policy `Delete` (inherited from the class), about 4 seconds after the Pod was
scheduled (the PV is 2 s old while the PVC is 7 s old). Static vs dynamic side by side:

```text
STATIC:   admin writes pv.yaml  ->  dev writes pvc.yaml  ->  binding by matching  ->  Pod
DYNAMIC:  dev writes pvc.yaml (storageClassName)  ->  provisioner creates PV  ->  Bound  ->  Pod
```

## 7. Access modes

| Mode | Short | Meaning | Supported by |
| --- | --- | --- | --- |
| ReadWriteOnce | RWO | read/write by **one node** (several Pods on that node may share it) | almost everything: local-path, hostPath, cloud disks |
| ReadOnlyMany | ROX | read-only by many nodes | NFS, some cloud disks |
| ReadWriteMany | RWX | read/write by many nodes | NFS, CephFS, EFS, Azure Files |
| ReadWriteOncePod | RWOP | read/write by exactly **one Pod** | CSI drivers (k8s 1.29+) |

Access mode is a capability declaration, not enforcement: `local-path` and `hostPath` only offer RWO.

## 8. Reclaim policies

What happens to the PV (and the data) when its PVC is deleted:

| Policy | Effect | Typical for |
| --- | --- | --- |
| `Retain` | PV goes to `Released`, data kept, admin must clean up and delete/re-create the PV manually | static PVs, databases |
| `Delete` | PV and backing storage deleted automatically | dynamically provisioned volumes (default for most classes) |
| `Recycle` | `rm -rf` then back to `Available` (deprecated) | legacy NFS/hostPath |

```bash
kubectl delete pod static-pvc-demo -n s13
kubectl delete pvc static-pvc -n s13
kubectl get pv s13-static-pv
```

Output (captured 2026-10-07):

```text
pod "static-pvc-demo" deleted from s13 namespace
persistentvolumeclaim "static-pvc" deleted from s13 namespace
NAME            CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS     CLAIM            STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
s13-static-pv   1Gi        RWO            Retain           Released   s13/static-pvc   manual         <unset>                          94s
```

`Released` (not `Available`): a Retain PV keeps the old `claimRef` so no new claim can grab someone
else's data. To reuse it: `kubectl patch pv s13-static-pv -p '{"spec":{"claimRef":null}}'` or delete
and re-apply `pv.yaml` (the hostPath data stays on disk either way).

## 9. PV/PVC lifecycle (binding)

```text
Provisioning  ->  Binding  ->  Using  ->  Releasing  ->  Reclaiming
 (static PV      (PVC matched   (Pod mounts   (PVC deleted,   (Retain: Released, manual
  or dynamic)     to a PV,       the claim;    PV becomes      Delete: PV + data removed)
                  both Bound)    pvc-protection Released)
                                 finalizer blocks
                                 deletion while in use)
```

Things I noticed while testing: a PVC in use cannot be deleted until its Pod is gone
(`kubernetes.io/pvc-protection` finalizer keeps it `Terminating`), which is why I deleted the Pod
before the PVC in section 8; a PVC stays `Pending` forever when no PV matches (wrong
`storageClassName`, requested size larger than any PV, or access mode not offered); and
`kubectl describe pvc` is the first command to run in both cases. One more observation: the `sleep 3600`
demo Pods restart once an hour (`RESTARTS 3` after ~3.5 h), because `sleep` exits and the default
`restartPolicy: Always` restarts the container; the data in the hostPath and PVC volumes was still
there afterwards, only the `emptyDir` is cleared when the whole Pod goes away.

## Cleanup

```bash
kubectl delete -f pod-dynamic-pvc.yaml -f pvc-dynamic.yaml -f pod-static-pvc.yaml -f pvc-static.yaml \
               -f hostpath-pod.yaml -f emptydir-pod.yaml --ignore-not-found
kubectl delete -f pv.yaml --ignore-not-found
```

## Deliverables

- This README – volume documentation (emptyDir, hostPath, PV, PVC, StorageClass, dynamic provisioning, access modes, reclaim policies, lifecycle).
- `emptydir-pod.yaml`, `hostpath-pod.yaml`, `pv.yaml`, `pvc-static.yaml`, `pod-static-pvc.yaml`, `pvc-dynamic.yaml`, `pod-dynamic-pvc.yaml` – practical examples.
