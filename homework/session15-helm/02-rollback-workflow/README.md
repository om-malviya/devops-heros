# Task 2: Helm Rollback Workflow

Student: Om Malviya | Enrollment No: 24BCS10448

```text
Install (rev 1)  →  Upgrade (rev 2)  →  Verify  →  Upgrade again (rev 3)  →  Verify  →  Rollback to 2 (rev 4)  →  Verify
```

## The chart: `webapp/`

A small chart I wrote for this exercise. Three values matter for the workflow and all three are observable from outside:

| Value | Default | Where it shows up |
|---|---|---|
| `image.tag` | `alpine` | the Pod image (`nginx:<tag>`) |
| `replicaCount` | `1` | number of Pods |
| `message` | `Hello from webapp v1` | ConfigMap key `MESSAGE` **and** the `index.html` nginx serves |

```text
webapp/
  Chart.yaml
  values.yaml
  .helmignore
  templates/
    _helpers.tpl        name/fullname/labels helpers
    configmap.yaml      MESSAGE + index.html rendered from .Values.message
    deployment.yaml     nginx, mounts index.html from the ConfigMap, checksum/config annotation
    service.yaml        ClusterIP :80 -> named port http
    NOTES.txt           printed after install/upgrade/rollback
```

The `checksum/config` annotation on the Pod template is the SHA-256 of the rendered ConfigMap, so changing only `message` still triggers a rolling update (otherwise the Deployment would not restart and nginx would keep the old file).

### Lint and render (no cluster needed)

```bash
helm lint webapp
helm template webapp webapp -n s15 | grep -E 'kind:|replicas:|image:|MESSAGE|<h1>'
helm template webapp webapp -n s15 --set image.tag=1.27-alpine --set replicaCount=2 | grep -E 'replicas:|image:|<h1>'
helm template webapp webapp -n s15 --set image.tag=1.27-alpine --set replicaCount=3 --set message="Hello from webapp v3" | grep -E 'replicas:|image:|<h1>'
```

Output (captured 2026-10-07)

```text
==> Linting webapp
[INFO] Chart.yaml: icon is recommended

1 chart(s) linted, 0 chart(s) failed
kind: ConfigMap
  MESSAGE: "Hello from webapp v1"
    <h1>Hello from webapp v1</h1>
kind: Service
kind: Deployment
  replicas: 1
          image: "nginx:alpine"
            - name: MESSAGE
                  key: MESSAGE
    <h1>Hello from webapp v1</h1>
  replicas: 2
          image: "nginx:1.27-alpine"
    <h1>Hello from webapp v3</h1>
  replicas: 3
          image: "nginx:1.27-alpine"
```

(Full rendered manifest for the defaults: see the end of this file.)

## The script: `rollback-demo.sh`

`./rollback-demo.sh` runs the whole workflow in namespace `s15`, prints every command, prints `helm history` after each step and a `verify` block that checks replicas, image and message against what the revision should have (it exits non-zero if they differ). `./rollback-demo.sh --cleanup` removes everything. Everything below is the output of one run of the script on a single-node k3s cluster (Kubernetes v1.35, Helm v4.3.0), plus two extra checks I ran by hand at the end. The script took about 35 seconds.

---

### Step 1: Install (revision 1)

```bash
helm install webapp webapp -n s15 --create-namespace --wait --timeout 120s
helm history webapp -n s15
```

Output (captured 2026-10-08)

```text
NAME: webapp
LAST DEPLOYED: Thu Oct  8 02:57:54 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
NOTES:
webapp release "webapp" revision 1 deployed to namespace s15.

  image    : nginx:alpine
  replicas : 1
  message  : Hello from webapp v1
...
REVISION	UPDATED                 	STATUS  	CHART       	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:57:54 2026	deployed	webapp-0.1.0	1.27       	Install complete
```

Verify:

```bash
kubectl rollout status deployment/webapp -n s15 --timeout=120s
kubectl get deployment webapp -n s15 -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image'
kubectl get pods -n s15 -l app.kubernetes.io/instance=webapp
helm get values webapp -n s15
kubectl get configmap webapp -n s15 -o jsonpath='{.data.MESSAGE}'
```

Output (captured 2026-10-08)

```text
deployment "webapp" successfully rolled out
NAME     READY   DESIRED   IMAGE
webapp   1       1         nginx:alpine
NAME                     READY   STATUS    RESTARTS   AGE
webapp-bdd59ddd5-lphkp   1/1     Running   0          7s
USER-SUPPLIED VALUES:
null
Hello from webapp v1
VERIFY OK: replicas=1 image=nginx:alpine message="Hello from webapp v1"
```

### Step 2: Upgrade (revision 2) – `image.tag=1.27-alpine`, `replicaCount=2`

```bash
helm upgrade webapp webapp -n s15 --set image.tag=1.27-alpine --set replicaCount=2 --wait --timeout 120s
helm history webapp -n s15
```

Output (captured 2026-10-08)

```text
Release "webapp" has been upgraded. Happy Helming!
NAME: webapp
LAST DEPLOYED: Thu Oct  8 02:58:01 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 2
DESCRIPTION: Upgrade complete
NOTES:
webapp release "webapp" revision 2 deployed to namespace s15.

  image    : nginx:1.27-alpine
  replicas : 2
  message  : Hello from webapp v1
...
REVISION	UPDATED                 	STATUS    	CHART       	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:57:54 2026	superseded	webapp-0.1.0	1.27       	Install complete
2       	Thu Oct  8 02:58:01 2026	deployed  	webapp-0.1.0	1.27       	Upgrade complete
```

### Step 3: Verify revision 2

```bash
kubectl get deployment webapp -n s15 -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image'
kubectl get pods -n s15 -l app.kubernetes.io/instance=webapp
helm get values webapp -n s15
kubectl get configmap webapp -n s15 -o jsonpath='{.data.MESSAGE}'
```

Output (captured 2026-10-08)

```text
NAME     READY   DESIRED   IMAGE
webapp   2       2         nginx:1.27-alpine
NAME                      READY   STATUS      RESTARTS   AGE
webapp-7dd4ff7855-kbg4d   1/1     Running     0          6s
webapp-7dd4ff7855-mdbkb   1/1     Running     0          9s
webapp-bdd59ddd5-lphkp    0/1     Completed   0          16s
USER-SUPPLIED VALUES:
image:
  tag: 1.27-alpine
replicaCount: 2
Hello from webapp v1
VERIFY OK: replicas=2 image=nginx:1.27-alpine message="Hello from webapp v1"
```

I observed that the ReplicaSet hash changed (`bdd59ddd5` → `7dd4ff7855`) because the image changed, so the old Pod was replaced and a second one was added. The old Pod shows `Completed` for a moment: nginx exits with code 0 on SIGTERM and this Kubernetes version reports that phase while the Pod is being removed.

### Step 4: Upgrade again (revision 3) – `replicaCount=3`, new message

I use `--reuse-values` so the `1.27-alpine` tag from revision 2 is kept; without it Helm would go back to the chart default `alpine` for everything I do not pass on the command line.

```bash
helm upgrade webapp webapp -n s15 --reuse-values --set replicaCount=3 --set message="Hello from webapp v3" --wait --timeout 120s
helm history webapp -n s15
```

Output (captured 2026-10-08)

```text
Release "webapp" has been upgraded. Happy Helming!
NAME: webapp
LAST DEPLOYED: Thu Oct  8 02:58:10 2026
NAMESPACE: s15
STATUS: deployed
REVISION: 3
DESCRIPTION: Upgrade complete
NOTES:
webapp release "webapp" revision 3 deployed to namespace s15.

  image    : nginx:1.27-alpine
  replicas : 3
  message  : Hello from webapp v3
...
REVISION	UPDATED                 	STATUS    	CHART       	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:57:54 2026	superseded	webapp-0.1.0	1.27       	Install complete
2       	Thu Oct  8 02:58:01 2026	superseded	webapp-0.1.0	1.27       	Upgrade complete
3       	Thu Oct  8 02:58:10 2026	deployed  	webapp-0.1.0	1.27       	Upgrade complete
```

### Step 5: Verify revision 3

```bash
kubectl get deployment webapp -n s15 -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image'
kubectl get pods -n s15 -l app.kubernetes.io/instance=webapp
helm get values webapp -n s15
kubectl get configmap webapp -n s15 -o jsonpath='{.data.MESSAGE}'
```

Output (captured 2026-10-08)

```text
NAME     READY   DESIRED   IMAGE
webapp   3       3         nginx:1.27-alpine
NAME                      READY   STATUS      RESTARTS   AGE
webapp-7b69db558f-8lcrp   1/1     Running     0          17s
webapp-7b69db558f-fxbrg   1/1     Running     0          14s
webapp-7b69db558f-g2j6r   1/1     Running     0          7s
webapp-7dd4ff7855-mdbkb   0/1     Completed   0          26s
USER-SUPPLIED VALUES:
image:
  tag: 1.27-alpine
message: Hello from webapp v3
replicaCount: 3
Hello from webapp v3
VERIFY OK: replicas=3 image=nginx:1.27-alpine message="Hello from webapp v3"
```

The Pods were rolled again (new hash `7b69db558f`) even though the image did not change, because the `checksum/config` annotation changed with the new message.

### Step 6: Rollback to revision 2 (creates revision 4)

```bash
helm rollback webapp 2 -n s15 --wait --timeout 120s
helm history webapp -n s15
```

Output (captured 2026-10-08)

```text
Rollback was a success! Happy Helming!
REVISION	UPDATED                 	STATUS    	CHART       	APP VERSION	DESCRIPTION
1       	Thu Oct  8 02:57:54 2026	superseded	webapp-0.1.0	1.27       	Install complete
2       	Thu Oct  8 02:58:01 2026	superseded	webapp-0.1.0	1.27       	Upgrade complete
3       	Thu Oct  8 02:58:10 2026	superseded	webapp-0.1.0	1.27       	Upgrade complete
4       	Thu Oct  8 02:58:27 2026	deployed  	webapp-0.1.0	1.27       	Rollback to 2
```

Rollback does not delete revision 3; it copies revision 2's manifest and values into a new revision 4. I can still `helm rollback webapp 3` later if needed.

### Step 7: Verify the rollback

```bash
kubectl get deployment webapp -n s15 -o custom-columns='NAME:.metadata.name,READY:.status.readyReplicas,DESIRED:.spec.replicas,IMAGE:.spec.template.spec.containers[0].image'
kubectl get pods -n s15 -l app.kubernetes.io/instance=webapp
helm get values webapp -n s15
kubectl get configmap webapp -n s15 -o jsonpath='{.data.MESSAGE}'
helm list -n s15
```

Output (captured 2026-10-08)

```text
NAME     READY   DESIRED   IMAGE
webapp   2       2         nginx:1.27-alpine
NAME                      READY   STATUS      RESTARTS   AGE
webapp-7b69db558f-8lcrp   0/1     Completed   0          27s
webapp-7dd4ff7855-4djrs   1/1     Running     0          10s
webapp-7dd4ff7855-nz8vk   1/1     Running     0          7s
USER-SUPPLIED VALUES:
image:
  tag: 1.27-alpine
replicaCount: 2
Hello from webapp v1
VERIFY OK: replicas=2 image=nginx:1.27-alpine message="Hello from webapp v1"
NAME  	NAMESPACE	REVISION	UPDATED                             	STATUS  	CHART       	APP VERSION
webapp	s15      	4       	2026-10-08 02:58:27.798287 +0530 IST	deployed	webapp-0.1.0	1.27
```

Everything is back to the revision-2 state: 2 replicas, `nginx:1.27-alpine`, the original message. The ReplicaSet hash `7dd4ff7855` is the same one revision 2 created, which confirms the Pod template is byte-identical. Two extra checks I ran by hand:

```bash
kubectl port-forward svc/webapp -n s15 18080:80 & sleep 3; curl -s http://localhost:18080; kill %1
kubectl get rs -n s15 -l app.kubernetes.io/instance=webapp
kubectl get secrets -n s15 -l owner=helm
```

Output (captured 2026-10-08)

```text
<html><body>
<h1>Hello from webapp v1</h1>
<p>release=webapp revision=2 image=nginx:1.27-alpine</p>
</body></html>

NAME                DESIRED   CURRENT   READY   AGE
webapp-7b69db558f   0         0         0       13m
webapp-7dd4ff7855   2         2         2       13m
webapp-bdd59ddd5    0         0         0       13m

NAME                           TYPE                 DATA   AGE
sh.helm.release.v1.webapp.v1   helm.sh/release.v1   1      13m
sh.helm.release.v1.webapp.v2   helm.sh/release.v1   1      13m
sh.helm.release.v1.webapp.v3   helm.sh/release.v1   1      13m
sh.helm.release.v1.webapp.v4   helm.sh/release.v1   1      12m
```

Two details worth noting: the page says `revision=2` although the release is at revision 4, because a rollback re-applies the **stored manifest** of revision 2 instead of re-rendering the templates (so `.Release.Revision` is not re-evaluated); and all three ReplicaSets still exist (old ones scaled to 0), which is the Deployment's own rollout history independent of Helm's four release Secrets.

### Clean up

```bash
./rollback-demo.sh --cleanup
```

Output (captured 2026-10-08)

```text
$ helm uninstall webapp -n s15
release "webapp" uninstalled

$ kubectl delete namespace s15 --ignore-not-found
namespace "s15" deleted
```

---

## What I learned

* Every `install`/`upgrade`/`rollback` creates a new revision; `helm history` is the audit trail, backed by one Secret per revision.
* `--set` values do not persist across upgrades unless I pass `--reuse-values` (or keep them in a values file, which is the better practice).
* A ConfigMap-only change needs the checksum annotation to restart Pods.
* `helm rollback N` is a forward operation (new revision), which keeps the history intact and makes "roll back the rollback" possible; it re-applies the stored manifest rather than re-rendering.
* `--atomic --timeout` on upgrade is the automated version of this workflow: Helm rolls back by itself if the new revision does not become healthy.

## Full rendered manifest (defaults)

```bash
helm template webapp webapp -n s15
```

Output (captured 2026-10-07)

```text
---
# Source: webapp/templates/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: webapp
    app.kubernetes.io/version: "alpine"
    app.kubernetes.io/managed-by: Helm
data:
  MESSAGE: "Hello from webapp v1"
  index.html: |
    <html><body>
    <h1>Hello from webapp v1</h1>
    <p>release=webapp revision=1 image=nginx:alpine</p>
    </body></html>
---
# Source: webapp/templates/service.yaml
apiVersion: v1
kind: Service
metadata:
  name: webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: webapp
    app.kubernetes.io/version: "alpine"
    app.kubernetes.io/managed-by: Helm
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: webapp
  ports:
    - name: http
      port: 80
      targetPort: http
      protocol: TCP
---
# Source: webapp/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: webapp
  labels:
    helm.sh/chart: webapp-0.1.0
    app.kubernetes.io/name: webapp
    app.kubernetes.io/instance: webapp
    app.kubernetes.io/version: "alpine"
    app.kubernetes.io/managed-by: Helm
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: webapp
      app.kubernetes.io/instance: webapp
  template:
    metadata:
      labels:
        app.kubernetes.io/name: webapp
        app.kubernetes.io/instance: webapp
      annotations:
        # changes whenever the ConfigMap content changes -> forces a rollout on message change
        checksum/config: fc20b4239e71f047a24c7ddcb116b5f515e96d1fc95f198e2c4111826eb57c49
    spec:
      containers:
        - name: nginx
          image: "nginx:alpine"
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
              protocol: TCP
          env:
            - name: MESSAGE
              valueFrom:
                configMapKeyRef:
                  name: webapp
                  key: MESSAGE
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
          readinessProbe:
            httpGet:
              path: /
              port: http
            initialDelaySeconds: 2
            periodSeconds: 5
          resources:
            limits:
              cpu: 100m
              memory: 64Mi
            requests:
              cpu: 10m
              memory: 16Mi
      volumes:
        - name: html
          configMap:
            name: webapp
            items:
              - key: index.html
                path: index.html
```

## Deliverables

* `webapp/` – the chart (Chart.yaml, values.yaml, templates: deployment, service, configmap, _helpers.tpl, NOTES.txt).
* `rollback-demo.sh` – runs install → upgrade → verify → upgrade → verify → rollback → verify with `helm history` after every step.
* `README.md` – this document with the complete process and captured output.
