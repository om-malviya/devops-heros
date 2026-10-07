# Task 4 – Ingress vs Ingress Controller

Student: Om Malviya | Enrollment No: 24BCS10448

## What is Ingress?

An **Ingress** is a Kubernetes API object (`networking.k8s.io/v1`, kind `Ingress`). It is a declarative
set of **Layer-7 (HTTP/HTTPS) routing rules**: which hostnames and URL paths should be forwarded to
which Service and port, and optionally which TLS certificate to terminate with.

It is only data stored in etcd. Writing an Ingress is like writing a rulebook; nothing reads the
rulebook unless a controller is installed.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  namespace: s12
spec:
  rules:
    - host: demo.local
      http:
        paths:
          - path: /app1
            pathType: Prefix
            backend:
              service:
                name: app1
                port:
                  number: 80
```

What an Ingress can express: host-based routing (`api.example.com` vs `www.example.com`), path-based
routing (`/app1`, `/app2`), TLS termination (`spec.tls` referencing a `kubernetes.io/tls` Secret), a
default backend, and `pathType` (`Prefix`, `Exact`, `ImplementationSpecific`).

What it cannot do: it does not listen on any port, does not proxy a single packet, and has no IP
address of its own.

## What is an Ingress Controller?

An **Ingress Controller** is a running application (a Deployment or DaemonSet of reverse-proxy pods)
that:

1. **watches** the API server for `Ingress`, `IngressClass`, `Service` and `EndpointSlice` objects,
2. **translates** them into its own proxy configuration (Traefik routers, nginx `server`/`location`
   blocks, an AWS ALB listener, ...),
3. **receives** external traffic, usually through a `LoadBalancer` or `NodePort` Service, and forwards
   each request to the right backend pods.

Common controllers:

| Controller | Where I meet it | IngressClass name |
| --- | --- | --- |
| Traefik | k3s installs it by default (namespace `kube-system`) | `traefik` |
| ingress-nginx | `minikube addons enable ingress`, Helm chart on any cluster | `nginx` |
| AWS Load Balancer Controller | EKS, creates an ALB per Ingress | `alb` |
| GKE Ingress (GCLB) | GKE built-in | `gce` |
| HAProxy, Contour (Envoy), Kong, Istio gateway | add-ons | various |

The `IngressClass` object is the link between the two: an Ingress selects a controller via
`spec.ingressClassName`, or falls back to the class annotated as default.

```bash
kubectl get ingressclass
```

Output (captured 2026-10-07, k3s):

```text
NAME      CONTROLLER                      PARAMETERS   AGE
traefik   traefik.io/ingress-controller   <none>       8m15s
```

Expected output (minikube with addon; not run, I only had the k3s cluster):

```text
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       5m
```

## Difference between them

| | Ingress | Ingress Controller |
| --- | --- | --- |
| Kind of thing | API object (YAML, stored in etcd) | Running software (pods) |
| Created by | Application developer / team, per app | Cluster administrator, once per cluster |
| Scope | Namespaced, usually one per app | Cluster-wide, handles Ingresses from all namespaces |
| Contains | Routing rules: hosts, paths, backends, TLS | A reverse proxy + a control loop that watches Ingress objects |
| Network presence | None (no IP, no port) | Has a Service (LoadBalancer/NodePort) with an external address |
| Portability | Standard Kubernetes API, same YAML on every cluster | Vendor specific; annotations differ per controller |
| Installed by default? | API is always there | **No** on most clusters (k3s and some managed offerings are exceptions) |
| Analogy | The flight board that says "6E-501 boards at Gate 4" | The airport building with gates, staff and runways |

## Why both are required

- **Without a controller** the Ingress is accepted (`kubectl apply` succeeds, no error) but nothing
  happens: `ADDRESS` stays empty forever and `curl` cannot connect. This is one of the most confusing
  first experiences on a fresh `kubeadm` or `kind` cluster.

  ```bash
  kubectl get ingress -n s12
  ```

  Expected output on a cluster with no controller (not run: my k3s cluster always has Traefik; the
  closest I observed is Task 5 scenario 3, where the controller exists but refuses one rule):

  ```text
  NAME           CLASS    HOSTS        ADDRESS   PORTS   AGE
  demo-ingress   <none>   demo.local             80      10m
  ```

- **Without Ingress objects** a controller is a proxy with an empty routing table; every request gets
  the controller's default `404 page not found`.

- Kubernetes deliberately separates the **"what"** (Ingress, portable) from the **"how"** (controller,
  pluggable). The same `ingress.yaml` from Task 3 works unchanged on k3s/Traefik, minikube/nginx and
  EKS/ALB; only the controller installation differs. This is the same pattern as PVC vs
  StorageClass provisioner, or Service vs kube-proxy.

- Operationally, one controller with one external LoadBalancer replaces one LoadBalancer Service per
  application, which is both cheaper (one cloud LB instead of N) and simpler (one place for TLS,
  rate limiting, auth).

## Examples

### 1. Install / verify a controller

```bash
# k3s: already installed
kubectl -n kube-system get deploy traefik

# minikube
minikube addons enable ingress
kubectl -n ingress-nginx get pods

# any cluster via Helm
helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace
```

### 2. Path-based routing (used in Task 3)

`../03-ingress/ingress.yaml`: `demo.local/app1 -> app1:80`, `demo.local/app2 -> app2:80`.

```bash
curl -H 'Host: demo.local' http://$NODE_IP/app1   # Hello from app1
curl -H 'Host: demo.local' http://$NODE_IP/app2   # Hello from app2
```

### 3. Host-based routing

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: host-based
  namespace: s12
spec:
  rules:
    - host: app1.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1
                port:
                  number: 80
    - host: app2.demo.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2
                port:
                  number: 80
```

```bash
curl -H 'Host: app1.demo.local' http://$NODE_IP/   # Hello from app1
curl -H 'Host: app2.demo.local' http://$NODE_IP/   # Hello from app2
```

### 4. TLS termination

```bash
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=demo.local/O=homework"
kubectl create secret tls demo-tls -n s12 --cert=tls.crt --key=tls.key
```

```yaml
spec:
  tls:
    - hosts: [demo.local]
      secretName: demo-tls
  rules:
    - host: demo.local
      # ...same paths as before
```

```bash
curl -k --resolve demo.local:443:$NODE_IP https://demo.local/app1
```

Expected output (not run: the TLS variant needs a certificate Secret that is not part of this homework;
only the plain-HTTP Ingress from Task 3 was deployed):

```text
Hello from app1
```

The certificate lives in the controller; the backend pods still speak plain HTTP.

### 5. Controller-specific behaviour (why annotations differ)

Stripping the `/app1` prefix before forwarding:

```yaml
# ingress-nginx
metadata:
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  rules:
    - http:
        paths:
          - path: /app1(/|$)(.*)
            pathType: ImplementationSpecific
```

```yaml
# Traefik: a Middleware CRD + annotation
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: strip-app1
  namespace: s12
spec:
  stripPrefix:
    prefixes: ["/app1"]
---
# on the Ingress:
metadata:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: s12-strip-app1@kubernetescrd
```

Same intent, different syntax: this is exactly the "how" that the controller owns.

### 6. Explicitly choosing a controller

```yaml
spec:
  ingressClassName: traefik   # or nginx, alb, ...
```

If a cluster has two controllers (for example Traefik for internal and nginx for public traffic),
every Ingress must name its class, otherwise only the default class picks it up.

## Summary

Ingress = the routing rules (what). Ingress Controller = the proxy that enforces them (how). Kubernetes
ships the API for the first and leaves the second pluggable, so both must exist for traffic to flow.

## Deliverables

- This README – all five bullets of Task 4 (what is Ingress, what is an Ingress Controller, differences, why both, examples).
