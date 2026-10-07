# Task 1: Kubernetes Troubleshooting Commands

Student: Om Malviya | Enrollment No: 24BCS10448

This folder is my hands-on practice of the `kubectl` commands I need when something is wrong in a cluster.
Everything runs in the `s14` namespace. I use two demo manifests:

* `pod.yaml` – a Pod `cmd-demo` with two containers (`nginx` and a `busybox` sidecar that prints a heartbeat), so I can practise the `-c` flag.
* `deployment.yaml` – a Deployment `cmd-web` (2 x `nginx:alpine`) plus a ClusterIP Service, so I can practise `top`, `-o wide` and label selectors.

All outputs below were captured on a single-node k3s cluster (`colima`, Kubernetes v1.35.0+k3s1, arm64, metrics-server installed). Pod IPs are in `10.42.0.0/16` and Service IPs in `10.43.0.0/16` on k3s; they will differ on kind/minikube.

---

## 0. Setup

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f pod.yaml -f deployment.yaml
kubectl get pods -n s14
```

Output (captured 2026-10-08)

```text
namespace/s14 unchanged
pod/cmd-demo created
deployment.apps/cmd-web created
service/cmd-web created
NAME                       READY   STATUS    RESTARTS   AGE
cmd-demo                   2/2     Running   0          20s
cmd-web-5469cf8c57-fz4sq   1/1     Running   0          20s
cmd-web-5469cf8c57-zvqq7   1/1     Running   0          20s
```

(`namespace/s14 unchanged` because I had already created it for the Task 2 scenarios.)

---

## 1. `kubectl get` – "What is happening?"

`get` is always my first command. It gives a one-line summary per resource: READY, STATUS, RESTARTS, AGE.

```bash
kubectl get pods -n s14
kubectl get all -n s14
kubectl get pods -n s14 --show-labels
kubectl get pods -n s14 -l app=cmd-web
```

Output (captured 2026-10-08)

```text
NAME                       READY   STATUS    RESTARTS   AGE
cmd-demo                   2/2     Running   0          45s
cmd-web-5469cf8c57-fz4sq   1/1     Running   0          45s
cmd-web-5469cf8c57-zvqq7   1/1     Running   0          45s

NAME                           READY   STATUS    RESTARTS   AGE
pod/cmd-demo                   2/2     Running   0          45s
pod/cmd-web-5469cf8c57-fz4sq   1/1     Running   0          45s
pod/cmd-web-5469cf8c57-zvqq7   1/1     Running   0          45s

NAME              TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/cmd-web   ClusterIP   10.43.228.102   <none>        80/TCP    45s

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cmd-web   2/2     2            2           45s

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/cmd-web-5469cf8c57   2         2         2       45s

NAME                       READY   STATUS    RESTARTS   AGE   LABELS
cmd-demo                   2/2     Running   0          45s   app=cmd-demo
cmd-web-5469cf8c57-fz4sq   1/1     Running   0          45s   app=cmd-web,pod-template-hash=5469cf8c57
cmd-web-5469cf8c57-zvqq7   1/1     Running   0          45s   app=cmd-web,pod-template-hash=5469cf8c57

NAME                       READY   STATUS    RESTARTS   AGE
cmd-web-5469cf8c57-fz4sq   1/1     Running   0          45s
cmd-web-5469cf8c57-zvqq7   1/1     Running   0          45s
```

`kubectl get pods -n s14 -w` keeps the terminal open and prints a new line every time a Pod changes state. I stop it with `Ctrl+C`. (I used it in Task 2 to watch `ErrImagePull` flip to `ImagePullBackOff`, see `../02-issues/errimagepull/README.md`.)

What I look at first: `READY` (e.g. `0/1`), `STATUS` (anything other than `Running`/`Completed`) and `RESTARTS` (growing numbers mean a crash loop).

---

## 2. `kubectl get -o wide` – where is it running?

`-o wide` adds the Pod IP, the node, and (for Deployments) the image and selector. I use it to see whether Pods are spread across nodes and to grab a Pod IP for endpoint comparisons.

```bash
kubectl get pods -n s14 -o wide
kubectl get deployment cmd-web -n s14 -o wide
kubectl get nodes -o wide
```

Output (captured 2026-10-08)

```text
NAME                       READY   STATUS    RESTARTS   AGE   IP            NODE     NOMINATED NODE   READINESS GATES
cmd-demo                   2/2     Running   0          45s   10.42.0.107   colima   <none>           <none>
cmd-web-5469cf8c57-fz4sq   1/1     Running   0          45s   10.42.0.109   colima   <none>           <none>
cmd-web-5469cf8c57-zvqq7   1/1     Running   0          45s   10.42.0.108   colima   <none>           <none>

NAME      READY   UP-TO-DATE   AVAILABLE   AGE   CONTAINERS   IMAGES         SELECTOR
cmd-web   2/2     2            2           45s   nginx        nginx:alpine   app=cmd-web

NAME     STATUS   ROLES           AGE     VERSION        INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
colima   Ready    control-plane   3h54m   v1.35.0+k3s1   192.168.5.1   <none>        Ubuntu 24.04.4 LTS   6.8.0-117-generic   containerd://2.1.5-k3s1
```

---

## 3. `-o yaml` and `-o jsonpath` – the raw object

When the table hides something (for example the exact reason a container is waiting), I print the full object or pick a field with JSONPath.

```bash
kubectl get pod cmd-demo -n s14 -o yaml | sed -n '1,20p'
kubectl get pod cmd-demo -n s14 -o jsonpath='{.status.podIP}{"\n"}'
kubectl get pods -n s14 -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'
kubectl get pods -n s14 -o custom-columns='NAME:.metadata.name,IMAGES:.spec.containers[*].image,RESTARTS:.status.containerStatuses[*].restartCount'
```

Output (captured 2026-10-08; the long `last-applied-configuration` annotation line is cut)

```text
apiVersion: v1
kind: Pod
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: |
      {"apiVersion":"v1","kind":"Pod","metadata":{"annotations":{},"labels":{"app":"cmd-demo"},"name":"cmd-demo", ...}
  creationTimestamp: "2026-10-07T20:57:05Z"
  generation: 1
  labels:
    app: cmd-demo
  name: cmd-demo
  namespace: s14
  resourceVersion: "8732"
  uid: f9b1c256-2c2a-4381-8f12-944bdf49117b
spec:
  containers:
  - image: nginx:alpine
    imagePullPolicy: IfNotPresent
    name: nginx
    ports:

10.42.0.107

cmd-demo	Running
cmd-web-5469cf8c57-fz4sq	Running
cmd-web-5469cf8c57-zvqq7	Running

NAME                       IMAGES                      RESTARTS
cmd-demo                   nginx:alpine,busybox:1.36   0,0
cmd-web-5469cf8c57-fz4sq   nginx:alpine                0
cmd-web-5469cf8c57-zvqq7   nginx:alpine                0
```

---

## 4. `kubectl describe` – "Why is it happening?"

`describe` prints the spec, the current state of every container (State / Last State / Exit Code), the Conditions, and most importantly the **Events** at the bottom.

```bash
kubectl describe pod cmd-demo -n s14
kubectl describe deployment cmd-web -n s14
kubectl describe service cmd-web -n s14
```

Output (captured 2026-10-08; Pod, trimmed to the sections I actually read)

```text
Name:             cmd-demo
Namespace:        s14
Node:             colima/192.168.5.1
Start Time:       Thu, 08 Oct 2026 02:27:05 +0530
Labels:           app=cmd-demo
Status:           Running
IP:               10.42.0.107
Containers:
  nginx:
    Container ID:   containerd://46a9b157177ea781624cb109708332a1a31eacd89b3da3e4985532a6e2e078d7
    Image:          nginx:alpine
    Image ID:       docker.io/library/nginx@sha256:df221db836e1754089190208cee7eeda94f233197056426eda74a43ab1abeac2
    Port:           80/TCP
    State:          Running
      Started:      Thu, 08 Oct 2026 02:27:05 +0530
    Ready:          True
    Restart Count:  0
    Limits:
      cpu:     100m
      memory:  64Mi
    Requests:
      cpu:        10m
      memory:     16Mi
  sidecar:
    Image:         busybox:1.36
    Command:
      sh
      -c
      echo "sidecar started"
      while true; do
        echo "heartbeat $(date +%T)"
        sleep 10
      done
    State:          Running
    Ready:          True
    Restart Count:  0
Conditions:
  Type                        Status
  PodReadyToStartContainers   True
  Initialized                 True
  Ready                       True
  ContainersReady             True
  PodScheduled                True
QoS Class:                   Burstable
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  43s   default-scheduler  Successfully assigned s14/cmd-demo to colima
  Normal  Pulled     44s   kubelet            spec.containers{nginx}: Container image "nginx:alpine" already present on machine and can be accessed by the pod
  Normal  Created    44s   kubelet            spec.containers{nginx}: Container created
  Normal  Started    44s   kubelet            spec.containers{nginx}: Container started
  Normal  Pulled     44s   kubelet            spec.containers{sidecar}: Container image "busybox:1.36" already present on machine and can be accessed by the pod
  Normal  Created    44s   kubelet            spec.containers{sidecar}: Container created
  Normal  Started    44s   kubelet            spec.containers{sidecar}: Container started
```

Output (captured 2026-10-08; Deployment, trimmed)

```text
Name:                   cmd-web
Namespace:              s14
Selector:               app=cmd-web
Replicas:               2 desired | 2 updated | 2 total | 2 available | 0 unavailable
StrategyType:           RollingUpdate
RollingUpdateStrategy:  25% max unavailable, 25% max surge
Conditions:
  Type           Status  Reason
  ----           ------  ------
  Available      True    MinimumReplicasAvailable
  Progressing    True    NewReplicaSetAvailable
NewReplicaSet:   cmd-web-5469cf8c57 (2/2 replicas created)
Events:
  Type    Reason             Age   From                   Message
  ----    ------             ----  ----                   -------
  Normal  ScalingReplicaSet  44s   deployment-controller  Scaled up replica set cmd-web-5469cf8c57 from 0 to 2
```

Output (captured 2026-10-08; Service – the three lines I always check are Selector, TargetPort and Endpoints)

```text
Name:                     cmd-web
Namespace:                s14
Selector:                 app=cmd-web
Type:                     ClusterIP
IP:                       10.43.228.102
Port:                     <unset>  80/TCP
TargetPort:               80/TCP
Endpoints:                10.42.0.109:80,10.42.0.108:80
Session Affinity:         None
Internal Traffic Policy:  Cluster
Events:                   <none>
```

I noticed that on this Kubernetes version (1.35) the kubelet events are prefixed with the container name (`spec.containers{nginx}: ...`), which makes multi-container Pods easier to read.

---

## 5. `kubectl logs` – "What is the application saying?"

```bash
# logs of the only / first container
kubectl logs cmd-web-5469cf8c57-fz4sq -n s14
# a specific container in a multi-container Pod
kubectl logs cmd-demo -n s14 -c sidecar
# follow (stream) new lines, Ctrl+C to stop
kubectl logs cmd-demo -n s14 -c sidecar -f
# only the last N lines / last X minutes
kubectl logs cmd-demo -n s14 -c sidecar --tail=3
kubectl logs cmd-demo -n s14 -c sidecar --since=1m
# logs of the previous (crashed) instance of the container
kubectl logs cmd-demo -n s14 -c sidecar --previous
# all pods of a label, all containers
kubectl logs -n s14 -l app=cmd-web --all-containers --prefix
```

Output (captured 2026-10-08; nginx start-up lines trimmed)

```text
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
/docker-entrypoint.sh: Looking for shell scripts in /docker-entrypoint.d/
/docker-entrypoint.sh: Launching /docker-entrypoint.d/10-listen-on-ipv6-by-default.sh
...
/docker-entrypoint.sh: Configuration complete; ready for start up
2026/10/07 20:57:05 [notice] 1#1: using the "epoll" event method
2026/10/07 20:57:05 [notice] 1#1: nginx/1.31.6
2026/10/07 20:57:05 [notice] 1#1: start worker processes
2026/10/07 20:57:05 [notice] 1#1: start worker process 30
...

sidecar started
heartbeat 20:57:06
heartbeat 20:57:16
heartbeat 20:57:26
heartbeat 20:57:36
heartbeat 20:57:46

sidecar started            <- with -f the same lines appear and then a new one every 10 s
heartbeat 20:57:06
...
heartbeat 20:57:46
(12 s later, before I stopped it)

heartbeat 20:57:36         <- --tail=3
heartbeat 20:57:46
heartbeat 20:57:56

sidecar started            <- --since=1m (the Pod is younger than a minute, so everything)
heartbeat 20:57:06
...
heartbeat 20:57:56

Error from server (BadRequest): previous terminated container "sidecar" in pod "cmd-demo" not found

[pod/cmd-web-5469cf8c57-fz4sq/nginx] 2026/10/07 20:57:05 [notice] 1#1: using the "epoll" event method
[pod/cmd-web-5469cf8c57-fz4sq/nginx] 2026/10/07 20:57:05 [notice] 1#1: nginx/1.31.6
[pod/cmd-web-5469cf8c57-fz4sq/nginx] 2026/10/07 20:57:05 [notice] 1#1: start worker processes
...
[pod/cmd-web-5469cf8c57-zvqq7/nginx] 2026/10/07 20:57:05 [notice] 1#1: nginx/1.31.6
[pod/cmd-web-5469cf8c57-zvqq7/nginx] 2026/10/07 20:57:05 [notice] 1#1: start worker processes
```

I observed that `--previous` only works after a restart; on a healthy container it returns the "not found" error shown above. That is exactly why it is the key flag for `CrashLoopBackOff`: the current container may have no output yet, but the previous one has the crash message. (In Task 2 I also learned it has to be run while the Pod is in `CrashLoopBackOff`, not while the current container is briefly in `Error`, see `../02-issues/crashloopbackoff/README.md`.)

If a Pod has several containers and I omit `-c`, kubectl does not error any more; it picks the first container and tells me:

```text
$ kubectl logs cmd-demo -n s14
Defaulted container "nginx" out of: nginx, sidecar
/docker-entrypoint.sh: /docker-entrypoint.d/ is not empty, will attempt to perform configuration
...
```

Note the timestamps: the container clock is UTC (`20:57`), my laptop is IST (`02:27`); `describe` shows local time, `logs` shows what the app wrote.

---

## 6. `kubectl exec` – "Check from inside the container"

```bash
# interactive shell (nginx:alpine has sh, not bash)
kubectl exec -it cmd-demo -n s14 -c nginx -- sh
# one-shot commands (what I ran instead of the interactive shell so it could be captured)
kubectl exec cmd-demo -n s14 -c nginx -- sh -c 'hostname; id; ls /usr/share/nginx/html'
kubectl exec cmd-demo -n s14 -c nginx -- nginx -v
kubectl exec cmd-demo -n s14 -c nginx -- wget -qO- http://localhost | head -4
kubectl exec cmd-demo -n s14 -c sidecar -- cat /etc/resolv.conf
kubectl exec cmd-demo -n s14 -c sidecar -- wget -qO- http://cmd-web.s14.svc.cluster.local | head -4
```

Output (captured 2026-10-08)

```text
cmd-demo
uid=0(root) gid=0(root) groups=0(root),1(bin),2(daemon),3(sys),4(adm),6(disk),10(wheel),11(floppy),20(dialout),26(tape),27(video)
50x.html
index.html

nginx version: nginx/1.31.6

<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>

search s14.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.43.0.10
options ndots:5

<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
```

The last command is my favourite connectivity test: from a Pod I call the Service by its DNS name. If that works, DNS, the Service, the endpoints and the application are all fine.

`exec` needs a running container; for a crash-looping Pod I rely on `logs --previous` and `describe` instead (or `kubectl debug`).

---

## 7. Events – "What did Kubernetes try to do?"

There are two ways to read events: the classic `kubectl get events` (sortable, filterable) and the newer `kubectl events` command.

```bash
kubectl get events -n s14 --sort-by=.lastTimestamp
kubectl get events -n s14 --field-selector type=Warning
kubectl events -n s14
kubectl events -n s14 --for pod/cmd-demo
kubectl events -n s14 --watch
```

Output (captured 2026-10-08; trimmed to the events of the demo objects, see the note below)

```text
LAST SEEN   TYPE      REASON              OBJECT                          MESSAGE
58s         Normal    Scheduled           pod/cmd-web-5469cf8c57-zvqq7    Successfully assigned s14/cmd-web-5469cf8c57-zvqq7 to colima
58s         Normal    Scheduled           pod/cmd-web-5469cf8c57-fz4sq    Successfully assigned s14/cmd-web-5469cf8c57-fz4sq to colima
58s         Normal    Scheduled           pod/cmd-demo                    Successfully assigned s14/cmd-demo to colima
59s         Normal    Pulled              pod/cmd-web-5469cf8c57-fz4sq    Container image "nginx:alpine" already present on machine and can be accessed by the pod
59s         Normal    Started             pod/cmd-demo                    Container started
59s         Normal    SuccessfulCreate    replicaset/cmd-web-5469cf8c57   Created pod: cmd-web-5469cf8c57-fz4sq
59s         Normal    Created             pod/cmd-web-5469cf8c57-fz4sq    Container created
59s         Normal    SuccessfulCreate    replicaset/cmd-web-5469cf8c57   Created pod: cmd-web-5469cf8c57-zvqq7
59s         Normal    ScalingReplicaSet   deployment/cmd-web              Scaled up replica set cmd-web-5469cf8c57 from 0 to 2
59s         Normal    Pulled              pod/cmd-demo                    Container image "nginx:alpine" already present on machine and can be accessed by the pod
58s         Normal    Started             pod/cmd-demo                    Container started

LAST SEEN   TYPE      REASON             OBJECT                 MESSAGE
2m58s       Warning   BackOff            pod/crash-demo         Back-off restarting failed container app in pod crash-demo_s14(74b11d21-...)
3m25s       Warning   Failed             pod/image-demo         Error: ImagePullBackOff
19m         Warning   FailedScheduling   pod/pending-cpu        0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory. ...
19m         Warning   FailedScheduling   pod/pending-selector   0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector. ...
3m33s       Warning   Failed             pod/registry-demo      Error: ImagePullBackOff

LAST SEEN   TYPE     REASON      OBJECT         MESSAGE
59s         Normal   Pulled      Pod/cmd-demo   Container image "nginx:alpine" already present on machine and can be accessed by the pod
59s         Normal   Created     Pod/cmd-demo   Container created
59s         Normal   Started     Pod/cmd-demo   Container started
59s         Normal   Pulled      Pod/cmd-demo   Container image "busybox:1.36" already present on machine and can be accessed by the pod
59s         Normal   Created     Pod/cmd-demo   Container created
59s         Normal   Scheduled   Pod/cmd-demo   Successfully assigned s14/cmd-demo to colima
58s         Normal   Started     Pod/cmd-demo   Container started
```

Notes I made:
* `--sort-by=.lastTimestamp` puts the newest event at the bottom, which is what I want during an incident. (The order above is not perfectly chronological because several events share the same second.)
* `--field-selector type=Warning` removes the noise; `FailedScheduling`, `Failed` (image pull), `BackOff`, `FailedMount` and `Unhealthy` are all Warnings. On a healthy namespace it prints `No resources found in s14 namespace.`; here it did show Warnings, because I had already run the Task 2 scenarios (`crash-demo`, `image-demo`, `pending-*`, `registry-demo`) in the same namespace a few minutes earlier and events are kept for one hour. The demo objects themselves produced no Warning. I trimmed those stale lines from the other two blocks.
* `kubectl events` (the newer command) groups repeated events as `2m58s (x162 over 3h41m)` and capitalises the kind (`Pod/cmd-demo`); `--for pod/cmd-demo` filters to one object and `--watch` keeps streaming (I stopped it with Ctrl+C after 5 s).
* Events are kept for one hour by default, so I look at them early.

---

## 8. `kubectl explain` – built-in API documentation

When I am not sure which field goes where (or why `kubectl apply` rejects my YAML), `explain` prints the schema straight from the API server.

```bash
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.resources.limits
kubectl explain deployment.spec.strategy --recursive
```

Output (captured 2026-10-08; trimmed)

```text
KIND:       Pod
VERSION:    v1

FIELD: containers <[]Container>

DESCRIPTION:
    List of containers belonging to the pod. Containers cannot currently be
    added or removed. There must be at least one container in a Pod. Cannot be
    updated.
    A single application container that you want to run within a pod.

FIELDS:
  args	<[]string>
    Arguments to the entrypoint. The container image's CMD is used if this is
    not provided. ...
  command	<[]string>
    Entrypoint array. Not executed within a shell. ...
  env	<[]EnvVar>
    List of environment variables to set in the container. Cannot be updated.
  envFrom	<[]EnvFromSource>
  image	<string>
    Container image name. More info:
    https://kubernetes.io/docs/concepts/containers/images ...
  imagePullPolicy	<string>
  enum: Always, IfNotPresent, Never
    Image pull policy. One of Always, Never, IfNotPresent. Defaults to Always if
    :latest tag is specified, or IfNotPresent otherwise. Cannot be updated.
  ...

KIND:       Pod
VERSION:    v1

FIELD: limits <map[string]Quantity>

DESCRIPTION:
    Limits describes the maximum amount of compute resources allowed. More info:
    https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
    Quantity is a fixed-point representation of a number. ...

GROUP:      apps
KIND:       Deployment
VERSION:    v1

FIELD: strategy <DeploymentStrategy>

DESCRIPTION:
    The deployment strategy to use to replace existing pods with new ones.
    DeploymentStrategy describes how to replace existing pods with new ones.

FIELDS:
  rollingUpdate	<RollingUpdateDeployment>
    maxSurge	<IntOrString>
    maxUnavailable	<IntOrString>
  type	<string>
  enum: Recreate, RollingUpdate
```

---

## 9. `kubectl top` – live CPU and memory

`top` reads from the Metrics API (metrics-server). It is the quickest way to see whether a Pod is close to its limit (a hint for `OOMKilled`) or whether a node is saturated (a hint for `Pending`).

```bash
kubectl top nodes
kubectl top pods -n s14
kubectl top pods -n s14 --containers
kubectl top pods -n s14 --sort-by=memory
```

Output (captured 2026-10-08; k3s ships metrics-server, so this worked out of the box)

```text
NAME     CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
colima   1574m        39%      3003Mi          50%

NAME                       CPU(cores)   MEMORY(bytes)
cmd-demo                   1m           5Mi
cmd-web-5469cf8c57-fz4sq   0m           4Mi
cmd-web-5469cf8c57-zvqq7   0m           4Mi

POD                        NAME      CPU(cores)   MEMORY(bytes)
cmd-demo                   nginx     0m           5Mi
cmd-demo                   sidecar   1m           0Mi
cmd-web-5469cf8c57-fz4sq   nginx     0m           4Mi
cmd-web-5469cf8c57-zvqq7   nginx     0m           4Mi

NAME                       CPU(cores)   MEMORY(bytes)
cmd-demo                   1m           5Mi
cmd-web-5469cf8c57-fz4sq   0m           4Mi
cmd-web-5469cf8c57-zvqq7   0m           4Mi
```

The node is a 4-CPU / 6 GB VM shared with the other sessions' workloads, hence 39 % CPU with my three tiny Pods using almost nothing.

If metrics-server is not installed (default on kind/minikube) the command fails with:

Expected output (not reproduced here because k3s already had metrics-server)

```text
error: Metrics API not available
```

On kind I would install it with:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl patch -n kube-system deployment metrics-server --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

(`--kubelet-insecure-tls` is only acceptable on a local lab cluster.)

---

## 10. Clean up

```bash
kubectl delete -f pod.yaml -f deployment.yaml
```

Output (captured 2026-10-08)

```text
pod "cmd-demo" deleted from s14 namespace
deployment.apps "cmd-web" deleted from s14 namespace
service "cmd-web" deleted from s14 namespace
```

---

## Summary table

| Command | Question it answers | Flags I used most |
|---|---|---|
| `kubectl get` | What is the current state? | `-n`, `-l`, `--show-labels`, `-w`, `-A` |
| `kubectl get -o wide` | Where is it running, which IP/image? | `-o wide` |
| `kubectl get -o yaml/jsonpath` | What does the full object look like? | `-o yaml`, `-o jsonpath=`, `-o custom-columns=` |
| `kubectl describe` | Why is it in that state? (State, Conditions, Events) | `describe pod/deploy/svc/node` |
| `kubectl logs` | What does the app say? | `-c`, `-f`, `--previous`, `--tail`, `--since`, `-l` |
| `kubectl exec` | What does it look like from inside? | `-it ... -- sh`, `-c`, one-shot commands |
| `kubectl get events` / `kubectl events` | What did the control plane try? | `--sort-by=.lastTimestamp`, `--field-selector type=Warning`, `--for`, `--watch` |
| `kubectl explain` | Which fields exist and what do they mean? | `--recursive` |
| `kubectl top` | How much CPU/memory is used right now? | `nodes`, `pods`, `--containers`, `--sort-by` |

## Deliverables

* `pod.yaml` – two-container demo Pod used for `logs -c`, `exec -c`, `describe`.
* `deployment.yaml` – Deployment + Service used for `get -o wide`, `top`, label selectors, DNS test.
* `README.md` – this file: every command with its purpose and captured output.
