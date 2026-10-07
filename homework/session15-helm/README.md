# Session 15 – Helm
Student: Om Malviya | Enrollment No: 24BCS10448

Helm is the package manager for Kubernetes: one **chart** (templates + default values) is rendered with different **values** into a **release** per environment, and every install/upgrade/rollback is tracked as a revision.

All releases in this homework live in namespace `s15`. I used Helm `v4.3.0` against a single-node k3s cluster (Kubernetes v1.35.0+k3s1), so every block - lint/template as well as install/upgrade/rollback/uninstall and the repo/search commands - is real captured output (`Output (captured 2026-10-08)`; the lint/template blocks were captured a day earlier). Two Helm-4 differences I noticed: `helm status --show-resources` is gone (resources are listed by default) and `--dry-run` wants `--dry-run=client`.

```text
session15-helm/
  01-helm-commands/      Task 1 – every Helm command with purpose and output
  02-rollback-workflow/  Task 2 – webapp chart + rollback-demo.sh + documented workflow
  mini-project/          Task 3 – notes-chart (values.yaml / values-prod.yaml), install, upgrade, rollback
```

## Task 1: Helm Commands

[01-helm-commands/README.md](01-helm-commands/README.md) – for each command: execute it, understand what it does, capture the output, document it.

| Command | Covered with |
|---|---|
| `helm create` | `demo-chart` skeleton, file list |
| `helm install` | `demo` release in `s15`, `--dry-run`, `--wait`, `upgrade --install` |
| `helm list` | `-n`, `-A`, `-o json` |
| `helm status` | resources listed by default in Helm 4 |
| `helm get` | `values` (`--all`), `manifest`, `notes`, `all` |
| `helm upgrade` | `--set replicaCount=2`, `--reuse-values`, `-f`, `--atomic` |
| `helm history` | revision table |
| `helm rollback` | `rollback demo 1`, history after rollback |
| `helm uninstall` | plain and `--keep-history` |
| `helm repo` | `add` / `update` / `list` / `remove` with the Bitnami repo, all run (note on the 2025 catalog change) |
| `helm search` | `search repo nginx`, `--versions`, `search hub nginx` |

## Task 2: Helm Rollback

[02-rollback-workflow/README.md](02-rollback-workflow/README.md) documents the complete workflow

```text
Install → Upgrade → Verify → Upgrade again → Verify → Rollback → Verify
```

using my `webapp/` chart (nginx, values `image.tag`, `replicaCount`, `message` rendered into a ConfigMap and served as `index.html`). `rollback-demo.sh` runs all steps, prints `helm history` after each one and checks replicas/image/message after every change; the README contains the output of one full run (all four `VERIFY OK`).

## Task 3: Mini Project

[mini-project/README.md](mini-project/README.md) implements the course Notes-app chart: `notes-chart/` with `values.yaml` (dev) and `values-prod.yaml` (prod), templates for Deployment/Service/ConfigMap, lint, `helm template` sample output, install for dev and prod, upgrade, bad upgrade (`ImagePullBackOff`, Helm still says `deployed`), rollback and clean up - all captured.

## Core concepts in my words

* **Chart vs release vs values** – the chart is the recipe, values are the ingredients, the release is the cooked meal in a specific namespace. One chart, many releases.
* **`version` vs `appVersion`** – `version` is the chart's own semver and changes when templates change; `appVersion` is the application version (usually the image tag) and is informational.
* **Values precedence** – `values.yaml` < `-f file` < `--set`; `--set` wins. Environment-specific values belong in files (`values-prod.yaml`) so they are reviewable in Git; `--set` is for quick experiments.
* **Revisions** – every install/upgrade/rollback stores a new Secret `sh.helm.release.v1.<name>.v<N>`; rollback is a new revision, history is never lost.
* **Safety flags** – `helm lint` + `helm template` before the cluster, `--dry-run` against the cluster, `--wait`/`--atomic --timeout` to make upgrades fail (and auto-rollback) when Pods do not become Ready.
* **Helm 3/4 vs Helm 2** – no Tiller, client-only, uses my kubeconfig permissions.

## Screenshots

| Screenshot | Stands in for it |
|---|---|
| Each Helm command output (Task 1) | `01-helm-commands/README.md`, one block per command |
| Chart lint/template | captured blocks in `02-rollback-workflow/README.md` and `mini-project/README.md` |
| Install / upgrade / history / rollback (Task 2) | `02-rollback-workflow/README.md` steps 1-7 |
| Mini project install / upgrade / rollback | `mini-project/README.md` steps 10-15 |

## Deliverables

* `01-helm-commands/README.md` – Task 1: all Helm commands with purpose and output.
* `02-rollback-workflow/webapp/` – Helm chart (Chart.yaml, values.yaml, templates: deployment, service, configmap, _helpers.tpl, NOTES.txt).
* `02-rollback-workflow/rollback-demo.sh` – install → upgrade → verify → upgrade → verify → rollback → verify.
* `02-rollback-workflow/README.md` – Task 2 documented with `helm history` after each step.
* `mini-project/notes-chart/` – Task 3 chart with `values.yaml`, `values-prod.yaml`, templates.
* `mini-project/README.md` – installation, upgrade, rollback, `helm template` output.
* This `README.md` – index and task overview.
