# Session 07 – Docker Multi-Stage Build
Student: Om Malviya | Enrollment No: 24BCS10448

## Task 1: Run Multi-Stage Dockerfile

* Clone the repository containing the multi-stage Dockerfile.
* Build the Docker image using the multi-stage Dockerfile.
* Run a container from the image.
* Access the application running inside the container.
* Verify that the application displays: `Hello World from Docker multi-stage build`
* Verify the running container using `docker ps`.
* Confirm that the application is running on port 8080.

### Clone the repository

```bash
git clone https://github.com/Nency-Ravaliya/devops-heros.git
cd devops-heros/session6-7-docker/multi-stage-dockerfile
ls
```

Output (captured 2026-10-07)
```text
Dockerfile
package.json
server.js
```

When I read the course version I noticed two differences from the task text: `server.js` listened on port **3000** and printed `Hello World from Docker Multi-Stage Build!`. The task requires port **8080** and the exact text `Hello World from Docker multi-stage build`, so I copied the app into `multi-stage-app/` and changed the port, the message and the `EXPOSE` line. I also updated the base image to `node:22-alpine`, added `npm cache clean`, `NODE_ENV=production` and `USER node` in the production stage.

### Build

```bash
cd homework/session07-docker-multistage
docker build -t multistage-app:1.0 ./multi-stage-app
```

Output (captured 2026-10-07; the Docker CLI on this machine has no buildx plugin, so the legacy builder prints `Step n/m` lines. The npm "new version available" notices and the `Running in` / `Removed intermediate container` lines are trimmed.)
```text
Sending build context to Docker daemon  5.632kB
Step 1/14 : FROM node:22-alpine AS builder
 ---> 0a7108bf6c7b
Step 2/14 : WORKDIR /app
 ---> Using cache
 ---> fde7941e4084
Step 3/14 : COPY package*.json ./
 ---> 4e9a8b9fd427
Step 4/14 : RUN npm install

added 68 packages, and audited 69 packages in 18s

28 packages are looking for funding
  run `npm fund` for details

found 0 vulnerabilities
 ---> 306eb8c35fa0
Step 5/14 : COPY . .
 ---> 93a67c77e3e3
Step 6/14 : FROM node:22-alpine AS production
 ---> 0a7108bf6c7b
Step 7/14 : ENV NODE_ENV=production
 ---> 407686e4247e
Step 8/14 : WORKDIR /app
 ---> 0fc8c98f1d8f
Step 9/14 : COPY --from=builder /app/package*.json ./
 ---> 56df9030aa1c
Step 10/14 : RUN npm install --omit=dev && npm cache clean --force

added 68 packages, and audited 69 packages in 3s

28 packages are looking for funding
  run `npm fund` for details

found 0 vulnerabilities
npm warn using --force Recommended protections disabled.
 ---> 0b90fa2a3cfd
Step 11/14 : COPY --from=builder /app/server.js ./
 ---> 75b990976809
Step 12/14 : USER node
 ---> 73eb65a9c064
Step 13/14 : EXPOSE 8080
 ---> a71650d7a0dc
Step 14/14 : CMD ["node", "server.js"]
 ---> 57c59512d6e6
Successfully built 57c59512d6e6
Successfully tagged multistage-app:1.0
```

Steps 1–5 are the `builder` stage and steps 6–14 the `production` stage; the second `FROM` (step 6) starts again from the bare `node:22-alpine` layer `0a7108bf6c7b`, which is why nothing from the builder's `npm install` survives except what `COPY --from=builder` brings over.

### Run and access

```bash
docker run -d --name multistage-app -p 8080:8080 multistage-app:1.0
curl http://localhost:8080
```

Output (captured 2026-10-07)
```text
6270600ab8eb7ccdcf8cd5a2e4ef2883c4b7a837631612b71c51fd92dfe22b50
<h1>Hello World from Docker multi-stage build</h1>
```

Opening http://localhost:8080 in the browser shows the heading **Hello World from Docker multi-stage build**.

### docker ps – container running on port 8080

```bash
docker ps
```

Output (captured 2026-10-07; `docker ps --filter name=multistage-app` – other, unrelated containers from another session were running on the machine and are filtered out)
```text
CONTAINER ID   IMAGE                COMMAND                  CREATED         STATUS         PORTS                                         NAMES
6270600ab8eb   multistage-app:1.0   "docker-entrypoint.s…"   3 seconds ago   Up 3 seconds   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp   multistage-app
```

The `PORTS` column `0.0.0.0:8080->8080/tcp` confirms the app is served on port 8080. Everything above is wrapped in `./run-multistage.sh`.

## Task 2: Documentation

* Name: **Om Malviya**
* Enrollment number: **24BCS10448**
* Output showing the application running successfully: the `curl http://localhost:8080` block in Task 1 (`<h1>Hello World from Docker multi-stage build</h1>`).
* Output of `docker ps` showing the running container on port 8080: the `docker ps` block in Task 1.

### What a multi-stage build is (in my words)

A multi-stage Dockerfile has more than one `FROM`. Each `FROM` starts a new, empty stage. Earlier stages are used to compile/bundle/install, and the last stage copies only the finished artefacts with `COPY --from=<stage>`. Only the final stage becomes the image that is tagged and pushed; everything else is thrown away after the build.

Why the image size drops:

1. **Build tools stay behind** – compilers (JDK, gcc), bundlers (Vite, webpack), `npm`/`pip` caches are only in the builder stage.
2. **Dev dependencies are not shipped** – the production stage runs `npm install --omit=dev`, so test frameworks and linters are not in the image.
3. **Source code and intermediate files are dropped** – only `server.js` (or `.class` files / `dist/`) is copied.
4. **Smaller runtime base** – the last stage can use a lighter base (`eclipse-temurin:21-jre-alpine` instead of `-jdk-alpine`, `nginx:alpine` instead of `node:22-alpine`).
5. **Fewer layers = fewer leftovers** – a single-stage image keeps every layer, including the one that downloaded the cache you later `rm -rf`'d.

Size comparison (measured on the day of the build; the exact numbers depend on the base image versions):

```bash
docker images
```

Output (captured 2026-10-07; filtered to the relevant images – the machine also had unrelated images from other sessions)
```text
REPOSITORY                         TAG                     IMAGE ID       CREATED              SIZE
multistage-app                     1.0                     57c59512d6e6   38 seconds ago       243MB
hello-nginx                        1.0                     b7149c70a341   2 minutes ago        93MB
hello-react                        1.0                     2a5927112408   2 minutes ago        93.2MB
hello-java                         1.0                     2cc7f27444e4   3 minutes ago        286MB
hello-python                       1.0                     3b7fc568c351   4 minutes ago        223MB
hello-nodejs                       1.0                     3fcb15714bb5   4 minutes ago        234MB
eclipse-temurin                    21-jre-alpine           51ab5e3302e7   11 days ago          287MB
eclipse-temurin                    21-jdk-alpine           0bfc69a4758a   11 days ago          556MB
node                               22-alpine               0a7108bf6c7b   13 days ago          234MB
nginx                              alpine                  df221db836e1   2 weeks ago          93.9MB
```

What the real numbers show (Docker 29 reports uncompressed disk usage, so everything is larger than the compressed sizes on Docker Hub, but the ratios are what matter):

* `multistage-app:1.0` is 243 MB against 234 MB for bare `node:22-alpine` – only 9 MB for Express and its production dependencies. `npm install` in the builder stage pulled the same 68 packages, but that stage's layers are not part of the tagged image.
* `hello-java:1.0` is 286 MB, essentially the size of `eclipse-temurin:21-jre-alpine` (287 MB). The JDK builder image is 556 MB, so copying only the `.class` file into the JRE stage saves ~270 MB (almost half).
* `hello-react:1.0` is 93.2 MB, 0.2 MB more than `nginx:alpine`; a single-stage image that kept the `node:22-alpine` builder plus `node_modules` would have been well over 234 MB, so the multi-stage build cuts it by more than 2.5x.

For this particular Node app both stages use the same base, so the saving is mainly the dev-dependency tree and npm cache. The Java and React apps from Session 06 show the big win: JDK → JRE roughly halves the image, and Node → Nginx cuts it by ~6x.

## Task 3: Docker Application Deployment

Deploy at least 3 different types of applications using Docker:

* Node.js – `../session06-docker-hello-world/nodejs-app` (plain `http` module, port 3000)
* Python – `../session06-docker-hello-world/python-app` (Flask, port 5000)
* Java – `../session06-docker-hello-world/java-app` (Java 21 `HttpServer`, multi-stage JDK→JRE, port 8080)

I reuse the Dockerfiles I wrote in Session 06 rather than duplicating them. `./deploy-three-apps.sh` builds all three, runs them on host ports 3001/3002/3003 and curls each.

```bash
./deploy-three-apps.sh
```

Output (captured 2026-10-07; the `Running in ...` / `Removed intermediate container` lines of the legacy builder are trimmed – everything else is verbatim)
```text
=== Building hello-nodejs:1.0 from ../session06-docker-hello-world/nodejs-app
Sending build context to Docker daemon  6.144kB
Step 1/6 : FROM node:22-alpine
 ---> 0a7108bf6c7b
Step 2/6 : WORKDIR /app
 ---> fde7941e4084
Step 3/6 : COPY package.json server.js ./
 ---> 2cfb588bf1a2
Step 4/6 : USER node
 ---> 0c16f5b2cbc4
Step 5/6 : EXPOSE 3000
 ---> 1c16c212826c
Step 6/6 : CMD ["node", "server.js"]
 ---> 3fcb15714bb5
Successfully built 3fcb15714bb5
Successfully tagged hello-nodejs:1.0
=== Building hello-python:1.0 from ../session06-docker-hello-world/python-app
Sending build context to Docker daemon  6.144kB
Step 1/7 : FROM python:3.12-slim
 ---> 05cda9777409
Step 2/7 : WORKDIR /app
 ---> 18c665287da2
Step 3/7 : COPY requirements.txt .
 ---> 4e13733cecd6
Step 4/7 : RUN pip install --no-cache-dir -r requirements.txt
 ---> 97d402125505
Step 5/7 : COPY app.py .
 ---> 35e96b652e59
Step 6/7 : EXPOSE 5000
 ---> e0e771146132
Step 7/7 : CMD ["python", "app.py"]
 ---> 3b7fc568c351
Successfully built 3b7fc568c351
Successfully tagged hello-python:1.0
=== Building hello-java:1.0 from ../session06-docker-hello-world/java-app
Sending build context to Docker daemon  5.632kB
Step 1/9 : FROM eclipse-temurin:21-jdk-alpine AS build
 ---> 0bfc69a4758a
Step 2/9 : WORKDIR /src
 ---> a9c395b07190
Step 3/9 : COPY HelloWorld.java .
 ---> 5301f4d9084c
Step 4/9 : RUN javac -d /out HelloWorld.java
 ---> 8bdcf0b49cf6
Step 5/9 : FROM eclipse-temurin:21-jre-alpine
 ---> 51ab5e3302e7
Step 6/9 : WORKDIR /app
 ---> 218f3cebf536
Step 7/9 : COPY --from=build /out /app
 ---> 833170b021f8
Step 8/9 : EXPOSE 8080
 ---> 2743640e8852
Step 9/9 : CMD ["java", "-cp", "/app", "HelloWorld"]
 ---> 2cc7f27444e4
Successfully built 2cc7f27444e4
Successfully tagged hello-java:1.0

=== Running hello-nodejs on http://localhost:3001
bd16521f80d3173ddf27fee7633f406b3471f3325d8781ea47d8d810d9531c11
=== Running hello-python on http://localhost:3002
70dd121f56eee06b4bbbd820bc7bac3349b8af992ee018bcdf606b6a2168c013
=== Running hello-java on http://localhost:3003
868b98716f76c04272bcbcba09a394b9017d734ced426bb3d6d8a0e57d3fb55e

=== Waiting for apps to start...

NAMES          IMAGE              STATUS         PORTS
hello-java     hello-java:1.0     Up 3 seconds   0.0.0.0:3003->8080/tcp, [::]:3003->8080/tcp
hello-python   hello-python:1.0   Up 3 seconds   0.0.0.0:3002->5000/tcp, [::]:3002->5000/tcp
hello-nodejs   hello-nodejs:1.0   Up 3 seconds   0.0.0.0:3001->3000/tcp, [::]:3001->3000/tcp

=== curl http://localhost:3001  (hello-nodejs)
<h1>Hello World from Node.js in Docker!</h1>
=== curl http://localhost:3002  (hello-python)
<h1>Hello World from Python (Flask) in Docker!</h1>
=== curl http://localhost:3003  (hello-java)
<h1>Hello World from Java in Docker!</h1>

=== Image sizes
REPOSITORY     TAG       SIZE
hello-nginx    1.0       93MB
hello-react    1.0       93.2MB
hello-apache   1.0       115MB
hello-java     1.0       286MB
hello-python   1.0       223MB
hello-nodejs   1.0       234MB
```

The builds were instant (`---> <id>` with no `Running in` lines) because every layer was already cached from Session 06; the size table also lists the other three Session 06 images because the filter is `reference=hello-*`.

Manual equivalent:

```bash
docker build -t hello-nodejs:1.0 ../session06-docker-hello-world/nodejs-app
docker build -t hello-python:1.0 ../session06-docker-hello-world/python-app
docker build -t hello-java:1.0   ../session06-docker-hello-world/java-app
docker run -d --name hello-nodejs -p 3001:3000 hello-nodejs:1.0
docker run -d --name hello-python -p 3002:5000 hello-python:1.0
docker run -d --name hello-java   -p 3003:8080 hello-java:1.0
curl http://localhost:3001; curl http://localhost:3002; curl http://localhost:3003
```

## Cleanup

```bash
./cleanup.sh
```

Output (captured 2026-10-07)
```text
removed multistage-app
removed hello-nodejs
removed hello-python
removed hello-java
```

## Screenshots

| Screenshot required | Stands in |
|---|---|
| Application running successfully (Task 1/2) | `curl http://localhost:8080` captured output block |
| `docker ps` showing port 8080 (Task 1/2) | `docker ps` captured output block in Task 1 |
| Three applications deployed (Task 3) | `./deploy-three-apps.sh` captured output block |

## Deliverables

* `multi-stage-app/` – `Dockerfile` (two stages), `server.js` (port 8080, exact message), `package.json`, `.dockerignore`
* `run-multistage.sh` – build + run + curl + `docker ps` for Task 1
* `deploy-three-apps.sh` – builds and runs the Node.js, Python and Java apps from Session 06 (Task 3)
* `cleanup.sh` – removes all containers started by the scripts
* `README.md` – this file (Task 2 documentation: name, enrollment number, outputs, multi-stage explanation)
