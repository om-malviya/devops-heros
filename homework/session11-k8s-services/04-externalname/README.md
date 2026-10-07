# 04 – ExternalName

Student: Om Malviya | Enrollment No: 24BCS10448

An ExternalName Service has no selector, no pods, no ClusterIP and no
Endpoints. CoreDNS simply answers the Service's cluster DNS name with a CNAME
to the external hostname. It lets in-cluster code use a stable internal name
for something that lives outside the cluster (managed database, SaaS API).

```text
 client pod ── nslookup external-site ──▶ CoreDNS
                                            │ external-site.s11.svc.cluster.local  CNAME  example.com.
                                            │ example.com.  A  104.20.23.154   (via upstream DNS)
                                            ▼
 client pod ── HTTP directly to 104.20.23.154 (no kube-proxy involved)
```

## Files

| File | Purpose |
| --- | --- |
| `service.yaml` | `type: ExternalName`, `externalName: example.com` |

## Deploy

```bash
kubectl apply -f ../namespace.yaml -f ../client-pod.yaml
kubectl apply -f service.yaml
```

Output (captured 2026-10-08)
```text
service/external-site created
```

## Verify the Service

```bash
kubectl -n s11 get svc,endpoints external-site
```

Output (captured 2026-10-08)
```text
Warning: v1 Endpoints is deprecated in v1.33+; use discovery.k8s.io/v1 EndpointSlice
NAME            TYPE           CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
external-site   ExternalName   <none>       example.com   <none>    114s
Error from server (NotFound): endpoints "external-site" not found
```

The missing Endpoints object is expected: there is nothing to proxy to.

```bash
kubectl -n s11 describe svc external-site
```

Output (captured 2026-10-08)
```text
Name:              external-site
Namespace:         s11
Labels:            <none>
Annotations:       <none>
Selector:          <none>
Type:              ExternalName
IP Families:       <none>
IP:
IPs:               <none>
External Name:     example.com
Session Affinity:  None
Events:            <none>
```

## Test connectivity

DNS first – this is where ExternalName does its work:

```bash
kubectl -n s11 exec client -- nslookup external-site
```

Output (captured 2026-10-08) (busybox `nslookup` NXDOMAIN lines for the other search domains removed)
```text
Server:		10.43.0.10
Address:	10.43.0.10:53

external-site.s11.svc.cluster.local	canonical name = example.com
Name:	example.com
Address: 104.20.23.154
Name:	example.com
Address: 172.66.147.243
```

Then HTTP. The remote server sees the real hostname only if I set the Host
header, because the TCP connection goes straight to example.com:

```bash
kubectl -n s11 exec client -- wget -qO- --header "Host: example.com" http://external-site | grep -m1 '<title>'
```

Output (captured 2026-10-08) (example.com now serves its whole page on one line, so `grep` printed the full line; shortened here)
```text
<!doctype html><html lang=en><head><meta charset=utf-8>...<title>Example Domain</title>...</html>
```

Without the header example.com still answers (it ignores Host), but a real
API or a TLS endpoint would not: certificates are issued for
`example.com`, not for `external-site`.

If the lab cluster has no internet egress, the `nslookup` still shows the
CNAME line (that comes from CoreDNS) but the A record lookup fails:

Expected output (not observed: this cluster had internet egress, kept for reference)
```text
external-site.s11.svc.cluster.local     canonical name = example.com
nslookup: can't resolve 'example.com': Try again
```

## What I observed

- `CLUSTER-IP` is `<none>` and `kubectl get endpoints` returns NotFound;
  ExternalName is implemented entirely in CoreDNS.
- The CNAME is the only thing Kubernetes adds. The second hop (`example.com
  -> 104.20.23.154 / 172.66.147.243`, example.com moved to Cloudflare in
  2025) is answered by CoreDNS's `forward` plugin through the node's
  upstream resolver. busybox's `nslookup` only asks for A records, so no
  IPv6 address is shown.
- Ports are not remapped and `externalName` must be a hostname, not an IP.
  To point an internal name at a bare IP I would use a selector-less
  ClusterIP Service plus a hand-written Endpoints/EndpointSlice instead.

## Cleanup

```bash
kubectl delete -f service.yaml
```

## Deliverables

- `service.yaml` – ExternalName Service aliasing `example.com`.
- `README.md` – deploy, verify (no ClusterIP, no endpoints), `nslookup` CNAME and HTTP test, cleanup.
