# 05 – Headless Service

Student: Om Malviya | Enrollment No: 24BCS10448

A headless Service (`clusterIP: None`) allocates no virtual IP and
programs no kube-proxy rules. DNS returns the pod IPs directly, and when the
Service backs a StatefulSet each pod gets its own stable DNS name
`<pod>.<svc>.<ns>.svc.cluster.local`. This is how clustered databases and
message brokers find their peers.

```text
 nslookup web          ──▶  10.42.0.35, 10.42.0.36, 10.42.0.37   (one A record per ready pod)
 nslookup web-0.web    ──▶  10.42.0.35                            (that pod only)
 nslookup web-1.web    ──▶  10.42.0.36
 nslookup web-2.web    ──▶  10.42.0.37
```

## Files

| File | Purpose |
| --- | --- |
| `service.yaml` | Service `web`, `clusterIP: None`, selector `app=web-headless`, port 80 |
| `statefulset.yaml` | StatefulSet `web`, `serviceName: web`, 3 replicas of nginx; an init container writes `I am web-N` into index.html |

## Deploy

The headless Service should exist before the StatefulSet so the pod DNS
records are created as the pods come up.

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f service.yaml
kubectl apply -f statefulset.yaml
kubectl -n s11 rollout status statefulset/web
```

Output (captured 2026-10-08) (repeated progress lines removed)
```text
service/web created
statefulset.apps/web created
Waiting for 3 pods to be ready...
Waiting for 2 pods to be ready...
Waiting for 1 pods to be ready...
partitioned roll out complete: 3 new pods have been updated...
```

## Verify the Service

```bash
kubectl -n s11 get svc,endpoints web
kubectl -n s11 get pods -l app=web-headless -o wide
```

Output (captured 2026-10-08)
```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME          TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/web   ClusterIP   None         <none>        80/TCP    114s

NAME            ENDPOINTS                                   AGE
endpoints/web   10.42.0.35:80,10.42.0.36:80,10.42.0.37:80   114s
NAME    READY   STATUS    RESTARTS   AGE    IP           NODE     NOMINATED NODE   READINESS GATES
web-0   1/1     Running   0          114s   10.42.0.35   colima   <none>           <none>
web-1   1/1     Running   0          86s    10.42.0.36   colima   <none>           <none>
web-2   1/1     Running   0          83s    10.42.0.37   colima   <none>           <none>
```

Note `CLUSTER-IP` is `None`, the pods have ordinal names instead of random
hashes, and they were created in order (`web-1` is 28 s younger than `web-0`
because it was only created once `web-0` passed its readiness probe).

## Test connectivity

### DNS: the Service name returns every pod IP

```bash
kubectl -n s11 exec client -- nslookup web
```

Output (captured 2026-10-08) (busybox `nslookup` NXDOMAIN lines for the other search domains removed)
```text
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web.s11.svc.cluster.local
Address: 10.42.0.36
Name:	web.s11.svc.cluster.local
Address: 10.42.0.35
Name:	web.s11.svc.cluster.local
Address: 10.42.0.37
```

Compare with a normal ClusterIP Service, which returns one virtual IP:

```bash
kubectl -n s11 exec client -- nslookup web-clusterip   # from 01-clusterip, if deployed
```

Output (captured 2026-10-08)
```text
Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156
```

### DNS: per-pod A records

```bash
kubectl -n s11 exec client -- nslookup web-0.web.s11.svc.cluster.local
kubectl -n s11 exec client -- nslookup web-2.web.s11.svc.cluster.local
```

(I first tried the short form `nslookup web-2.web`; busybox's `nslookup`
applet answered `Can't find web-2.web: No answer` because it does not walk
the search list for names that already contain a dot. The libc resolver
that `wget` uses does, so `wget http://web-2.web` works fine; for `nslookup`
I use the full name.)

Output (captured 2026-10-08)
```text
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-0.web.s11.svc.cluster.local
Address: 10.42.0.35

Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-2.web.s11.svc.cluster.local
Address: 10.42.0.37
```

### HTTP: each pod answers with its own name

```bash
kubectl -n s11 exec client -- sh -c 'for p in web-0 web-1 web-2; do wget -qO- http://$p.web.s11.svc.cluster.local; done'
```

Output (captured 2026-10-08)
```text
I am web-0
I am web-1
I am web-2
```

Hitting the Service name instead goes to whichever IP the resolver picked
first (no kube-proxy balancing, the client decides):

```bash
kubectl -n s11 exec client -- sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://web; done | sort | uniq -c'
```

Output (captured 2026-10-08)
```text
      3 I am web-0
      2 I am web-1
      1 I am web-2
```

(CoreDNS shuffles the A records on each answer because of its
`loadbalance` plugin, and `wget` takes the first one, so the spread is
roughly even; with only six requests 3/2/1 is as even as it gets.)

### Stable identity survives a restart

```bash
kubectl -n s11 delete pod web-1
kubectl -n s11 get pods -l app=web-headless -o wide -w
```

Output (captured 2026-10-08) (duplicate watch lines removed)
```text
pod "web-1" deleted from s11 namespace
NAME    READY   STATUS    RESTARTS   AGE     IP           NODE     NOMINATED NODE   READINESS GATES
web-0   1/1     Running   0          8m36s   10.42.0.35   colima   <none>           <none>
web-1   1/1     Running   0          6m35s   10.42.0.50   colima   <none>           <none>
web-2   1/1     Running   0          8m5s    10.42.0.37   colima   <none>           <none>
web-1   1/1     Terminating   0          6m37s   10.42.0.50   colima   <none>           <none>
web-1   0/1     Completed     0          6m37s   10.42.0.50   colima   <none>           <none>
web-1   0/1     Pending       0          0s      <none>       <none>   <none>           <none>
web-1   0/1     Pending       0          0s      <none>       colima   <none>           <none>
web-1   0/1     Init:0/1      0          0s      <none>       colima   <none>           <none>
web-1   0/1     PodInitializing   0          1s      10.42.0.99   colima   <none>           <none>
web-1   0/1     Running           0          2s      10.42.0.99   colima   <none>           <none>
web-1   1/1     Running           0          3s      10.42.0.99   colima   <none>           <none>
```

The pod came back with the same name `web-1` (new IP 10.42.0.99; its
previous IP 10.42.0.50 was itself the result of an earlier delete I did
without the watch running, which is why its AGE was lower than `web-0`'s).
Note the ordered restart: `Init:0/1` runs the hostname-writing init
container again before nginx starts. `web-1.web.s11.svc.cluster.local`
now resolves to the new IP, so peers that cached the name keep working:

```bash
kubectl -n s11 exec client -- nslookup web-1.web.s11.svc.cluster.local
```

Output (captured 2026-10-08)
```text
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-1.web.s11.svc.cluster.local
Address: 10.42.0.99
```

## What I observed

- With `clusterIP: None` the only thing Kubernetes provides is DNS records
  and an Endpoints list; there is no VIP to connect to and no DNAT.
- The StatefulSet gives predictable names `web-0..2`, ordered start-up and a
  per-pod DNS entry under the headless Service named in `serviceName`.
- This combination is what Kafka, MongoDB replica sets, Cassandra and etcd
  need: a member must address a specific peer, not "any replica".

## Cleanup

```bash
kubectl delete -f statefulset.yaml -f service.yaml
```

## Deliverables

- `service.yaml` – headless Service `web` (`clusterIP: None`).
- `statefulset.yaml` – StatefulSet `web` with 3 replicas answering with their own name.
- `README.md` – deploy, verify, per-pod DNS (`web-0.web.s11.svc.cluster.local`), stable identity test, cleanup.
