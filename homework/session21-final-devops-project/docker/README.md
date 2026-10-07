# docker/

| File | Purpose |
|------|---------|
| `backend.Dockerfile` | python:3.12-slim, non-root user (uid 10001), runs `alembic upgrade head` then uvicorn on 8000 |
| `frontend.Dockerfile` | multi-stage: node:22-alpine build -> nginxinc/nginx-unprivileged:1.30-alpine (uid 101, port 8080, `USER 101` repeated for scanners) |
| `docker-compose.yml` | postgres + backend + frontend with a named volume and a Postgres healthcheck |

```bash
# from homework/session21-final-devops-project
docker build -f docker/backend.Dockerfile  -t taskboard-backend:local  application/backend
docker build -f docker/frontend.Dockerfile -t taskboard-frontend:local application/frontend
docker compose -f docker/docker-compose.yml up --build      # http://localhost:3000
docker compose -f docker/docker-compose.yml down -v         # stop and delete the DB volume
```

The nginx config is a template (`application/frontend/nginx.conf.template`); the image entrypoint
substitutes `BACKEND_HOST`/`BACKEND_PORT`, so the same image works in Compose (`backend`) and in
Kubernetes (`taskboard-backend`).

## Run on this machine (2026-10-08)

Host ports 8000/3000/5432 were busy, so I added a local override that only remaps the host side
(`ports: !override [...]` replaces the list; without `!override` Compose merges both lists and still binds 8000):

```bash
docker compose -f docker/docker-compose.yml -f compose.ports.override.yml up -d --build
docker compose -f docker/docker-compose.yml -f compose.ports.override.yml ps
docker compose -f docker/docker-compose.yml -f compose.ports.override.yml down -v
```

```text
Output (captured 2026-10-08)
NAME                   IMAGE                      STATUS                        PORTS
taskboard-backend-1    taskboard-backend:local    Up 56 seconds (healthy)       0.0.0.0:8200->8000/tcp
taskboard-frontend-1   taskboard-frontend:local   Up 55 seconds (healthy)       0.0.0.0:8201->8080/tcp
taskboard-postgres-1   postgres:16-alpine         Up About a minute (healthy)   0.0.0.0:8232->5432/tcp
$ curl -s localhost:8200/health; curl -s localhost:8201/api/tasks/stats
{"status":"UP"}{"total":2,"todo":1,"inProgress":1,"done":0}
$ docker images | grep taskboard
taskboard-frontend   local   90.5MB     (nginx-unprivileged:1.30-alpine; the 1.27-alpine build was 76.2MB but failed the Trivy gate)
taskboard-backend    local   358MB
```

The frontend base image was bumped from `1.27-alpine` to `1.30-alpine` after Trivy reported 42 fixable
HIGH/CRITICAL OS CVEs in the old Alpine 3.21 layer (details in `../security/SECURITY.md`).
