# Issue: ImagePullBackOff

Student: Om Malviya | Enrollment No: 24BCS10448

Kubernetes could not download the container image. After the first failures (`ErrImagePull`) kubelet backs off and the Pod shows `ImagePullBackOff`. The container never starts, so there are **no logs** to read; the answer is always in the Events.

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pod image-demo -n s14
```

Output (captured 2026-10-08, before)

```text
pod/image-demo created
NAME         READY   STATUS             RESTARTS   AGE
image-demo   0/1     ImagePullBackOff   0          101s
```

## 2. Investigate

```bash
kubectl describe pod image-demo -n s14
kubectl logs image-demo -n s14
kubectl get pod image-demo -n s14 -o jsonpath='{.spec.containers[0].image}{"\n"}'
```

Output (captured 2026-10-08; describe trimmed)

```text
Status:           Pending
Containers:
  web:
    Container ID:
    Image:          nginx:this-tag-does-not-exist
    Image ID:
    State:          Waiting
      Reason:       ImagePullBackOff
    Ready:          False
    Restart Count:  0
Events:
  Type     Reason     Age                From               Message
  ----     ------     ----               ----               -------
  Normal   Scheduled  101s               default-scheduler  Successfully assigned s14/image-demo to colima
  Warning  Failed     55s (x3 over 98s)  kubelet            spec.containers{web}: Failed to pull image "nginx:this-tag-does-not-exist": rpc error: code = NotFound desc = failed to pull and unpack image "docker.io/library/nginx:this-tag-does-not-exist": failed to resolve reference "docker.io/library/nginx:this-tag-does-not-exist": docker.io/library/nginx:this-tag-does-not-exist: not found
  Warning  Failed     55s (x3 over 98s)  kubelet            spec.containers{web}: Error: ErrImagePull
  Normal   BackOff    20s (x5 over 98s)  kubelet            spec.containers{web}: Back-off pulling image "nginx:this-tag-does-not-exist"
  Warning  Failed     20s (x5 over 98s)  kubelet            spec.containers{web}: Error: ImagePullBackOff
  Normal   Pulling    6s (x4 over 100s)  kubelet            spec.containers{web}: Pulling image "nginx:this-tag-does-not-exist"

Error from server (BadRequest): container "web" in pod "image-demo" is waiting to start: trying and failing to pull image

nginx:this-tag-does-not-exist
```

Note that the Pod phase is still `Pending` (and `Container ID` / `Image ID` are empty): no container has ever been created.

## 3. Root cause

The event message is explicit: `docker.io/library/nginx:this-tag-does-not-exist: not found`. The repository `nginx` exists, but the **tag** does not. I double-checked by looking at the tags on Docker Hub (`alpine`, `1.27-alpine`, ... exist; `this-tag-does-not-exist` does not).

## 4. Fix

```diff
-      image: nginx:this-tag-does-not-exist
+      image: nginx:alpine
```

```bash
kubectl apply -f fixed.yaml      # image is a mutable field, no delete needed
```

Output (captured 2026-10-08)

```text
pod/image-demo configured
```

## 5. Verify

```bash
kubectl get pod image-demo -n s14
kubectl get events -n s14 --field-selector involvedObject.name=image-demo --sort-by=.lastTimestamp | tail -3
```

Output (captured 2026-10-08, after)

```text
NAME         READY   STATUS    RESTARTS   AGE
image-demo   1/1     Running   0          3m20s
62s         Normal    Pulled      pod/image-demo   Container image "nginx:alpine" already present on machine and can be accessed by the pod
62s         Normal    Created     pod/image-demo   Container created
61s         Normal    Started     pod/image-demo   Container started
```

The Pod kept its name and AGE (3m20s) because I only patched the image; kubelet picked up the new image on its next retry and started the container (`already present on machine` because other Pods in the cluster had already pulled `nginx:alpine`).

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| ImagePullBackOff | `0/1 ImagePullBackOff`, `Failed to pull image ... not found` | `kubectl describe pod` (Events) | Image tag does not exist | Correct the tag (`nginx:alpine`), `kubectl apply` is enough |

Checklist I use for any pull problem: 1) typo in name or tag? 2) does the registry need credentials (`imagePullSecrets`)? 3) can the node reach the registry (proxy/firewall/DNS)? 4) rate limit (`toomanyrequests`)? 5) architecture mismatch (`no match for platform`)?

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
