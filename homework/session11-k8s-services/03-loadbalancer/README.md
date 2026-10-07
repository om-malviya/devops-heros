# 03 – LoadBalancer

Student: Om Malviya | Enrollment No: 24BCS10448

`type: LoadBalancer` builds on NodePort and ClusterIP, then asks an external
controller for a public (or at least node-external) IP. On a cloud this is an
AWS/GCP/Azure load balancer; on k3s it is the built-in `servicelb` (Klipper);
on minikube it needs `minikube tunnel`.

```text
 internet ──▶ external LB IP :80 ──▶ node:nodePort ──▶ ClusterIP:80 ──▶ pod:8080
```

## Files

| File | Purpose |
| --- | --- |
| `deployment.yaml` | 3 x http-echo pods, label `app=web-loadbalancer` |
| `service.yaml` | `type: LoadBalancer`, port 8081 -> targetPort 8080 (why 8081: see below) |

## Deploy

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f deployment.yaml -f service.yaml
kubectl -n s11 rollout status deployment/web-loadbalancer
```

Output (captured 2026-10-08)
```text
deployment.apps/web-loadbalancer created
service/web-loadbalancer created
deployment "web-loadbalancer" successfully rolled out
```

## Verify the Service

The EXTERNAL-IP column depends on the environment.

### k3s (servicelb enabled by default)

My first version of `service.yaml` used `port: 80`. On k3s that never got an
external IP:

```bash
kubectl -n s11 get svc web-loadbalancer
kubectl -n kube-system get pods -l svccontroller.k3s.cattle.io/svcname=web-loadbalancer
kubectl -n kube-system describe pod -l svccontroller.k3s.cattle.io/svcname=web-loadbalancer | sed -n '/^Events:/,$p'
```

Output (captured 2026-10-08) (with `port: 80`)
```text
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
web-loadbalancer   LoadBalancer   10.43.217.158   <pending>     80:32618/TCP   104s
NAME                                    READY   STATUS    RESTARTS   AGE
svclb-web-loadbalancer-02f32f56-d9z7d   0/1     Pending   0          104s
Events:
  Type     Reason            Age    From               Message
  ----     ------            ----   ----               -------
  Warning  FailedScheduling  2m46s  default-scheduler  0/1 nodes are available: 1 node(s) didn't have free ports for the requested pod ports. no new claims to deallocate, preemption: 0/1 nodes are available: 1 node(s) didn't have free ports for the requested pod ports.
```

servicelb implements a LoadBalancer by running a DaemonSet pod that binds
the Service port as a `hostPort` on every node. k3s ships Traefik as a
LoadBalancer Service, so its `svclb-traefik` pod already holds host ports
80 and 443; a second pod asking for host port 80 can never be scheduled
and the Service stays `<pending>`. I changed the Service to `port: 8081`
(the `targetPort` 8080 and the pods are untouched) and re-applied:

```bash
kubectl apply -f service.yaml
kubectl -n s11 get svc,endpoints web-loadbalancer
kubectl -n kube-system get pods -l svccontroller.k3s.cattle.io/svcname=web-loadbalancer
```

Output (captured 2026-10-08)
```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME                       TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
service/web-loadbalancer   LoadBalancer   10.43.217.158   192.168.5.1   8081:32618/TCP   8m26s

NAME                         ENDPOINTS                                         AGE
endpoints/web-loadbalancer   10.42.0.32:8080,10.42.0.33:8080,10.42.0.34:8080   8m26s

NAME                                    READY   STATUS    RESTARTS   AGE
svclb-web-loadbalancer-02f32f56-cd752   1/1     Running   0          14s
```

Within seconds of the change the svclb pod was Running and servicelb
reported the node IP `192.168.5.1` as EXTERNAL-IP. The NodePort (`32618`)
is allocated randomly at creation, so it differs between runs.

### minikube without tunnel

```bash
kubectl -n s11 get svc web-loadbalancer
```

Expected output (not run: no minikube on this machine)
```text
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
web-loadbalancer   LoadBalancer   10.104.33.120   <pending>     8081:31742/TCP   25s
```

`<pending>` stays forever because nothing implements the load-balancer API.
The Service still works through its NodePort and ClusterIP.

### minikube with tunnel (second terminal, needs sudo)

```bash
minikube tunnel
```

```bash
kubectl -n s11 get svc web-loadbalancer
```

Expected output (not run: no minikube on this machine)
```text
NAME               TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)          AGE
web-loadbalancer   LoadBalancer   10.104.33.120   10.104.33.120   8081:31742/TCP   2m
```

### Managed cloud (for reference)

Expected output (not run: no cloud account available)
```text
NAME               TYPE           CLUSTER-IP     EXTERNAL-IP                                      PORT(S)          AGE
web-loadbalancer   LoadBalancer   10.100.5.77    a1b2c3d4e5-123456.ap-south-1.elb.amazonaws.com   8081:31742/TCP   90s
```

```bash
kubectl -n s11 describe svc web-loadbalancer | sed -n '/^Type:/,/^Endpoints:/p;/^Events:/,$p'
```

Output (captured 2026-10-08) (k3s)
```text
Type:                     LoadBalancer
IP Family Policy:         SingleStack
IP Families:              IPv4
IP:                       10.43.217.158
IPs:                      10.43.217.158
LoadBalancer Ingress:     192.168.5.1 (VIP)
Port:                     http  8081/TCP
TargetPort:               8080/TCP
NodePort:                 http  32618/TCP
Endpoints:                10.42.0.33:8080,10.42.0.32:8080,10.42.0.34:8080
Events:
  Type    Reason                Age                  From                   Message
  ----    ------                ----                 ----                   -------
  Normal  EnsuringLoadBalancer  14s (x2 over 8m26s)  service-controller     Ensuring load balancer
  Normal  AppliedDaemonSet      14s (x2 over 8m26s)  service-lb-controller  Applied LoadBalancer DaemonSet kube-system/svclb-web-loadbalancer-02f32f56
  Normal  UpdatedLoadBalancer   14s                  service-lb-controller  Updated LoadBalancer with new IPs: [] -> [192.168.5.1]
```

## Test connectivity

The external IP is the colima VM's address, which my macOS host cannot
route to (the `curl` times out, `rc=28`), so I tested it from the client pod
as well, where it answers:

```bash
LB_IP=$(kubectl -n s11 get svc web-loadbalancer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LB IP: $LB_IP"
curl -s -m 3 http://$LB_IP:8081; echo "rc=$?"
for i in 1 2 3; do kubectl -n s11 exec client -- wget -qO- http://$LB_IP:8081; done
```

Output (captured 2026-10-08)
```text
LB IP: 192.168.5.1
rc=28
hello from loadbalancer backend
hello from loadbalancer backend
hello from loadbalancer backend
```

Because colima forwards host ports bound inside the VM, the svclb pod's
`hostPort` 8081 also showed up on my laptop:

```bash
curl -s http://localhost:8081
```

Output (captured 2026-10-08)
```text
hello from loadbalancer backend
```

Fallbacks that work everywhere (the NodePort and ClusterIP underneath):

```bash
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
kubectl -n s11 exec client -- wget -qO- http://$NODE_IP:32618
kubectl -n s11 exec client -- wget -qO- http://web-loadbalancer:8081
kubectl -n s11 exec client -- nslookup web-loadbalancer
```

Output (captured 2026-10-08) (busybox `nslookup` NXDOMAIN lines for the other search domains removed)
```text
hello from loadbalancer backend
hello from loadbalancer backend
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-loadbalancer.s11.svc.cluster.local
Address: 10.43.217.158
```

## What I observed

- The Service got all three layers: a ClusterIP, a random NodePort (32618)
  and, where a controller exists, an external IP. Internally it behaves
  exactly like ClusterIP.
- `<pending>` does not always mean "no controller". On k3s it meant the
  servicelb pod could not get host port 80 because Traefik already had it;
  the `FailedScheduling` event on the `svclb-*` pod told me why. Moving the
  Service to port 8081 fixed it and `servicelb` assigned the node's IP within
  seconds. On plain minikube it would stay `<pending>` until
  `minikube tunnel` runs.
- The external IP is only as reachable as the node itself: from inside the
  cluster `192.168.5.1:8081` worked, from macOS it did not, but colima's port
  forwarding exposed the same host port as `localhost:8081`.
- Each LoadBalancer costs a real cloud resource, so the usual production
  pattern is one LoadBalancer in front of an Ingress controller and
  ClusterIP for everything else.

## Cleanup

```bash
kubectl delete -f service.yaml -f deployment.yaml
```

## Deliverables

- `deployment.yaml` – 3 http-echo pods.
- `service.yaml` – LoadBalancer Service on port 8081 (80 is taken by Traefik's servicelb pod on k3s).
- `README.md` – deploy, the port-80 `<pending>` problem and its fix, verify on k3s (servicelb), minikube (`<pending>` / tunnel) and cloud, test, cleanup.
