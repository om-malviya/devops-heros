# Final Troubleshooting Challenge

Six faults were introduced on purpose into otherwise healthy TaskBoard manifests. Each folder contains
`broken.yaml` (apply it to reproduce), `fixed.yaml` (the correction) and a `README.md` that walks through the
six required steps: identify -> investigate -> root cause -> fix -> verify -> document.

| # | Folder | Fault | Symptom in `kubectl` |
|---|--------|-------|----------------------|
| 1 | `01-wrong-image-tag/` | image tag that does not exist in GHCR | `ImagePullBackOff` |
| 2 | `02-service-selector-mismatch/` | Service selector `app=taskboard-api` vs pod label `app=taskboard-backend` | `ENDPOINTS <none>`, 503 |
| 3 | `03-wrong-secret-key/` | `secretKeyRef.key: DB_URL` (Secret has `DATABASE_URL`) | `CreateContainerConfigError` / `CrashLoopBackOff` |
| 4 | `04-readiness-probe-wrong-path/` | readiness probe on `/readyz` instead of `/ready` | `Running` but `0/1 READY` forever |
| 5 | `05-hpa-no-resource-requests/` | HPA on a Deployment without CPU requests | `TARGETS <unknown>/60%`, never scales |
| 6 | `06-ingress-wrong-backend-port/` | Ingress `/api` -> Service port 8080 (Service listens on 8000) | 503/502 on `/api`, UI "Backend unavailable" |

## Generic triage order I use

```bash
kubectl -n taskboard get pods -o wide                 # which pod, which state?
kubectl -n taskboard describe pod <pod>               # events: pull errors, probe failures, config errors
kubectl -n taskboard logs <pod> [--previous]          # application output of the current / crashed container
kubectl -n taskboard get endpoints,svc                # does traffic have somewhere to go?
kubectl -n taskboard describe ingress taskboard       # resolved backends per path
kubectl -n taskboard get hpa; kubectl top pods        # autoscaling inputs
kubectl get events -n taskboard --sort-by=.lastTimestamp | tail -20
```

All six scenarios were executed on a k3s cluster on 2026-10-08; each README now shows the captured symptom and recovery (images from `localhost:5002`, Ingress class `traefik`, substituted with `sed` at apply time).

Reset to the healthy state at any time:

```bash
kubectl apply -k kubernetes/
```
