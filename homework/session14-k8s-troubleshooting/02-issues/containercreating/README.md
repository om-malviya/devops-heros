# Issue: ContainerCreating (stuck)

Student: Om Malviya | Enrollment No: 24BCS10448

`ContainerCreating` is a normal transient state: the Pod is scheduled and kubelet is pulling images and setting up volumes/network. It becomes an issue when it **stays** there. The usual reason is a volume that cannot be mounted: a ConfigMap/Secret that does not exist.

### What I got wrong first

My first version of `broken.yaml` mounted a missing ConfigMap **and** a missing PVC. That Pod never reached `ContainerCreating`:

Output (captured 2026-10-08, first attempt)

```text
NAME      READY   STATUS    RESTARTS   AGE
cc-demo   0/1     Pending   0          57s

Events:
  Type     Reason            Age   From               Message
  ----     ------            ----  ----               -------
  Warning  FailedScheduling  56s   default-scheduler  0/1 nodes are available: persistentvolumeclaim "data-missing" not found. not found
```

The scheduler's volume-binding plugin checks PVCs **before** choosing a node, so a missing PVC is a `Pending` problem, not a `ContainerCreating` problem. ConfigMaps and Secrets are not checked by the scheduler; only the kubelet notices them when it mounts the volumes, which is exactly the stuck-in-ContainerCreating case I wanted. So `broken.yaml` now mounts a missing ConfigMap and a missing Secret.

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pod cc-demo -n s14
```

Output (captured 2026-10-08, before)

```text
pod/cc-demo created
NAME      READY   STATUS              RESTARTS   AGE
cc-demo   0/1     ContainerCreating   0          88s
```

Ninety seconds in `ContainerCreating` for a tiny `nginx:alpine` image that is already on the node is suspicious.

## 2. Investigate

```bash
kubectl describe pod cc-demo -n s14 | sed -n '/Volumes:/,$p'
kubectl get configmap cc-config-missing -n s14
kubectl get secret cc-secret-missing -n s14
```

Output (captured 2026-10-08)

```text
Volumes:
  config:
    Type:      ConfigMap (a volume populated by a ConfigMap)
    Name:      cc-config-missing
    Optional:  false
  creds:
    Type:        Secret (a volume populated by a Secret)
    SecretName:  cc-secret-missing
    Optional:    false
  kube-api-access-hdgtj:
    Type:                    Projected (a volume that contains injected data from multiple sources)
    ...
Events:
  Type     Reason       Age                From               Message
  ----     ------       ----               ----               -------
  Normal   Scheduled    88s                default-scheduler  Successfully assigned s14/cc-demo to colima
  Warning  FailedMount  24s (x8 over 88s)  kubelet            MountVolume.SetUp failed for volume "creds" : secret "cc-secret-missing" not found
  Warning  FailedMount  24s (x8 over 88s)  kubelet            MountVolume.SetUp failed for volume "config" : configmap "cc-config-missing" not found

Error from server (NotFound): configmaps "cc-config-missing" not found
Error from server (NotFound): secrets "cc-secret-missing" not found
```

## 3. Root cause

Kubelet reports `FailedMount` for both volumes (8 retries in 88 s): the ConfigMap `cc-config-missing` and the Secret `cc-secret-missing` do not exist in namespace `s14`. Kubelet retries forever and the container is never created, so there are no container events and no logs.

## 4. Fix

Create the ConfigMap and the Secret the Pod needs and reference them by their real names (`cc-config`, `cc-secret`):

```diff
   volumes:
     - name: config
       configMap:
-        name: cc-config-missing
+        name: cc-config
     - name: creds
       secret:
-        secretName: cc-secret-missing
+        secretName: cc-secret
```

Volume sources are immutable on a Pod, so I recreate it:

```bash
kubectl delete pod cc-demo -n s14
kubectl apply -f fixed.yaml      # creates ConfigMap cc-config + Secret cc-secret + the Pod
```

Output (captured 2026-10-08)

```text
pod "cc-demo" deleted from s14 namespace
configmap/cc-config created
secret/cc-secret created
pod/cc-demo created
```

If the Pod had needed real persistence I would create the PVC first and check it binds before creating the Pod:

```bash
kubectl get storageclass          # k3s has "local-path" as default
kubectl get pvc -n s14            # STATUS must be Bound before the Pod can start
```

## 5. Verify

```bash
kubectl get pod cc-demo -n s14
kubectl exec cc-demo -n s14 -- cat /etc/app/app.properties
kubectl exec cc-demo -n s14 -- ls /etc/creds
```

Output (captured 2026-10-08, after)

```text
NAME      READY   STATUS    RESTARTS   AGE
cc-demo   1/1     Running   0          119s
greeting=hello
log.level=info
api-key
```

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| Stuck ContainerCreating | `FailedMount ... configmap "cc-config-missing" not found`, `secret "cc-secret-missing" not found` | `kubectl describe pod` (Volumes + Events), `kubectl get cm/secret` | Volume sources do not exist | Create ConfigMap + Secret, recreate the Pod |
| (side finding) missing PVC | `Pending`, `FailedScheduling ... persistentvolumeclaim "data-missing" not found` | `kubectl describe pod` | Scheduler checks PVCs first | Create the PVC (and a StorageClass that can bind it) |

Tip: a ConfigMap/Secret volume can be marked `optional: true` if the app can start without it; then the Pod starts and the directory is simply empty.

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
