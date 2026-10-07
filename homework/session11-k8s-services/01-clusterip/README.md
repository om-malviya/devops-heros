# 01 – ClusterIP

Student: Om Malviya | Enrollment No: 24BCS10448

ClusterIP is the default Service type. It gives a set of pods one stable
virtual IP and one DNS name that only work from inside the cluster.

```text
 client pod ── http://web-clusterip ──▶ CoreDNS ──▶ 10.43.x.x (ClusterIP)
                                                        │ kube-proxy DNAT
                                   ┌────────────────────┼────────────────────┐
                                   ▼                    ▼                    ▼
                           pod 10.42.0.11:8080  pod 10.42.0.12:8080  pod 10.42.0.13:8080
```

## Files

| File | Purpose |
| --- | --- |
| `deployment.yaml` | 3 x `hashicorp/http-echo` pods, label `app=web-clusterip`, listen 8080 |
| `service.yaml` | `type: ClusterIP`, port 80 -> targetPort 8080, selector `app=web-clusterip` |

## Deploy

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f deployment.yaml -f service.yaml
kubectl -n s11 rollout status deployment/web-clusterip
```

Output (captured 2026-10-08)
```text
namespace/s11 created
pod/client created
deployment.apps/web-clusterip created
service/web-clusterip created
Waiting for deployment "web-clusterip" rollout to finish: 0 of 3 updated replicas are available...
Waiting for deployment "web-clusterip" rollout to finish: 1 of 3 updated replicas are available...
Waiting for deployment "web-clusterip" rollout to finish: 2 of 3 updated replicas are available...
deployment "web-clusterip" successfully rolled out
```

## Verify the Service

```bash
kubectl -n s11 get pods -l app=web-clusterip -o wide
kubectl -n s11 get svc,endpoints web-clusterip
```

Output (captured 2026-10-08)
```text
NAME                             READY   STATUS    RESTARTS   AGE    IP           NODE     NOMINATED NODE   READINESS GATES
web-clusterip-5df8dbbc74-8sjr8   1/1     Running   0          104s   10.42.0.27   colima   <none>           <none>
web-clusterip-5df8dbbc74-nqhkj   1/1     Running   0          104s   10.42.0.28   colima   <none>           <none>
web-clusterip-5df8dbbc74-vhvf7   1/1     Running   0          104s   10.42.0.29   colima   <none>           <none>
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/web-clusterip   ClusterIP   10.43.109.156   <none>        80/TCP    104s

NAME                      ENDPOINTS                                         AGE
endpoints/web-clusterip   10.42.0.27:8080,10.42.0.28:8080,10.42.0.29:8080   104s
```

The Endpoints list is exactly the pod IPs above, with the `targetPort`.

```bash
kubectl -n s11 describe svc web-clusterip
```

Output (captured 2026-10-08)
```text
Name:                     web-clusterip
Namespace:                s11
Labels:                   app=web-clusterip
Annotations:              <none>
Selector:                 app=web-clusterip
Type:                     ClusterIP
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.43.109.156
IPs:                      10.43.109.156
Port:                     http  80/TCP
TargetPort:               8080/TCP
Endpoints:                10.42.0.28:8080,10.42.0.27:8080,10.42.0.29:8080
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

## Test connectivity

From inside the cluster, by name, by FQDN and by IP:

```bash
kubectl -n s11 exec client -- wget -qO- http://web-clusterip
kubectl -n s11 exec client -- wget -qO- http://web-clusterip.s11.svc.cluster.local
kubectl -n s11 exec client -- wget -qO- http://10.43.109.156
kubectl -n s11 exec client -- nslookup web-clusterip
```

Output (captured 2026-10-08) (busybox `nslookup` also prints `** server can't find web-clusterip.svc.cluster.local: NXDOMAIN` for the other search domains it tries; those lines removed)
```text
hello from clusterip backend
hello from clusterip backend
hello from clusterip backend
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156
```

From outside the cluster the ClusterIP is not routable:

```bash
curl -m 3 http://10.43.109.156
```

Output (captured 2026-10-08)
```text
curl: (28) Connection timed out after 3001 milliseconds
```

For developer access use port-forward instead:

```bash
kubectl -n s11 port-forward svc/web-clusterip 8080:80 &
curl -s http://localhost:8080
```

Output (captured 2026-10-08)
```text
Forwarding from 127.0.0.1:8080 -> 8080
Forwarding from [::1]:8080 -> 8080
hello from clusterip backend
```

Load balancing across the three pods is visible in the pod logs. The counts
below include every request made since the pods started (the `deploy-all.sh`
check and my earlier tests, 125 in total), not just these 9, and they are
spread almost evenly:

```bash
kubectl -n s11 exec client -- sh -c 'for i in $(seq 1 9); do wget -qO- http://web-clusterip >/dev/null; done'
for p in $(kubectl -n s11 get pods -l app=web-clusterip -o name); do echo "$p: $(kubectl -n s11 logs $p | grep -c GET)"; done
```

Output (captured 2026-10-08)
```text
pod/web-clusterip-5df8dbbc74-8sjr8: 43
pod/web-clusterip-5df8dbbc74-nqhkj: 43
pod/web-clusterip-5df8dbbc74-vhvf7: 39
```

## What I observed

- `CLUSTER-IP` is allocated from the service CIDR (`10.43.0.0/16` on k3s,
  `10.96.0.0/12` on minikube) and never changes while the Service exists,
  even if every pod behind it is replaced.
- CoreDNS resolved the short name because the client is in the same
  namespace; the FQDN works from anywhere in the cluster. busybox's
  `nslookup` is noisy: it queries every entry of the `search` list and
  prints an NXDOMAIN line for each miss before the answer, which is
  exactly the `ndots:5` behaviour described in `../fqdn/README.md`.
- The ClusterIP does not exist on any interface; kube-proxy rewrites the
  destination to one of the endpoint IPs, which is why it is unreachable
  from my laptop.

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment.yaml
```

## Deliverables

- `deployment.yaml` – 3 http-echo pods.
- `service.yaml` – ClusterIP Service, port 80 -> 8080.
- `README.md` – deploy, verify svc/endpoints, in-cluster connectivity test, cleanup.
