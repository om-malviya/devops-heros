# Apache-app – Hello World (Apache httpd)

Container port: **80**. Image: `hello-apache:1.0`.

```bash
cd Apache-app
docker build -t hello-apache:1.0 .
docker run -d --name hello-apache -p 3004:80 hello-apache:1.0
curl http://localhost:3004
```

Output (captured 2026-10-07)
```text
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Hello World - Apache</title>
</head>
<body>
    <h1>Hello World from Apache httpd in Docker!</h1>
</body>
</html>
```

Stop: `docker rm -f hello-apache`
