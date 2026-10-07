# Task 3 – Ingress

Student: Om Malviya | Enrollment No: 24BCS10448

Two tiny HTTP apps (`hashicorp/http-echo`, multi-arch) are exposed through ClusterIP Services and one
Ingress routes `demo.local/app1` and `demo.local/app2` to them. One entry point, path-based routing.

```text
curl -H 'Host: demo.local' http://localhost/app1      (node IP / LoadBalancer IP on a real cluster)
            |
            v
  Ingress Controller (Traefik on k3s / ingress-nginx on minikube)   <- reads Ingress "demo-ingress"
            |-- /app1 --> Service app1:80 --> http-echo pods  "Hello from app1"
            '-- /app2 --> Service app2:80 --> http-echo pods  "Hello from app2"
```

Files:

| File | Purpose |
| --- | --- |
| `app1-deployment.yaml` | Deployment `app1` (2 replicas) + Service `app1` (80 -> 5678) |
| `app2-deployment.yaml` | Deployment `app2` (2 replicas) + Service `app2` (80 -> 5678) |
| `ingress.yaml` | Ingress `demo-ingress`, host `demo.local`, paths `/app1`, `/app2` |

## Step 0 – Make sure an Ingress Controller exists

The Ingress object alone does nothing; a controller must be running (see `../04-ingress-vs-controller/`).

k3s ships Traefik and registers it as the default IngressClass:

```bash
kubectl get ingressclass
kubectl get pods -n kube-system -l app.kubernetes.io/name=traefik
kubectl get svc -n kube-system traefik
```

Output (captured 2026-10-07, k3s v1.35.0+k3s1 running in a Colima VM):

```text
NAME      CONTROLLER                      PARAMETERS   AGE
traefik   traefik.io/ingress-controller   <none>       8m15s

NAME                       READY   STATUS    RESTARTS   AGE
traefik-6d98778dfc-8gsvf   1/1     Running   0          8m15s

NAME      TYPE           CLUSTER-IP     EXTERNAL-IP   PORT(S)                      AGE
traefik   LoadBalancer   10.43.71.127   192.168.5.1   80:31040/TCP,443:31326/TCP   8m15s
```

The `EXTERNAL-IP` of the Traefik LoadBalancer is the node's own IP (k3s' built-in ServiceLB publishes
it on every node).

Minikube alternative (ingress-nginx, class `nginx`):

```bash
minikube addons enable ingress
kubectl get pods -n ingress-nginx
kubectl get ingressclass
```

Because `ingress.yaml` does not set `ingressClassName`, the default class is used on both clusters.
If a cluster has several controllers, uncomment the right `ingressClassName` line in `ingress.yaml`
(`traefik` or `nginx`). The two controllers also differ in annotations (Traefik uses
`traefik.ingress.kubernetes.io/...`, nginx uses `nginx.ingress.kubernetes.io/...`), which is why I kept
this Ingress free of controller-specific annotations.

## Step 1 – Deploy the applications

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f app1-deployment.yaml -f app2-deployment.yaml
kubectl get pods -n s12 -l 'app in (app1,app2)'
```

Output (captured 2026-10-07):

```text
deployment.apps/app1 created
service/app1 created
deployment.apps/app2 created
service/app2 created

NAME                    READY   STATUS    RESTARTS   AGE
app1-66fbc7fcf5-fz74c   1/1     Running   0          66s
app1-66fbc7fcf5-lzjf2   1/1     Running   0          66s
app2-55f795fcd7-fwgkj   1/1     Running   0          65s
app2-55f795fcd7-kjmkm   1/1     Running   0          65s
```

## Step 2 – Verify the Services

```bash
kubectl get svc,endpoints -n s12
```

Output (captured 2026-10-07):

```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME           TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
service/app1   ClusterIP   10.43.157.16   <none>        80/TCP    66s
service/app2   ClusterIP   10.43.36.136   <none>        80/TCP    65s

NAME             ENDPOINTS                         AGE
endpoints/app1   10.42.0.22:5678,10.42.0.23:5678   66s
endpoints/app2   10.42.0.24:5678,10.42.0.25:5678   65s
```

(The warning is new in recent Kubernetes: `kubectl get endpointslices -n s12` gives the same information.)
Both Services are ClusterIP only, so they are not reachable from outside: that is the job of the Ingress.

## Step 3 – Configure the Ingress

```bash
kubectl apply -f ingress.yaml
kubectl get ingress -n s12
```

Output (captured 2026-10-07; the ADDRESS appeared after a few seconds):

```text
ingress.networking.k8s.io/demo-ingress created
NAME           CLASS     HOSTS        ADDRESS       PORTS   AGE
demo-ingress   traefik   demo.local   192.168.5.1   80      65s
```

(On minikube: CLASS `nginx`, ADDRESS `192.168.49.2`.)

```bash
kubectl describe ingress demo-ingress -n s12
```

Output (captured 2026-10-07):

```text
Name:             demo-ingress
Labels:           app=demo
Namespace:        s12
Address:          192.168.5.1
Ingress Class:    traefik
Default backend:  <default>
Rules:
  Host        Path  Backends
  ----        ----  --------
  demo.local
              /app1   app1:80 (10.42.0.23:5678,10.42.0.22:5678)
              /app2   app2:80 (10.42.0.25:5678,10.42.0.24:5678)
Annotations:  <none>
Events:       <none>
```

The `Backends` column resolving to real pod IPs is the first confirmation that the routing is wired
correctly (compare with the broken scenario in `../05-troubleshooting/`).

## Step 4 – Access the application through the Ingress

Find the node IP (on k3s the Traefik LoadBalancer Service is published on the node IP):

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "$NODE_IP"
```

Output (captured 2026-10-07):

```text
192.168.5.1
```

On a k3s node or a VM with a routable IP this is the address to curl. My cluster runs inside a Colima
VM on macOS, and I observed that `192.168.5.1` is the VM's internal address: `curl http://192.168.5.1/`
from the Mac times out (`rc=28`), while the same request from a pod inside the cluster works
(`kubectl run curltest --rm -i --image=busybox:1.36 -- wget -qO- --header='Host: demo.local'
http://192.168.5.1/app2` -> `Hello from app2`). Colima forwards the VM's port 80 to the Mac, so from
the laptop the ingress entry point is simply `http://localhost`. A fallback that works on any cluster is
`kubectl port-forward -n kube-system svc/traefik 18080:80` and then `http://localhost:18080`.

```bash
INGRESS=http://localhost        # or http://$NODE_IP on a real node, or http://localhost:18080 via port-forward
```

Option A – no DNS change, send the Host header manually:

```bash
curl -H 'Host: demo.local' $INGRESS/app1
curl -H 'Host: demo.local' $INGRESS/app2
```

Output (captured 2026-10-08):

```text
Hello from app1
Hello from app2
```

Option B – make the hostname resolve. The permanent way is an `/etc/hosts` entry
(`echo "127.0.0.1  demo.local" | sudo tee -a /etc/hosts`, then `curl http://demo.local/app1`); I did
not run that because it needs `sudo` on the shared machine. `curl --resolve` does the same mapping
for a single request without touching `/etc/hosts`:

```bash
curl --resolve demo.local:80:127.0.0.1 http://demo.local/app1
```

Output (captured 2026-10-08):

```text
Hello from app1
```

(On minikube use `minikube ip` for the address.)

## Step 5 – Verify routing

| Request | Result (captured 2026-10-08) | Why |
| --- | --- | --- |
| `curl -H 'Host: demo.local' $INGRESS/app1` | `Hello from app1` | path rule `/app1` -> Service `app1` |
| `curl -H 'Host: demo.local' $INGRESS/app2` | `Hello from app2` | path rule `/app2` -> Service `app2` |
| `curl -H 'Host: demo.local' $INGRESS/app1/anything` | `Hello from app1` | `pathType: Prefix` matches sub-paths |
| `curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: demo.local' $INGRESS/other` | `404` | no rule for `/other` |
| `curl -sS -o /dev/null -w '%{http_code}\n' $INGRESS/app1` | `404` | Host header missing -> no rule matches |

```bash
curl -H 'Host: demo.local' $INGRESS/app1/anything
curl -sS -o /dev/null -w '%{http_code}\n' -H 'Host: demo.local' $INGRESS/other
curl -H 'Host: demo.local' $INGRESS/other
curl -sS -o /dev/null -w '%{http_code}\n' $INGRESS/app1
curl -i -H 'Host: demo.local' $INGRESS/app1
```

Output (captured 2026-10-08):

```text
Hello from app1
404
404 page not found
404
HTTP/1.1 200 OK
Content-Length: 16
Content-Type: text/plain; charset=utf-8
Date: Wed, 07 Oct 2026 20:58:17 GMT
X-App-Name: http-echo
X-App-Version: 1.0.0

Hello from app1
```

The plain-text `404 page not found` body is Traefik's own answer (no router matched), not something
from a backend.

Repeating the request several times and checking the pod logs shows the load being spread over both
replicas:

```bash
for i in 1 2 3 4; do curl -s -H 'Host: demo.local' $INGRESS/app1; done
kubectl logs -n s12 -l app=app1 --tail=4 --prefix
```

Output (captured 2026-10-08):

```text
Hello from app1
Hello from app1
Hello from app1
Hello from app1
[pod/app1-66fbc7fcf5-fz74c/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:39580 "GET /app1/anything HTTP/1.1" 200 16 "curl/8.7.1" 21.876µs
[pod/app1-66fbc7fcf5-fz74c/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:39580 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 9.667µs
[pod/app1-66fbc7fcf5-fz74c/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:39580 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 3.125µs
[pod/app1-66fbc7fcf5-fz74c/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:39580 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 31.376µs
[pod/app1-66fbc7fcf5-lzjf2/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:49504 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 14.625µs
[pod/app1-66fbc7fcf5-lzjf2/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:49504 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 4.25µs
[pod/app1-66fbc7fcf5-lzjf2/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:49504 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 3.25µs
[pod/app1-66fbc7fcf5-lzjf2/http-echo] 2026/10/07 20:58:17 demo.local 10.42.0.13:49504 "GET /app1 HTTP/1.1" 200 16 "curl/8.7.1" 14.751µs
```

Both replicas (`fz74c` and `lzjf2`) received requests, and the source address `10.42.0.13` is the
Traefik pod, not my laptop. I observed that the backend receives the full path `/app1` (no rewrite). http-echo answers the same
text for any path, so no rewrite annotation is needed; for a real backend that expects `/`, Traefik
would need a `Middleware` (StripPrefix) and nginx the `rewrite-target` annotation.

## Cleanup

```bash
kubectl delete -f ingress.yaml -f app1-deployment.yaml -f app2-deployment.yaml
sudo sed -i.bak '/demo.local/d' /etc/hosts   # only if you added the hosts entry
pkill -f 'port-forward -n kube-system svc/traefik'   # only if you used the port-forward fallback
```

## Deliverables

- `app1-deployment.yaml`, `app2-deployment.yaml` – application Deployments + Services.
- `ingress.yaml` – Ingress YAML with host `demo.local` and path routing.
- This README – controller check, deploy, access via Ingress, routing verification.
