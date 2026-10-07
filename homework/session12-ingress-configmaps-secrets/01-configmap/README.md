# Task 1 – ConfigMap

Student: Om Malviya | Enrollment No: 24BCS10448

A ConfigMap keeps non-sensitive configuration outside the container image so the same image can run
in dev, staging and production with different settings. In this demo I create one ConfigMap that holds
four literal keys and one whole file, and then inject it into a Pod **as environment variables and as a
mounted volume at the same time**.

Files:

| File | Purpose |
| --- | --- |
| `configmap.yaml` | ConfigMap `app-config` with literal keys (`APP_ENV`, `LOG_LEVEL`, `APP_PORT`, `THEME_COLOR`) and a file key `app.properties` |
| `pod.yaml` | Pod `configmap-demo` (nginx:alpine) using `envFrom`, `env/configMapKeyRef` and a `configMap` volume at `/etc/config` |

## Step 1 – Create the ConfigMap (store configuration values)

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f configmap.yaml
kubectl get configmap -n s12
kubectl describe configmap app-config -n s12
```

Output (captured 2026-10-07):

```text
namespace/s12 created
configmap/app-config created

NAME               DATA   AGE
app-config         5      42s
kube-root-ca.crt   1      42s

Name:         app-config
Namespace:    s12
Labels:       app=configmap-demo
Annotations:  <none>

Data
====
APP_ENV:
----
production

APP_PORT:
----
8080

LOG_LEVEL:
----
INFO

THEME_COLOR:
----
blue

app.properties:
----
app.name=configmap-demo
app.env=production
app.log.level=INFO
app.max.booking.days=30
app.default.currency=INR



BinaryData
====

Events:  <none>
```

Read a single key with jsonpath:

```bash
kubectl get configmap app-config -n s12 -o jsonpath='{.data.LOG_LEVEL}{"\n"}'
```

Output (captured 2026-10-07):

```text
INFO
```

The same ConfigMap could also have been created imperatively (I used the YAML so it is versioned):

```bash
kubectl create configmap app-config -n s12 \
  --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=INFO \
  --from-file=app.properties --dry-run=client -o yaml
```

## Step 2 – Inject the ConfigMap into a Pod

`pod.yaml` uses all three injection styles:

```yaml
envFrom:                      # every key -> env var with the same name
  - configMapRef:
      name: app-config
env:                          # one key -> env var with a custom name
  - name: UI_THEME
    valueFrom:
      configMapKeyRef:
        name: app-config
        key: THEME_COLOR
volumeMounts:                 # every key -> a file in /etc/config
  - name: config-volume
    mountPath: /etc/config
    readOnly: true
volumes:
  - name: config-volume
    configMap:
      name: app-config
```

```bash
kubectl apply -f pod.yaml
kubectl get pod configmap-demo -n s12
```

Output (captured 2026-10-07):

```text
pod/configmap-demo created
NAME             READY   STATUS    RESTARTS   AGE
configmap-demo   1/1     Running   0          42s
```

(The first start took about 30 s because `nginx:alpine` had to be pulled; the events show
`Successfully pulled image "nginx:alpine" in 31.246s`.)

## Step 3 – Verify the values inside the container

Environment variables:

```bash
kubectl exec -n s12 configmap-demo -- env | grep -E 'APP_ENV|LOG_LEVEL|APP_PORT|THEME_COLOR|UI_THEME'
```

Output (captured 2026-10-07):

```text
APP_ENV=production
APP_PORT=8080
LOG_LEVEL=INFO
THEME_COLOR=blue
UI_THEME=blue
```

I had expected `app.properties` to be skipped by `envFrom` because a dot is not a valid shell
variable name, but on this cluster (k3s v1.35) it *was* injected: `env | grep '^app'` shows a
multi-line variable `app.properties=app.name=configmap-demo ...`. Kubernetes only rejects names that
contain characters outside `[-._a-zA-Z0-9]`, and a dot is allowed; a shell simply cannot reference the
variable by that name. Either way the key is only useful as a file, which is why I also mount the
ConfigMap.

Mounted files:

```bash
kubectl exec -n s12 configmap-demo -- ls -l /etc/config/
kubectl exec -n s12 configmap-demo -- cat /etc/config/app.properties
kubectl exec -n s12 configmap-demo -- cat /etc/config/LOG_LEVEL
```

Output (captured 2026-10-07):

```text
total 0
lrwxrwxrwx    1 root     root            14 Oct  7 17:11 APP_ENV -> ..data/APP_ENV
lrwxrwxrwx    1 root     root            15 Oct  7 17:11 APP_PORT -> ..data/APP_PORT
lrwxrwxrwx    1 root     root            16 Oct  7 17:11 LOG_LEVEL -> ..data/LOG_LEVEL
lrwxrwxrwx    1 root     root            18 Oct  7 17:11 THEME_COLOR -> ..data/THEME_COLOR
lrwxrwxrwx    1 root     root            21 Oct  7 17:11 app.properties -> ..data/app.properties

app.name=configmap-demo
app.env=production
app.log.level=INFO
app.max.booking.days=30
app.default.currency=INR

INFO
```

Every key became a file (the symlinks into `..data/` are how the kubelet swaps the whole directory
atomically when the ConfigMap changes).

## Step 4 – What happens when the ConfigMap is updated?

```bash
kubectl patch configmap app-config -n s12 --type merge -p '{"data":{"LOG_LEVEL":"DEBUG"}}'
sleep 60
kubectl exec -n s12 configmap-demo -- env | grep LOG_LEVEL
kubectl exec -n s12 configmap-demo -- cat /etc/config/LOG_LEVEL
```

Output (captured 2026-10-07):

```text
configmap/app-config patched
LOG_LEVEL=INFO
DEBUG
```

I observed the difference between the two injection methods: the environment variable is frozen at
container start (a restart, e.g. `kubectl rollout restart deployment/...` for a Deployment, is needed),
while the mounted file is refreshed by the kubelet within about a minute without any restart.

## Cleanup

```bash
kubectl delete -f pod.yaml -f configmap.yaml
```

## Deliverables

- `configmap.yaml` – ConfigMap YAML (literal keys + file key).
- `pod.yaml` – Pod injecting the ConfigMap as env vars and as a volume.
- This README – commands and expected output for create / inject / verify.
