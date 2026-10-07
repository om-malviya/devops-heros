# CoreDNS

Student: Om Malviya | Enrollment No: 24BCS10448

This is Task 4 of Session 11.

## Task 4: CoreDNS

### What is CoreDNS?

CoreDNS is a DNS server written in Go, built as a chain of plugins. Each
plugin handles one concern (answer from Kubernetes objects, cache, forward
upstream, log, expose metrics) and a short config file called a **Corefile**
decides which plugins run for which zone. It is a CNCF graduated project and
has been the default cluster DNS since Kubernetes 1.13, replacing kube-dns
(which was three containers: dnsmasq + kubedns + sidecar).

In a cluster it runs as a Deployment in `kube-system` behind a ClusterIP
Service named `kube-dns` (the name was kept for compatibility):

```bash
kubectl -n kube-system get deploy,pods,svc -l k8s-app=kube-dns
```

Output (captured 2026-10-08)
```text
NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/coredns   1/1     1            1           4h5m

NAME                           READY   STATUS    RESTARTS   AGE
pod/coredns-54bf7cdff9-hwhc7   1/1     Running   0          4h5m

NAME               TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
service/kube-dns   ClusterIP   10.43.0.10   <none>        53/UDP,53/TCP,9153/TCP   4h5m
```

(`10.43.0.10` on k3s, `10.96.0.10` on minikube/kubeadm; it is always the
10th IP of the service CIDR.)

### Why Kubernetes uses CoreDNS

- **Pods need names, not IPs.** Pod IPs change on every restart; Services
  need a name clients can hard-code. DNS is the protocol every language and
  tool already speaks, so no client library is needed.
- **Single process, single binary.** Easier to run, upgrade and secure than
  the three-container kube-dns.
- **Plugin architecture.** The `kubernetes` plugin watches the API; other
  plugins add caching, rewriting, split-horizon, custom zones, or
  forwarding to a corporate DNS, all from one config file.
- **Observability.** Built-in `health`, `ready` and Prometheus `metrics`
  endpoints.
- **Spec compliance.** Implements the Kubernetes DNS specification
  (A/AAAA/SRV/PTR records for Services and pods, headless semantics,
  ExternalName CNAMEs).

### How Service discovery works

```text
 kube-apiserver                           CoreDNS pod
 ──────────────                           ───────────
 Service web-clusterip created  ──watch──▶ kubernetes plugin keeps an in-memory
 EndpointSlice updated          ──watch──▶ index of Services, EndpointSlices,
 Pod Ready/NotReady             ──watch──▶ Namespaces
                                           │
 client pod: nslookup web-clusterip        │
   resolv.conf -> 10.43.0.10 ─────────────▶│ lookup "web-clusterip.s11.svc.cluster.local"
                                           │ type ClusterIP  -> A  10.43.109.156
                                           │ type headless   -> A  per ready endpoint
                                           │ type ExternalName -> CNAME example.com
                                           │ pod-N.svc       -> A  that pod's IP
```

Records are never written to a zone file; CoreDNS answers from its watch
cache, so a new Service is resolvable within a second or two of creation.

The kubelet is the other half: when it starts a pod with the default
`dnsPolicy: ClusterFirst` it writes `/etc/resolv.conf` inside the pod with
`nameserver <kube-dns ClusterIP>`, the namespace-specific `search` list and
`options ndots:5`. So every container's resolver already points at CoreDNS
without any application configuration.

### How DNS queries are resolved

```text
 1. app calls getaddrinfo("web-clusterip")
 2. libc/musl reads /etc/resolv.conf:
      search s11.svc.cluster.local svc.cluster.local cluster.local
      nameserver 10.43.0.10
      options ndots:5
    "web-clusterip" has 0 dots (< 5) -> try search domains first
 3. UDP query  web-clusterip.s11.svc.cluster.local.  A  -> 10.43.0.10:53
 4. kube-proxy DNATs 10.43.0.10 to a CoreDNS pod IP
 5. CoreDNS plugin chain for zone ".":
      errors -> health/ready (no-op) -> kubernetes (zone cluster.local matches)
      -> found Service web-clusterip in ns s11 -> answer A 10.43.109.156, TTL 30
      -> cache stores it -> reply
 6. If the name is NOT under cluster.local (e.g. example.com):
      kubernetes plugin: not my zone -> fallthrough
      cache: miss
      forward -> upstream from the node's /etc/resolv.conf (e.g. 192.168.64.1 or 8.8.8.8)
      cache: store -> reply
 7. If the name is under cluster.local but does not exist:
      kubernetes plugin answers NXDOMAIN immediately (no forwarding)
```

A worked example of the search-list cost: resolving `example.com` from a
pod makes these queries in order, each one a round-trip to CoreDNS:

```text
example.com.s11.svc.cluster.local.  -> NXDOMAIN (kubernetes plugin)
example.com.svc.cluster.local.      -> NXDOMAIN
example.com.cluster.local.          -> NXDOMAIN
example.com.                        -> forwarded upstream -> A 104.20.23.154
```

### CoreDNS configuration

The config lives in the `coredns` ConfigMap:

```bash
kubectl -n kube-system get cm coredns -o yaml
```

Output (captured 2026-10-08) (k3s v1.35; `metadata` trimmed to name/namespace)
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          fallthrough in-addr.arpa ip6.arpa
        }
        hosts /etc/coredns/NodeHosts {
          ttl 60
          reload 15s
          fallthrough
        }
        prometheus :9153
        cache 30
        loop
        reload
        loadbalance
        import /etc/coredns/custom/*.override
        forward . /etc/resolv.conf
    }
    import /etc/coredns/custom/*.server
  NodeHosts: |
    192.168.5.1 colima
```

The real k3s Corefile differs slightly from the generic one I had in mind:
`forward` is written last (order in the file does not matter, see below),
and there are two `import` lines for the optional `coredns-custom`
ConfigMap, one inside the server block (`*.override`) and one outside
(`*.server`, for whole extra server blocks). `NodeHosts` maps my single
node name `colima` to `192.168.5.1`.

Each line is a plugin; the order they execute in is fixed by CoreDNS, not
by the file:

| Plugin | What it does |
| --- | --- |
| `.:53 { }` | Server block: answer every zone (`.`) on port 53 (UDP and TCP) |
| `errors` | Log errors to stdout (visible with `kubectl logs`) |
| `health` | HTTP `/health` on :8080, used by the pod's liveness probe |
| `ready` | HTTP `/ready` on :8181, returns 200 only once all plugins (e.g. the API watch) are ready; used by the readiness probe |
| `kubernetes cluster.local in-addr.arpa ip6.arpa` | The core plugin: serves `cluster.local` and reverse zones from Services/EndpointSlices/Pods |
| `  pods insecure` | Answer `<ip-with-dashes>.<ns>.pod.cluster.local` without checking the pod exists (compat mode; `pods verified` checks) |
| `  fallthrough in-addr.arpa ip6.arpa` | Reverse lookups not found in the cluster continue to later plugins (`forward`) instead of NXDOMAIN |
| `  ttl 30` (optional) | TTL on cluster records, default 5 s |
| `hosts /etc/coredns/NodeHosts` | k3s-only: resolve node names to node IPs from a hosts file; `fallthrough` passes other names on |
| `prometheus :9153` | Expose `/metrics` (query counts, latency, cache hits) |
| `forward . /etc/resolv.conf` | Send everything not answered so far to the upstream resolvers listed in the CoreDNS pod's `/etc/resolv.conf` (inherited from the node). Can be `forward . 8.8.8.8 1.1.1.1` |
| `cache 30` | Cache positive and negative answers for up to 30 s, so repeated lookups never hit the API index or the upstream |
| `loop` | Send a random probe through the forward path; if it comes back, a forwarding loop exists and CoreDNS exits (prevents 100% CPU) |
| `reload` | Watch the Corefile and reload on change (ConfigMap edits apply in ~2 minutes without restarting the pods) |
| `loadbalance` | Round-robin shuffle of A/AAAA records in each answer, so multi-endpoint (headless) answers spread load |
| `import /etc/coredns/custom/*.override` / `*.server` | k3s: include extra snippets (inside the block) or extra server blocks (outside it) from the optional `coredns-custom` ConfigMap |

Common customisations:

```text
# forward a corporate zone to an internal DNS
corp.example.internal:53 {
    forward . 10.0.0.53
}

# rewrite a legacy name to a Service
.:53 {
    rewrite name old-db.legacy.local db.s11.svc.cluster.local
    ...
}

# turn on per-query logging for debugging (noisy)
.:53 {
    log
    ...
}
```

Apply changes with `kubectl -n kube-system edit cm coredns` (or the
`coredns-custom` ConfigMap on k3s) and wait for `reload`, or force it with
`kubectl -n kube-system rollout restart deployment coredns`.

### How to troubleshoot DNS issues

Work from the outside in: is CoreDNS up, can the pod reach it, is the name
right, is it a cluster name or an external one.

**1. Is CoreDNS running and ready?**

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide
kubectl -n kube-system get svc kube-dns
kubectl -n kube-system get endpoints kube-dns
```

Output (captured 2026-10-08)
```text
NAME                       READY   STATUS    RESTARTS   AGE    IP           NODE     NOMINATED NODE   READINESS GATES
coredns-54bf7cdff9-hwhc7   1/1     Running   0          4h5m   10.42.0.10   colima   <none>           <none>
NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.43.0.10   <none>        53/UDP,53/TCP,9153/TCP   4h5m
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME       ENDPOINTS                                     AGE
kube-dns   10.42.0.10:9153,10.42.0.10:53,10.42.0.10:53   4h5m
```

(`kubectl get endpoints` lists `10.42.0.10:53` twice because the Service has
both a UDP and a TCP port 53.)

If the pod is `CrashLoopBackOff`, read the logs; the classic cause is a
forwarding loop (node `/etc/resolv.conf` pointing to `127.0.0.53` /
systemd-resolved):

```bash
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=20
```

Output (captured 2026-10-08) (healthy; repeated lines removed)
```text
[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.override
[WARNING] No files matching import glob pattern: /etc/coredns/custom/*.server
```

Expected output (loop problem; not reproduced here, reference only)
```text
[FATAL] plugin/loop: Loop (127.0.0.1:52337 -> :53) detected for zone ".", see https://coredns.io/plugins/loop#troubleshooting. Query: "HINFO 1234567890.1234567890." 
```

On my cluster the last 20 lines were only the two `[WARNING] No files
matching import glob pattern` messages, repeated each time `reload`
re-parsed the Corefile. They are harmless: the `coredns-custom` ConfigMap
simply does not exist. The startup banner (`.:53`, `CoreDNS-1.x`,
`linux/arm64`) had already scrolled out of the tail.

Fix for the loop: point kubelet at the real resolver
(`--resolv-conf=/run/systemd/resolve/resolv.conf`) or change
`forward . /etc/resolv.conf` to explicit upstream IPs.

**2. Check the configuration**

```bash
kubectl -n kube-system get cm coredns -o yaml
kubectl -n kube-system describe deployment coredns | grep -A3 -E 'Liveness|Readiness'
```

Look for a wrong cluster domain, a missing `forward`, or a typo that made
`reload` refuse the new Corefile (the log says `[ERROR] Restart failed`).

**3. Test from a pod with DNS tools**

```bash
kubectl -n s11 run dnsutils --rm -it --restart=Never \
  --image=registry.k8s.io/e2e-test-images/agnhost:2.47 --command -- sh
# or reuse the busybox client:
kubectl -n s11 exec -it client -- sh
```

(`--command` is required: the agnhost image's entrypoint is the `agnhost`
binary, and without it `sh` is passed as an agnhost sub-command and fails
with `unknown command "sh"`, which is what happened on my first try.)

Inside the pod:

```bash
cat /etc/resolv.conf
nslookup kubernetes.default.svc.cluster.local
nslookup web-clusterip
nslookup web-clusterip.s11.svc.cluster.local
nslookup example.com
```

Output (captured 2026-10-08) (busybox `nslookup` NXDOMAIN lines for the other search domains removed)
```text
search s11.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5

Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	kubernetes.default.svc.cluster.local
Address: 10.43.0.1

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156

Non-authoritative answer:
Name:	example.com
Address: 172.66.147.243
Name:	example.com
Address: 104.20.23.154
```

The same checks from the agnhost pod, whose `nslookup` (from bind-tools) is
quieter than busybox's and which also has `dig`:

```bash
kubectl -n s11 run dnsutils --rm -i --restart=Never \
  --image=registry.k8s.io/e2e-test-images/agnhost:2.47 --command -- \
  sh -c 'cat /etc/resolv.conf; nslookup web-clusterip.s11.svc.cluster.local; dig +short web-clusterip.s11.svc.cluster.local'
```

Output (captured 2026-10-08)
```text
search s11.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5
Server:		10.43.0.10
Address:	10.43.0.10#53

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156

10.43.109.156
pod "dnsutils" deleted from s11 namespace
```

How to read failures:

| Symptom | Likely cause | Check |
| --- | --- | --- |
| `nameserver` in resolv.conf is not the kube-dns IP | pod uses `dnsPolicy: Default` or `hostNetwork` without `ClusterFirstWithHostNet` | `kubectl get pod <p> -o jsonpath='{.spec.dnsPolicy}'` |
| `;; connection timed out; no servers could be reached` | CoreDNS down, or a NetworkPolicy / firewall blocking UDP+TCP 53 to kube-system | step 1; `kubectl get networkpolicy -A` |
| `kubernetes.default` resolves but `web-clusterip` does not | Service does not exist in *this* namespace; use `svc.ns` form | `kubectl get svc -A \| grep web-clusterip` |
| Name resolves but the connection fails | DNS is fine; the Service has no endpoints (selector/label mismatch, pods not Ready) | `kubectl -n s11 get endpoints web-clusterip` |
| Cluster names OK, external names fail | upstream `forward` target unreachable from the node, or no egress | `kubectl -n kube-system logs -l k8s-app=kube-dns \| grep -i 'i/o timeout'` |
| Slow lookups of external names | `ndots:5` search expansion (3 NXDOMAINs before the real query) | use trailing dot or `dnsConfig.options ndots:2` |
| Stale answer after Service recreate | `cache 30` TTL | wait 30 s or restart CoreDNS |

**4. Watch queries live**

Add `log` to the Corefile temporarily, then:

```bash
kubectl -n kube-system logs -f -l k8s-app=kube-dns
```

Expected output (not run: I did not edit the Corefile of the shared lab cluster)
```text
[INFO] 10.42.0.50:41233 - 5123 "A IN web-clusterip.s11.svc.cluster.local. udp 53 false 512" NOERROR qr,aa,rd 104 0.000211s
[INFO] 10.42.0.50:41233 - 5124 "A IN example.com.s11.svc.cluster.local. udp 51 false 512" NXDOMAIN qr,aa,rd 144 0.000098s
[INFO] 10.42.0.50:41233 - 5125 "A IN example.com. udp 29 false 512" NOERROR qr,rd,ra 56 0.021877s
```

The second line is the `ndots` expansion in action; the third shows the
forwarded query taking 20 ms versus 0.2 ms for the cluster answer.

**5. Query CoreDNS directly, bypassing the pod resolver**

```bash
kubectl -n s11 exec client -- nslookup web-clusterip.s11.svc.cluster.local 10.43.0.10
kubectl -n s11 exec client -- nslookup web-clusterip.s11.svc.cluster.local 10.42.0.10   # the CoreDNS pod IP
```

Output (captured 2026-10-08)
```text
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156

Server:		10.42.0.10
Address:	10.42.0.10:53

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156
```

If the pod IP answers but the Service IP does not, kube-proxy is the
problem, not CoreDNS. Here both answer, as they should.

**6. Metrics**

```bash
kubectl -n kube-system port-forward svc/kube-dns 9153:9153 &
curl -s localhost:9153/metrics | grep -E '^coredns_dns_(requests|responses)_total' | head
```

Output (captured 2026-10-08)
```text
Forwarding from 127.0.0.1:9153 -> 9153
Forwarding from [::1]:9153 -> 9153
coredns_dns_requests_total{family="1",proto="udp",server="dns://:53",type="A",view="",zone="."} 348097
coredns_dns_requests_total{family="1",proto="udp",server="dns://:53",type="AAAA",view="",zone="."} 348155
coredns_dns_requests_total{family="1",proto="udp",server="dns://:53",type="SRV",view="",zone="."} 1
coredns_dns_requests_total{family="1",proto="udp",server="dns://:53",type="other",view="",zone="."} 1
coredns_dns_responses_total{plugin="",rcode="SERVFAIL",server="dns://:53",view="",zone="."} 6
coredns_dns_responses_total{plugin="loadbalance",rcode="NOERROR",server="dns://:53",view="",zone="."} 585487
coredns_dns_responses_total{plugin="loadbalance",rcode="NXDOMAIN",server="dns://:53",view="",zone="."} 110761
```

A high NXDOMAIN ratio is usually the `ndots` search expansion again. On
this cluster about 16% of all answers were NXDOMAIN (110761 of ~696000) even
though nothing was misconfigured; that is the search list at work. The
`AAAA` count matching the `A` count shows that musl/glibc resolvers ask for
both record types in parallel, and the `SRV` request of 1 is my own lookup
from `../fqdn/README.md`.

## Deliverables

- `README.md` – this document: what CoreDNS is, why Kubernetes uses it, how Service discovery and query resolution work (with flow diagrams), the default Corefile with every plugin explained, and a step-by-step troubleshooting guide (pods/logs, ConfigMap, dnsutils pod, nslookup, resolv.conf, ndots, direct queries, metrics).
