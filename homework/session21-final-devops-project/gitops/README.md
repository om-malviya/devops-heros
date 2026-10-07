# gitops/ - Argo CD

Git is the single source of truth for what runs in the cluster. CI builds, scans and pushes images;
Argo CD (running *inside* the cluster) pulls the Helm chart from this repository and reconciles it.

```text
developer -> git push -> GitHub Actions (test, scan, build, push ghcr.io/...:<sha>)
                                  |
                                  v  (commit / parameter bump of backend.image.tag)
                     Argo CD watches homework/session21-final-devops-project/helm/taskboard
                                  |
                                  v
                  helm template -> kubectl apply (automated, prune, selfHeal)
```

| File | Purpose |
|------|---------|
| `argocd/application-dev.yaml` | Application `taskboard-dev`: values-dev.yaml, automated sync, prune + selfHeal, CreateNamespace |
| `argocd/application-prod.yaml` | Application `taskboard-prod`: values-prod.yaml, selfHeal but **no** auto-prune, pinned image tags |
| `install-argocd.sh` | installs Argo CD and applies the dev Application |

## Usage

```bash
./gitops/install-argocd.sh
kubectl -n argocd get applications
argocd app get taskboard-dev           # with the CLI: brew install argocd ; argocd login localhost:8443
argocd app sync taskboard-dev
argocd app history taskboard-dev && argocd app rollback taskboard-dev 1
```

```text
Output (captured 2026-10-08, k3s - before the repository was pushed to GitHub)
$ ./gitops/install-argocd.sh
==> Installing Argo CD v2.13.3 into namespace argocd
namespace/argocd created ... (59 objects)
==> Waiting for the Argo CD server to become ready
==> Registering the TaskBoard application
application.argoproj.io/taskboard-dev created
==> Initial admin password (change it after first login):
<redacted>
$ kubectl -n argocd get applications
NAME            SYNC STATUS   HEALTH STATUS
taskboard-dev   Unknown       Healthy
$ kubectl -n argocd get application taskboard-dev -o jsonpath='{.status.conditions}'
[{"type":"ComparisonError","message":"Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = authentication required"}]
```

`SYNC STATUS Unknown` + `ComparisonError ... authentication required` is what Argo CD shows while
`https://github.com/om-malviya/devops-heros.git` does not exist yet (GitHub answers that way for unknown
repositories). Nothing was applied to the cluster. Once the repository is pushed the repo-server fetches `main`,
renders the chart and the automated sync reports `Synced / Healthy`. Argo CD was removed again afterwards
(`kubectl delete application`, `kubectl delete -f install.yaml`, `kubectl delete ns argocd`).

## Why `selfHeal` and `prune`

* `selfHeal: true` - if somebody runs `kubectl scale deploy ... --replicas=10` by hand, Argo CD puts it back
  to what Git says within ~3 minutes (drift correction). The backend replica count is excluded via
  `ignoreDifferences` because the HPA legitimately owns it.
* `prune: true` (dev only) - deleting a template from the chart deletes the object from the cluster.
  In prod it is `false`, so deletions show as OutOfSync and need a human `argocd app sync --prune`.

## Promoting a new version

1. CI pushes `ghcr.io/om-malviya/taskboard-backend:<sha>`.
2. A commit updates `backend.image.tag` in `application-dev.yaml` (or in `values-dev.yaml`); a PR does the same
   for prod. The Git history is the deployment audit log.
3. Argo CD detects the change, renders the chart, applies it and reports Synced/Healthy.
