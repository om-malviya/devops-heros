# Session 16 – CI/CD & GitHub Actions
Student: Om Malviya | Enrollment No: 24BCS10448

## Task: Demo Project – a complete CI/CD pipeline with GitHub Actions

I adapted the course project `10-final-cicd-pipeline` into a small Flask API around the
course calculator module, containerised it, and wrote a three-job GitHub Actions workflow
(`ci` → `build` → `cd`). The sections below cover every concept in the task list:
CI vs CD, CI/CD pipeline, GitHub Actions, workflow, jobs, steps, runners, secrets,
artifacts, build, test and pipeline execution.

> **Where the workflow lives.** This folder is part of my fork of the course repo, and GitHub
> only reads workflows from the repository root `.github/workflows/`. The real workflow is
> therefore at **`/.github/workflows/session16-ci-cd.yml`** (repo root). It uses `paths:`
> filters so it only runs when this folder changes, plus `defaults.run.working-directory`
> so every command runs inside `homework/session16-cicd-github-actions/`. An identical copy
> is kept in `./.github/workflows/session16-ci-cd.yml` for completeness. All line numbers
> below refer to that file.

### Project structure

```text
homework/session16-cicd-github-actions/
├── app/
│   ├── __init__.py
│   ├── calculator.py        # add / subtract / multiply / divide (course module) + dispatcher
│   └── main.py              # Flask API: GET /, GET /health, GET /api/calc?a=&b=&op=
├── tests/
│   ├── test_calculator.py   # unit tests for the module
│   └── test_api.py          # HTTP tests with Flask's test client
├── k8s/
│   ├── deployment.yaml      # image placeholder __IMAGE__ rendered by the CD job
│   └── service.yaml
├── .github/workflows/session16-ci-cd.yml   # copy of the root workflow
├── Dockerfile               # python:3.12-slim, non-root numeric uid 10001, gunicorn
├── .dockerignore
├── build.sh                 # packages build/ (+ optional docker build)
├── requirements.txt         # flask, gunicorn
├── requirements-dev.txt     # + pytest, pytest-cov, flake8
├── pytest.ini / .flake8
└── README.md
```

## 1. Concepts

### CI vs CD

| | Continuous Integration (CI) | Continuous Delivery / Deployment (CD) |
|---|---|---|
| Question it answers | "Does this change break anything?" | "Can this change go to users?" |
| Trigger | every push / pull request | only after CI passed, usually on `main` |
| What it does | checkout, install, lint, test, build | package, publish (registry), deploy |
| In my workflow | job `ci` (lines 40–77) and job `build` (lines 80–144) | job `cd` (lines 148–227) |

Continuous *Delivery* means the artifact is always ready to deploy (my image is pushed to
GHCR); Continuous *Deployment* means it is deployed automatically (my `Deploy to Kubernetes`
step, when cluster credentials exist). My pipeline does both, the second one guarded by a secret.

### CI/CD pipeline

A pipeline is an ordered chain of stages where a failure stops everything after it:

```text
git push ──► ci (lint + pytest) ──► build (docker build + smoke test) ──► cd (push to GHCR ──► deploy)
                    │                        │                                   │
                  FAIL ─► stop            FAIL ─► stop                   only on push to main
```

The order is enforced with `needs:` (line 82: `build` needs `ci`; line 150: `cd` needs `build`).

### GitHub Actions

GitHub Actions is the automation service built into GitHub. It watches repository events
(push, pull request, manual button) and runs the YAML workflow on a machine it provides.
Reusable building blocks (`actions/checkout`, `actions/setup-python`, `docker/build-push-action`,
`docker/login-action`, `actions/upload-artifact`) are called with `uses:`; my own shell
commands with `run:`.

### Workflow

The workflow is the YAML file. Its parts:

* `name:` (line 6) – the name shown in the Actions tab.
* `on:` (lines 8–19) – triggers: `push` and `pull_request` to `main`, filtered with `paths:` to
  this folder and the workflow file itself, plus `workflow_dispatch` so I can run it manually.
* `env:` (lines 22–25) – variables available to every job (`PROJECT_DIR`, `IMAGE_NAME`, `PYTHON_VERSION`).
* `defaults.run.working-directory` (lines 28–30) – every `run:` executes inside the project folder.
* `permissions:` (lines 33–34) – the token gets read-only access unless a job asks for more.
* `jobs:` (line 36 onward).

### Jobs

A job is a group of steps that runs on one fresh runner. I have three:

| Job | Lines | `needs` | Purpose |
|---|---|---|---|
| `ci` | 40–77 | – | lint + unit tests + test-report artifact |
| `build` | 80–144 | `ci` | build Docker image, smoke-test it, save as artifact |
| `cd` | 148–227 | `build` | push image to GHCR, render manifests, deploy (guarded) |

Jobs without `needs` would run in parallel; with `needs` they form the pipeline. The `cd`
job also has an `if:` (line 151) so it is skipped for pull requests and for non-`main` branches.
Jobs pass data to each other through `outputs:` (lines 84–86 define `image` and `tag`; the
`cd` job reads them on lines 157–158).

### Steps

Steps are the individual commands or actions inside a job and run sequentially on the same
runner, so files created by one step are visible to the next. Example from `ci`:

1. `actions/checkout@v4` – clone the repo (line 44).
2. `actions/setup-python@v5` with pip caching (lines 47–52).
3. `pip install -r requirements-dev.txt` (lines 54–57).
4. `flake8 app tests` (lines 59–60).
5. `pytest ... --junitxml --cov` (lines 62–67).
6. `actions/upload-artifact@v4` with `if: always()` (lines 69–75) – the report is uploaded even when tests fail, which is exactly when I need it.

A step can have an `id:` so later steps can read its outputs (`steps.meta.outputs.image`,
lines 91–96 and 101–114; `steps.kubeconfig.outputs.configured`, lines 197–221).

### Runners

A runner is the virtual machine that executes a job. Every job declares
`runs-on: ubuntu-latest` (lines 42, 83, 152): a GitHub-hosted Ubuntu VM with Python, Docker,
curl and kubectl pre-installed, created fresh for each job and destroyed afterwards. That is
why each job has to check out the code again and why I transport the image between jobs as an
artifact instead of relying on the local Docker cache. Self-hosted runners would be used when
the job must reach a private network (for example a Kubernetes cluster on a laptop).

### Secrets

Secrets are encrypted values stored in the repository settings and exposed to the workflow as
`${{ secrets.NAME }}`. They are masked in logs. I use two:

| Secret | Where used | How it is created |
|---|---|---|
| `GITHUB_TOKEN` | GHCR login, lines 172–177 | automatic, created by GitHub for every run; the `cd` job raises its permission to `packages: write` (lines 153–155) so it may push images |
| `KUBE_CONFIG` | lines 197–220 | optional, created by me: `base64 < ~/.kube/config \| tr -d '\n'` pasted into **Settings → Secrets and variables → Actions → New repository secret** |

Rules I followed from the course: never hardcode a credential in YAML, never `echo` a secret.
The `Check whether a KUBE_CONFIG secret is configured` step (lines 197–208) only tests
`[ -n "$KUBE_CONFIG" ]` and writes `configured=true/false` to `$GITHUB_OUTPUT`; the real
deploy step (lines 210–220) and the simulated deploy step (lines 222–227) are selected with
`if:` on that output. So the pipeline is green with or without a cluster.

### Artifacts

An artifact is a file set produced by a job that GitHub stores after the runner is gone
(downloadable from the run summary page, and from other jobs with `actions/download-artifact`).
I upload three:

| Artifact | Produced by | Lines | Content |
|---|---|---|---|
| `test-report` | `ci` | 69–75 | `reports/junit.xml`, `reports/coverage.xml` |
| `docker-image` | `build` | 129–144 | `dist/image.tar` (`docker save` of both tags) |
| `k8s-manifests` | `cd` | 191–195 | rendered `deployment.yaml` / `service.yaml` with the real image tag |

`docker-image` is downloaded again on lines 163–170 of the `cd` job and `docker load`-ed, so
the image that gets pushed is byte-for-byte the one that was tested.

### Build

The build stage is the `build` job. Lines 91–96 compute the image name
`ghcr.io/<owner>/session16-calculator-api` – `${GITHUB_REPOSITORY_OWNER,,}` lowercases the
owner because GHCR rejects upper-case names – and a short tag `${GITHUB_SHA::7}`.
Lines 98–114 set up Buildx and build the `Dockerfile` with `load: true` (image stays local,
not pushed yet) and a GitHub Actions layer cache. Lines 116–127 start the container and curl
`/health` and `/api/calc`, so a broken image fails the pipeline before anything is published.
Locally the equivalent is `./build.sh` (packaging) or `./build.sh --docker`.

### Test

The test stage is in `ci`: flake8 for static checks, then pytest with a JUnit XML report and
coverage (lines 59–67). 23 tests cover the calculator functions, the dispatcher and all HTTP
status codes of the API (200, 400 for missing/invalid/non-finite parameters, division by zero, 404).
Query parameters are parsed with a helper that rejects `nan`/`inf` – a finding that Semgrep's
`p/flask` ruleset reported in the Session 17 project, fixed in both copies of the app.

### Pipeline execution

```text
Developer                GitHub                       Runner (ubuntu-latest)
   │  git push main         │                               │
   ├───────────────────────►│ event matches on.push.paths   │
   │                        ├── start job ci ──────────────►│ checkout → python → lint → pytest → upload test-report
   │                        │◄── success ───────────────────┤
   │                        ├── start job build ───────────►│ buildx → docker build → smoke test → docker save → upload docker-image
   │                        │◄── success ───────────────────┤
   │                        ├── start job cd (push to main)►│ download image → login GHCR → push :sha :latest
   │                        │                               │ render k8s → KUBE_CONFIG? apply+rollout : print manifest
   │                        │◄── success ───────────────────┤
   │  green check on commit │                               │
```

On a pull request the same workflow runs `ci` and `build` only; `cd` shows as *skipped*.
If `ci` fails (for example `return a + b + 1` in `add`), `build` and `cd` never start – this is
the course "failure scenario", and it works the same here because of `needs:`.

## 2. Running everything locally

### Install and test

```bash
cd homework/session16-cicd-github-actions
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
flake8 app tests
pytest -v --junitxml=reports/junit.xml --cov=app --cov-report=term-missing --cov-report=xml:reports/coverage.xml
```

Output (captured 2026-10-07):

```text
$ flake8 app tests
(no output – no issues)

$ pytest -v --junitxml=reports/junit.xml --cov=app --cov-report=term-missing --cov-report=xml:reports/coverage.xml
============================= test session starts ==============================
platform darwin -- Python 3.12.0, pytest-9.1.1, pluggy-1.6.0 -- .venv/bin/python
cachedir: .pytest_cache
rootdir: .../homework/session16-cicd-github-actions
configfile: pytest.ini
testpaths: tests
plugins: cov-6.0.0, platformdirs-4.12.3, anyio-4.15.1
collecting ... collected 23 items

tests/test_api.py::test_index PASSED                                     [  4%]
tests/test_api.py::test_health PASSED                                    [  8%]
tests/test_api.py::test_calc_add PASSED                                  [ 13%]
tests/test_api.py::test_calc_default_op_is_add PASSED                    [ 17%]
tests/test_api.py::test_calc_missing_param PASSED                        [ 21%]
tests/test_api.py::test_calc_not_a_number PASSED                         [ 26%]
tests/test_api.py::test_calc_unknown_op PASSED                           [ 30%]
tests/test_api.py::test_calc_divide_by_zero PASSED                       [ 34%]
tests/test_api.py::test_unknown_route PASSED                             [ 39%]
tests/test_api.py::test_calc_rejects_nan_and_inf[nan] PASSED             [ 43%]
tests/test_api.py::test_calc_rejects_nan_and_inf[NaN] PASSED             [ 47%]
tests/test_api.py::test_calc_rejects_nan_and_inf[inf] PASSED             [ 52%]
tests/test_api.py::test_calc_rejects_nan_and_inf[-Infinity] PASSED       [ 56%]
tests/test_calculator.py::test_add PASSED                                [ 60%]
tests/test_calculator.py::test_subtract PASSED                           [ 65%]
tests/test_calculator.py::test_multiply PASSED                           [ 69%]
tests/test_calculator.py::test_divide PASSED                             [ 73%]
tests/test_calculator.py::test_divide_by_zero PASSED                     [ 78%]
tests/test_calculator.py::test_calculate_dispatch[add-2-3-5] PASSED      [ 82%]
tests/test_calculator.py::test_calculate_dispatch[sub-2-3--1] PASSED     [ 86%]
tests/test_calculator.py::test_calculate_dispatch[mul-2-3-6] PASSED      [ 91%]
tests/test_calculator.py::test_calculate_dispatch[div-9-3-3] PASSED      [ 95%]
tests/test_calculator.py::test_calculate_unknown_op PASSED               [100%]

- generated xml file: .../homework/session16-cicd-github-actions/reports/junit.xml -

---------- coverage: platform darwin, python 3.12.0-final-0 ----------
Name                Stmts   Miss  Cover   Missing
-------------------------------------------------
app/__init__.py         0      0   100%
app/calculator.py      22      6    73%   42-47
app/main.py            39      1    97%   78
-------------------------------------------------
TOTAL                  61      7    89%
Coverage XML written to file reports/coverage.xml

============================== 23 passed in 0.18s ==============================
```

I observed that the only uncovered lines are the `if __name__ == "__main__":` demo blocks,
which is expected.

### Build script

```bash
./build.sh
```

Output (captured 2026-10-07):

```text
=================================
Starting Application Build
=================================

Build files:
build/app/__init__.py
build/app/calculator.py
build/app/main.py
build/build-info.txt
build/requirements.txt

Application: Session 16 Calculator API
Git SHA:     8376590
Build Date:  2026-10-07T16:59:32Z
Build Status: SUCCESS

Build completed successfully.
```

### Run the API with gunicorn (same command as the Dockerfile `CMD`)

```bash
gunicorn --bind 127.0.0.1:8000 --workers 1 app.main:app &
curl -s localhost:8000/health
curl -s 'localhost:8000/api/calc?a=10&b=5&op=add'
curl -s 'localhost:8000/api/calc?a=10&b=0&op=div'
curl -s localhost:8000/
```

Output (captured 2026-10-07):

```text
$ curl -s localhost:8000/health
{"status":"ok"}
$ curl -s 'localhost:8000/api/calc?a=10&b=5&op=add'
{"a":10.0,"b":5.0,"op":"add","result":15.0}
$ curl -s 'localhost:8000/api/calc?a=10&b=0&op=div'
{"error":"Cannot divide by zero"}   (HTTP 400)
$ curl -s localhost:8000/
{"app":"session16-calculator-api","endpoints":["/","/health","/api/calc?a=10&b=5&op=add"],"git_sha":"abc1234","operations":["add","div","mul","sub"],"version":"1.0.0"}
```

### Docker image

Port 8000 was already taken on my machine by another container, so I published the image on
host port 8101 (`-p 8101:8000`).

```bash
docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t session16-calculator-api:local .
docker run -d --rm -p 8101:8000 --name s16-calc session16-calculator-api:local
curl -s localhost:8101/health
curl -s 'localhost:8101/api/calc?a=10&b=5&op=add'
curl -s 'localhost:8101/api/calc?a=10&b=0&op=div'
curl -s localhost:8101/
docker exec s16-calc id          # proves the non-root user
docker ps --filter name=s16-calc
docker stop s16-calc
```

Output (captured 2026-10-08):

```text
$ docker build --build-arg GIT_SHA=$(git rev-parse --short HEAD) -t session16-calculator-api:local .
Step 1/13 : FROM python:3.12-slim
Step 2/13 : ARG GIT_SHA=local
Step 3/13 : ARG APP_VERSION=1.0.0
Step 4/13 : ENV GIT_SHA=${GIT_SHA}     APP_VERSION=${APP_VERSION}     PYTHONDONTWRITEBYTECODE=1     PYTHONUNBUFFERED=1     PIP_NO_CACHE_DIR=1
Step 5/13 : WORKDIR /app
Step 6/13 : COPY requirements.txt .
Step 7/13 : RUN pip install --no-cache-dir -r requirements.txt
Successfully installed blinker-1.9.0 click-8.5.0 flask-3.1.3 gunicorn-23.0.0 itsdangerous-2.2.0 jinja2-3.1.6 markupsafe-3.0.4 packaging-26.3 werkzeug-3.1.9
Step 8/13 : COPY app ./app
Step 9/13 : RUN groupadd --system app && useradd --system --gid app --uid 10001 app     && chown -R app:app /app
Step 10/13 : USER 10001
Step 11/13 : EXPOSE 8000
Step 12/13 : HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3   CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status==200 else 1)"
Step 13/13 : CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app.main:app"]
Successfully built 195f2ad726f7
Successfully tagged session16-calculator-api:local

$ docker run -d --rm -p 8101:8000 --name s16-calc session16-calculator-api:local
06e7633179d82ff9c7025152c2be0b50486f2ef1f09040fb117d73054ec57eb4
$ curl -s localhost:8101/health
{"status":"ok"}
$ curl -s 'localhost:8101/api/calc?a=10&b=5&op=add'
{"a":10.0,"b":5.0,"op":"add","result":15.0}
$ curl -s 'localhost:8101/api/calc?a=10&b=0&op=div'
{"error":"Cannot divide by zero"}   (HTTP 400)
$ curl -s localhost:8101/
{"app":"session16-calculator-api","endpoints":["/","/health","/api/calc?a=10&b=5&op=add"],"git_sha":"8376590","operations":["add","div","mul","sub"],"version":"1.0.0"}
$ docker exec s16-calc id
uid=10001(app) gid=999(app) groups=999(app)
$ docker ps --filter name=s16-calc
CONTAINER ID   IMAGE                            COMMAND                  CREATED         STATUS                            PORTS                                         NAMES
06e7633179d8   session16-calculator-api:local   "gunicorn --bind 0.0…"   4 seconds ago   Up 3 seconds (health: starting)   0.0.0.0:8101->8000/tcp, [::]:8101->8000/tcp   s16-calc
$ docker stop s16-calc
s16-calc
```

I observed that `git_sha` is now the real commit (`8376590`, passed in with `--build-arg`)
instead of the `local` default, and that `id` inside the container is uid 10001 – the Docker
daemon here uses the classic builder, hence the `Step n/13` lines instead of BuildKit's `=>` lines.

As a bonus check I ran the Session 17 image scanner against this image too:
`trivy image --severity HIGH,CRITICAL --ignore-unfixed session16-calculator-api:local` reported
`0` vulnerabilities for Debian 13.7 and for every Python package (captured 2026-10-07).

## 3. Setting up the repository for the pipeline

1. Push the fork to GitHub; the workflow file must be at `.github/workflows/session16-ci-cd.yml` in the repo root.
2. **Settings → Actions → General → Workflow permissions**: leave "Read repository contents and packages permissions" – the job-level `permissions: packages: write` (lines 153–155) is enough for `GITHUB_TOKEN` to push to GHCR.
3. Optional CD to a real cluster: **Settings → Secrets and variables → Actions → New repository secret**, name `KUBE_CONFIG`, value `base64 < ~/.kube/config | tr -d '\n'`. The cluster must be reachable from the internet (a laptop kind/minikube cluster is not; in that case the pipeline prints the manifest and I apply it by hand – see below).
4. After the first push the image appears under the profile's **Packages** as `ghcr.io/<owner>/session16-calculator-api`. GHCR packages are private by default; to pull from a cluster without a pull secret, open the package → **Package settings → Change visibility → Public**.
5. Manual deploy of the rendered manifest. In the pipeline the `k8s-manifests` artifact already
   contains the GHCR image reference. That image only exists after the `cd` job has pushed, so to
   test the manifests on my local k3s cluster I pushed the locally built image to a throw-away
   registry and rendered `__IMAGE__` to it with the same `sed` the CD job uses (k3s pulls from
   `localhost:5001` over plain HTTP because the registry container runs on the same VM):

```bash
docker run -d -p 5001:5000 --name s16-registry registry:2
docker tag session16-calculator-api:local localhost:5001/session16-calculator-api:local
docker push localhost:5001/session16-calculator-api:local

IMAGE=localhost:5001/session16-calculator-api:local      # pipeline: ghcr.io/<owner>/session16-calculator-api:<sha>
kubectl create namespace s16
sed "s|__IMAGE__|$IMAGE|" k8s/deployment.yaml | kubectl -n s16 apply -f -
kubectl -n s16 apply -f k8s/service.yaml
kubectl -n s16 rollout status deployment/session16-calculator-api --timeout=120s
kubectl -n s16 get pods,svc -o wide
kubectl -n s16 port-forward svc/session16-calculator-api 8101:80 &
curl -s 'localhost:8101/api/calc?a=6&b=7&op=mul'
```

Output (captured 2026-10-07, first attempt – the rollout failed):

```text
deployment.apps/session16-calculator-api created
service/session16-calculator-api created
Waiting for deployment "session16-calculator-api" rollout to finish: 0 of 2 updated replicas are available...
error: timed out waiting for the condition
NAME                                            READY   STATUS                       RESTARTS   AGE   IP           NODE     NOMINATED NODE   READINESS GATES
pod/session16-calculator-api-7d756fbd45-4j2rc   0/1     CreateContainerConfigError   0          2m    10.42.0.70   colima   <none>           <none>
pod/session16-calculator-api-7d756fbd45-sk7hc   0/1     CreateContainerConfigError   0          2m    10.42.0.69   colima   <none>           <none>

$ kubectl -n s16 describe pod session16-calculator-api-7d756fbd45-4j2rc | sed -n '/^Events:/,$p'
Events:
  Type     Reason     Age                 From               Message
  ----     ------     ----                ----               -------
  Normal   Scheduled  2m                  default-scheduler  Successfully assigned s16/session16-calculator-api-7d756fbd45-4j2rc to colima
  Normal   Pulling    2m                  kubelet            spec.containers{api}: Pulling image "localhost:5001/session16-calculator-api:local"
  Normal   Pulled     118s                kubelet            spec.containers{api}: Successfully pulled image "localhost:5001/session16-calculator-api:local" in 1.077s (1.077s including waiting). Image size: 45697315 bytes.
  Warning  Failed     3s (x11 over 118s)  kubelet            spec.containers{api}: Error: container has runAsNonRoot and image has non-numeric user (app), cannot verify user is non-root (pod: "session16-calculator-api-7d756fbd45-4j2rc_s16(833ed414-0df1-4743-98c6-9fddf94b5ac6)", container: api)
```

   The image was pulled fine, but the kubelet refused to start it: the Deployment says
   `runAsNonRoot: true`, and the Dockerfile had `USER app` – a *name*. The kubelet only sees the
   image config, not `/etc/passwd`, so it cannot prove that `app` is non-root and fails the pod
   with `CreateContainerConfigError`. The fix is to use the numeric uid in both places:
   `USER 10001` in the `Dockerfile` and `runAsUser: 10001` next to `runAsNonRoot: true` in
   `k8s/deployment.yaml`. After rebuilding and pushing the image:

Output (captured 2026-10-08, after the fix):

```text
$ sed "s|__IMAGE__|$IMAGE|" k8s/deployment.yaml | kubectl -n s16 apply -f -
deployment.apps/session16-calculator-api configured
$ kubectl -n s16 rollout status deployment/session16-calculator-api --timeout=120s
Waiting for deployment "session16-calculator-api" rollout to finish: 1 out of 2 new replicas have been updated...
Waiting for deployment "session16-calculator-api" rollout to finish: 1 old replicas are pending termination...
deployment "session16-calculator-api" successfully rolled out
$ kubectl -n s16 get pods,svc -o wide
NAME                                            READY   STATUS    RESTARTS   AGE   IP            NODE     NOMINATED NODE   READINESS GATES
pod/session16-calculator-api-6dc5b896c9-8c77f   1/1     Running   0          61s   10.42.0.119   colima   <none>           <none>
pod/session16-calculator-api-6dc5b896c9-wwtb8   1/1     Running   0          74s   10.42.0.117   colima   <none>           <none>

NAME                               TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE     SELECTOR
service/session16-calculator-api   ClusterIP   10.43.132.128   <none>        80/TCP    3h43m   app=session16-calculator-api
$ kubectl -n s16 get deployment session16-calculator-api
NAME                       READY   UP-TO-DATE   AVAILABLE   AGE
session16-calculator-api   2/2     2            2           3h43m
$ kubectl -n s16 exec session16-calculator-api-6dc5b896c9-8c77f -- id
uid=10001(app) gid=999(app) groups=999(app)
$ kubectl -n s16 port-forward svc/session16-calculator-api 8101:80 &
$ curl -s 'localhost:8101/api/calc?a=6&b=7&op=mul'
{"a":6.0,"b":7.0,"op":"mul","result":42.0}
$ curl -s localhost:8101/health
{"status":"ok"}
```

   This is a good example of why the pipeline smoke-tests the container *and* why a real deploy
   step matters: `docker run` was perfectly happy with `USER app`, only Kubernetes' non-root
   check caught it. Clean-up afterwards: `kubectl delete namespace s16`,
   `docker rm -f s16-registry`.

## 4. Pipeline output (captured from GitHub Actions)

The fork was pushed on 2026-10-08 and the workflow ran on the first commit that touched this
folder. Run: https://github.com/om-malviya/devops-heros/actions/runs/37715592913

```text
Output (captured 2026-10-08, GitHub Actions run #37715592913, commit f7d0ed7, trigger: push to main)
Session 16 - CI/CD Pipeline   ✓ success   1m 29s
│
├── ✓ CI - Lint and Test                              13s   (01:58:57 → 01:59:10 UTC)
│     ✓ Lint with flake8
│     ✓ Run unit tests (JUnit + coverage)   TOTAL  61  7  89%   ·   23 passed in 0.35s
│     ✓ Upload test report artifact         Artifact test-report has been successfully uploaded! Final size is 1296 bytes.
│
├── ✓ Build - Docker image                            41s   (01:59:12 → 01:59:53 UTC)
│     ✓ Set up Docker Buildx
│     ✓ Build image (not pushed yet)
│     ✓ Smoke test the container            {"status":"ok"}
│                                           {"a":10.0,"b":5.0,"op":"add","result":15.0}
│     ✓ Save image as tar                   -rw------- 1 runner runner 125M Oct  8 01:59 image.tar
│     ✓ Upload image artifact
│
└── ✓ CD - Push to GHCR and Deploy                    27s   (01:59:55 → 02:00:22 UTC)
      ✓ Download image artifact             docker-image (Size: 46247795)
      ✓ Load image                          Loaded image: ghcr.io/om-malviya/session16-calculator-api:f7d0ed7
                                            Loaded image: ghcr.io/om-malviya/session16-calculator-api:latest
      ✓ Login to GitHub Container Registry  Login Succeeded!
      ✓ Push image (sha + latest tags)      f7d0ed7: digest: sha256:5024064b0f787cbe5979931cec542f6aee652977e9a62936084add7f7c2bc965 size: 2199
                                            latest:  digest: sha256:5024064b0f787cbe5979931cec542f6aee652977e9a62936084add7f7c2bc965 size: 2199
      ✓ Render Kubernetes manifests          20:          image: ghcr.io/om-malviya/session16-calculator-api:f7d0ed7
      ✓ Upload rendered manifests
      ✓ Check whether a KUBE_CONFIG secret is configured
      - Deploy to Kubernetes                 (skipped – no KUBE_CONFIG secret on the fork)
      ✓ Simulated deploy (no cluster credentials)   ::notice title=Deploy skipped::No KUBE_CONFIG secret. Manifest that would be applied:

Artifacts (3 + buildx record): test-report (1.3 kB), docker-image (46 MB), k8s-manifests (843 B)
Package: ghcr.io/om-malviya/session16-calculator-api  tags: f7d0ed7, latest
```

I observed that the only non-green item is the deliberately skipped `Deploy to Kubernetes` step:
the fork has no `KUBE_CONFIG` secret, so the CD job falls through to the simulated deploy and
prints the rendered manifest instead, exactly as designed. The image push itself is real: the
package is visible under the om-malviya account on GHCR with the commit-SHA tag and `latest`.
The runner also printed two warnings worth knowing: `actions/*@v4` actions are being migrated
from Node 20 to Node 24, and `ubuntu-latest` moves to Ubuntu 26 from October 2026; neither
affects the result.

On a pull request: `CI` ✓, `Build` ✓, `CD` skipped (grey). With the intentional bug
`return a + b + 1`: `CI` ✗ at step "Run unit tests" (`test_add` and
`test_calc_add` fail), `Build` and `CD` are not started.

## Screenshots

The captured terminal blocks stand in for screenshots. Rows 1, 2, 3, 4 and 5 are now backed by
the real run in section 4 (run 37715592913); rows 6-8 describe views in the GitHub UI that have
no terminal equivalent.

| # | Screenshot to capture | What it must show | Stand-in in this README |
|---|---|---|---|
| 1 | Actions tab → run list | workflow "Session 16 - CI/CD Pipeline" with a green check for the latest `main` commit | section 4 job tree |
| 2 | Run summary page | the graph `CI - Lint and Test → Build - Docker image → CD - Push to GHCR and Deploy`, all green, and the three artifacts at the bottom | section 4 |
| 3 | `CI` job log, step "Run unit tests" | `23 passed` and the coverage table | captured pytest output in section 2 |
| 4 | `Build` job log, step "Smoke test the container" | `{"status":"ok"}` and the calc result returned from the container | captured `docker run` + curl output in section 2 |
| 5 | `CD` job log, step "Push image" | GHCR digest lines for the `:sha` and `:latest` tags | section 4 (digest sha256:5024064b…) |
| 6 | Profile → Packages → `session16-calculator-api` | the image with both tags | – |
| 7 | A pull request's Checks tab | `CI` and `Build` green, `CD` skipped | – |
| 8 | A failing run (intentional `a + b + 1`) | red `CI`, `Build`/`CD` not run | – |
| 9 | `kubectl get pods` after the manual deploy | two `Running` pods and the Service | captured kubectl output in section 3 (including the first failed rollout and the fix) |

## Deliverables

* Application source code – `app/calculator.py`, `app/main.py`, tests in `tests/`.
* Dockerfile – `Dockerfile` (+ `.dockerignore`, `build.sh`).
* GitHub Actions workflow – root `/.github/workflows/session16-ci-cd.yml` (copy: `.github/workflows/session16-ci-cd.yml`).
* CI pipeline – job `ci` (lint, tests, test-report artifact) and job `build` (image, smoke test, image artifact).
* CD pipeline – job `cd` (GHCR push with `GITHUB_TOKEN`, manifest rendering, guarded Kubernetes deploy) with `k8s/deployment.yaml`, `k8s/service.yaml`.
* Screenshots of pipeline execution – `## Screenshots` section (what to capture) and the captured local outputs in section 2.
* README.md – this file.
