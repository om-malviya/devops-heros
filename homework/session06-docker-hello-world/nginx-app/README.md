# nginx-app – Hello World (Nginx)

Container port: **80**. Image: `hello-nginx:1.0`.

```bash
cd nginx-app
docker build -t hello-nginx:1.0 .
docker run -d --name hello-nginx -p 3006:80 hello-nginx:1.0
curl http://localhost:3006
```

Output (captured 2026-10-07)
```text
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Hello World - Nginx</title>
</head>
<body>
    <h1>Hello World from Nginx in Docker!</h1>
</body>
</html>
```

Stop: `docker rm -f hello-nginx`
