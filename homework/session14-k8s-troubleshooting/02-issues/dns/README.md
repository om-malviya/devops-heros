# Issue: DNS (wrong Service name / namespace, checking CoreDNS)

Student: Om Malviya | Enrollment No: 24BCS10448

Inside the cluster every Service gets a DNS name:

```text
<service>.<namespace>.svc.cluster.local
```

From a Pod in the **same** namespace the short name `<service>` works because of the `search` list in `/etc/resolv.conf`. From another namespace I must use `<service>.<namespace>`. Most "DNS problems" I have hit were actually a wrong name or namespace, not CoreDNS itself.

The client Pod is `busybox:1.36` (my first choice, `registry.k8s.io/e2e-test-images/dnsutils:1.3`, no longer exists on the registry and went straight into `ImagePullBackOff` - a small real-life ImagePullBackOff on top of the DNS exercise).

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pods -n s14 -l app=api
kubectl logs dns-client -n s14
```

Output (captured 2026-10-08, before)

```text
deployment.apps/api created
service/api-svc created
pod/dns-client created
NAME                  READY   STATUS    RESTARTS   AGE
api-8cd89c994-w444l   1/1     Running   0          2m44s
Calling http://api-service:8080/hostname
ERROR: could not reach http://api-service:8080/hostname
Calling http://api-svc.default:8080/hostname
wget: bad address 'api-service:8080'
wget: bad address 'api-svc.default:8080'
ERROR: could not reach api-svc.default
```

`bad address` from wget means **name resolution** failed (as opposed to `Connection refused`/`timed out`, which mean the name resolved but the connection failed). The two `wget:` lines are printed after the `ERROR:` lines because stderr and stdout are buffered differently in the container log.

## 2. Investigate

```bash
# 1. Does the name resolve from the client?
kubectl exec dns-client -n s14 -- nslookup api-service
kubectl exec dns-client -n s14 -- nslookup api-svc.default.svc.cluster.local
# 2. What Services actually exist?
kubectl get svc -n s14
# 3. What does the Pod's resolver config look like?
kubectl exec dns-client -n s14 -- cat /etc/resolv.conf
# 4. Is cluster DNS itself healthy?
kubectl exec dns-client -n s14 -- nslookup kubernetes.default.svc.cluster.local
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get svc -n kube-system kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=5
```

Output (captured 2026-10-08)

```text
Server:		10.43.0.10
Address:	10.43.0.10:53

** server can't find api-service.s14.svc.cluster.local: NXDOMAIN
** server can't find api-service.svc.cluster.local: NXDOMAIN
** server can't find api-service.cluster.local: NXDOMAIN
command terminated with exit code 1

Server:		10.43.0.10
Address:	10.43.0.10:53

** server can't find api-svc.default.svc.cluster.local: NXDOMAIN
command terminated with exit code 1

NAME      TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
api-svc   ClusterIP   10.43.255.13    <none>        8080/TCP   2m44s
web-svc   ClusterIP   10.43.144.157   <none>        80/TCP     2m44s

search s14.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5

Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	kubernetes.default.svc.cluster.local
Address: 10.43.0.1

NAME                       READY   STATUS    RESTARTS   AGE
coredns-54bf7cdff9-hwhc7   1/1     Running   0          4h10m

NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.43.0.10   <none>        53/UDP,53/TCP,9153/TCP   4h10m

[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.server
[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override
[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.server
```

Two things I learned while capturing this:

* busybox's `nslookup` only walks the `search` list for single-label names. For `api-svc.default` (one dot) it asked for exactly that name and got `NXDOMAIN`, and `nslookup kubernetes.default` failed the same way even though DNS is fine. That is why I use the FQDN in the health check (`kubernetes.default.svc.cluster.local` resolves to `10.43.0.1`). `wget` uses the libc resolver, which does honour `ndots:5`, so its behaviour matches the application's.
* k3s's CoreDNS does not enable the `log` plugin, so its logs only show start-up warnings, not the queries. To see per-query lines like `A IN api-service.s14.svc.cluster.local. ... NXDOMAIN` I would add `log` to the Corefile (`kubectl edit configmap coredns -n kube-system`). The `nslookup` output from the client gives me the same information anyway.

## 3. Root cause

* CoreDNS is healthy: `kubernetes.default.svc.cluster.local` resolves, the CoreDNS Pod is Running, the `kube-dns` Service is on the nameserver IP from `resolv.conf` (`10.43.0.10`).
* `nslookup` shows exactly what was asked: `api-service.s14.svc.cluster.local` (no such Service - the real one is `api-svc`) and `api-svc.default.svc.cluster.local` (right Service, wrong namespace - it lives in `s14`). Both answers are `NXDOMAIN`.

So the client configuration is wrong, not DNS.

## 4. Fix

```diff
-          value: "http://api-service:8080/hostname"
+          value: "http://api-svc:8080/hostname"
...
-          wget -qO- --timeout=3 http://api-svc.default:8080/hostname
+          wget -qO- --timeout=3 http://api-svc.s14.svc.cluster.local:8080/hostname
```

`env` and `command` are immutable, so the client Pod is recreated:

```bash
kubectl delete pod dns-client -n s14
kubectl apply -f fixed.yaml
```

Output (captured 2026-10-08)

```text
pod "dns-client" deleted from s14 namespace
deployment.apps/api unchanged
service/api-svc unchanged
pod/dns-client created
```

## 5. Verify

```bash
kubectl logs dns-client -n s14
kubectl exec dns-client -n s14 -- nslookup api-svc
kubectl exec dns-client -n s14 -- nslookup api-svc.s14.svc.cluster.local
```

Output (captured 2026-10-08, after)

```text
Calling http://api-svc:8080/hostname
api-8cd89c994-w444l
Calling http://api-svc.s14.svc.cluster.local:8080/hostname
api-8cd89c994-w444l

Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	api-svc.s14.svc.cluster.local
Address: 10.43.255.13

** server can't find api-svc.cluster.local: NXDOMAIN
** server can't find api-svc.svc.cluster.local: NXDOMAIN
command terminated with exit code 1

Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	api-svc.s14.svc.cluster.local
Address: 10.43.255.13
```

The agnhost `/hostname` endpoint answers with the backend Pod name, so both URLs reach the right Pod. (busybox `nslookup api-svc` finds the answer in the first search domain and then still prints NXDOMAIN for the other two search domains and exits 1 - cosmetic, the `Name:`/`Address:` lines are what count. The FQDN query is clean.)

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| DNS name does not resolve | `wget: bad address`, `NXDOMAIN` | `nslookup` from a Pod, `kubectl get svc`, `cat /etc/resolv.conf`, CoreDNS Pod/Service check | Wrong Service name + wrong namespace | Use `api-svc` / `api-svc.s14.svc.cluster.local`, recreate the client |

If `kubernetes.default.svc.cluster.local` had also failed, I would have looked at CoreDNS itself: Pod not Running, `kubectl logs -n kube-system -l k8s-app=kube-dns` showing errors, the `kube-dns` Service with no endpoints, or a NetworkPolicy blocking UDP/TCP 53 egress.

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
