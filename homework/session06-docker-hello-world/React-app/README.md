# React-app – Hello World (React + Vite, served by Nginx)

Container port: **80**. Image: `hello-react:1.0`. Multi-stage: `node:22-alpine` builds, `nginx:alpine` serves.

```bash
cd React-app
docker build -t hello-react:1.0 .
docker run -d --name hello-react -p 3005:80 hello-react:1.0
curl http://localhost:3005
```

Output (captured 2026-10-07; the bundle file name is hashed by Vite, so it changes whenever the source changes)
```text
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Hello World - React</title>
    <script type="module" crossorigin src="/assets/index-DjJxFPA_.js"></script>
  </head>
  <body>
    <div id="root"></div>
  </body>
</html>
```

The text "Hello World from React in Docker!" is rendered by React in the browser at http://localhost:3005 (it is inside the JS bundle, not the raw HTML).
To check it from the terminal: `curl -s http://localhost:3005/assets/$(curl -s http://localhost:3005 | grep -o 'index-[^"]*\.js') | grep -o 'Hello World from React in Docker!'`

`npm install` is only run inside the Docker build; `node_modules` is excluded via `.dockerignore`.

Stop: `docker rm -f hello-react`
