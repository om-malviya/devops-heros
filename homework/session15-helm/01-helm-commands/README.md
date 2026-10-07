# Task 1: Helm Commands

Student: Om Malviya | Enrollment No: 24BCS10448

For every Helm command covered in the session: the command, what it does, and the output. I practised with the chart scaffolded by `helm create` and with the Bitnami repository, always in namespace `s15` on a single-node k3s cluster (Kubernetes v1.35).

My local Helm is v4 (`v4.3.0`). Two small differences from Helm 3 that I hit: `helm status --show-resources` no longer exists (v4 lists the resources by default), and `--dry-run` without a value warns that `--dry-run=client` is the new spelling.

---

## 0. `helm version`

```bash
helm version --short
```

Output (captured 2026-10-08)

```text
v4.3.0+gbec5b06
```

---

## 1. `helm create` – scaffold a new chart

Generates a complete, working chart skeleton (Deployment, Service, ServiceAccount, Ingress, HTTPRoute, HPA, tests, helpers, NOTES).

```bash
helm create demo-chart
find demo-chart -type f | sort
```

Output (captured 2026-10-08)

```text
Creating demo-chart
demo-chart/.helmignore
demo-chart/Chart.yaml
demo-chart/templates/NOTES.txt
demo-chart/templates/_helpers.tpl
demo-chart/templates/deployment.yaml
demo-chart/templates/hpa.yaml
demo-chart/templates/httproute.yaml
demo-chart/templates/ingress.yaml
demo-chart/templates/service.yaml
demo-chart/templates/serviceaccount.yaml
demo-chart/templates/tests/test-connection.yaml
demo-chart/values.yaml
```

The generated chart deploys `nginx` (`image.repository: nginx`, `tag: ""` which falls back to `Chart.appVersion`). Before installing I always lint and render it:

```bash
helm lint demo-chart
helm template demo demo-chart -n s15 | grep -E '^kind:'
```

Output (captured 2026-10-08)

```text
==> Linting demo-chart
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
kind: ServiceAccount
kind: Service
kind: Deployment
kind: Pod
```

(The `Pod` is the `helm test` connection test under `templates/tests/`.)

---

## 2. `helm install` – create a release

Renders the chart with the values and creates every object in the cluster. Release metadata is stored as a Secret (`sh.helm.release.v1.<release>.v1`) in the namespace.

```bash
helm install demo demo-chart -n s15 --create-namespace
```

Output (captured 2026-10-08)

```text
NAME: demo
LAST DEPLOYED: Thu Oct  8 02:46:26 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15 -l "app.kubernetes.io/name=demo-chart,app.kubernetes.io/instance=demo" -o jsonpath="{.items[0].metadata.name}")
  export CONTAINER_PORT=$(kubectl get pod --namespace s15 $POD_NAME -o jsonpath="{.spec.containers[0].ports[0].containerPort}")
  echo "Visit http://127.0.0.1:8080 to use your application"
  kubectl --namespace s15 port-forward $POD_NAME 8080:$CONTAINER_PORT
```

Useful variants I tried:

```bash
helm install demo demo-chart -n s15 --dry-run | head -12          # render + validate, create nothing
helm upgrade --install demo demo-chart -n s15 --wait --timeout 120s   # idempotent form used in CI/CD
```

Output (captured 2026-10-08)

```text
level=WARN msg="--dry-run is deprecated and should be replaced with '--dry-run=client'"
NAME: demo
LAST DEPLOYED: Thu Oct  8 02:46:26 2026
NAMESPACE: s15
STATUS: pending-install
REVISION: 1
DESCRIPTION: Dry run complete
HOOKS:
---
# Source: demo-chart/templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod

Release "demo" has been upgraded. Happy Helming!
NAME: demo
LAST DEPLOYED: Thu Oct  8 02:46:26 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
```

`upgrade --install` on an existing release is an upgrade, so it produced **revision 2** even though nothing changed; this shows up in `helm history` below.

---

## 3. `helm list` – which releases exist

```bash
helm list -n s15
helm list -A            # all namespaces
helm list -n s15 -o json
```

Output (captured 2026-10-08)

```text
NAME	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART           	APP VERSION
demo	s15      	2       	2026-10-08 02:46:26.658837 +0530 IST	deployed	demo-chart-0.1.0	1.16.0

NAME       	NAMESPACE  	REVISION	UPDATED                                	STATUS  	CHART                      	APP VERSION
demo       	s15        	2       	2026-10-08 02:46:26.658837 +0530 IST   	deployed	demo-chart-0.1.0           	1.16.0
traefik    	kube-system	1       	2026-10-07 17:04:20.128507129 +0000 UTC	deployed	traefik-37.1.1+up37.1.0    	v3.5.1
traefik-crd	kube-system	1       	2026-10-07 17:04:18.674461507 +0000 UTC	deployed	traefik-crd-37.1.1+up37.1.0	v3.5.1

[{"name":"demo","namespace":"s15","revision":"2","updated":"2026-10-08 02:46:26.658837 +0530 IST","status":"deployed","chart":"demo-chart-0.1.0","app_version":"1.16.0"}]
```

`-A` also shows the two Traefik releases that k3s installs itself in `kube-system`.

---

## 4. `helm status` – state of one release

Same information as the install output, re-queried now. Helm v4 lists the owned resources by default (`--show-resources` was removed):

```bash
helm status demo -n s15
```

Output (captured 2026-10-08; NOTES trimmed)

```text
NAME: demo
LAST DEPLOYED: Thu Oct  8 02:48:23 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
RESOURCES:
==> v1/Service
NAME              TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
demo-demo-chart   ClusterIP   10.43.76.11   <none>        80/TCP    13s

==> v1/Deployment
NAME              READY   UP-TO-DATE   AVAILABLE   AGE
demo-demo-chart   1/1     1            1           13s

==> v1/Pod(related)
NAME                               READY   STATUS    RESTARTS   AGE
demo-demo-chart-55957d6dc9-q96f5   1/1     Running   0          13s

==> v1/ServiceAccount
NAME              AGE
demo-demo-chart   13s

NOTES:
1. Get the application URL by running these commands:
  ...
```

(This block is from a second, fresh `helm install demo` I did after step 9 to retake the output without the removed flag, hence REVISION 1 and a different timestamp.)

---

## 5. `helm get` – what Helm stored for the release

| Sub-command | Shows |
|---|---|
| `helm get values` | only the values I overrode (`--all` adds the chart defaults) |
| `helm get manifest` | the rendered Kubernetes YAML that was applied |
| `helm get notes` | the NOTES.txt |
| `helm get hooks` | hook manifests (tests, pre/post jobs) |
| `helm get all` | everything above plus the release metadata |

```bash
helm get values demo -n s15
helm get values demo -n s15 --all | head -12
helm get manifest demo -n s15 | grep -E '^kind:|^  name:'
helm get notes demo -n s15 | head -3
helm get all demo -n s15 | head -8
```

Output (captured 2026-10-08)

```text
USER-SUPPLIED VALUES:
null

COMPUTED VALUES:
affinity: {}
autoscaling:
  enabled: false
  maxReplicas: 100
  minReplicas: 1
  targetCPUUtilizationPercentage: 80
fullnameOverride: ""
httpRoute:
  annotations: {}
  enabled: false
  hostnames:

kind: ServiceAccount
  name: demo-demo-chart
kind: Service
  name: demo-demo-chart
kind: Deployment
  name: demo-demo-chart

NOTES:
1. Get the application URL by running these commands:
  export POD_NAME=$(kubectl get pods --namespace s15 -l "app.kubernetes.io/name=demo-chart,app.kubernetes.io/instance=demo" -o jsonpath="{.items[0].metadata.name}")

NAME: demo
LAST DEPLOYED: Thu Oct  8 02:46:26 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 2
CHART: demo-chart
VERSION: 0.1.0
APP_VERSION: 1.16.0
```

`USER-SUPPLIED VALUES: null` because I installed with defaults only; after the upgrade below it shows `replicaCount: 2`.

---

## 6. `helm upgrade` – change a release (new revision)

Re-renders with the new values/chart and applies a diff. Every upgrade creates a new revision.

```bash
helm upgrade demo demo-chart -n s15 --set replicaCount=2 --wait --timeout 120s
kubectl get pods -n s15
helm get values demo -n s15
```

Output (captured 2026-10-08; NOTES trimmed)

```text
Release "demo" has been upgraded. Happy Helming!
NAME: demo
LAST DEPLOYED: Thu Oct  8 02:47:04 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 3
DESCRIPTION: Upgrade complete
NOTES:
...
NAME                               READY   STATUS    RESTARTS   AGE
demo-demo-chart-55957d6dc9-pjdcn   1/1     Running   0          39s
demo-demo-chart-55957d6dc9-wcmfd   1/1     Running   0          1s
USER-SUPPLIED VALUES:
replicaCount: 2
```

Flags I noted: `--reuse-values` (keep previous overrides and add new ones), `-f values-prod.yaml`, `--atomic --timeout 60s` (automatic rollback if the upgrade does not become healthy), `--install`, `--wait` (block until the Pods are Ready - I used it so the next command sees the final state).

---

## 7. `helm history` – all revisions of a release

```bash
helm history demo -n s15
```

Output (captured 2026-10-08)

```text
REVISION	UPDATED                 	STATUS    	CHART           	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:46:26 2026	superseded	demo-chart-0.1.0	1.16.0     	Install complete
2       	Thu Oct  8 02:46:26 2026	superseded	demo-chart-0.1.0	1.16.0     	Upgrade complete
3       	Thu Oct  8 02:47:04 2026	deployed  	demo-chart-0.1.0	1.16.0     	Upgrade complete
```

Revision 2 is the no-op `upgrade --install` from step 2; revision 3 is the `replicaCount=2` upgrade.

---

## 8. `helm rollback` – go back to a revision

Re-applies the manifest of revision N as a **new** revision; history is never deleted.

```bash
helm rollback demo 1 -n s15 --wait --timeout 120s
helm history demo -n s15
kubectl get pods -n s15
```

Output (captured 2026-10-08)

```text
Rollback was a success! Happy Helming!
REVISION	UPDATED                 	STATUS    	CHART           	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:46:26 2026	superseded	demo-chart-0.1.0	1.16.0     	Install complete
2       	Thu Oct  8 02:46:26 2026	superseded	demo-chart-0.1.0	1.16.0     	Upgrade complete
3       	Thu Oct  8 02:47:04 2026	superseded	demo-chart-0.1.0	1.16.0     	Upgrade complete
4       	Thu Oct  8 02:47:05 2026	deployed  	demo-chart-0.1.0	1.16.0     	Rollback to 1
NAME                               READY   STATUS        RESTARTS   AGE
demo-demo-chart-55957d6dc9-pjdcn   1/1     Running       0          39s
demo-demo-chart-55957d6dc9-wcmfd   1/1     Terminating   0          1s
```

Back to one replica: the second Pod is `Terminating` right after the rollback. `helm rollback demo -n s15` without a number rolls back to the previous revision.

---

## 9. `helm uninstall` – remove the release

Deletes every object the release created and (by default) its history Secrets.

```bash
helm uninstall demo -n s15
helm list -n s15
kubectl get all -n s15
kubectl get secrets -n s15
```

Output (captured 2026-10-08)

```text
release "demo" uninstalled
NAME	NAMESPACE	REVISION	UPDATED	STATUS	CHART	APP VERSION
NAME                                   READY   STATUS        RESTARTS   AGE
pod/demo-demo-chart-55957d6dc9-pjdcn   1/1     Terminating   0          39s
pod/demo-demo-chart-55957d6dc9-wcmfd   1/1     Terminating   0          1s
No resources found in s15 namespace.
```

The Pods are still `Terminating` a second after the uninstall (nginx needs a moment to stop); the release Secrets are already gone. With `--keep-history` the revision Secrets stay so that `helm history` still works and `helm rollback` could resurrect the release:

```bash
helm uninstall demo -n s15 --keep-history
helm history demo -n s15
helm uninstall demo -n s15          # removes the kept history as well
```

Output (captured 2026-10-08)

```text
release "demo" uninstalled
REVISION	UPDATED                 	STATUS     	CHART           	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:48:23 2026	uninstalled	demo-chart-0.1.0	1.16.0     	Uninstallation complete
release "demo" uninstalled
```

---

## 10. `helm repo` – manage chart repositories

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm repo list
helm repo remove bitnami      # run at the very end, after the searches below
```

Output (captured 2026-10-08)

```text
"bitnami" has been added to your repositories
Hang tight while we grab the latest from your chart repositories...
...Successfully got an update from the "bitnami" chart repository
...Successfully got an update from the "prometheus-community" chart repository
Update Complete. ⎈Happy Helming!⎈
NAME                	URL
prometheus-community	https://prometheus-community.github.io/helm-charts
bitnami             	https://charts.bitnami.com/bitnami
"bitnami" has been removed from your repositories
```

(`prometheus-community` was already configured on my machine from another session; `repo update` refreshes every repo.)

Note: since August 2025 Bitnami moved most of its free images/charts to the `bitnamilegacy` registry and the "Bitnami Secure Images" catalog, so the exact list of charts and versions returned by the commands below changes over time. The commands themselves stay the same; the alternative is to reference charts as OCI artifacts, e.g. `helm install my-nginx oci://registry-1.docker.io/bitnamicharts/nginx`.

---

## 11. `helm search` – find charts

`search repo` searches the repositories I added locally (fast, offline after `repo update`); `search hub` queries Artifact Hub over the internet.

```bash
helm search repo nginx
helm search repo bitnami/nginx --versions | head -5
helm search hub nginx | head -8
```

Output (captured 2026-10-08)

```text
NAME                                          	CHART VERSION	APP VERSION	DESCRIPTION
bitnami/nginx                                 	25.2.1       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx-ingress-controller              	12.0.7       	1.13.1     	NGINX Ingress Controller is an Ingress controll...
bitnami/nginx-intel                           	2.1.15       	0.4.9      	DEPRECATED NGINX Open Source for Intel is a lig...
prometheus-community/prometheus-nginx-exporter	1.23.1       	1.5.3      	A Helm chart for NGINX Prometheus Exporter

NAME                            	CHART VERSION	APP VERSION	DESCRIPTION
bitnami/nginx                   	25.2.1       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.2.0       	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.1.15      	1.31.6     	NGINX Open Source is a web server that can be a...
bitnami/nginx                   	25.1.14      	1.31.6     	NGINX Open Source is a web server that can be a...

URL                                               	CHART VERSION  	APP VERSION	DESCRIPTION
https://artifacthub.io/packages/helm/cloudpirat...	0.16.12        	1.31.6     	Nginx is a high-performance HTTP server and rev...
https://artifacthub.io/packages/helm/quench-ngi...	0.0.15         	1.30.5     	High-performance web server, reverse proxy, and...
https://artifacthub.io/packages/helm/krakazyabr...	1.0.0          	1.19.0     	Nginx Helm chart for Kubernetes
https://artifacthub.io/packages/helm/dhinesh/nginx	25.2.1         	1.31.6     	NGINX Open Source is a web server that can be a...
https://artifacthub.io/packages/helm/bitnami/nginx	25.2.1         	1.31.6     	NGINX Open Source is a web server that can be a...
https://artifacthub.io/packages/helm/niceos/nginx 	1.31.1+niceos.2	1.31.1     	Bitnami-compatible NGINX Helm chart for NiceOS
https://artifacthub.io/packages/helm/bitnami-ak...	13.2.12        	1.23.2     	NGINX Open Source is a web server that can be a...
```

(Chart/app versions are the ones I saw on 2026-10-08; they move constantly. `search hub` returns many community forks of the same chart, so I read the URL column carefully.)

Installing from the repo works the same way as from a local directory (not run here, the Bitnami images need an amd64/arm64 check first):

Expected output

```bash
helm install my-nginx bitnami/nginx -n s15 --set service.type=ClusterIP
helm uninstall my-nginx -n s15
```

---

## Summary table

| Command | What it does | Needs a cluster? |
|---|---|---|
| `helm create <name>` | generate a chart skeleton | no |
| `helm lint <chart>` / `helm template <rel> <chart>` | validate / render locally | no |
| `helm install <rel> <chart>` | create a release (revision 1) | yes |
| `helm list [-A]` | list releases | yes |
| `helm status <rel>` | state + resources of a release | yes |
| `helm get values/manifest/notes/all <rel>` | what Helm stored for the release | yes |
| `helm upgrade <rel> <chart>` | apply changes, new revision | yes |
| `helm history <rel>` | all revisions and their status | yes |
| `helm rollback <rel> [N]` | restore revision N as a new revision | yes |
| `helm uninstall <rel>` | delete all release resources | yes |
| `helm repo add/update/list/remove` | manage chart repositories | internet |
| `helm search repo/hub <kw>` | find charts locally / on Artifact Hub | repo: no, hub: internet |

## Deliverables

* `README.md` – this file: every command with its purpose and captured output.
* The chart used for the cluster commands is the stock `helm create demo-chart` output (generated in a scratch directory, not committed); my own charts are in `../02-rollback-workflow/webapp` and `../mini-project/notes-chart`.
