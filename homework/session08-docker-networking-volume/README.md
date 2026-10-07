# Session 08 – Docker Networking & Volumes
Student: Om Malviya | Enrollment No: 24BCS10448

I ran every step on my Mac (Apple Silicon) with Docker 29 running in a Colima VM on 2026-10-07; every command is also kept in a runnable script (`task1-networking.sh`, `task2-host-network.sh`, `task3-bind-mount.sh`, `cleanup.sh`) and the outputs below are labelled **Output (captured 2026-10-07)**. The scripts are idempotent: each one removes anything left over from a previous run before starting. One practical change: I publish the frontend on host port **8091** (not 8081) because port 8081 was already taken by another container on my machine while I was testing.

## Task 1: Docker Container Networking

* Create 3 containers: Frontend, Backend, Database.
* Use Nginx or Alpine images for the frontend and backend (I use `nginx:alpine`, which is Nginx on Alpine and already has `ping`, `wget`, `nc`, `getent`).
* Use the MySQL image for the database (`mysql:8`).
* Create 3 different Docker networks (`frontend-net`, `backend-net`, `db-net`).
* Add the backend container to 2 networks (`frontend-net` + `backend-net`).
* Check connectivity between the containers.

### Network layout

```
 host:8091
    |
    v
+----------+      frontend-net       +----------+      backend-net        +----------+
| frontend |-------------------------| backend  |-------------------------|    db    |
| nginx    |  172.19.0.2  172.19.0.3 | nginx    | 172.20.0.2   172.20.0.3 | mysql:8  |
+----------+                         +----------+                         +----------+
                                                                              |
                                                                           db-net
                                                                          172.21.0.2
                                                                       (db is alone here)

 frontend  -> frontend-net
 backend   -> frontend-net + backend-net        (2 networks)
 db        -> backend-net  + db-net
 frontend  X  db   : no common network -> no DNS, no route (isolation)
```

### Commands

```bash
# networks
docker network create --driver bridge frontend-net
docker network create --driver bridge backend-net
docker network create --driver bridge db-net
docker network ls --filter name=-net

# containers
docker run -d --name frontend --network frontend-net -p 8091:80 nginx:alpine
docker run -d --name backend  --network backend-net nginx:alpine
docker network connect frontend-net backend                     # backend now in 2 networks
docker run -d --name db --network db-net \
  -e MYSQL_ROOT_PASSWORD=rootpass123 -e MYSQL_DATABASE=demo mysql:8
docker network connect backend-net db

# which networks is each container in?
docker inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}={{$v.IPAddress}} {{end}}' backend
```

Output (captured 2026-10-07)
```text
NETWORK ID     NAME           DRIVER    SCOPE
2ed119022a27   backend-net    bridge    local
21f62777069c   db-net         bridge    local
01c04b06dcc0   frontend-net   bridge    local

frontend  -> frontend-net=172.19.0.2
backend   -> backend-net=172.20.0.2 frontend-net=172.19.0.3
db        -> backend-net=172.20.0.3 db-net=172.21.0.2
```

The subnets came out as 172.19/20/21 rather than 172.18/19/20 because another bridge network already existed on the machine and had taken 172.18.0.0/16. The same membership seen from the network side:

```bash
docker ps --filter name=frontend --filter name=backend --filter name=db \
  --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
for n in frontend-net backend-net db-net; do
  docker network inspect $n --format '{{.Name}} subnet={{(index .IPAM.Config 0).Subnet}} containers: {{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'
done
docker network inspect backend-net
```

Output (captured 2026-10-07; the full `docker network inspect backend-net` JSON is trimmed to the `Containers` section)
```text
NAMES      IMAGE          STATUS          PORTS
db         mysql:8        Up 43 seconds   3306/tcp, 33060/tcp
backend    nginx:alpine   Up 2 minutes    80/tcp
frontend   nginx:alpine   Up 2 minutes    0.0.0.0:8091->80/tcp, [::]:8091->80/tcp
frontend-net subnet=172.19.0.0/16 containers: frontend=172.19.0.2/16 backend=172.19.0.3/16
backend-net subnet=172.20.0.0/16 containers: backend=172.20.0.2/16 db=172.20.0.3/16
db-net subnet=172.21.0.0/16 containers: db=172.21.0.2/16
[
    {
        "Name": "backend-net",
        "Id": "2ed119022a276899860b410a0de8f06e24dc568e7817e0bf8e36dba25d7f5cc4",
        "Driver": "bridge",
        "IPAM": { "Config": [ { "Subnet": "172.20.0.0/16", "Gateway": "172.20.0.1" } ] },
        "Containers": {
            "971dd5024d38...": { "Name": "backend", "IPv4Address": "172.20.0.2/16" },
            "b1c63260cc92...": { "Name": "db",      "IPv4Address": "172.20.0.3/16" }
        }
    }
]
```

`backend` appears in both `frontend-net` and `backend-net`, which is the "backend in 2 networks" requirement; `db` appears in `backend-net` and `db-net`, and `frontend` only in `frontend-net`.

### Connectivity checks

```bash
# from backend (member of both networks) - everything should work
docker exec backend ping -c 2 frontend
docker exec backend wget -qO- http://frontend | grep -o "<title>.*</title>"
docker exec backend getent hosts db
docker exec backend nc -zv -w 3 db 3306

# from frontend - backend works, db must NOT be reachable
docker exec frontend getent hosts backend
docker exec frontend wget -qO- http://backend | grep -o "<title>.*</title>"
docker exec frontend getent hosts db
docker exec frontend ping -c 1 -W 2 db
```

Output (captured 2026-10-07)
```text
PING frontend (172.19.0.2): 56 data bytes
64 bytes from 172.19.0.2: seq=0 ttl=64 time=1.174 ms
64 bytes from 172.19.0.2: seq=1 ttl=64 time=0.053 ms

--- frontend ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 0.053/0.613/1.174 ms
<title>Welcome to nginx!</title>
172.20.0.3        db  db
db (172.20.0.3:3306) open

172.19.0.3        backend  backend
<title>Welcome to nginx!</title>
                                   <- getent hosts db prints nothing, exit code 2
ping: bad address 'db'
```

The script (`./task1-networking.sh`) wraps the failing commands so the run does not abort; its tail reads:

```text
--- getent hosts db (expected to FAIL: frontend is not in a network with db)
no DNS entry for db from frontend (expected)
--- ping db (expected to FAIL)
ping: bad address 'db'
frontend cannot reach db (expected)

=== Host access: curl http://localhost:8091 (frontend)
<title>Welcome to nginx!</title>
```

I observed that Docker's embedded DNS (127.0.0.11) only resolves names of containers that share a network with the caller. `backend` resolves both `frontend` and `db` because it sits in both networks; `frontend` cannot even resolve `db`, so the database is isolated from the web tier without any firewall rules. This is the same pattern as the course's `demo/docker-compose.yml` (frontend_net / backend_net).

Script version with MySQL readiness wait:

```bash
./task1-networking.sh
```

### Declarative version

`docker-compose.yml` expresses exactly the same topology (3 services, 3 networks, backend in two of them, MySQL healthcheck, named volume for `/var/lib/mysql`).

```bash
docker compose up -d
docker compose ps
docker compose exec backend getent hosts db
docker compose down -v
```

Output (captured 2026-10-07; `docker compose up -d` progress lines trimmed to the final state of each resource)
```text
 Volume session08-docker-networking-volume_db_data Created
 Network session08-docker-networking-volume_frontend-net Created
 Network session08-docker-networking-volume_backend-net Created
 Network session08-docker-networking-volume_db-net Created
 Container db Started
 Container frontend Started
 Container db Healthy
 Container backend Started
NAME       IMAGE          COMMAND                  SERVICE    CREATED         STATUS                   PORTS
backend    nginx:alpine   "/docker-entrypoint.…"   backend    5 seconds ago   Up Less than a second    80/tcp
db         mysql:8        "docker-entrypoint.s…"   db         5 seconds ago   Up 5 seconds (healthy)   3306/tcp, 33060/tcp
frontend   nginx:alpine   "/docker-entrypoint.…"   frontend   5 seconds ago   Up 5 seconds             0.0.0.0:8091->80/tcp, [::]:8091->80/tcp
172.20.0.2        db  db
```

`backend` only started after `db` reported `Healthy` (the `depends_on: condition: service_healthy`), and `docker compose exec frontend getent hosts db` exits with status 2 and prints nothing, the same isolation as in the manual version. `docker compose down -v` then removed the three containers, the three networks and the `db_data` volume.

## Task 2: Host Network

* Pull the Apache2 image from Docker Hub (`httpd:alpine` – the official Apache HTTP Server image).
* Create an Apache2 container using the host network (`--network host`).
* Access the Apache website directly on port 80.

```bash
docker pull httpd:alpine
docker run -d --name apache-host --network host httpd:alpine
docker ps --filter name=apache-host
docker port apache-host
curl http://localhost:80
```

Output (captured 2026-10-07, macOS with Docker running in a Colima VM)
```text
alpine: Pulling from library/httpd
Digest: sha256:3440c39d8d6f54fa9ad2549e5a60c19ddd435faadc29c1ad28aa795f71888889
Status: Image is up to date for httpd:alpine
docker.io/library/httpd:alpine
5196a08f940bce720541fd307f78b72a2de8a58fe387d710bf0afef86f057d71
NAMES         IMAGE          STATUS         PORTS
apache-host   httpd:alpine   Up 2 seconds
                                     <- docker port prints nothing: there is no mapping
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">
<html>
<head>
<title>It works! Apache httpd</title>
</head>
<body>
<p>It works!</p>
</body>
</html>
```

(`httpd:alpine` was already cached from Session 06, hence `Image is up to date`; `docker ps` is shown with `--format` because other, unrelated containers were running on the machine.)

With `--network host` the container has no network namespace of its own: it uses the host's interfaces, so httpd's `Listen 80` binds directly on the host and no `-p` is required (and `-p` is ignored with a warning). The `PORTS` column in `docker ps` is empty and `docker port apache-host` prints nothing. Because the container shares the host's network namespace, `netstat` inside it lists the *host's* listeners, with httpd among them:

```bash
docker exec apache-host netstat -ltnp | grep ':80 '
curl -sI http://localhost:80 | head -3
```

Output (captured 2026-10-07)
```text
tcp        0      0 :::80                   :::*                    LISTEN      1/httpd
HTTP/1.1 200 OK
Date: Wed, 07 Oct 2026 17:14:21 GMT
Server: Apache/2.4.69 (Unix)
```

**What actually happened on macOS.** I expected `curl localhost:80` on the Mac to fail, because on macOS the Docker engine runs inside a Linux VM and `--network host` means the *VM's* network, not the Mac's. It worked anyway: Colima (Lima) automatically forwards every port that starts listening in the VM to the Mac through an SSH tunnel (`lsof -iTCP:80` on the Mac shows an `ssh` process listening on `*:80`), so port 80 of the VM became port 80 of my Mac without any `-p`. The one oddity I hit is that *inside* the VM `wget http://127.0.0.1:80` returned `404 Not Found` while `wget http://[::1]:80` returned Apache's page; the Apache access log only shows the `::1` requests, so the IPv4 loopback is being answered by something else that the Colima VM runs on port 80 (it also has Kubernetes ports open). The Mac's forwarded connections arrive over `::1`, which is why `curl localhost:80` reaches Apache. On Docker Desktop (no automatic forwarding) the same command would give "connection refused" unless *Settings -> Resources -> Network -> Enable host networking* is turned on, and on a Linux host it simply works as a normal host listener (`ss -ltnp | grep ':80 '`).

Because the host-network path worked, the fallback branch of `task2-host-network.sh` did not run. I ran the portable alternative by hand so both variants are documented:

```bash
docker run -d --name apache-bridge -p 8080:80 httpd:alpine
docker ps --filter name=apache --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
curl -s http://localhost:8080 | grep -o '<p>.*</p>'
docker port apache-bridge
```

Output (captured 2026-10-07)
```text
62f00b3539a052e211a2e79483dd0c08b50942750540e55ca1684eecee4913ed
NAMES           IMAGE          STATUS              PORTS
apache-bridge   httpd:alpine   Up 2 seconds        0.0.0.0:8080->80/tcp, [::]:8080->80/tcp
apache-host     httpd:alpine   Up About a minute
<p>It works!</p>
80/tcp -> 0.0.0.0:8080
80/tcp -> [::]:8080
```

The two rows side by side show the difference: the bridge container has a published-port mapping, the host-network container has none and is reachable on the host's own port 80.

```bash
./task2-host-network.sh
```

## Task 3: Bind Mount

* Create a folder on your local machine: `bind-mount/html/`.
* Create an `index.html` file with `Hello students` as the content.
* Bind mount the folder to an Nginx container.
* Access the Nginx website and verify the content.
* Modify the `index.html` file.
* Verify that the changes are reflected without restarting the container.

```bash
mkdir -p bind-mount/html
echo '<h1>Hello students</h1>' > bind-mount/html/index.html

docker run -d --name nginx-bind -p 8082:80 \
  -v "$PWD/bind-mount/html:/usr/share/nginx/html:ro" nginx:alpine
curl http://localhost:8082

# edit on the host, container keeps running
echo '<h1>Hello students - file updated at 2026-10-07 22:30:00</h1>' > bind-mount/html/index.html
curl http://localhost:8082
docker ps --filter name=nginx-bind --format "table {{.Names}}\t{{.Status}}"
```

Output (captured 2026-10-07, from `./task3-bind-mount.sh`; the script also prints the mount from `docker inspect`)
```text
=== 1. Local folder and index.html
total 8
-rw-r--r--@ 1 ommalviya  staff  24 Oct  7 22:43 index.html
<h1>Hello students</h1>

=== 2. Run Nginx with the folder bind-mounted
b18ebfd8eb30374a524e2086e8196183f33eb041792ede66f1555c8812a5ee8b
bind: /Users/ommalviya/Desktop/DevOps/devops-heros/homework/session08-docker-networking-volume/bind-mount/html -> /usr/share/nginx/html (ro)

=== 3. Access the site
<h1>Hello students</h1>

=== 4. Modify index.html on the HOST (container is NOT restarted)
<h1>Hello students - file updated at 2026-10-07 22:43:49</h1>

=== 5. Access again - change is visible immediately
<h1>Hello students - file updated at 2026-10-07 22:43:49</h1>

--- container status (same uptime, no restart):
NAMES        STATUS         PORTS
nginx-bind   Up 2 seconds   0.0.0.0:8082->80/tcp, [::]:8082->80/tcp

=== 6. Restore the original content so the repo file stays 'Hello students'
<h1>Hello students</h1>
```

The second `curl` shows the new text and `STATUS` still says `Up 25 seconds` – the container was never restarted. A bind mount maps the host directory straight into the container's filesystem, so Nginx reads the file from my disk on every request. I mounted it read-only (`:ro`) because the container has no reason to write to my source folder. The script `task3-bind-mount.sh` performs these steps and finally restores the file to `Hello students` so the repository copy stays unchanged.

```bash
./task3-bind-mount.sh
```

Bind mount vs named volume (what I learned): a bind mount points at a path I choose on the host and is ideal for live-editing content/config during development; a named volume (`-v db_data:/var/lib/mysql`, as in the compose file) is managed by Docker under `/var/lib/docker/volumes` and is the right choice for database data that should survive container recreation but does not need to be edited from the host.

## Task 4: Overlay Network

* Research Docker overlay networks.
* Understand their use cases.
* Understand how overlay networks work across multiple Docker hosts.

### What it is
The `overlay` driver creates a single virtual Layer-2 network that spans several Docker hosts. Containers on different machines get IPs from one subnet and talk to each other by name as if they were on the same bridge. It is the networking driver used by Docker Swarm services (and it was the inspiration for the CNI overlays like Flannel/Calico VXLAN used in Kubernetes).

### How it works across hosts
1. **Control plane** – the hosts must be part of a Swarm (`docker swarm init` / `docker swarm join`). Swarm managers keep the network's IPAM state (which container has which IP on which host) in their Raft store, and nodes exchange it over the gossip protocol (TCP/UDP **7946**).
2. **Data plane: VXLAN** – each container's Ethernet frame is wrapped in a UDP packet (port **4789**) with a 24-bit VXLAN Network Identifier and sent to the physical IP of the host that runs the destination container. There it is unwrapped and delivered to the container's `veth`. The containers never see the underlay.
3. **Service discovery** – the embedded DNS resolves service/container names to overlay IPs; for swarm services a virtual IP plus IPVS load-balances across replicas, and the `ingress` overlay network provides the routing mesh so any node can accept a published port.
4. **Encryption (optional)** – `--opt encrypted` turns on IPsec between the hosts' VXLAN tunnels.
5. Each host also has a `docker_gwbridge` bridge that gives overlay-attached containers outbound (NAT) access to the outside world.

```
 Host A (10.0.0.11)                            Host B (10.0.0.12)
 +---------------------------+                 +---------------------------+
 | web.1  10.10.0.2          |                 | api.1  10.10.0.3          |
 |   |  veth                 |                 |   |  veth                 |
 | [br0 overlay my-overlay]  |                 | [br0 overlay my-overlay]  |
 |   | vxlan0 (VNI 4097)     |   UDP 4789      |   | vxlan0 (VNI 4097)     |
 |   +-- eth0 ---------------|=================|-------------- eth0 --+    |
 +---------------------------+  encapsulated   +---------------------------+
                       gossip/control: TCP+UDP 7946 between nodes
```

### Commands

```bash
docker swarm init --advertise-addr <manager-ip>
# on the other hosts: docker swarm join --token <token> <manager-ip>:2377

docker network create -d overlay --attachable my-overlay
docker network create -d overlay --opt encrypted --subnet 10.10.0.0/24 secure-overlay
docker network ls --filter driver=overlay

# standalone container on an attachable overlay (any node)
docker run -d --name web --network my-overlay nginx:alpine
# swarm service spread across nodes
docker service create --name api --network my-overlay --replicas 3 nginx:alpine
docker exec web getent hosts api        # resolves to the service VIP
docker network inspect my-overlay       # shows Peers (the hosts) and containers on this node
```

Expected output (I could not capture this one: an overlay network needs Swarm mode and at least two Docker hosts, and I did not want to turn the single-node Colima daemon into a Swarm manager just for a listing)
```text
NETWORK ID     NAME             DRIVER    SCOPE
k3h9x2v8qp1a   ingress          overlay   swarm
p7r2s9t4u6w1   my-overlay       overlay   swarm
d4e5f6a7b8c9   secure-overlay   overlay   swarm
10.10.0.5         api
```

### Use cases
* Multi-host deployments: a stack whose frontend, API and database run on different machines but must see each other by name.
* Swarm services with replicas on several nodes, plus the ingress routing mesh for published ports.
* Isolating tenants/applications on a shared cluster (one overlay per stack).
* Encrypted east-west traffic between hosts (`--opt encrypted`) without touching the physical network.

### Overlay vs bridge

| | bridge (default / user-defined) | overlay |
|---|---|---|
| Scope | one host (`SCOPE local`) | many hosts (`SCOPE swarm`) |
| Requires | nothing | Swarm mode (managers for state, ports 2377/7946/4789 open) |
| Encapsulation | none, plain Linux bridge + NAT | VXLAN over UDP 4789 |
| Name resolution | embedded DNS between containers on the same bridge | embedded DNS + service VIPs across all nodes |
| Performance | fastest | small overhead for encapsulation (more with encryption) |
| Typical use | local dev, single-server apps, docker compose on one machine (Tasks 1–3 here) | production clusters, services spread across nodes |

**When to use which:** everything in this homework runs on one host, so user-defined bridge networks are the right tool – they already give me DNS and isolation. I would switch to overlay only when containers must communicate across more than one Docker host (Swarm), or when I need encrypted inter-host traffic without changing the underlying network.

## Cleanup

```bash
./cleanup.sh
```

Output (captured 2026-10-07)
```text
container frontend not present
container backend not present
container db not present
container apache-host not present
container apache-bridge not present
container nginx-bind not present
network frontend-net not present
network backend-net not present
network db-net not present
compose project not running
```

Everything reports "not present" because I had already torn each task down as I went (`docker rm -f` + `docker network rm` after Task 1, `docker compose down -v`, and the Apache/Nginx containers after Tasks 2 and 3); when the resources exist the script prints `removed container <name>` / `removed network <name>` / `compose project removed` instead. While writing the script I found that `docker rm -f` exits 0 even for a container that does not exist, so the script checks `docker container inspect` first instead of relying on the exit code of `rm -f`.

## Screenshots

| Screenshot required | Stands in |
|---|---|
| 3 networks, 3 containers, backend in 2 networks | `docker network ls` / `docker inspect` / `docker network inspect` captured output in Task 1 |
| Connectivity between containers | ping / wget / getent / nc captured output in Task 1 |
| Apache on host network, port 80 | `docker ps` + `curl http://localhost:80` captured output in Task 2 |
| Bind mount before/after edit | two `curl` outputs + `docker ps` status captured in Task 3 |
| Overlay research | Task 4 text, diagram and comparison table |

## Deliverables

* `task1-networking.sh` – creates 3 networks + frontend/backend/db, connects backend to 2 networks, runs all connectivity checks (Task 1)
* `docker-compose.yml` – the same Task 1 topology declaratively, with MySQL healthcheck and named volume
* `task2-host-network.sh` – httpd on `--network host`, port 80 check, macOS fallback (Task 2)
* `bind-mount/html/index.html` – the `Hello students` page; `task3-bind-mount.sh` – mount, edit, verify live, restore (Task 3)
* `cleanup.sh` – removes all containers and networks created above
* `README.md` – this file, including the Task 4 overlay network research
