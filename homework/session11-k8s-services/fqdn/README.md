# FQDN in Kubernetes

Student: Om Malviya | Enrollment No: 24BCS10448

This is Task 3 of Session 11. Commands use the `client` pod and Services from
this session (namespace `s11`) and from Session 10 (namespace `s10`).

## Task 3: FQDN

### What is FQDN?

A **Fully Qualified Domain Name** is a DNS name that specifies the complete
path from the host to the DNS root, so it means the same thing no matter
where it is resolved from. `web-clusterip` is a relative name (it depends
on the resolver's search list); `web-clusterip.s11.svc.cluster.local.` is
fully qualified. The trailing dot marks the root and tells the resolver not
to append any search domain; it is usually omitted when typing but implied.

```text
 host label . sub-domains . top-level domain . root
 www        . example     . com              . (.)
 web-clusterip . s11 . svc . cluster . local . (.)
```

### Kubernetes Service DNS

Every Service gets DNS records from CoreDNS the moment it is created:

| Service type | Record | Points to |
| --- | --- | --- |
| ClusterIP / NodePort / LoadBalancer | `A` (and `AAAA`) | the ClusterIP |
| Headless (`clusterIP: None`) | one `A` per ready pod | pod IPs |
| ExternalName | `CNAME` | the external hostname |
| Any with named ports | `SRV _http._tcp.<svc>.<ns>.svc.cluster.local` | port number + target |

```bash
kubectl -n s11 exec client -- nslookup web-clusterip.s11.svc.cluster.local
kubectl -n s11 exec client -- nslookup -type=srv _http._tcp.web-clusterip.s11.svc.cluster.local
```

Output (captured 2026-10-08)
```text
Server:		10.43.0.10
Address:	10.43.0.10:53

Name:	web-clusterip.s11.svc.cluster.local
Address: 10.43.109.156

Server:		10.43.0.10
Address:	10.43.0.10:53

_http._tcp.web-clusterip.s11.svc.cluster.local	service = 0 100 80 web-clusterip.s11.svc.cluster.local
```

### Kubernetes DNS naming convention

```text
   web-clusterip  .  s11  .  svc  .  cluster.local
   └─────┬─────┘    └─┬─┘    └┬┘     └──────┬──────┘
   Service name    namespace  object   cluster domain
   (metadata.name)            type     (set at cluster install; default
                              svc|pod  cluster.local, kubelet --cluster-domain)
```

General forms:

| Object | FQDN pattern |
| --- | --- |
| Service | `<service>.<namespace>.svc.<cluster-domain>` |
| Pod of a StatefulSet behind a headless Service | `<pod-name>.<service>.<namespace>.svc.<cluster-domain>` |
| Any pod, by IP | `<ip-with-dashes>.<namespace>.pod.<cluster-domain>` |
| Pod with `hostname`/`subdomain` set | `<hostname>.<subdomain>.<namespace>.svc.<cluster-domain>` |

### Namespace-based DNS

The namespace is part of the name, so the same Service name can exist in
many namespaces without conflict, and short names are resolved relative to
the *caller's* namespace through the search list in `/etc/resolv.conf`.

```bash
kubectl -n s11 exec client -- cat /etc/resolv.conf
```

Output (captured 2026-10-08)
```text
search s11.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5
```

How a short name is expanded (first match wins):

| Typed in a pod in `s11` | Resolver tries | Result |
| --- | --- | --- |
| `web-clusterip` | `web-clusterip.s11.svc.cluster.local` | found (same namespace) |
| `web-rolling` | `web-rolling.s11.svc.cluster.local`, `web-rolling.svc.cluster.local`, `web-rolling.cluster.local`, `web-rolling` | NXDOMAIN; it lives in `s10` |
| `web-rolling.s10` | `web-rolling.s10.svc.cluster.local` (second search domain) | found |
| `web-rolling.s10.svc.cluster.local` | (fewer than 5 dots, so search list is tried first, then the literal name) | found |

```bash
kubectl -n s11 exec client -- wget -qO- -T 2 http://web-rolling          || echo "short name fails across namespaces"
kubectl -n s11 exec client -- wget -qO- -T 2 http://web-rolling.s10
kubectl -n s11 exec client -- wget -qO- -T 2 http://web-rolling.s10.svc.cluster.local
```

Output (captured 2026-10-08)
```text
wget: bad address 'web-rolling'
command terminated with exit code 1
short name fails across namespaces
v1
v1
```

(`web-rolling` answered `v1` because at that moment Session 10's Deployment
had been rolled back to v1.)

`ndots:5` means "if the name has fewer than 5 dots, try the search domains
before trying it as-is". For an external name like `api.example.com` (2
dots) that produces three useless lookups
(`api.example.com.s11.svc.cluster.local`, `...svc.cluster.local`,
`...cluster.local`) before the real one. Fixes: use a trailing dot
(`api.example.com.`) or lower `ndots` with `spec.dnsConfig`:

```yaml
spec:
  dnsConfig:
    options:
      - name: ndots
        value: "2"
```

### Pod-to-Service communication

```text
 client pod (s11)                     CoreDNS (kube-system)             Service / pods
 ───────────────                      ─────────────────────             ──────────────
 wget http://web-clusterip
   │ 1. resolver reads /etc/resolv.conf
   │    appends s11.svc.cluster.local
   │ 2. UDP 53 to 10.43.0.10 ───────▶ kubernetes plugin looks up
   │                                   Service web-clusterip in ns s11
   │ 3. ◀──────────── A 10.43.109.156 ─┘
   │ 4. TCP to 10.43.109.156:80
   │      kube-proxy DNAT ──────────────────────────────────────▶ 10.42.0.12:8080
   │ 5. ◀────────────────────────────────────── "hello from clusterip backend"
```

Application code only ever contains the name (`http://web-clusterip`, or
`http://web-clusterip.s11` from another namespace); nothing about IPs or
ports of pods leaks into configuration.

### Examples of Kubernetes FQDNs

| FQDN | What it is | Resolves to |
| --- | --- | --- |
| `kubernetes.default.svc.cluster.local` | the API server Service, exists in every cluster | `10.43.0.1` |
| `kube-dns.kube-system.svc.cluster.local` | CoreDNS itself | `10.43.0.10` |
| `web-clusterip.s11.svc.cluster.local` | ClusterIP Service from `01-clusterip` | `10.43.109.156` |
| `web-rolling.s10.svc.cluster.local` | NodePort Service from Session 10 | its ClusterIP `10.43.34.175` |
| `web.s11.svc.cluster.local` | headless Service from `05-headless` | `10.42.0.35`, `.37`, `.99` |
| `web-0.web.s11.svc.cluster.local` | first StatefulSet pod | `10.42.0.35` |
| `external-site.s11.svc.cluster.local` | ExternalName Service | `CNAME example.com` |
| `10-42-0-35.s11.pod.cluster.local` | any pod by IP | `10.42.0.35` |
| `_http._tcp.web-clusterip.s11.svc.cluster.local` | SRV record for the named port | `0 100 80 web-clusterip.s11.svc.cluster.local` |

Verification from the client pod:

```bash
kubectl -n s11 exec client -- sh -c '
for n in kubernetes.default.svc.cluster.local kube-dns.kube-system.svc.cluster.local \
         web-0.web.s11.svc.cluster.local 10-42-0-35.s11.pod.cluster.local; do
  echo "== $n"; nslookup $n 2>&1 | grep -A1 "^Name"; done'
```

Output (captured 2026-10-08)
```text
== kubernetes.default.svc.cluster.local
Name:	kubernetes.default.svc.cluster.local
Address: 10.43.0.1
== kube-dns.kube-system.svc.cluster.local
Name:	kube-dns.kube-system.svc.cluster.local
Address: 10.43.0.10
== web-0.web.s11.svc.cluster.local
Name:	web-0.web.s11.svc.cluster.local
Address: 10.42.0.35
== 10-42-0-35.s11.pod.cluster.local
Name:	10-42-0-35.s11.pod.cluster.local
Address: 10.42.0.35
```

(On minikube the service CIDR is `10.96.0.0/12`, so expect `10.96.0.1` and
`10.96.0.10` for the first two.)

The remaining rows of the table, checked the same way:

```bash
kubectl -n s11 exec client -- sh -c 'for n in web-rolling.s10.svc.cluster.local web.s11.svc.cluster.local external-site.s11.svc.cluster.local; do echo "== $n"; nslookup $n 2>&1 | grep -E "^Name|^Address: |canonical" | grep -v 10.43.0.10; done'
```

Output (captured 2026-10-08)
```text
== web-rolling.s10.svc.cluster.local
Name:	web-rolling.s10.svc.cluster.local
Address: 10.43.34.175
== web.s11.svc.cluster.local
Name:	web.s11.svc.cluster.local
Address: 10.42.0.35
Name:	web.s11.svc.cluster.local
Address: 10.42.0.37
Name:	web.s11.svc.cluster.local
Address: 10.42.0.99
== external-site.s11.svc.cluster.local
external-site.s11.svc.cluster.local	canonical name = example.com
Name:	example.com
Address: 172.66.147.243
Name:	example.com
Address: 104.20.23.154
```

(`web-1` had been deleted and recreated in `05-headless`, hence `.99`
instead of `.36`; the headless answer tracks the current pod IPs.)

### Cheat sheet

```text
same namespace       : http://<svc>
other namespace      : http://<svc>.<ns>            (or the full FQDN)
specific pod (STS)   : http://<pod>.<svc>.<ns>.svc.cluster.local
external, avoid ndots: http://api.example.com.      (trailing dot)
check resolver       : cat /etc/resolv.conf ; nslookup <name>
```

## Deliverables

- `README.md` – this document: what an FQDN is, Service DNS records, the `<svc>.<ns>.svc.cluster.local` naming convention, namespace-based resolution with `/etc/resolv.conf` search list and `ndots`, pod-to-service flow, and a table of concrete FQDN examples with verification commands.
