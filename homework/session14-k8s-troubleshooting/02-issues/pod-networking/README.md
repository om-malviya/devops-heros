# Issue: Pod networking (wrong containerPort/targetPort, NetworkPolicy deny)

Student: Om Malviya | Enrollment No: 24BCS10448

Here DNS works and the Service has endpoints, but connections still fail. Two separate bugs are stacked in `broken.yaml` so I can show how to tell them apart:

| Symptom from the client | Meaning |
|---|---|
| `Connection refused` | the packet was answered with a TCP reset / ICMP unreachable: nothing listens on that port (wrong `targetPort`/`containerPort`) **or** a policy engine that rejects instead of drops |
| `timed out` / hangs | the packet was silently dropped: NetworkPolicy on a CNI that drops, firewall, CNI problem |

> NetworkPolicy is only enforced when the CNI (or an add-on controller) supports it. kind's default CNI (kindnet) ignores it. k3s, which I used here, enforces it with its embedded kube-router network-policy controller - and that controller **rejects** (ICMP port unreachable) rather than dropping, so on k3s a blocked connection also reads as `Connection refused`. I had to prove enforcement differently, see step 5.

## 1. Identify the problem

```bash
kubectl apply -f broken.yaml
kubectl get pods,svc,endpoints -n s14 -l app=echo
kubectl get networkpolicy -n s14
kubectl exec net-client -n s14 -- wget -qO- --timeout=3 http://echo-svc/hostname
```

Output (captured 2026-10-08, before)

```text
deployment.apps/echo created
service/echo-svc created
networkpolicy.networking.k8s.io/deny-all-ingress created
pod/net-client created

NAME                       READY   STATUS    RESTARTS   AGE
pod/echo-8488885f8-8ctmh   1/1     Running   0          20s
NAME               POD-SELECTOR   AGE
deny-all-ingress   <none>         20s

wget: can't connect to remote host (10.43.207.167): Connection refused
command terminated with exit code 1
```

(The Service and Endpoints objects have no `app=echo` label, so the `-l` filter only returned the Pod; I query them by name below.)

## 2. Investigate

```bash
# Which port does the process really listen on?
kubectl exec deploy/echo -n s14 -- netstat -tlnp
kubectl get deploy echo -n s14 -o jsonpath='{.spec.template.spec.containers[0].args}{"  containerPort="}{.spec.template.spec.containers[0].ports[0].containerPort}{"\n"}'
kubectl get svc echo-svc -n s14 -o jsonpath='{.spec.ports[0]}{"\n"}'
# Hit the Pod IP directly on both ports (bypasses the Service)
POD_IP=$(kubectl get pod -n s14 -l app=echo -o jsonpath='{.items[0].status.podIP}')
kubectl exec net-client -n s14 -- wget -qO- --timeout=3 http://$POD_IP:80/hostname
kubectl exec net-client -n s14 -- wget -qO- --timeout=3 http://$POD_IP:8080/hostname
# Any NetworkPolicy in the namespace?
kubectl describe networkpolicy deny-all-ingress -n s14
```

Output (captured 2026-10-08)

```text
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp        0      0 :::8080                 :::*                    LISTEN      1/agnhost
["netexec","--http-port=8080"]  containerPort=80
{"port":80,"protocol":"TCP","targetPort":80}

wget: can't connect to remote host (10.42.0.6): Connection refused
wget: can't connect to remote host (10.42.0.6): Connection refused     <- 8080 is the right port, yet still refused: that is the policy

Name:         deny-all-ingress
Namespace:    s14
Created on:   2026-10-08 02:46:04 +0530 IST
Spec:
  PodSelector:     <none> (Allowing the specific traffic to all pods in this namespace)
  Allowing ingress traffic:
    <none> (Selected pods are isolated for ingress connectivity)
  Not affecting egress traffic
  Policy Types: Ingress
```

## 3. Root cause

1. The container runs `netexec --http-port=8080` but the Pod template declares `containerPort: 80` and the Service forwards to `targetPort: 80`. Nothing listens on 80 -> `Connection refused`. An endpoint list of `10.42.0.6:80` would look fine, which is misleading: endpoints only prove the selector matched, not that the port is open.
2. `deny-all-ingress` selects every Pod (`podSelector: {}`) and allows no ingress, so even the right port (8080 on the Pod IP) is refused by the policy controller. On a CNI that drops instead of rejecting this would be `download timed out`; on a CNI without policy support the 8080 request would have succeeded.

## 4. Fix

```diff
           ports:
-            - containerPort: 80
+            - containerPort: 8080
+              name: http
 ...
     - port: 80
-      targetPort: 80
+      targetPort: http
```

and add an allow rule instead of removing default-deny (least privilege):

```yaml
kind: NetworkPolicy
metadata:
  name: allow-client-to-echo
spec:
  podSelector:
    matchLabels: { app: echo }
  ingress:
    - from:
        - podSelector:
            matchLabels: { role: client }
      ports:
        - port: 8080
```

```bash
kubectl apply -f fixed.yaml
kubectl rollout status deploy/echo -n s14 --timeout=60s
```

Output (captured 2026-10-08)

```text
deployment.apps/echo configured
service/echo-svc configured
networkpolicy.networking.k8s.io/deny-all-ingress unchanged
networkpolicy.networking.k8s.io/allow-client-to-echo created
pod/net-client unchanged
Waiting for deployment "echo" rollout to finish: 1 old replicas are pending termination...
deployment "echo" successfully rolled out
```

## 5. Verify

```bash
kubectl get endpoints echo-svc -n s14
kubectl get networkpolicy -n s14
kubectl exec net-client -n s14 -- wget -qO- --timeout=3 http://echo-svc/hostname
# a Pod WITHOUT role=client must still be blocked ...
kubectl run -n s14 outsider --rm -i --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=3 http://echo-svc/hostname
# ... and the same Pod WITH role=client must get through (proves the policy is really enforced)
kubectl run -n s14 outsider-client --rm -i --labels=role=client --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=3 http://echo-svc/hostname
```

Output (captured 2026-10-08, after)

```text
NAME       ENDPOINTS         AGE
echo-svc   10.42.0.23:8080   2m9s

NAME                   POD-SELECTOR   AGE
allow-client-to-echo   app=echo       5s
deny-all-ingress       <none>         2m9s

echo-7bc7f97c7d-bj2lb

wget: can't connect to remote host (10.43.207.167): Connection refused
pod "outsider" deleted from s14 namespace
pod s14/outsider terminated (Error)

echo-7bc7f97c7d-bj2lb
pod "outsider-client" deleted from s14 namespace
```

The endpoint now says `:8080`, the labelled client gets the hostname back, and the only difference between the two `kubectl run` tests is the `role=client` label - so the NetworkPolicy is enforced on this cluster, just with a "refused" instead of a "timed out" symptom. (My first attempt at a proof - deleting `deny-all-ingress` and retrying the outsider - still gave `Connection refused`, which was correct: `allow-client-to-echo` on its own already isolates the echo Pod for everything except `role=client`. Any policy that selects a Pod makes it isolated.)

## 6. Document

| Problem | What I saw | Command that helped | Root cause | Fix |
|---|---|---|---|---|
| Connection refused via Service | endpoints present but `Connection refused` | `netstat -tlnp` inside the Pod, `wget` to Pod IP on each port | `targetPort` 80 vs process on 8080 | `containerPort`/`targetPort` 8080 (named port) |
| Still refused on the right port | `Connection refused` to Pod IP:8080 (would be `timed out` on a dropping CNI) | `kubectl get/describe networkpolicy`, `kubectl run` with/without the allowed label | default-deny ingress policy, enforced by k3s | Add allow policy from `role=client` |

## Deliverables

* `broken.yaml` – reproduces the issue in namespace `s14`.
* `fixed.yaml` – the corrected manifest(s).
* `README.md` – identify, investigate, root cause, fix, verify, document, with captured before/after output.
