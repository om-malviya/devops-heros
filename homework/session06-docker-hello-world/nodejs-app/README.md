# nodejs-app – Hello World (Node.js `http` module)

Container port: **3000**. Image: `hello-nodejs:1.0`.

```bash
cd nodejs-app
docker build -t hello-nodejs:1.0 .
docker run -d --name hello-nodejs -p 3001:3000 hello-nodejs:1.0
curl http://localhost:3001
```

Output (captured 2026-10-07)
```text
<h1>Hello World from Node.js in Docker!</h1>
```

Stop: `docker rm -f hello-nodejs`
