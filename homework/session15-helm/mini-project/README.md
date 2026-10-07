# Task 3: Mini Project – Package and Deploy the Notes App with Helm

Student: Om Malviya | Enrollment No: 24BCS10448

The course mini project asks me to write a chart `notes-chart` from scratch (an nginx Pod that stands in for a Notes web app), with a `values.yaml` for development and a `values-prod.yaml` for production, then install, upgrade to production values, check the history, simulate a bad upgrade, roll back and clean up. I use namespace `s15` on a single-node k3s cluster (Kubernetes v1.35, Helm v4.3.0).

## The chart

```text
notes-chart/
  Chart.yaml
  values.yaml            development defaults: 1 replica, nginx:1.26-alpine, environment=development
  values-prod.yaml       production overrides: 3 replicas, nginx:1.27-alpine, environment=production
  .helmignore
  templates/
    _helpers.tpl         common labels (app, app.kubernetes.io/*, helm.sh/chart, environment)
    configmap.yaml       {{ .Release.Name }}-config  : APP_NAME, ENVIRONMENT
    deployment.yaml      {{ .Release.Name }}-deploy  : replicas, image, envFrom the ConfigMap, readiness probe
    service.yaml         {{ .Release.Name }}-svc     : NodePort 30090 -> 80
    NOTES.txt            post-install hints
```

Differences from the course listing, on purpose: I use the `-alpine` nginx tags (small, multi-arch for arm64/amd64), I added a `_helpers.tpl` with standard labels, a readiness probe, and a `NOTES.txt`. Resource names and the values structure are exactly as in the course so the course commands work unchanged.

### values.yaml

```yaml
replicaCount: 1
image:
  repository: nginx
  tag: "1.26-alpine"
service:
  port: 80
  nodePort: 30090
app:
  name: notes-app
  environment: development
```

### values-prod.yaml

```yaml
replicaCount: 3
image:
  repository: nginx
  tag: "1.27-alpine"
service:
  port: 80
  nodePort: 30090
app:
  name: notes-app
  environment: production
```

---

## Step 1-7: Create the chart

Done; files are in `notes-chart/` (see above).

## Step 8: Lint

```bash
helm lint notes-chart
helm lint notes-chart -f notes-chart/values-prod.yaml
```

Output (captured 2026-10-08)

```text
==> Linting notes-chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
==> Linting notes-chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
```

## Step 9: Render locally

```bash
helm template notes-dev notes-chart -n s15
```

Output (captured 2026-10-07)

```text
---
# Source: notes-chart/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: notes-dev-config
  labels:
    app: notes-dev
    app.kubernetes.io/name: notes-chart
    app.kubernetes.io/instance: notes-dev
    app.kubernetes.io/managed-by: Helm
    helm.sh/chart: notes-chart-0.1.0
    environment: development
data:
  APP_NAME: "notes-app"
  ENVIRONMENT: "development"
---
# Source: notes-chart/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: notes-dev-svc
  labels:
    app: notes-dev
    app.kubernetes.io/name: notes-chart
    app.kubernetes.io/instance: notes-dev
    app.kubernetes.io/managed-by: Helm
    helm.sh/chart: notes-chart-0.1.0
    environment: development
spec:
  type: NodePort
  selector:
    app: notes-dev
  ports:
    - port: 80
      targetPort: 80
      nodePort: 30090
---
# Source: notes-chart/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notes-dev-deploy
  labels:
    app: notes-dev
    app.kubernetes.io/name: notes-chart
    app.kubernetes.io/instance: notes-dev
    app.kubernetes.io/managed-by: Helm
    helm.sh/chart: notes-chart-0.1.0
    environment: development
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notes-dev
  template:
    metadata:
      labels:
        app: notes-dev
        environment: development
    spec:
      containers:
        - name: notes
          image: "nginx:1.26-alpine"
          ports:
            - containerPort: 80
          envFrom:
            - configMapRef:
                name: notes-dev-config
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 2
            periodSeconds: 5
```

Every `{{ }}` was replaced: `{{ .Release.Name }}` → `notes-dev`, values → `1`, `nginx:1.26-alpine`, `development`. The same render with production values:

```bash
helm template notes-dev notes-chart -n s15 -f notes-chart/values-prod.yaml | grep -E 'replicas:|image:|ENVIRONMENT'
```

Output (captured 2026-10-07)

```text
  ENVIRONMENT: "production"
  replicas: 3
          image: "nginx:1.27-alpine"
```

---

## Step 10: Install (development)

```bash
helm install notes-dev notes-chart -n s15 --create-namespace
kubectl rollout status deploy/notes-dev-deploy -n s15 --timeout=120s
kubectl get pods -n s15 -l app=notes-dev
kubectl get services -n s15 -l app=notes-dev
kubectl get configmaps -n s15
```

Output (captured 2026-10-08)

```text
NAME: notes-dev
LAST DEPLOYED: Thu Oct  8 03:08:23 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
TEST SUITE: None
NOTES:
Notes app "notes-dev" (development) deployed - revision 1.

  image    : nginx:1.26-alpine
  replicas : 1
  NodePort : 30090

Verify:
  kubectl get pods,svc,configmap -n s15 -l app=notes-dev
  kubectl port-forward svc/notes-dev-svc -n s15 8080:80
  curl -s http://localhost:8080 | head -4

Waiting for deployment "notes-dev-deploy" rollout to finish: 0 of 1 updated replicas are available...
deployment "notes-dev-deploy" successfully rolled out
NAME                                READY   STATUS    RESTARTS   AGE
notes-dev-deploy-857c6b6564-hcr2v   1/1     Running   0          14s
NAME            TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
notes-dev-svc   NodePort   10.43.189.61   <none>        80:30090/TCP   14s
NAME               DATA   AGE
kube-root-ca.crt   1      22m
notes-dev-config   2      14s
webapp             2      10m
```

(`webapp` is the ConfigMap of the Task 2 release, which was still installed in the same namespace at that moment.)

Checking the ConfigMap reached the container:

```bash
kubectl exec deploy/notes-dev-deploy -n s15 -- env | grep -E 'APP_NAME|ENVIRONMENT'
```

Output (captured 2026-10-08)

```text
ENVIRONMENT=development
APP_NAME=notes-app
```

### Installing a separate production release

The same chart can also be installed as its own release with the prod values (this is what I would do for a real prod cluster, instead of upgrading the dev release):

```bash
helm install notes-prod notes-chart -n s15 -f notes-chart/values-prod.yaml --set service.nodePort=30091
kubectl rollout status deploy/notes-prod-deploy -n s15 --timeout=120s
helm list -n s15
kubectl get pods -n s15 -l app=notes-prod
```

Output (captured 2026-10-08; NOTES trimmed)

```text
NAME: notes-prod
LAST DEPLOYED: Thu Oct  8 03:08:38 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
Notes app "notes-prod" (production) deployed - revision 1.

  image    : nginx:1.27-alpine
  replicas : 3
  NodePort : 30091
...
Waiting for deployment "notes-prod-deploy" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "notes-prod-deploy" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "notes-prod-deploy" rollout to finish: 2 of 3 updated replicas are available...
deployment "notes-prod-deploy" successfully rolled out
NAME      	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART            	APP VERSION
notes-dev 	s15      	1       	2026-10-08 03:08:23.98364 +0530 IST 	deployed	notes-chart-0.1.0	1.0
notes-prod	s15      	1       	2026-10-08 03:08:38.968103 +0530 IST	deployed	notes-chart-0.1.0	1.0
webapp    	s15      	4       	2026-10-08 02:58:27.798287 +0530 IST	deployed	webapp-0.1.0     	1.27
NAME                                 READY   STATUS    RESTARTS   AGE
notes-prod-deploy-557768cd4f-cdfzc   1/1     Running   0          6s
notes-prod-deploy-557768cd4f-ttx4x   1/1     Running   0          6s
notes-prod-deploy-557768cd4f-wbjlr   1/1     Running   0          6s
```

(I override `nodePort` because two Services in one cluster cannot share NodePort 30090.) For the remaining steps I follow the course and upgrade `notes-dev` in place.

## Step 11: Upgrade to production values

```bash
helm upgrade notes-dev notes-chart -n s15 -f notes-chart/values-prod.yaml
kubectl rollout status deploy/notes-dev-deploy -n s15 --timeout=120s
kubectl get pods -n s15 -l app=notes-dev
kubectl get configmap notes-dev-config -n s15 -o jsonpath='{.data}{"\n"}'
```

Output (captured 2026-10-08; NOTES and some rollout lines trimmed)

```text
Release "notes-dev" has been upgraded. Happy Helming!
NAME: notes-dev
LAST DEPLOYED: Thu Oct  8 03:08:45 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
NOTES:
Notes app "notes-dev" (production) deployed - revision 2.

  image    : nginx:1.27-alpine
  replicas : 3
  NodePort : 30090
...
Waiting for deployment "notes-dev-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
Waiting for deployment "notes-dev-deploy" rollout to finish: 2 out of 3 new replicas have been updated...
Waiting for deployment "notes-dev-deploy" rollout to finish: 1 old replicas are pending termination...
deployment "notes-dev-deploy" successfully rolled out
NAME                                READY   STATUS        RESTARTS   AGE
notes-dev-deploy-857c6b6564-hcr2v   1/1     Terminating   0          41s
notes-dev-deploy-f9468fb59-7f78s    1/1     Running       0          20s
notes-dev-deploy-f9468fb59-8fdn6    1/1     Running       0          7s
notes-dev-deploy-f9468fb59-kqqwd    1/1     Running       0          13s
{"APP_NAME":"notes-app","ENVIRONMENT":"production"}
```

A new ReplicaSet (`f9468fb59`, image 1.27) replaced the old one (`857c6b6564`) with a rolling update; the last old Pod is still `Terminating` in the listing.

## Step 12: Check release history

```bash
helm history notes-dev -n s15
```

Output (captured 2026-10-08)

```text
REVISION	UPDATED                 	STATUS    	CHART            	APP VERSION	DESCRIPTION
1       	Thu Oct  8 03:08:23 2026	superseded	notes-chart-0.1.0	1.0        	Install complete
2       	Thu Oct  8 03:08:45 2026	deployed  	notes-chart-0.1.0	1.0        	Upgrade complete
```

## Step 13: Simulate a bad upgrade

```bash
helm upgrade notes-dev notes-chart -n s15 -f notes-chart/values-prod.yaml --set image.tag=broken-tag-does-not-exist
kubectl get pods -n s15 -l app=notes-dev                 # 45 s later
kubectl get events -n s15 --field-selector type=Warning --sort-by=.lastTimestamp | tail -3
helm history notes-dev -n s15
kubectl rollout status deploy/notes-dev-deploy -n s15 --timeout=20s
```

Output (captured 2026-10-08; NOTES trimmed)

```text
Release "notes-dev" has been upgraded. Happy Helming!
NAME: notes-dev
LAST DEPLOYED: Thu Oct  8 03:09:06 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 3
DESCRIPTION: Upgrade complete
NOTES:
Notes app "notes-dev" (production) deployed - revision 3.

  image    : nginx:broken-tag-does-not-exist
  replicas : 3
  NodePort : 30090
...
NAME                               READY   STATUS             RESTARTS   AGE
notes-dev-deploy-d5db46c55-rg9nk   0/1     ImagePullBackOff   0          45s
notes-dev-deploy-f9468fb59-7f78s   1/1     Running            0          66s
notes-dev-deploy-f9468fb59-8fdn6   1/1     Running            0          53s
notes-dev-deploy-f9468fb59-kqqwd   1/1     Running            0          59s
15s         Warning   Failed   pod/notes-dev-deploy-d5db46c55-rg9nk   Error: ImagePullBackOff
0s          Warning   Failed   pod/notes-dev-deploy-d5db46c55-rg9nk   Error: ErrImagePull
0s          Warning   Failed   pod/notes-dev-deploy-d5db46c55-rg9nk   Failed to pull image "nginx:broken-tag-does-not-exist": failed to pull and unpack image "docker.io/library/nginx:broken-tag-does-not-exist": failed to resolve reference "docker.io/library/nginx:broken-tag-does-not-exist": failed to do request: Head "https://registry-1.docker.io/v2/library/nginx/manifests/broken-tag-does-not-exist": dial tcp: lookup registry-1.docker.io: no such host
REVISION	UPDATED                 	STATUS    	CHART            	APP VERSION	DESCRIPTION
1       	Thu Oct  8 03:08:23 2026	superseded	notes-chart-0.1.0	1.0        	Install complete
2       	Thu Oct  8 03:08:45 2026	superseded	notes-chart-0.1.0	1.0        	Upgrade complete
3       	Thu Oct  8 03:09:06 2026	deployed  	notes-chart-0.1.0	1.0        	Upgrade complete
Waiting for deployment "notes-dev-deploy" rollout to finish: 1 out of 3 new replicas have been updated...
error: timed out waiting for the condition
```

Things I observed:
* Helm reports revision 3 as `deployed` even though the Pod is broken – without `--wait`/`--atomic` Helm only checks that the API server accepted the manifests. `kubectl rollout status` is what tells the truth (`timed out`, stuck at 1 of 3 new replicas).
* Because the Deployment uses a rolling update with `maxUnavailable` 25%, the three old Pods stay Running and only the new Pod fails. The app is still serving; a bad image never takes it down completely. With `--atomic --timeout 60s` Helm would have rolled back by itself.
* The last pull attempt in the events failed with a transient `dial tcp: lookup registry-1.docker.io: no such host` from inside the VM; the earlier attempts (and the identical scenario in Session 14) returned `not found` for the tag. Either way the Pod is `ImagePullBackOff` and the fix is the same.

## Step 14: Rollback to revision 2

```bash
helm rollback notes-dev 2 -n s15
kubectl get pods -n s15 -l app=notes-dev
helm history notes-dev -n s15
kubectl get configmap notes-dev-config -n s15 -o jsonpath='{.data}{"\n"}'
```

Output (captured 2026-10-08)

```text
Rollback was a success! Happy Helming!
NAME                               READY   STATUS    RESTARTS   AGE
notes-dev-deploy-f9468fb59-7f78s   1/1     Running   0          98s
notes-dev-deploy-f9468fb59-8fdn6   1/1     Running   0          85s
notes-dev-deploy-f9468fb59-kqqwd   1/1     Running   0          91s
REVISION	UPDATED                 	STATUS    	CHART            	APP VERSION	DESCRIPTION
1       	Thu Oct  8 03:08:23 2026	superseded	notes-chart-0.1.0	1.0        	Install complete
2       	Thu Oct  8 03:08:45 2026	superseded	notes-chart-0.1.0	1.0        	Upgrade complete
3       	Thu Oct  8 03:09:06 2026	superseded	notes-chart-0.1.0	1.0        	Upgrade complete
4       	Thu Oct  8 03:10:11 2026	deployed  	notes-chart-0.1.0	1.0        	Rollback to 2
{"APP_NAME":"notes-app","ENVIRONMENT":"production"}
```

The `ImagePullBackOff` Pod is gone (its ReplicaSet `d5db46c55` was scaled to 0) and the three healthy Pods from revision 2 (same ReplicaSet `f9468fb59`, same AGE) were never touched.

## Step 15: Clean up

```bash
helm uninstall notes-dev -n s15
helm uninstall notes-prod -n s15
kubectl get pods -n s15 -l 'app in (notes-dev,notes-prod)'
kubectl get services -n s15
helm list -n s15
```

Output (captured 2026-10-08)

```text
release "notes-dev" uninstalled
release "notes-prod" uninstalled
No resources found in s15 namespace.
NAME     TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
webapp   ClusterIP   10.43.144.14   <none>        80/TCP    12m
NAME  	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART       	APP VERSION
webapp	s15      	4       	2026-10-08 02:58:27.798287 +0530 IST	deployed	webapp-0.1.0	1.27
```

Only the Task 2 `webapp` release was left, which I removed afterwards with `../02-rollback-workflow/rollback-demo.sh --cleanup` (that also deletes the `s15` namespace).

## What I practised

```text
[PASS] Created a Helm chart from scratch (Chart.yaml, values, templates, helpers, NOTES)
[PASS] Used values.yaml and values-prod.yaml (-f) for two environments
[PASS] helm lint + helm template before touching the cluster
[PASS] Deployed with helm install (dev and prod releases)
[PASS] Upgraded the release with different values
[PASS] Simulated a bad upgrade (broken image tag -> ImagePullBackOff)
[PASS] Rolled back to a healthy revision and read helm history
[PASS] Cleaned up with helm uninstall
```

## Screenshots

| Screenshot | Stands in for it |
|---|---|
| Chart files | tree listing + values at the top of this file |
| `helm lint` / `helm template` | captured blocks in Step 8 / 9 |
| Installation | Step 10 captured output |
| Upgrade | Step 11 / 12 captured output |
| Bad upgrade + rollback | Step 13 / 14 captured output |

## Deliverables

* `notes-chart/Chart.yaml`, `values.yaml`, `values-prod.yaml` – chart metadata and environment values.
* `notes-chart/templates/` – `deployment.yaml`, `service.yaml`, `configmap.yaml`, `_helpers.tpl`, `NOTES.txt`.
* `README.md` – lint and template output, install (dev/prod), upgrade, bad upgrade, rollback, clean up, all captured.
