# Scenario 1: Wrong image tag -> ImagePullBackOff

Prerequisite: the healthy stack from `kubernetes/` (or the Helm chart) is deployed in namespace `taskboard`.

On the k3s cluster used for the captured output the images come from a local registry and the Ingress class is Traefik, so every apply below was piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#' <file> | kubectl apply -f -`.

```bash
kubectl apply -f troubleshooting/01-wrong-image-tag/broken.yaml
```

## 1. Identify the issue

`kubectl get pods` shows the backend pod stuck in `ErrImagePull` / `ImagePullBackOff`, the frontend shows 'Backend unavailable'.

## 2. Investigate logs and resources

```bash
kubectl -n taskboard get pods
kubectl -n taskboard describe pod -l app=taskboard-backend | sed -n '/Events/,$p'
kubectl -n taskboard get deploy taskboard-backend -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get pods -l app=taskboard-backend
NAME                                 READY   STATUS             RESTARTS   AGE
taskboard-backend-6db658b5f-bw4kk    1/1     Running            4          8m42s   <- old ReplicaSet pod, kept alive by maxUnavailable: 0
taskboard-backend-7b5498f9c4-2g2bw   0/1     ImagePullBackOff   0          27s
taskboard-backend-7b5498f9c4-flj9h   0/1     ErrImagePull       0          40s
$ kubectl -n taskboard get events --field-selector reason=Failed --sort-by=.lastTimestamp | tail -3
12s   Warning   Failed   pod/taskboard-backend-7b5498f9c4-2g2bw   Error: ErrImagePull
12s   Warning   Failed   pod/taskboard-backend-7b5498f9c4-2g2bw   Failed to pull image "ghcr.io/om-malviya/taskboard-backend:v9.9.9-does-not-exist": failed to pull and unpack image ...: failed to resolve reference ...: failed to authorize: failed to fetch anonymous token: unexpected status from GET request to https://ghcr.io/token?scope=repository%3Aom-malviya%2Ftaskboard-backend%3Apull&service=ghcr.io: 403 Forbidden
8s    Warning   Failed   pod/taskboard-backend-7b5498f9c4-flj9h   Error: ImagePullBackOff
$ kubectl -n taskboard get deploy taskboard-backend -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
ghcr.io/om-malviya/taskboard-backend:v9.9.9-does-not-exist
```

## 3. Root cause

The Deployment references a tag that was never pushed to GHCR. In the captured run the message is `403 Forbidden` from the GHCR token endpoint, because the whole repository does not exist yet; once the repository exists but the tag does not, the message becomes `manifest unknown`. Either way the pod ends in `ImagePullBackOff`. The kubelet retries with exponential back-off, which is what `ImagePullBackOff` means. The same symptom appears for a typo in the registry/name or a private registry without an `imagePullSecret` (then the message is `unauthorized`).

## 4. Fix

```bash
kubectl -n taskboard set image deployment/taskboard-backend backend=ghcr.io/om-malviya/taskboard-backend:latest
# or, the GitOps way: correct the tag in Git and apply the fixed manifest
kubectl apply -f fixed.yaml
```

## 5. Verify

```bash
kubectl -n taskboard rollout status deployment/taskboard-backend
kubectl -n taskboard get pods -l app=taskboard-backend
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard rollout status deployment/taskboard-backend --timeout=180s
Waiting for deployment "taskboard-backend" rollout to finish: 2 old replicas are pending termination...
deployment "taskboard-backend" successfully rolled out
$ kubectl -n taskboard get pods -l app=taskboard-backend
NAME                                READY   STATUS    RESTARTS   AGE
taskboard-backend-6db658b5f-bw4kk   1/1     Running   4          9m3s
taskboard-backend-6db658b5f-f8ftr   1/1     Running   0          18s
```

## 6. Document

| | |
|---|---|
| Symptom | `kubectl get pods` shows the backend pod stuck in `ErrImagePull` / `ImagePullBackOff`, the frontend shows 'Backend unavailable'. |
| Root cause | The Deployment references a tag that was never pushed to GHCR (`manifest unknown`). |
| Fix | `kubectl apply -f fixed.yaml` (see diff below) |
| Lesson | Always deploy immutable tags produced by CI (the git SHA) and let the pipeline fail if the push failed; `latest` hides which build is running. |

```bash
diff troubleshooting/01-wrong-image-tag/broken.yaml troubleshooting/01-wrong-image-tag/fixed.yaml
```
