# Scenario 5: HPA without CPU requests -> unknown metrics, no scaling

Prerequisite: the healthy stack from `kubernetes/` (or the Helm chart) is deployed in namespace `taskboard`.

On the k3s cluster used for the captured output the images come from a local registry and the Ingress class is Traefik, so every apply below was piped through
`sed -e 's#ghcr.io/om-malviya/taskboard-backend:latest#localhost:5002/taskboard-backend:local#' -e 's#ingressClassName: nginx#ingressClassName: traefik#' <file> | kubectl apply -f -`.

```bash
kubectl apply -f troubleshooting/05-hpa-no-resource-requests/broken.yaml
```

## 1. Identify the issue

`kubectl get hpa` shows `TARGETS <unknown>/60%`, the HPA never scales even under load, and `describe hpa` reports `FailedGetResourceMetric`.

## 2. Investigate logs and resources

```bash
kubectl -n taskboard get hpa
kubectl -n taskboard describe hpa taskboard-backend | sed -n '/Conditions/,$p'
kubectl -n taskboard get deploy taskboard-backend -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo
kubectl top pods -n taskboard
```

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get hpa
NAME                REFERENCE                      TARGETS              MINPODS   MAXPODS   REPLICAS   AGE
taskboard-backend   Deployment/taskboard-backend   cpu: <unknown>/60%   2         6         2          12m
$ kubectl -n taskboard describe hpa taskboard-backend | sed -n '/^Conditions/,/^Events/p'
Conditions:
  Type            Status  Reason                   Message
  ----            ------  ------                   -------
  AbleToScale     True    SucceededGetScale        the HPA controller was able to get the target's current scale
  ScalingActive   False   FailedGetResourceMetric  the HPA was unable to compute the replica count: failed to get cpu utilization: missing request for cpu in container backend of Pod taskboard-backend-667556cccc-lz4vp
  ScalingLimited  True    TooFewReplicas           the desired replica count is less than the minimum replica count
$ kubectl -n taskboard get events --field-selector involvedObject.kind=HorizontalPodAutoscaler --sort-by=.lastTimestamp | tail -2
6s   Warning   FailedGetResourceMetric        horizontalpodautoscaler/taskboard-backend   failed to get cpu utilization: missing request for cpu in container backend of Pod taskboard-backend-667556cccc-lz4vp
6s   Warning   FailedComputeMetricsReplicas   horizontalpodautoscaler/taskboard-backend   invalid metrics (1 invalid out of 1), first error is: failed to get cpu resource metric value: ...
$ kubectl -n taskboard get deploy taskboard-backend -o jsonpath='{.spec.template.spec.containers[0].resources}'; echo
{}
$ kubectl top pods -n taskboard -l app=taskboard-backend             # metrics-server itself is fine
NAME                                 CPU(cores)   MEMORY(bytes)
taskboard-backend-667556cccc-ln4dd   4m           63Mi
taskboard-backend-667556cccc-lz4vp   2m           63Mi
```

## 3. Root cause

CPU *utilisation* is `usage / request`. Without `resources.requests.cpu` on the container the denominator does not exist, so metrics-server data cannot be turned into a percentage and the HPA reports `<unknown>`. (If `kubectl top` itself fails, the cause is a missing metrics-server instead - `kubectl get apiservice v1beta1.metrics.k8s.io`.)

## 4. Fix

```bash
kubectl apply -f fixed.yaml      # adds requests cpu=100m/memory=128Mi and limits
# generate load to see it scale:
kubectl -n taskboard run load --rm -it --image=busybox --restart=Never -- sh -c 'while true; do wget -q -O- http://taskboard-backend:8000/api/tasks >/dev/null; done'
```

## 5. Verify

```bash
kubectl -n taskboard get hpa
kubectl -n taskboard describe hpa taskboard-backend | sed -n '/^Conditions/,/^Events/p'
```

(No load generator was run, so the capture shows the metric becoming valid at 2 %; the scale-out to 4 replicas under load is what the HPA would do next.)

```text
Output (captured 2026-10-08, k3s)
$ kubectl -n taskboard get hpa                                        # ~75 s after the fix
NAME                REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
taskboard-backend   Deployment/taskboard-backend   cpu: 2%/60%   2         6         2          14m
$ kubectl -n taskboard describe hpa taskboard-backend | sed -n '/^Conditions/,/^Events/p'
Conditions:
  Type            Status  Reason            Message
  ----            ------  ------            -------
  AbleToScale     True    ReadyForNewScale  recommended size matches current size
  ScalingActive   True    ValidMetricFound  the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
  ScalingLimited  True    TooFewReplicas    the desired replica count is less than the minimum replica count
```

## 6. Document

| | |
|---|---|
| Symptom | `kubectl get hpa` shows `TARGETS <unknown>/60%`, the HPA never scales even under load, and `describe hpa` reports `FailedGetResourceMetric`. |
| Root cause | CPU *utilisation* is `usage / request`. |
| Fix | `kubectl apply -f fixed.yaml` (see diff below) |
| Lesson | An HPA has two hard prerequisites: metrics-server and resource requests on every container of the target. Without either it silently does nothing. |

```bash
diff troubleshooting/05-hpa-no-resource-requests/broken.yaml troubleshooting/05-hpa-no-resource-requests/fixed.yaml
```
