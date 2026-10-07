# Issue: ErrImagePull

Student: Om Malviya | Enrollment No: 24BCS10448

`ErrImagePull` and `ImagePullBackOff` are two phases of the same problem:

```text
Pull attempt fails  ->  ErrImagePull   (shown right after each failed attempt)
kubelet waits       ->  ImagePullBackOff (shown while waiting before the next attempt)
```

This scenario uses an image in a private/non-existent registry path (`ghcr.io/om-malviya-example/private-api:1.0.0`), which is the typical reason for `ErrImagePull` in real projects: the image exists but the cluster has no credentials, or the name is wrong.

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pod registry-demo -n s14 -w
```

Output (captured 2026-10-08, before; I stopped the watch after ~70 s)

```text
pod/registry-demo created
NAME            READY   STATUS              RESTARTS   AGE
registry-demo   0/1     ContainerCreating   0          0s
registry-demo   0/1     ErrImagePull        0          2s
registry-demo   0/1     ImagePullBackOff    0          16s
registry-demo   0/1     ErrImagePull        0          34s
registry-demo   0/1     ImagePullBackOff    0          46s
registry-demo   0/1     ErrImagePull        0          62s
```

The watch shows the two states alternating exactly as described above, with the back-off growing.

## 2. Investigate

```bash
kubectl describe pod registry-demo -n s14 | sed -n '/Events:/,$p'
kubectl get pod registry-demo -n s14 -o jsonpath='{.spec.imagePullSecrets}{"\n"}'
kubectl get secrets -n s14 --field-selector type=kubernetes.io/dockerconfigjson
```

Output (captured 2026-10-08)

```text
Events:
  Type     Reason     Age                 From               Message
  ----     ------     ----                ----               -------
  Normal   Scheduled  101s                default-scheduler  Successfully assigned s14/registry-demo to colima
  Warning  Failed     51s                 kubelet            spec.containers{api}: Failed to pull image "ghcr.io/om-malviya-example/private-api:1.0.0": failed to pull and unpack image "ghcr.io/om-malviya-example/private-api:1.0.0": failed to resolve reference "ghcr.io/om-malviya-example/private-api:1.0.0": failed to do request: Head "https://ghcr.io/v2/om-malviya-example/private-api/manifests/1.0.0": dial tcp: lookup ghcr.io: Try again
  Normal   BackOff    15s (x5 over 100s)  kubelet            spec.containers{api}: Back-off pulling image "ghcr.io/om-malviya-example/private-api:1.0.0"
  Warning  Failed     15s (x5 over 100s)  kubelet            spec.containers{api}: Error: ImagePullBackOff
  Normal   Pulling    3s (x4 over 101s)   kubelet            spec.containers{api}: Pulling image "ghcr.io/om-malviya-example/private-api:1.0.0"
  Warning  Failed     2s (x3 over 100s)   kubelet            spec.containers{api}: Failed to pull image "ghcr.io/om-malviya-example/private-api:1.0.0": failed to pull and unpack image "ghcr.io/om-malviya-example/private-api:1.0.0": failed to resolve reference "ghcr.io/om-malviya-example/private-api:1.0.0": failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://ghcr.io/token?scope=repository%3Aom-malviya-example%2Fprivate-api%3Apull&service=ghcr.io: 403 Forbidden
  Warning  Failed     2s (x4 over 100s)   kubelet            spec.containers{api}: Error: ErrImagePull

                                   <- empty line: the Pod has no imagePullSecrets
No resources found in s14 namespace.
```

Two different `Failed` messages appeared, which is a good reminder to read **all** the events: one attempt failed with `dial tcp: lookup ghcr.io: Try again` (a transient DNS hiccup inside the VM – a network problem, not an auth problem), the other three with `403 Forbidden` from the token endpoint.

## 3. Root cause

The registry answered `403 Forbidden` to an anonymous token request: the image is private (or does not exist, GHCR answers the same way for both) and the Pod has no `imagePullSecrets` (`{.spec.imagePullSecrets}` is empty, no `dockerconfigjson` Secret in the namespace). Compared with the previous issue, the message is about **authorization**, not `not found`.

## 4. Fix

Two valid fixes:

**A. Use an image the cluster can pull (what `fixed.yaml` does, because I do not own a private registry):**

```diff
-      image: ghcr.io/om-malviya-example/private-api:1.0.0
+      image: registry.k8s.io/e2e-test-images/agnhost:2.47
+      args: ["netexec", "--http-port=8080"]
```

**B. Keep the private image and give the cluster credentials (how I would do it at work):**

```bash
kubectl create secret docker-registry ghcr-creds -n s14 \
  --docker-server=ghcr.io \
  --docker-username=om-malviya-example \
  --docker-password=ghp_FAKE_TOKEN_REPLACE_ME \
  --docker-email=student@example.com
```

```yaml
spec:
  imagePullSecrets:
    - name: ghcr-creds
  containers:
    - name: api
      image: ghcr.io/om-malviya-example/private-api:1.0.0
```

Because fix A also adds `args`, which is immutable on a Pod, a plain `apply` is rejected; `replace --force` deletes and recreates the Pod:

```bash
kubectl apply -f fixed.yaml
kubectl replace --force -f fixed.yaml
```

Output (captured 2026-10-08)

```text
The Pod "registry-demo" is invalid: spec: Forbidden: pod updates may not change fields other than `spec.containers[*].image`,`spec.initContainers[*].image`,`spec.activeDeadlineSeconds`,`spec.tolerations` (only additions to existing tolerations),`spec.terminationGracePeriodSeconds` (allow it to be set to 1 if it was previously negative)
@@ -94,7 +94,10 @@
    "Name": "api",
    "Image": "ghcr.io/om-malviya-example/private-api:1.0.0",
    "Command": null,
-   "Args": null,
+   "Args": [
+    "netexec",
+    "--http-port=8080"
+   ],

pod "registry-demo" deleted from s14 namespace
pod/registry-demo replaced
```

(With fix B only `imagePullSecrets` changes, which is also immutable, so the Pod would be recreated as well. For a Deployment all of this is a normal rolling update.)

## 5. Verify

```bash
kubectl get pod registry-demo -n s14
kubectl exec registry-demo -n s14 -- wget -qO- localhost:8080/hostname
```

Output (captured 2026-10-08, after)

```text
NAME            READY   STATUS    RESTARTS   AGE
registry-demo   1/1     Running   0          55s
registry-demo
```

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| ErrImagePull | STATUS flipping `ErrImagePull` / `ImagePullBackOff`, `403 Forbidden ... anonymous token` | `kubectl get pod -w`, `kubectl describe pod` (Events), `-o jsonpath='{.spec.imagePullSecrets}'` | Private/unknown registry image, no pull secret | Public image (A) or `imagePullSecrets` + docker-registry Secret (B); recreate the Pod |

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
