# python-app – Hello World (Flask)

Container port: **5000**. Image: `hello-python:1.0`.

```bash
cd python-app
docker build -t hello-python:1.0 .
docker run -d --name hello-python -p 3002:5000 hello-python:1.0
curl http://localhost:3002
```

Output (captured 2026-10-07)
```text
<h1>Hello World from Python (Flask) in Docker!</h1>
```

Stop: `docker rm -f hello-python`
