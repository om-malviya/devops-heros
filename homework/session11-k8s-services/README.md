# Session 11 – Kubernetes Networking & Services

Student: Om Malviya | Enrollment No: 24BCS10448

All manifests in this session are namespaced to `s11` so the whole lab can be
applied with `./deploy-all.sh` and removed with `./cleanup.sh`. Every block
labelled **Output (captured 2026-10-08)** was produced on a single-node k3s
cluster (`v1.35.0+k3s1`, node `colima`, 4 CPU / 6 GB, macOS arm64 host via
colima, kubectl `v1.37.1`). Blocks still labelled **Expected output** are the
minikube / cloud variants I could not run here, each with the reason. Three
environment details recur in the outputs: kubectl 1.37 prints `Warning: v1
Endpoints is deprecated in v1.33+` whenever I `get endpoints`; busybox's
`nslookup` prints an NXDOMAIN line for every search domain it tries before
the real answer (I trim those and say so); and the LoadBalancer Service uses
port 8081 because k3s' Traefik already holds host port 80 (see
`03-loadbalancer/README.md`).

Images: `hashicorp/http-echo:1.0` (answers with a fixed text so `wget -qO-`
shows which backend replied), `nginx:alpine`, `busybox:1.36` (client with
`wget` and `nslookup`).

```bash
kubectl apply -f namespace.yaml -f client-pod.yaml
./deploy-all.sh          # applies 01..05, waits, prints svc/endpoints and a connectivity check
./cleanup.sh             # kubectl delete namespace s11
```

Output (captured 2026-10-08) (tail of `deploy-all.sh`)
```text
== services and endpoints
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE   SELECTOR
service/external-site      ExternalName   <none>          example.com   <none>           22s   <none>
service/web                ClusterIP      None            <none>        80/TCP           22s   app=web-headless
service/web-clusterip      ClusterIP      10.43.134.29    <none>        80/TCP           22s   app=web-clusterip
service/web-loadbalancer   LoadBalancer   10.43.227.111   192.168.5.1   8081:32386/TCP   22s   app=web-loadbalancer
service/web-nodeport       NodePort       10.43.6.89      <none>        80:30081/TCP     22s   app=web-nodeport

NAME                         ENDPOINTS                                         AGE
endpoints/web                10.42.0.35:80,10.42.0.38:80,10.42.0.40:80         22s
endpoints/web-clusterip      10.42.0.27:8080,10.42.0.28:8080,10.42.0.29:8080   22s
endpoints/web-loadbalancer   10.42.0.32:8080,10.42.0.33:8080,10.42.0.34:8080   22s
endpoints/web-nodeport       10.42.0.30:8080,10.42.0.31:8080                   22s

== quick connectivity check from the client pod
clusterip   : hello from clusterip backend
nodeport    : hello from nodeport backend
loadbalancer: hello from loadbalancer backend
headless    : I am web-0
externalname: external-site.s11.svc.cluster.local	canonical name = example.com
```

## The ports, once

```text
 outside ──▶ nodePort 30081 (on every node)      only NodePort / LoadBalancer
                 │
                 ▼
          port 80 (Service / ClusterIP)           what other pods connect to
                 │
                 ▼
          targetPort 8080 (container)             what the process listens on
```

## Task 1: Kubernetes Services

| # | Type | Folder | Reachable from | Gets ClusterIP | DNS answer |
| --- | --- | --- | --- | --- | --- |
| 1 | ClusterIP | [`01-clusterip/`](01-clusterip/README.md) | inside the cluster only | yes | A -> VIP |
| 2 | NodePort | [`02-nodeport/`](02-nodeport/README.md) | `<node-ip>:30081` + inside | yes | A -> VIP |
| 3 | LoadBalancer | [`03-loadbalancer/`](03-loadbalancer/README.md) | external IP `192.168.5.1:8081` from k3s servicelb (or `minikube tunnel` / cloud LB) + NodePort + inside | yes | A -> VIP |
| 4 | ExternalName | [`04-externalname/`](04-externalname/README.md) | n/a, DNS alias to `example.com` | no | CNAME |
| 5 | Headless | [`05-headless/`](05-headless/README.md) | pod IPs directly; `web-0.web.s11.svc.cluster.local` | `None` | A per pod |

Each folder contains the YAML, and a README with: deploy, verify
(`kubectl get svc,endpoints`, `describe`), connectivity test from the client
pod (`wget -qO-`, `nslookup`) and from outside where applicable, expected
output, what I observed, and cleanup. That covers all six per-service bullets
in the spec (create YAML, deploy, verify, test connectivity, capture output,
add to README).

## Task 2: Kubernetes Object Comparison

[`comparison/README.md`](comparison/README.md): Deployment vs ReplicaSet
(purpose, pod management, scaling, rolling updates, relationship);
Deployment vs DaemonSet vs StatefulSet (use cases, pod creation, scaling,
networking, storage, examples, with manifests); ReplicaSet vs Service
(responsibilities, why a Service is required, how traffic reaches pods).

## Task 3: FQDN

[`fqdn/README.md`](fqdn/README.md): what an FQDN is, Service DNS records,
naming convention `<svc>.<ns>.svc.cluster.local`, namespace-based resolution
and `/etc/resolv.conf` search list / `ndots`, pod-to-service flow, and a table
of real FQDNs from this lab with verification commands.

## Task 4: CoreDNS

[`coredns/README.md`](coredns/README.md): what CoreDNS is, why Kubernetes
uses it, Service discovery via the API watch, the query resolution path, the
Corefile with every plugin explained, and a troubleshooting procedure
(CoreDNS pods/logs, ConfigMap, dnsutils pod, `nslookup`, `resolv.conf`,
`ndots`, direct queries, metrics).

## Screenshots

Terminal output captured from the k3s cluster stands in for the screenshots:

| Spec item | Substitute block |
| --- | --- |
| ClusterIP verify / connectivity | `01-clusterip/README.md` `get svc,endpoints`, `describe svc`, `wget`/`nslookup` from client |
| NodePort verify / connectivity | `02-nodeport/README.md` `get svc` (`80:30081/TCP`), `curl http://<node-ip>:30081` |
| LoadBalancer verify / connectivity | `03-loadbalancer/README.md` port-80 `<pending>` diagnosis, k3s `EXTERNAL-IP 192.168.5.1`, `wget $LB_IP:8081`, `curl localhost:8081` |
| ExternalName verify / connectivity | `04-externalname/README.md` `get svc` (`EXTERNAL-IP example.com`), `nslookup` CNAME |
| Headless verify / connectivity | `05-headless/README.md` `nslookup web` (3 A records), `nslookup web-0.web...`, per-pod `wget` |
| Comparison evidence | `comparison/README.md` `ownerReferences`, `get endpoints` before/after pod deletion |
| FQDN evidence | `fqdn/README.md` `cat /etc/resolv.conf`, cross-namespace `wget`, FQDN `nslookup` loop |
| CoreDNS evidence | `coredns/README.md` `get pods -l k8s-app=kube-dns`, `get cm coredns -o yaml`, `logs` with `log` plugin |

## Deliverables

- `namespace.yaml` – Namespace `s11`.
- `client-pod.yaml` – busybox client Pod for `wget`/`nslookup` tests.
- `01-clusterip/` – `deployment.yaml`, `service.yaml`, `README.md`.
- `02-nodeport/` – `deployment.yaml`, `service.yaml` (nodePort 30081), `README.md`.
- `03-loadbalancer/` – `deployment.yaml`, `service.yaml` (port 8081), `README.md` (k3s servicelb incl. the port-80 conflict / minikube tunnel / cloud).
- `04-externalname/` – `service.yaml` (CNAME to example.com), `README.md`.
- `05-headless/` – `service.yaml` (`clusterIP: None`), `statefulset.yaml` (3 replicas), `README.md` (per-pod DNS).
- `comparison/README.md` – Task 2 object comparison.
- `fqdn/README.md` – Task 3 FQDN documentation.
- `coredns/README.md` – Task 4 CoreDNS documentation.
- `deploy-all.sh` / `cleanup.sh` – apply and remove the whole session.
- `README.md` – this index.
