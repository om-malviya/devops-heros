# Session 12 – Kubernetes Ingress, ConfigMaps & Secrets

Student: Om Malviya | Enrollment No: 24BCS10448

All resources live in namespace `s12`. Everything was written for a k3s cluster (Traefik ingress
controller installed by default) and also works on minikube after `minikube addons enable ingress`.
I ran everything on a single-node k3s v1.35 cluster (Colima VM on macOS, node name `colima`,
`kubectl` context `colima`); cluster output blocks are labelled `Output (captured <date>)`. What I could
not run is marked `Expected output` with the reason: the optional `/etc/hosts` edit (needs `sudo`) and,
in Task 4, the minikube / no-controller / TLS variants (I only had the k3s cluster).

```text
session12-ingress-configmaps-secrets/
├── namespace.yaml                 # Namespace s12
├── deploy-all.sh                  # apply Tasks 1-3 in order and wait for readiness
├── cleanup.sh                     # delete everything (incl. troubleshooting scenarios)
├── 01-configmap/                  # Task 1: configmap.yaml, pod.yaml, README.md
├── 02-secret/                     # Task 2: secret.yaml, pod.yaml, README.md
├── 03-ingress/                    # Task 3: app1/app2 deployments+services, ingress.yaml, README.md
├── 04-ingress-vs-controller/      # Task 4: README.md
└── 05-troubleshooting/            # Task 5: broken-*.yaml, fixed-*.yaml, README.md
```

Quick start:

```bash
./deploy-all.sh
# ... follow the printed verification commands ...
./cleanup.sh
```

Output (captured 2026-10-07, `./deploy-all.sh`):

```text
[1/5] Namespace
namespace/s12 created
[2/5] ConfigMap demo
configmap/app-config created
pod/configmap-demo created
[3/5] Secret demo
secret/db-secret created
pod/secret-demo created
[4/5] Ingress demo (app1 + app2 + ingress)
deployment.apps/app1 created
service/app1 created
deployment.apps/app2 created
service/app2 created
ingress.networking.k8s.io/demo-ingress created
[5/5] Waiting for workloads
pod/configmap-demo condition met
pod/secret-demo condition met
deployment "app1" successfully rolled out
deployment "app2" successfully rolled out

NAME                         DATA   AGE
configmap/app-config         5      33s
configmap/kube-root-ca.crt   1      33s

NAME               TYPE     DATA   AGE
secret/db-secret   Opaque   3      33s

NAME                        READY   STATUS    RESTARTS   AGE
pod/app1-66fbc7fcf5-fz74c   1/1     Running   0          33s
pod/app1-66fbc7fcf5-lzjf2   1/1     Running   0          33s
pod/app2-55f795fcd7-fwgkj   1/1     Running   0          32s
pod/app2-55f795fcd7-kjmkm   1/1     Running   0          32s
pod/configmap-demo          1/1     Running   0          33s
pod/secret-demo             1/1     Running   0          33s

NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/app1   ClusterIP   10.43.157.16   <none>        80/TCP    33s
service/app2   ClusterIP   10.43.36.136   <none>        80/TCP    32s

NAME                                     CLASS     HOSTS        ADDRESS       PORTS   AGE
ingress.networking.k8s.io/demo-ingress   traefik   demo.local   192.168.5.1   80      32s

Deployed. Verify with:
  kubectl exec -n s12 configmap-demo -- env | grep -E 'APP_|LOG_LEVEL|THEME|UI_THEME'
  ...
```

## Task 1: ConfigMap

Full write-up: [`01-configmap/README.md`](01-configmap/README.md).

- **Create ConfigMap** – `kubectl apply -f 01-configmap/configmap.yaml`.
- **Store configuration values** – literal keys `APP_ENV`, `LOG_LEVEL`, `APP_PORT`, `THEME_COLOR` plus a
  whole file `app.properties` under one key.
- **Inject ConfigMap into Pod** – `01-configmap/pod.yaml` uses `envFrom.configMapRef`,
  `env.valueFrom.configMapKeyRef` and a `configMap` volume mounted at `/etc/config`.
- **Verify values inside the container**:

```bash
kubectl exec -n s12 configmap-demo -- env | grep -E 'APP_ENV|LOG_LEVEL|APP_PORT|THEME_COLOR|UI_THEME'
kubectl exec -n s12 configmap-demo -- cat /etc/config/app.properties
```

Output (captured 2026-10-07):

```text
APP_ENV=production
APP_PORT=8080
LOG_LEVEL=INFO
THEME_COLOR=blue
UI_THEME=blue
app.name=configmap-demo
app.env=production
app.log.level=INFO
app.max.booking.days=30
app.default.currency=INR
```

What I learned: env vars are frozen at container start, mounted files are refreshed by the kubelet
when the ConfigMap changes (I patched `LOG_LEVEL` to `DEBUG` and after a minute `env` still said
`INFO` while `/etc/config/LOG_LEVEL` said `DEBUG`).

## Task 2: Secret

Full write-up: [`02-secret/README.md`](02-secret/README.md).

- **Create Secret** – `kubectl apply -f 02-secret/secret.yaml` (also shown with
  `kubectl create secret generic ... --dry-run=client -o yaml`).
- **Store sensitive values** – base64 of fake `DB_USER`, `DB_PASSWORD`, `DB_NAME`, encoded with `echo -n`.
- **Inject Secret into Pod** – `02-secret/pod.yaml` uses `secretKeyRef` env vars and a `secret`
  volume at `/etc/secrets` (`defaultMode: 0400`).
- **Verify the value inside the container**:

```bash
kubectl exec -n s12 secret-demo -- env | grep DB_
kubectl exec -n s12 secret-demo -- cat /etc/secrets/DB_PASSWORD; echo
```

Output (captured 2026-10-07):

```text
DB_USER=demo_user
DB_PASSWORD=fake-password-123
DB_NAME=demo_db
fake-password-123
```

- **Why Secrets should not be committed directly to Git** – base64 is reversible encoding
  (`base64 -d` recovers the value), Git history is permanent, and public repos are scanned by bots
  within minutes. Use Sealed Secrets, External Secrets Operator or SOPS, keep `*secret*.yaml` in
  `.gitignore`, and run gitleaks in a pre-commit hook. Details and examples in the Task 2 README,
  including the `echo` vs `echo -n` trailing-newline bug from the course's
  `troubleshooting/secret-base64-gotcha.md`.

## Task 3: Ingress

Full write-up: [`03-ingress/README.md`](03-ingress/README.md).

- **Deploy application** – `app1` and `app2` (`hashicorp/http-echo`, 2 replicas each).
- **Create Service** – ClusterIP `app1` and `app2`, port 80 -> 5678.
- **Configure Ingress** – `03-ingress/ingress.yaml`, host `demo.local`, `/app1` and `/app2`
  (`pathType: Prefix`), default IngressClass (Traefik on k3s / nginx on minikube).
- **Access application through Ingress**:

```bash
INGRESS=http://localhost   # Colima forwards the VM's port 80 to the Mac; on a real node use http://$NODE_IP
curl -H 'Host: demo.local' $INGRESS/app1
curl -H 'Host: demo.local' $INGRESS/app2
# or: echo "127.0.0.1 demo.local" | sudo tee -a /etc/hosts && curl http://demo.local/app1
```

Output (captured 2026-10-08):

```text
Hello from app1
Hello from app2
```

The node IP (`192.168.5.1`) is the Colima VM's internal address and is not routable from macOS; it
works from inside the cluster. Details and a `kubectl port-forward svc/traefik` fallback are in the
Task 3 README.

- **Verify routing** – `kubectl describe ingress demo-ingress -n s12` shows each path resolving to
  the correct Service and pod IPs (`/app1 app1:80 (10.42.0.23:5678,10.42.0.22:5678)`); an unknown
  path or a missing Host header returned `404` from Traefik, and the http-echo pod logs showed both
  replicas serving requests.

## Task 4: Ingress vs Ingress Controller

[`04-ingress-vs-controller/README.md`](04-ingress-vs-controller/README.md) covers all bullets: what
is Ingress (API object with L7 rules), what is an Ingress Controller (the proxy pods that watch and
enforce them: Traefik, ingress-nginx, ALB), a difference table, why both are required (an Ingress
without a controller gets no ADDRESS and does nothing), and examples (path routing, host routing,
TLS, controller-specific rewrite annotations, `ingressClassName`).

## Task 5: Troubleshooting

[`05-troubleshooting/README.md`](05-troubleshooting/README.md) walks three broken scenarios through
the six required steps (identify, troubleshooting commands, root cause, fix, before/after output,
screenshots-as-output):

1. Secret key name mismatch -> `CreateContainerConfigError` -> fix `secretKeyRef.key`.
2. Missing ConfigMap (typo) -> `CreateContainerConfigError`, event `configmap "app-confg" not found` -> fix name.
3. Ingress backend with wrong Service name/port -> `404 page not found` from Traefik, `describe ingress`
   shows `<error: services "app1-svc" not found>`, Traefik log `Cannot create service` -> fix backend
   to `app1:80`.

## Screenshots

Captured/expected terminal blocks in the READMEs stand in for screenshots:

| Screenshot required for | Stand-in |
| --- | --- |
| ConfigMap created and verified | `01-configmap/README.md` Steps 1-3 (`describe configmap`, `exec env`, `cat /etc/config/...`) |
| Secret created and verified | `02-secret/README.md` Steps 1-4 (base64 captured, `describe secret`, `exec env`, `cat /etc/secrets/...`) |
| Ingress routing | `03-ingress/README.md` Steps 3-5 (`get/describe ingress`, `curl` results) |
| Troubleshooting before/after | `05-troubleshooting/README.md` sections "1. Identify" and "5. After" for each scenario |

Cleanup was run at the end (`./cleanup.sh`, output in the Cleanup section below).

## Cleanup

```bash
./cleanup.sh
kubectl get namespace s12
```

Output (captured 2026-10-08):

```text
secret "ts-db-secret" deleted from s12 namespace
pod "ts-secret-pod" deleted from s12 namespace
pod "ts-configmap-pod" deleted from s12 namespace
ingress.networking.k8s.io "ts-ingress" deleted from s12 namespace
deployment.apps "app1" deleted from s12 namespace
service "app1" deleted from s12 namespace
deployment.apps "app2" deleted from s12 namespace
service "app2" deleted from s12 namespace
ingress.networking.k8s.io "demo-ingress" deleted from s12 namespace
pod "secret-demo" deleted from s12 namespace
secret "db-secret" deleted from s12 namespace
configmap "app-config" deleted from s12 namespace
pod "configmap-demo" deleted from s12 namespace
namespace "s12" deleted
Done. If you added 'demo.local' to /etc/hosts, remove it with:
  sudo sed -i.bak '/demo.local/d' /etc/hosts
Error from server (NotFound): namespaces "s12" not found
```

(`cleanup.sh` deletes the broken/fixed files too, which is why the `ts-*` objects go first; the
`broken-*.yaml` deletions are no-ops because the fixed files refer to the same object names.)

## Deliverables

- ConfigMap YAML – `01-configmap/configmap.yaml` (+ `01-configmap/pod.yaml`).
- Secret YAML – `02-secret/secret.yaml` (+ `02-secret/pod.yaml`).
- Ingress YAML – `03-ingress/ingress.yaml` (+ `03-ingress/app1-deployment.yaml`, `app2-deployment.yaml`).
- Ingress vs Ingress Controller – `04-ingress-vs-controller/README.md`.
- Troubleshooting documentation – `05-troubleshooting/README.md` with `broken-*.yaml` / `fixed-*.yaml`.
- Screenshots – output blocks listed under "Screenshots" above.
- README.md – this file; automation in `deploy-all.sh`, `cleanup.sh`, `namespace.yaml`.
