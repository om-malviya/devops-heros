# 02 – NodePort

Student: Om Malviya | Enrollment No: 24BCS10448

NodePort opens the same high port (30000–32767) on every node and forwards
it to a ClusterIP that is created underneath. It is the simplest way to reach
a Service from outside the cluster.

```text
 laptop ── http://<node-ip>:30081 ──▶ node ──▶ nodePort 30081
                                               │ kube-proxy
                                               ▼
                                     Service port 80 (ClusterIP 10.43.x.x)
                                               │
                                               ▼
                                     pod targetPort 8080
```

## Files

| File | Purpose |
| --- | --- |
| `deployment.yaml` | 2 x http-echo pods, label `app=web-nodeport` |
| `service.yaml` | `type: NodePort`, `port: 80`, `targetPort: 8080`, `nodePort: 30081` |

## Deploy

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f deployment.yaml -f service.yaml
kubectl -n s11 rollout status deployment/web-nodeport
```

Output (captured 2026-10-08)
```text
deployment.apps/web-nodeport created
service/web-nodeport created
deployment "web-nodeport" successfully rolled out
```

## Verify the Service

```bash
kubectl -n s11 get svc,endpoints web-nodeport
```

Output (captured 2026-10-08)
```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                   TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE
service/web-nodeport   NodePort   10.43.13.190   <none>        80:30081/TCP   110s

NAME                     ENDPOINTS                         AGE
endpoints/web-nodeport   10.42.0.30:8080,10.42.0.31:8080   110s
```

`80:30081/TCP` reads as "service port 80, node port 30081". A ClusterIP was
also allocated, so this Service works from inside the cluster exactly like
the previous example.

```bash
kubectl get nodes -o wide
```

Output (captured 2026-10-08)
```text
NAME     STATUS   ROLES           AGE     VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
colima   Ready    control-plane   9m43s   v1.35.0+k3s1   192.168.5.1   <none>        Ubuntu 24.04.4 LTS   6.8.0-117-generic   containerd://2.1.5-k3s1
```

## Test connectivity

From outside the cluster, using the node's IP. On a VM or bare-metal node
this is `curl http://<node-ip>:30081`. My node runs inside a colima VM whose
address `192.168.5.1` is not routable from macOS, so the first `curl` times
out; colima forwards the VM's ports to the host instead, so the same
NodePort answers on `localhost`:

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
curl -s -m 3 http://$NODE_IP:30081; echo "rc=$?"
curl -s http://localhost:30081
curl -s http://localhost:30081
```

Output (captured 2026-10-08)
```text
rc=28
hello from nodeport backend
hello from nodeport backend
```

On minikube the node IP is not always reachable from the host (docker
driver on macOS); use the helper instead:

```bash
minikube service web-nodeport -n s11 --url
curl -s $(minikube service web-nodeport -n s11 --url)
```

Expected output (not run: no minikube on this machine, the cluster is k3s under colima)
```text
http://192.168.49.2:30081
hello from nodeport backend
```

From inside the cluster the Service still answers on port 80 by name:

```bash
kubectl -n s11 exec client -- wget -qO- http://web-nodeport
kubectl -n s11 exec client -- nslookup web-nodeport
```

Output (captured 2026-10-08) (busybox `nslookup` NXDOMAIN lines for the other search domains removed)
```text
hello from nodeport backend
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-nodeport.s11.svc.cluster.local
Address: 10.43.13.190
```

The node port is also reachable from inside via the node IP (kube-proxy
programs it on every node), which confirms that `192.168.5.1:30081` really
is open, just not from my laptop:

```bash
kubectl -n s11 exec client -- wget -qO- http://192.168.5.1:30081
```

Output (captured 2026-10-08)
```text
hello from nodeport backend
```

## What I observed

- Three ports are involved: `nodePort` 30081 on the host, `port` 80 on the
  Service, `targetPort` 8080 in the container. Mixing them up is the most
  common NodePort mistake.
- If I omit `nodePort` Kubernetes picks a random one in 30000–32767; I pinned
  30081 so the README is reproducible. The port must be unique per cluster.
- NodePort exposes the app on every node, with no health-aware failover for
  clients that hard-code one node IP. That is why LoadBalancer or an Ingress
  sits in front of it in production.
- Whether `<node-ip>:<nodePort>` is reachable from your workstation depends
  on the network between you and the node, not on Kubernetes: here the VM's
  IP was unreachable but colima's port forwarding made `localhost:30081`
  work.

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment.yaml
```

## Deliverables

- `deployment.yaml` – 2 http-echo pods.
- `service.yaml` – NodePort Service on 30081.
- `README.md` – deploy, verify, test from node IP / minikube service and from inside, cleanup.
