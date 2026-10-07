# Session 06 – Docker Hello World Applications
Student: Om Malviya | Enrollment No: 24BCS10448

## Task: Hello World Applications

Create simple Hello World web applications using Docker for:

* Node.js application – `nodejs-app/` (plain `http` module, no framework)
* Python application – `python-app/` (Flask)
* Java application – `java-app/` (Java 21, JDK built-in `HttpServer`, multi-stage Dockerfile)
* Apache web server – `Apache-app/` (httpd static page)
* React application – `React-app/` (Vite + React, multi-stage: Node build, Nginx serve)
* Nginx application – `nginx-app/` (static page)

For each application I did the following (the spec requirements):

* Created a separate folder with the exact name required (`nodejs-app`, `python-app`, `java-app`, `Apache-app`, `React-app`, `nginx-app`).
* Added the application code.
* Created a Dockerfile.
* Build the Docker image (`docker build`, see table and `build-all.sh`).
* Run the application using Docker (`docker run -d -p ...`, see `run-all.sh`).
* Verify that Hello World is displayed on a web page (`curl` / browser, outputs below).

## Overview table

Each app listens on its own port inside the container. To run all six at the same time I map them to host ports 3001–3006 so nothing clashes.

| App | Folder | Container port | Host port | Image | Build command | Run command | Verify command |
|-----|--------|----------------|-----------|-------|---------------|-------------|----------------|
| Node.js | `nodejs-app/` | 3000 | 3001 | `hello-nodejs:1.0` | `docker build -t hello-nodejs:1.0 nodejs-app` | `docker run -d --name hello-nodejs -p 3001:3000 hello-nodejs:1.0` | `curl http://localhost:3001` |
| Python (Flask) | `python-app/` | 5000 | 3002 | `hello-python:1.0` | `docker build -t hello-python:1.0 python-app` | `docker run -d --name hello-python -p 3002:5000 hello-python:1.0` | `curl http://localhost:3002` |
| Java 21 | `java-app/` | 8080 | 3003 | `hello-java:1.0` | `docker build -t hello-java:1.0 java-app` | `docker run -d --name hello-java -p 3003:8080 hello-java:1.0` | `curl http://localhost:3003` |
| Apache httpd | `Apache-app/` | 80 | 3004 | `hello-apache:1.0` | `docker build -t hello-apache:1.0 Apache-app` | `docker run -d --name hello-apache -p 3004:80 hello-apache:1.0` | `curl http://localhost:3004` |
| React (Vite) | `React-app/` | 80 | 3005 | `hello-react:1.0` | `docker build -t hello-react:1.0 React-app` | `docker run -d --name hello-react -p 3005:80 hello-react:1.0` | `curl http://localhost:3005` |
| Nginx | `nginx-app/` | 80 | 3006 | `hello-nginx:1.0` | `docker build -t hello-nginx:1.0 nginx-app` | `docker run -d --name hello-nginx -p 3006:80 hello-nginx:1.0` | `curl http://localhost:3006` |

All commands are run from this folder (`homework/session06-docker-hello-world`).

## Helper scripts

```bash
./build-all.sh        # docker build for all six images
./run-all.sh          # docker run all six (ports 3001-3006), then docker ps + curl each
./stop-all.sh         # docker rm -f all six containers (add --images to also delete the images)
```

## How each app works

### nodejs-app
`server.js` uses only Node's built-in `http` module, so there is nothing to `npm install`. The Dockerfile is `FROM node:22-alpine`, copies `package.json` and `server.js`, switches to the unprivileged `node` user and runs `node server.js` on port 3000. I kept it Express-free so the image contains exactly two files of mine plus the Node runtime.

### python-app
`app.py` is a Flask app with a single `/` route; `app.run(host="0.0.0.0", port=5000)` is important because binding to `127.0.0.1` inside a container is not reachable through the published port. `requirements.txt` is copied and installed before `app.py` so the pip layer is cached when only code changes.

### java-app
`HelloWorld.java` uses `com.sun.net.httpserver.HttpServer` from the JDK, so no Maven or external jar is needed. The Dockerfile is multi-stage: `eclipse-temurin:21-jdk-alpine` runs `javac`, then only the compiled `.class` file is copied into `eclipse-temurin:21-jre-alpine`. The final image has no compiler or source code and is roughly half the size of the JDK image.

### Apache-app
A static `index.html` copied into `/usr/local/apache2/htdocs/`, which is the document root of the official `httpd:alpine` image. The base image already has the right `CMD` (`httpd-foreground`), so my Dockerfile only needs `COPY` and `EXPOSE 80`.

### React-app
A minimal Vite project (`package.json`, `index.html`, `vite.config.js`, `src/main.jsx`, `src/App.jsx`). Stage 1 (`node:22-alpine`) runs `npm install` and `npm run build`, which produces the static bundle in `dist/`. Stage 2 (`nginx:alpine`) serves `dist/` with a small `nginx.conf` that falls back to `index.html` for SPA routes. `node_modules` is in `.dockerignore`, so dependencies are only ever installed inside the build stage and the final image contains no Node.js at all.

### nginx-app
Same idea as Apache: static `index.html` copied into `/usr/share/nginx/html/`, the default root of `nginx:alpine`.

## Local checks I could run without Docker

I compiled and ran the Java and Node apps directly on my machine to be sure the code itself is correct before building images.

```bash
javac -d /tmp/hello-java java-app/HelloWorld.java
PORT=18080 java -cp /tmp/hello-java HelloWorld &
curl -s -i http://localhost:18080
kill %1
```

Output (captured 2026-10-07)
```text
HTTP/1.1 200 OK
Date: Wed, 07 Oct 2026 16:57:24 GMT
Content-type: text/html; charset=utf-8
Content-length: 42

<h1>Hello World from Java in Docker!</h1>
Java server listening on port 18080
```

```bash
PORT=13000 node nodejs-app/server.js &
curl -s -i http://localhost:13000
kill %1
```

Output (captured 2026-10-07)
```text
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Date: Wed, 07 Oct 2026 16:57:25 GMT
Connection: keep-alive
Keep-Alive: timeout=5
Transfer-Encoding: chunked

<h1>Hello World from Node.js in Docker!</h1>
Node.js server listening on port 13000
```

`python3 -m py_compile python-app/app.py` also passed (syntax check only; Flask itself is installed inside the image).

## Building the images

```bash
./build-all.sh
```

Output (captured 2026-10-07; trimmed – the full log is ~340 lines, I kept the first build in full, the `Successfully tagged` line of every build and the final size table. The Docker CLI on this machine has no buildx plugin, so the legacy builder prints `Step n/m` lines instead of the BuildKit `=>` lines.)
```text
=== Building hello-nodejs:1.0 from ./nodejs-app
Sending build context to Docker daemon  6.144kB
Step 1/6 : FROM node:22-alpine
22-alpine: Pulling from library/node
66fa63c7a061: Pull complete
a9986cd6f37d: Pull complete
87919ed734a3: Pull complete
74849c662da7: Pull complete
Digest: sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402
Status: Downloaded newer image for node:22-alpine
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
=== Building hello-python:1.0 from ./python-app
...
Successfully tagged hello-python:1.0
=== Building hello-java:1.0 from ./java-app
Step 1/9 : FROM eclipse-temurin:21-jdk-alpine AS build
...
Step 7/9 : COPY --from=build /out /app
Step 8/9 : EXPOSE 8080
...
Successfully tagged hello-java:1.0
=== Building hello-apache:1.0 from ./Apache-app
...
Successfully tagged hello-apache:1.0
=== Building hello-react:1.0 from ./React-app
Step 1/11 : FROM node:22-alpine AS build
...
Step 7/11 : RUN npm run build
...
Step 8/11 : FROM nginx:alpine
...
Step 10/11 : COPY --from=build /app/dist /usr/share/nginx/html
Step 11/11 : EXPOSE 80
Successfully built 2a5927112408
Successfully tagged hello-react:1.0
=== Building hello-nginx:1.0 from ./nginx-app
Sending build context to Docker daemon  4.096kB
Step 1/3 : FROM nginx:alpine
 ---> df221db836e1
Step 2/3 : COPY index.html /usr/share/nginx/html/index.html
 ---> af2225236fb4
Step 3/3 : EXPOSE 80
 ---> b7149c70a341
Successfully built b7149c70a341
Successfully tagged hello-nginx:1.0

=== Images built:
REPOSITORY     TAG       SIZE
hello-nginx    1.0       93MB
hello-react    1.0       93.2MB
hello-apache   1.0       115MB
hello-java     1.0       286MB
hello-python   1.0       223MB
hello-nodejs   1.0       234MB
```

The sizes are a bit larger than I had estimated because Docker 29 reports the uncompressed *disk usage* of every layer. `docker images --filter reference=hello-*` shows both columns:

```bash
docker images --filter "reference=hello-*"
```

Output (captured 2026-10-07)
```text
IMAGE              ID             DISK USAGE   CONTENT SIZE   EXTRA
hello-apache:1.0   096bd751ffcc        115MB           24MB   U
hello-java:1.0     2cc7f27444e4        286MB         73.4MB   U
hello-nginx:1.0    b7149c70a341         93MB         26.3MB   U
hello-nodejs:1.0   3fcb15714bb5        234MB         61.1MB   U
hello-python:1.0   3b7fc568c351        223MB         48.5MB   U
hello-react:1.0    2a5927112408       93.2MB         26.3MB   U
```

The two Nginx-based images (`hello-nginx`, `hello-react`) are the smallest; the React image is only 0.2 MB bigger than plain Nginx because the whole Node toolchain stayed in the build stage.

## Running the containers

```bash
./run-all.sh
```

Output (captured 2026-10-07)
```text
=== Starting hello-nodejs on http://localhost:3001 (container port 3000)
4119c1c9d8b7fe65af18e6bd1d3baceb1480fab294cfbae0b76d88af0a29c88e
=== Starting hello-python on http://localhost:3002 (container port 5000)
75e7b8f1641a1d9b3e193078a502762cfa8baf57938bc201b6d2f5cdc52f348c
=== Starting hello-java on http://localhost:3003 (container port 8080)
ddbffdac701209f2dc5d503beb76e2629812181b3a254091e86d401d4763a921
=== Starting hello-apache on http://localhost:3004 (container port 80)
895ccda3c5e79fb0d1274e32236cd4df9a2cd8c2333b87fd69cb2b6c7d6693b6
=== Starting hello-react on http://localhost:3005 (container port 80)
7b557c595e0446fbd5222e36a0fdbeff1c9711be62c928b9131689853ad587cf
=== Starting hello-nginx on http://localhost:3006 (container port 80)
7105a0cef7c43f98cb352197b4057dc8c54906687faf82c419420ede925b7952

=== Waiting for the apps to start...

NAMES          IMAGE              STATUS         PORTS
hello-nginx    hello-nginx:1.0    Up 3 seconds   0.0.0.0:3006->80/tcp, [::]:3006->80/tcp
hello-react    hello-react:1.0    Up 3 seconds   0.0.0.0:3005->80/tcp, [::]:3005->80/tcp
hello-apache   hello-apache:1.0   Up 3 seconds   0.0.0.0:3004->80/tcp, [::]:3004->80/tcp
hello-java     hello-java:1.0     Up 3 seconds   0.0.0.0:3003->8080/tcp, [::]:3003->8080/tcp
hello-python   hello-python:1.0   Up 3 seconds   0.0.0.0:3002->5000/tcp, [::]:3002->5000/tcp
hello-nodejs   hello-nodejs:1.0   Up 3 seconds   0.0.0.0:3001->3000/tcp, [::]:3001->3000/tcp

=== curl http://localhost:3001  (hello-nodejs)
<h1>Hello World from Node.js in Docker!</h1>
=== curl http://localhost:3002  (hello-python)
<h1>Hello World from Python (Flask) in Docker!</h1>
=== curl http://localhost:3003  (hello-java)
<h1>Hello World from Java in Docker!</h1>
=== curl http://localhost:3004  (hello-apache)
<title>Hello World - Apache</title>
<h1>Hello World from Apache httpd in Docker!</h1>
=== curl http://localhost:3005  (hello-react)
<title>Hello World - React</title>
=== curl http://localhost:3006  (hello-nginx)
<title>Hello World - Nginx</title>
<h1>Hello World from Nginx in Docker!</h1>
```

Note on React: the raw HTML returned by curl only contains `<div id="root">`; the "Hello World from React in Docker!" heading is rendered by the JavaScript bundle, so it is visible in the browser at http://localhost:3005. From the terminal it can be confirmed inside the bundle:

```bash
curl -s http://localhost:3005/assets/$(curl -s http://localhost:3005 | grep -o 'index-[^"]*\.js') | grep -o 'Hello World from React in Docker!'
```

Output (captured 2026-10-07)
```text
Hello World from React in Docker!
```

## Verifying individual apps

```bash
docker ps
curl http://localhost:3001
```

Output (captured 2026-10-07)
```text
CONTAINER ID   IMAGE              COMMAND                  CREATED         STATUS         PORTS                                         NAMES
7105a0cef7c4   hello-nginx:1.0    "/docker-entrypoint.…"   9 seconds ago   Up 8 seconds   0.0.0.0:3006->80/tcp, [::]:3006->80/tcp       hello-nginx
7b557c595e04   hello-react:1.0    "/docker-entrypoint.…"   9 seconds ago   Up 8 seconds   0.0.0.0:3005->80/tcp, [::]:3005->80/tcp       hello-react
895ccda3c5e7   hello-apache:1.0   "httpd-foreground"       9 seconds ago   Up 9 seconds   0.0.0.0:3004->80/tcp, [::]:3004->80/tcp       hello-apache
ddbffdac7012   hello-java:1.0     "/__cacert_entrypoin…"   9 seconds ago   Up 9 seconds   0.0.0.0:3003->8080/tcp, [::]:3003->8080/tcp   hello-java
75e7b8f1641a   hello-python:1.0   "python app.py"          9 seconds ago   Up 9 seconds   0.0.0.0:3002->5000/tcp, [::]:3002->5000/tcp   hello-python
4119c1c9d8b7   hello-nodejs:1.0   "docker-entrypoint.s…"   9 seconds ago   Up 9 seconds   0.0.0.0:3001->3000/tcp, [::]:3001->3000/tcp   hello-nodejs
<h1>Hello World from Node.js in Docker!</h1>
```

## Stopping everything

```bash
./stop-all.sh
```

Output (captured 2026-10-07)
```text
removed hello-nodejs
removed hello-python
removed hello-java
removed hello-apache
removed hello-react
removed hello-nginx
```

## What I observed / learned

* `EXPOSE` in a Dockerfile is documentation only; the real mapping is `-p host:container` at run time, which is why I can run six apps on six different host ports.
* Servers must bind `0.0.0.0` (Flask, Node, Java) or they are not reachable through the published port.
* Static servers (Apache, Nginx) need no `CMD` of my own – the official image already starts the daemon in the foreground.
* Multi-stage builds (Java, React) keep build tools out of the final image: JDK -> JRE, Node -> Nginx.

## Screenshots

Terminal output blocks stand in for screenshots:

| Screenshot required | Stands in |
|---|---|
| Image build | "Building the images" captured output |
| Containers running (`docker ps`) | "Running the containers" / "Verifying individual apps" captured output |
| Hello World in browser, per app | `curl` output per app in "Running the containers"; captured Java/Node local runs in "Local checks" |

## Deliverables

* `nodejs-app/` – `server.js`, `package.json`, `Dockerfile`, `.dockerignore`, `README.md` (Node.js http server, port 3000)
* `python-app/` – `app.py`, `requirements.txt`, `Dockerfile`, `.dockerignore`, `README.md` (Flask, port 5000)
* `java-app/` – `HelloWorld.java`, multi-stage `Dockerfile`, `README.md` (Java 21 HttpServer, port 8080)
* `Apache-app/` – `index.html`, `Dockerfile`, `README.md` (httpd:alpine, port 80)
* `React-app/` – Vite project (`package.json`, `index.html`, `vite.config.js`, `src/`), `nginx.conf`, multi-stage `Dockerfile`, `.dockerignore`, `README.md` (port 80)
* `nginx-app/` – `index.html`, `Dockerfile`, `README.md` (nginx:alpine, port 80)
* `build-all.sh`, `run-all.sh`, `stop-all.sh` – build, run (host ports 3001–3006) and stop all six
* `README.md` – this file
