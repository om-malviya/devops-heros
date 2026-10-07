# Session 20 – Task 3: GitOps demo with Argo CD
Student: Om Malviya | Enrollment No: 24BCS10448

## Task 3: GitOps
Learn: what is GitOps, Git as the source of truth, declarative configuration, continuous reconciliation, GitOps workflow, Kubernetes + GitOps.

## What is GitOps?

GitOps is operating infrastructure and applications the same way we develop software: the
**desired state** of the system lives in a Git repository as declarative files, and an automated
agent running *inside* the platform continuously makes the real system match that repository.
Nobody runs `kubectl apply` by hand; people change Git, the agent changes the cluster.

The four principles (OpenGitOps):

1. **Declarative** – the whole system is described as data (YAML), not as scripts of steps.
2. **Versioned and immutable** – that description is stored in Git, so every change has an author, a diff and a commit to roll back to.
3. **Pulled automatically** – an agent in the cluster pulls the desired state; CI does not need cluster credentials.
4. **Continuously reconciled** – the agent keeps comparing desired vs actual and corrects drift.

## Git as the source of truth

```text
Git (desired state)                    Kubernetes (actual state)
replicas: 3            ---compare--->  replicas: 2
                        <--reconcile-- Argo CD scales to 3
```

If Git says 3 replicas and the cluster has 2, the cluster is wrong, not Git. This gives me:

- **History and audit**: `git log` answers "who changed the deployment and when".
- **Review**: changes go through a pull request before they reach production.
- **Rollback**: `git revert` of a commit is a rollback; Argo CD applies the previous manifest.
- **Disaster recovery**: a new cluster plus the same repo gives the same system.
- **One workflow** for developers and operators.

## Declarative configuration

Imperative: "run `kubectl create deployment`, then `kubectl scale --replicas=3`, then `kubectl expose`".
The result depends on the order and on what already exists.

Declarative: `deployment.yaml` says `replicas: 3`. It does not matter whether there are 0, 2 or 5
replicas now; applying it always ends at 3. Declarative files are idempotent, diff-able and can be
re-applied forever, which is what makes continuous reconciliation possible. The demo app in
`gitops-repo/apps/demo-app` is pure declarative YAML plus a `kustomization.yaml`.

## Continuous reconciliation

```text
        +---------------------------------------------------+
        |                                                   |
        v                                                   |
   read desired state from Git                              |
        |                                                   |
        v                                                   |
   read actual state from the cluster API                   |
        |                                                   |
        v                                                   |
   diff  ---- equal ----> status: Synced / Healthy ---------+   (poll Git every 3 min,
        |                                                   |    watch cluster events)
      drift                                                 |
        |                                                   |
        v                                                   |
   apply desired state (sync) -------------------------------+
```

Argo CD runs this loop forever. Two kinds of drift are handled:

- **Git changed** (someone committed `replicas: 3`): Argo CD becomes `OutOfSync` and, because `automated` sync is on, applies it.
- **Cluster changed** (someone ran `kubectl scale --replicas=1` or deleted a pod): with `selfHeal: true` Argo CD puts it back. With `prune: true`, resources deleted from Git are deleted from the cluster.

## GitOps workflow

```text
 developer                 GitHub                        cluster
 ---------                 ------                        -------
 edit deployment.yaml
 git commit / git push ---> PR review, CI lint ---> merge to main
                                 |
                                 |  (Argo CD polls / webhook)
                                 v
                           +-----------+   compare    +-------------------+
                           |  Argo CD  | -----------> | Kubernetes API    |
                           | in-cluster| <----------- | Deployment/Service|
                           +-----------+   apply      +-------------------+
                                 |
                                 v
                        UI / CLI: Synced, Healthy
```

CI (build, test, scan, push image) stays separate from CD. CI's last step is often just
"commit the new image tag to the GitOps repo". The cluster pulls; nothing pushes into it.

## Kubernetes + GitOps: Argo CD and Flux

Kubernetes is a natural fit: its API is already declarative and its controllers already reconcile
(a Deployment controller keeps `replicas` pods running). GitOps simply adds one more controller
whose desired state comes from Git.

| | Argo CD | Flux |
|---|---|---|
| Project | CNCF graduated, Intuit origin | CNCF graduated, Weaveworks origin |
| Model | `Application` CRD points at repo+path; one Argo CD can manage many clusters | `GitRepository` + `Kustomization`/`HelmRelease` CRDs; typically one Flux per cluster |
| UI | rich web UI with resource tree and diff | CLI first (`flux`), UI via Weave GitOps/Headlamp |
| Sync | automated or manual, `selfHeal`, `prune`, sync waves, hooks | always automated, prune per Kustomization |
| Multi-tenancy | Projects, RBAC, SSO built in | relies on Kubernetes RBAC and namespaces |
| Image updates | Argo CD Image Updater (separate) | image automation controllers built in |

I use Argo CD here because the UI makes the reconciliation loop visible.

## Demo

### Files

```text
03-gitops/
├── install-argocd.sh                 installs Argo CD, waits, prints admin password
├── argocd/
│   ├── application.yaml              Argo CD Application (applied once by me, not in the watched path)
│   └── application-local-demo.yaml   same policy, but pointing at the public upstream course repo (see Step 2b)
└── gitops-repo/                      "the Git repository" Argo CD watches
    └── apps/demo-app/
        ├── kustomization.yaml
        ├── namespace.yaml            demo-app
        ├── deployment.yaml           nginx:alpine, replicas: 2
        └── service.yaml              ClusterIP :80
```

The Application points at this very repository:

```yaml
source:
  repoURL: https://github.com/om-malviya/devops-heros.git
  targetRevision: main
  path: homework/session20-monitoring-observability-gitops/03-gitops/gitops-repo/apps/demo-app
destination:
  server: https://kubernetes.default.svc
  namespace: demo-app
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

I verified the manifests render correctly with kustomize before pushing:

```bash
kubectl kustomize gitops-repo/apps/demo-app | grep -E '^kind:|replicas:|image:'
```

Output (captured 2026-10-07)

```text
kind: Namespace
kind: Service
kind: Deployment
  replicas: 2
      - image: nginx:alpine
```

### Step 1 – cluster and Argo CD

I ran the demo on the single-node k3s cluster that ships with Colima (kubectl context `colima`,
Kubernetes v1.35). With kind it would be `kind create cluster --name session20` first.

```bash
./install-argocd.sh
```

Output (captured 2026-10-08; 59 `serverside-applied` lines shortened to the first and last)

```text
==> Using kube-context: colima
==> Creating namespace argocd
namespace/argocd created
==> Applying Argo CD manifests (stable)
customresourcedefinition.apiextensions.k8s.io/applications.argoproj.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/applicationsets.argoproj.io serverside-applied
customresourcedefinition.apiextensions.k8s.io/appprojects.argoproj.io serverside-applied
serviceaccount/argocd-application-controller serverside-applied
... (59 resources in total)
networkpolicy.networking.k8s.io/argocd-server-network-policy serverside-applied
==> Waiting for Argo CD components to become ready (can take 2-5 min)
Waiting for deployment "argocd-server" rollout to finish: 0 of 1 updated replicas are available...
deployment "argocd-server" successfully rolled out
deployment "argocd-repo-server" successfully rolled out
partitioned roll out complete: 1 new pods have been updated...
==> Initial admin password:
QpeVnPjO29ABk4RB

UI:  https://localhost:8080   (user: admin, password above)
Run: kubectl port-forward svc/argocd-server -n argocd 8080:443
```

The `stable` manifest installed Argo CD v3.5.4 and the script finished in 71 s. The password above
is the one-time initial password of this throw-away install (the namespace was deleted again at
the end), so it is not a secret worth hiding.

```bash
kubectl get pods -n argocd
```

Output (captured 2026-10-08, about 2 minutes after the install)

```text
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          2m7s
argocd-applicationset-controller-5c66f59556-jf2m8   1/1     Running   0          2m7s
argocd-dex-server-64cc54b998-xkpxz                  1/1     Running   0          2m7s
argocd-notifications-controller-68d59788b7-vlfjm    1/1     Running   0          2m7s
argocd-redis-7f877d46b7-q95c2                       1/1     Running   0          2m7s
argocd-repo-server-7bc46c4ddf-bdp2k                 1/1     Running   0          2m7s
argocd-server-57bf79bfcc-ktnnl                      1/1     Running   0          2m7s
```

Right after the script returned, `argocd-dex-server` and `argocd-redis` were still in
`ImagePullBackOff` (one failed pull each from `ghcr.io` and `public.ecr.aws`, a transient
registry error); the kubelet retried and both were `Running` a minute later. The script only waits
for server, repo-server and the application controller, which is enough for syncing to start.

Open the UI in a second terminal: `kubectl port-forward svc/argocd-server -n argocd 8080:443`,
then https://localhost:8080 (accept the self-signed certificate), user `admin`.
Optional CLI: `brew install argocd && argocd login localhost:8080 --username admin --insecure`.

### Step 2 – register the Application (the only manual kubectl step)

```bash
kubectl apply -f argocd/application.yaml
kubectl get applications -n argocd
kubectl get application demo-app -n argocd -o jsonpath='{range .status.conditions[*]}{.type}: {.message}{"\n"}{end}'
```

Output (captured 2026-10-08)

```text
application.argoproj.io/demo-app created

NAME       SYNC STATUS   HEALTH STATUS
demo-app   Unknown       Healthy

ComparisonError: Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = failed to list refs: authentication required: Repository not found.
```

This is the honest result at the time of writing: my fork `github.com/om-malviya/devops-heros`
is **not pushed yet**, so GitHub answers "Repository not found" (for a non-existent repo it says
"authentication required" because it cannot tell a private repo from a missing one) and the
Application stays `Unknown` with a `ComparisonError`. Nothing was created in `demo-app`.
Argo CD keeps retrying on every refresh (3 min), so the moment the fork exists with this path on
`main` the same object syncs on its own; nothing on the cluster needs to change. `kubectl describe`
shows the same condition:

```bash
kubectl describe application demo-app -n argocd | sed -n '/^Status:/,$p'
```

Output (captured 2026-10-08, trimmed)

```text
Status:
  Conditions:
    Last Transition Time:  2026-10-07T21:11:48Z
    Message:               Failed to load target state: failed to generate manifest for source 1 of 1: rpc error: code = Unknown desc = failed to list refs: authentication required: Repository not found.
    Type:                  ComparisonError
  Health:
    Status:                Healthy
  Sync:
    Compared To:
      Destination:
        Namespace:  demo-app
        Server:     https://kubernetes.default.svc
      Source:
        Path:             homework/session20-monitoring-observability-gitops/03-gitops/gitops-repo/apps/demo-app
        Repo URL:         https://github.com/om-malviya/devops-heros.git
        Target Revision:  main
    Status:               Unknown
Events:
  Type    Reason           Age   From                           Message
  Normal  ResourceUpdated  19s   argocd-application-controller  Updated sync status:  -> Unknown
  Normal  ResourceUpdated  19s   argocd-application-controller  Updated health status:  -> Healthy
```

### Step 2b – the same loop against a repository that does exist

To show the reconciliation loop for real I added `argocd/application-local-demo.yaml`. It is the
same Application (automated sync, `selfHeal`, `prune`, `CreateNamespace=true`, same retry policy)
but its `source` points at the **public upstream course repository** and the mini-project folder
that contains plain manifests (`namespace.yaml`, `deployment.yaml`, `service.yaml`: nginx, 2
replicas, namespace `session20`):

```yaml
source:
  repoURL: https://github.com/Nency-Ravaliya/devops-heros.git
  targetRevision: main
  path: session20-monitoring-observability-gitops/08-mini-project/app
  directory:
    exclude: argocd-application.yaml   # that folder also holds an Application template; not a workload
```

```bash
kubectl apply -f argocd/application-local-demo.yaml
kubectl get applications -n argocd
kubectl get all -n session20
kubectl get application upstream-mini-demo -n argocd -o jsonpath='{range .status.resources[*]}{.kind}{"\t"}{.namespace}{"\t"}{.name}{"\t"}{.status}{"\n"}{end}'
kubectl get application upstream-mini-demo -n argocd -o jsonpath='{.status.sync.revision}{"\n"}{.status.operationState.phase} {.status.operationState.message}{"\n"}'
```

Output (captured 2026-10-08; `Synced/Healthy` was reached 21 s after the apply)

```text
application.argoproj.io/upstream-mini-demo created

NAME                 SYNC STATUS   HEALTH STATUS
demo-app             Unknown       Healthy
upstream-mini-demo   Synced        Healthy

NAME                                  READY   STATUS    RESTARTS   AGE
pod/session20-mini-78d474f65f-9bstj   1/1     Running   0          14s
pod/session20-mini-78d474f65f-qngqh   1/1     Running   0          14s

NAME                     TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/session20-mini   ClusterIP   10.43.17.71   <none>        80/TCP    14s

NAME                             READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/session20-mini   2/2     2            2           14s

NAME                                        DESIRED   CURRENT   READY   AGE
replicaset.apps/session20-mini-78d474f65f   2         2         2       14s

Namespace		session20	Synced
Service	session20	session20-mini	Synced
Deployment	session20	session20-mini	Synced

8376590a668ac8d6f2700d181c0739d0ed3fc5ea
Succeeded successfully synced (all tasks run)
```

I observed that I never applied `deployment.yaml` myself: Argo CD cloned the repository at commit
`8376590`, rendered the three manifests, created the namespace (because of `CreateNamespace=true`)
and then the Service and Deployment. Without the `argocd` CLI installed, `kubectl describe` gives
the same information as `argocd app get`:

```bash
kubectl describe application upstream-mini-demo -n argocd
```

Output (captured 2026-10-08 after Step 4, trimmed to the interesting parts)

```text
Spec:
  Destination:
    Namespace:  session20
    Server:     https://kubernetes.default.svc
  Project:      default
  Source:
    Directory:
      Exclude:        argocd-application.yaml
    Path:             session20-monitoring-observability-gitops/08-mini-project/app
    Repo URL:         https://github.com/Nency-Ravaliya/devops-heros.git
    Target Revision:  main
  Sync Policy:
    Automated:
      Prune:      true
      Self Heal:  true
    Sync Options:
      CreateNamespace=true
Status:
  Health:
    Status:                Healthy
  History:
    Deployed At:        2026-10-07T21:12:14Z
    Id:                 0
    Initiated By:
      Automated:  true
    Revision:     8376590a668ac8d6f2700d181c0739d0ed3fc5ea
  Operation State:
    Finished At:  2026-10-07T21:12:58Z
    Message:      successfully synced (all tasks run)
      Sync:
        Auto Heal Attempts Count:  1
        Prune:                     true
        Resources:
          Group:   apps
          Kind:    Deployment
          Name:    session20-mini
    Phase:       Succeeded
    Started At:  2026-10-07T21:12:56Z
    Sync Result:
      Resources:
        Images:
          nginx:1.27-alpine
        Kind:        Deployment
        Message:     deployment.apps/session20-mini configured
        Name:        session20-mini
        Namespace:   session20
```

### Step 3 – change desired state in Git (2 -> 3 replicas)

This step needs push access to the watched repository. I cannot push to the upstream course repo
and my fork is not online yet, so the blocks in this step stay `Expected output`; they describe
what happens once `application.yaml` points at the pushed fork (the self-heal part of the same
loop is captured for real in Step 4).

```bash
sed -i '' 's/replicas: 2/replicas: 3/' gitops-repo/apps/demo-app/deployment.yaml
git diff gitops-repo/apps/demo-app/deployment.yaml
```

Expected output

```text
-  replicas: 2
+  replicas: 3
```

```bash
git add gitops-repo/apps/demo-app/deployment.yaml
git commit -m "demo-app: scale to 3 replicas"
git push origin main

# Argo CD polls every 3 minutes; force an immediate refresh instead of waiting:
argocd app get demo-app --refresh >/dev/null   # or: kubectl annotate application demo-app -n argocd argocd.argoproj.io/refresh=normal --overwrite
kubectl get deployment demo-app -n demo-app -w
```

Expected output

```text
NAME       READY   UP-TO-DATE   AVAILABLE   AGE
demo-app   2/2     2            2           6m
demo-app   2/3     2            2           6m
demo-app   2/3     3            2           6m
demo-app   3/3     3            3           6m
```

```bash
kubectl get applications -n argocd
argocd app history demo-app
```

Expected output

```text
NAME       SYNC STATUS   HEALTH STATUS
demo-app   Synced        Healthy

ID  DATE                           REVISION
0   2026-10-07 22:40:12 +0530 IST  main (a1b2c3d)
1   2026-10-07 22:47:55 +0530 IST  main (e4f5a6b)
```

For a short moment the UI shows `OutOfSync` (Git = 3, cluster = 2), then a sync happens
automatically and it is back to `Synced`. Rolling back is `git revert e4f5a6b && git push`.

### Step 4 – self-healing (drift created in the cluster)

Done against the `upstream-mini-demo` Application from Step 2b. First I deleted a pod by hand:

```bash
kubectl get pods -n session20
kubectl delete pod -n session20 session20-mini-78d474f65f-9bstj --wait=false
sleep 6; kubectl get pods -n session20
```

Output (captured 2026-10-08, columns trimmed)

```text
session20-mini-78d474f65f-9bstj 1/1 Running 35s
session20-mini-78d474f65f-qngqh 1/1 Running 35s

pod "session20-mini-78d474f65f-9bstj" deleted from session20 namespace

session20-mini-78d474f65f-ncvsg 1/1 Running 6s
session20-mini-78d474f65f-qngqh 1/1 Running 41s
```

The pod came back within 6 s as `...-ncvsg`, but that is the Deployment's ReplicaSet doing its
normal job, not GitOps. The Application only flickered `Healthy -> Progressing -> Healthy`
(visible in the events below). The GitOps self-heal shows when I change the *Deployment* itself:

```bash
kubectl scale deployment session20-mini -n session20 --replicas=1
kubectl get application upstream-mini-demo -n argocd -o jsonpath='sync={.status.sync.status} health={.status.health.status}{"\n"}'
kubectl get deploy session20-mini -n session20 --no-headers
# then every 2 s:
kubectl get deploy session20-mini -n session20 -o jsonpath='{.spec.replicas}'; kubectl get application upstream-mini-demo -n argocd -o jsonpath='{.status.sync.status}'
```

Output (captured 2026-10-08)

```text
deployment.apps/session20-mini scaled
t+0s sync=Synced health=Healthy
session20-mini   2/1   2     2     42s
t+2s spec.replicas=1 sync=OutOfSync
t+4s spec.replicas=2 sync=Synced

NAME             READY   UP-TO-DATE   AVAILABLE   AGE
session20-mini   2/2     2            2           46s
NAME                 SYNC STATUS   HEALTH STATUS
demo-app             Unknown       Healthy
upstream-mini-demo   Synced        Progressing
```

Argo CD noticed `replicas: 1` in the cluster versus `replicas: 2` in Git within 2 s, reported
`OutOfSync`, and because `selfHeal: true` it re-applied the Git version: 2 s later
`spec.replicas` was 2 again and the Application `Synced` (the `Progressing` health is the second
pod starting). The event log of the Application tells the whole story with timestamps:

```bash
kubectl get events -n argocd --field-selector involvedObject.name=upstream-mini-demo -o custom-columns='TIME:.lastTimestamp,REASON:.reason,MESSAGE:.message'
```

Output (captured 2026-10-08)

```text
TIME                   REASON               MESSAGE
2026-10-07T21:12:14Z   OperationStarted     Initiated automated sync to '8376590a668ac8d6f2700d181c0739d0ed3fc5ea'
2026-10-07T21:12:14Z   ResourceUpdated      Updated sync status:  -> OutOfSync
2026-10-07T21:12:14Z   ResourceUpdated      Updated health status:  -> Missing
2026-10-07T21:12:14Z   ResourceUpdated      Updated health status: Missing -> Healthy
2026-10-07T21:12:14Z   OperationCompleted   Sync operation to 8376590a668ac8d6f2700d181c0739d0ed3fc5ea succeeded
2026-10-07T21:12:14Z   ResourceUpdated      Updated sync status: OutOfSync -> Synced
2026-10-07T21:12:14Z   ResourceUpdated      Updated health status: Healthy -> Progressing
2026-10-07T21:12:27Z   ResourceUpdated      Updated health status: Progressing -> Healthy
2026-10-07T21:12:50Z   ResourceUpdated      Updated health status: Healthy -> Progressing
2026-10-07T21:12:51Z   ResourceUpdated      Updated health status: Progressing -> Healthy
2026-10-07T21:12:56Z   OperationStarted     Initiated automated sync to '8376590a668ac8d6f2700d181c0739d0ed3fc5ea'
2026-10-07T21:12:56Z   ResourceUpdated      Updated sync status: Synced -> OutOfSync
2026-10-07T21:12:58Z   OperationCompleted   Partial sync operation to 8376590a668ac8d6f2700d181c0739d0ed3fc5ea succeeded
2026-10-07T21:12:59Z   ResourceUpdated      Updated sync status: OutOfSync -> Synced
2026-10-07T21:12:59Z   ResourceUpdated      Updated health status: Healthy -> Progressing
2026-10-07T21:13:01Z   ResourceUpdated      Updated health status: Progressing -> Healthy
```

Three phases: 21:12:14 the first automated sync (Missing -> Healthy), 21:12:50 the deleted pod
(health only), 21:12:56 my `kubectl scale` (Synced -> OutOfSync -> "Partial sync" of just the
Deployment -> Synced). `Auto Heal Attempts Count: 1` in the describe output above is the same
event. Without GitOps the manual change would have silently stayed.

Prune works the same way: deleting `service.yaml` from Git and pushing removes the Service from
the cluster, because `prune: true`.

### Cleanup

```bash
kubectl delete -f argocd/application-local-demo.yaml -f argocd/application.yaml   # finalizer removes the session20 resources too
kubectl get ns session20 demo-app
kubectl delete ns argocd
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io
kubectl get clusterrole,clusterrolebinding -o name | grep argocd | xargs kubectl delete   # cluster-scoped leftovers of install.yaml
kubectl get ns
```

Output (captured 2026-10-08)

```text
application.argoproj.io "upstream-mini-demo" deleted from argocd namespace
application.argoproj.io "demo-app" deleted from argocd namespace
Error from server (NotFound): namespaces "session20" not found
Error from server (NotFound): namespaces "demo-app" not found
namespace "argocd" deleted
customresourcedefinition.apiextensions.k8s.io "applications.argoproj.io" deleted
customresourcedefinition.apiextensions.k8s.io "applicationsets.argoproj.io" deleted
customresourcedefinition.apiextensions.k8s.io "appprojects.argoproj.io" deleted
clusterrole.rbac.authorization.k8s.io "argocd-application-controller" deleted
clusterrole.rbac.authorization.k8s.io "argocd-applicationset-controller" deleted
clusterrole.rbac.authorization.k8s.io "argocd-server" deleted
clusterrolebinding.rbac.authorization.k8s.io "argocd-application-controller" deleted
clusterrolebinding.rbac.authorization.k8s.io "argocd-applicationset-controller" deleted
clusterrolebinding.rbac.authorization.k8s.io "argocd-server" deleted
NAME                STATUS   AGE
default             Active   4h11m
kube-node-lease     Active   4h11m
kube-public         Active   4h11m
kube-system         Active   4h11m
```

The final `kubectl get ns` is trimmed to the default namespaces (other course sessions were using the same cluster). On kind, `kind delete cluster --name session20` would replace all of this.

## Screenshots

| Screenshot asked for | Stands in |
|---|---|
| Argo CD pods running | captured `kubectl get pods -n argocd` output |
| Argo CD UI: app Synced/Healthy | captured `kubectl get applications -n argocd` and `kubectl describe application` outputs (Step 2b) |
| Fork not yet pushed | captured `ComparisonError: Repository not found` (Step 2) |
| Git diff 2 -> 3 replicas | `git diff` expected output (needs the pushed fork) |
| Rollout to 3 replicas | `kubectl get deployment -w` expected output (needs the pushed fork) |
| Self-heal | captured `kubectl scale --replicas=1` -> `OutOfSync` -> `2/2 Synced` sequence and the Application events (Step 4) |
| Manifests rendered | captured `kubectl kustomize` output |

## Deliverables

- `README.md` – GitOps theory (what, Git as source of truth, declarative config, reconciliation loop, workflow, Argo CD vs Flux) and the demo steps with captured outputs.
- `gitops-repo/apps/demo-app/` – declarative desired state: namespace, nginx:alpine Deployment (2 replicas), Service, kustomization.
- `argocd/application.yaml` – Argo CD Application with automated sync, selfHeal and prune pointing at this repo path (syncs once the fork is pushed).
- `argocd/application-local-demo.yaml` – identical policy pointing at the public upstream course repo; used for the captured Synced/Healthy and self-heal demo.
- `install-argocd.sh` – installs Argo CD, waits for rollout, prints the initial admin password and port-forward command.
