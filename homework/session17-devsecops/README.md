# Session 17 – Complete CI/CD & DevSecOps
Student: Om Malviya | Enrollment No: 24BCS10448

## Task: DevSecOps Demo Project – CI/CD pipeline with security stages and gates

I extended the Session 16 project into a ten-job GitHub Actions pipeline that follows the
expected flow from the task exactly:

```text
Code → Build → Unit Test → SAST → SCA → Secret Scan → Docker Build → Container Image Scan → Security Gate → Push Image → Deploy to Kubernetes
```

CI/CD bullets: application build (job 1), unit testing (job 2), Docker image build (job 6),
container registry GHCR (job 9), Kubernetes deployment (job 10).
Security bullets: SAST (job 3), SCA (job 4), secret scanning (job 5), container image
scanning (job 7), security gates (job 8 plus `needs:` edges everywhere).

> **Where the workflow lives.** GitHub only loads workflows from the repository root, so the
> real file is **`/.github/workflows/session17-devsecops.yml`** (with `paths:` filters on this
> folder and `defaults.run.working-directory: homework/session17-devsecops`). The copy in
> `./.github/workflows/session17-devsecops.yml` is identical. Line numbers below refer to it.

### Project structure

```text
homework/session17-devsecops/
├── app/                      # Flask API: /, /health, /api/status, /api/calc?a=&b=&op=
│   ├── calculator.py
│   └── main.py
├── tests/                    # 23 pytest tests
├── k8s/
│   ├── deployment.yaml       # probes, resources, non-root, read-only FS, drop ALL caps
│   └── service.yaml          # NodePort 30080
├── security/                 # security tools configuration
│   ├── bandit.yaml           # SAST  - Bandit
│   ├── semgrep.yml           # SAST  - custom Semgrep rules (+ p/python, p/flask)
│   ├── pip-audit.md          # SCA   - pip-audit usage and flags
│   ├── trivy.yaml            # SCA + image scan - Trivy config (ignore-unfixed under vulnerability:)
│   ├── .trivyignore          # accepted-risk CVE list (empty)
│   └── gitleaks.toml         # secret scanning - Gitleaks rules + allowlist
├── .github/workflows/session17-devsecops.yml   # copy of the root workflow
├── Dockerfile                # python:3.12-slim, apt upgrade, non-root uid 10001, gunicorn
├── .dockerignore, build.sh, requirements.txt, requirements-dev.txt, pytest.ini, .flake8
├── SECURITY.md               # security policy: thresholds, exceptions, incident steps
└── README.md
```

## 1. Pipeline overview

```text
                 ┌─────────┐    ┌───────────┐
   git push ───► │ 1 build │ ─► │2 unit-test│
                 └─────────┘    └─────┬─────┘
                        ┌─────────────┼───────────────┐
                        ▼             ▼               ▼
                  ┌──────────┐  ┌──────────┐  ┌───────────────┐
                  │ 3 sast   │  │ 4 sca    │  │ 5 secret-scan │   (run in parallel)
                  │ bandit + │  │pip-audit+│  │   gitleaks    │
                  │ semgrep  │  │ trivy fs │  │               │
                  └────┬─────┘  └────┬─────┘  └──────┬────────┘
                       └─────────────┼───────────────┘
                                     ▼
                             ┌────────────────┐
                             │ 6 docker-build │
                             └───────┬────────┘
                                     ▼
                             ┌────────────────┐
                             │ 7 image-scan   │  trivy image, exit-code 1 on CRITICAL/HIGH
                             └───────┬────────┘
                                     ▼
                             ┌────────────────┐
                             │8 security-gate │  needs all scanners, if: always()
                             └───────┬────────┘
                               PASS  │  FAIL ─► stop (nothing published)
                                     ▼
                             ┌────────────────┐
                             │ 9 push-image   │  GHCR, push to main only
                             └───────┬────────┘
                                     ▼
                             ┌────────────────┐
                             │ 10 deploy-k8s  │  apply if KUBE_CONFIG secret exists, else print
                             └────────────────┘
```

| # | Job | Lines | `needs` | Tool(s) | Blocking? |
|---|---|---|---|---|---|
| 1 | `build` | 37–60 | – | pip, `compileall`, `build.sh` | yes |
| 2 | `unit-test` | 64–90 | build | flake8, pytest (JUnit + coverage) | yes |
| 3 | `sast` | 95–134 | unit-test | Bandit, Semgrep (SARIF → Security tab) | yes |
| 4 | `sca` | 138–170 | unit-test | pip-audit `--strict`, Trivy `fs` | yes |
| 5 | `secret-scan` | 173–186 | unit-test | Gitleaks (full history) | yes |
| 6 | `docker-build` | 191–237 | sast, sca, secret-scan | Buildx, smoke test, `docker save` | yes |
| 7 | `image-scan` | 241–284 | docker-build | Trivy image (table + SARIF, exit-code 1) | yes |
| 8 | `security-gate` | 289–322 | unit-test, sast, sca, secret-scan, image-scan | shell check of `needs.*.result` | the gate |
| 9 | `push-image` | 327–356 | docker-build, security-gate | `docker/login-action`, GHCR | – |
| 10 | `deploy-k8s` | 361–406 | docker-build, push-image | sed render, kubectl | – |

Jobs 3, 4 and 5 all `need` only `unit-test`, so they run in parallel (faster) while still
sitting between *Unit Test* and *Docker Build* in the flow – `docker-build` waits for all three
(line 193).

## 2. Security stages explained

### SAST – Static Application Security Testing (job 3, lines 95–134)

SAST reads **our own source code** without running it and looks for dangerous patterns
(eval/exec, shell=True, debug mode, hardcoded passwords, weak crypto, SQL built with f-strings).

* **Bandit** (lines 109–113) scans `app/` with `security/bandit.yaml`. `-ll -ii` = only
  MEDIUM+ severity *and* MEDIUM+ confidence fail the step; a SARIF file is also written for the artifact.
* **Semgrep** (lines 114–121) runs the community rulesets `p/python` and `p/flask` plus my four
  project rules in `security/semgrep.yml` (no `eval`/`exec`, no Flask `debug=True`, no
  `subprocess(..., shell=True)`, no `PASSWORD = "..."` style assignments). `--error` makes any
  finding exit 1. The SARIF is uploaded with `github/codeql-action/upload-sarif` (lines 122–127)
  so findings appear under **Security → Code scanning** with file and line.

### SCA – Software Composition Analysis (job 4, lines 138–170)

SCA checks **third-party dependencies** (Flask, gunicorn, their transitive packages) against
vulnerability databases. Our code can be perfect and still ship a vulnerable library.

* **pip-audit** (lines 147–152) resolves `requirements.txt` and queries the PyPA advisory
  database / OSV. `--strict` also fails if a package cannot be audited. Usage and flags are
  documented in `security/pip-audit.md`.
* **Trivy filesystem scan** (lines 153–162, `aquasecurity/trivy-action`) scans the project
  folder for vulnerable lock-file entries, IaC misconfigurations (Dockerfile, k8s manifests) and
  secrets, using `security/trivy.yaml`; `exit-code: "1"` with `severity: CRITICAL,HIGH` and
  `ignore-unfixed: true`.

### Secret scanning (job 5, lines 173–186)

Finds credentials committed to git: API keys, tokens, private keys, cloud credentials.
**Gitleaks** runs via `gitleaks/gitleaks-action@v2` with `fetch-depth: 0` (line 180) so the
*whole history* is scanned, not just the latest commit – a secret that was committed and then
deleted is still leaked. `security/gitleaks.toml` extends the default rules with a course demo
token pattern and allowlists `tests/` and `*.md` plus the known placeholders
(`replace-with-test-value`, `24BCS10448`). The action scans the whole fork, which is
the correct scope for secrets. For organisation-owned repositories a `GITLEAKS_LICENSE` secret
is required (comment on line 186); personal repositories need none.

### Container image scanning (job 7, lines 241–284)

The image is scanned **after** it is built and **before** it is pushed. Trivy inspects the OS
packages of `python:3.12-slim` (Debian), the Python packages installed by pip, and the image
config. Two runs of `aquasecurity/trivy-action`:

1. *Informational* (lines 258–266): table output, `exit-code: "0"`, includes MEDIUM so the log
   shows everything.
2. *Gate* (lines 267–278): `exit-code: "1"`, `severity: CRITICAL,HIGH`, `ignore-unfixed: true`
   (no fix available = cannot act on it today), honours `security/.trivyignore`, writes SARIF
   that is uploaded to code scanning (lines 279–284) even when the step fails (`if: always()`).

The Dockerfile runs `apt-get upgrade` so already-patched Debian CVEs do not trip the gate, and
the exact scanned image is what gets pushed (it travels as the `docker-image` artifact, lines
232–236 → 339–343).

### Security gates (job 8, lines 289–322 – and every `needs:`)

A scan *finds* a problem; a **gate** *decides* whether the pipeline may continue. Two kinds here:

1. **Implicit gates** – every `needs:` edge. If `sast` fails, `docker-build` (line 193) never
   starts, so nothing downstream happens.
2. **Explicit gate** – the `security-gate` job. It `needs` every scanner (line 291) and has
   `if: always()` (line 292) so it runs even when a scanner failed. Its single step reads
   `needs.<job>.result` for each check (lines 295–322), prints a table into the job summary and
   `exit 1`s if any result is not `success` (`failure`, `cancelled` or `skipped` all block). It
   is the one place that answers "may this image be published?". `push-image` requires
   `needs.security-gate.result == 'success'` (line 330) and `deploy-k8s` needs `push-image`.

**Blocking vs advisory.** All checks are blocking today. To make a scanner advisory (report but
do not block – useful when adopting a new tool with many legacy findings) add
`continue-on-error: true` to that *step*; the job result stays `success`, the gate passes, and
the finding is still visible as an annotation and in the SARIF/Security tab. Example:

```yaml
      - name: Semgrep (community rulesets + project rules)
        continue-on-error: true      # advisory while we triage
        run: semgrep scan ... --error app
```

Accepted risks are recorded with justification and expiry in `security/.trivyignore`,
`skips:` in `security/bandit.yaml`, `--ignore-vuln` for pip-audit, or the Gitleaks allowlist –
the policy is in `SECURITY.md`.

### CI/CD stages

* **Build (job 1)** – installs runtime deps, `python -m compileall app` (syntax errors fail
  here, before tests), `./build.sh` packages `build/` and it is uploaded as `build-output`.
* **Unit test (job 2)** – flake8 + pytest with JUnit and coverage, `test-report` artifact
  uploaded with `if: always()`.
* **Docker build (job 6)** – image name computed as `ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/session17-devsecops-api`
  (lowercased, lines 200–205), tag = short SHA, Buildx with GHA cache, container started and
  `/health` curled, `docker exec smoke id` proves uid 10001, image saved to `dist/image.tar`.
* **Container registry (job 9)** – `docker/login-action` to `ghcr.io` with the automatic
  `GITHUB_TOKEN` (job permission `packages: write`, lines 332–334), pushes `:<sha>` and `:latest`.
  Only on `push` to `main` (line 330) – pull requests stop after the gate.
* **Kubernetes deployment (job 10)** – `sed` replaces `__IMAGE__` in `k8s/deployment.yaml`
  with the scanned image (lines 369–374), manifests uploaded as `k8s-manifests`. A step checks
  `[ -n "$KUBE_CONFIG" ]` without printing it (lines 380–390); if the secret exists the next step
  writes `~/.kube/config`, `kubectl apply`s and waits for `rollout status` (lines 391–401),
  otherwise the rendered manifests are printed (lines 402–406). The Deployment has readiness and
  liveness probes on `/health`, resource limits, `runAsNonRoot`, `readOnlyRootFilesystem`,
  `capabilities.drop: [ALL]` and a `RuntimeDefault` seccomp profile.

## 3. Running every scanner locally

```bash
cd homework/session17-devsecops
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt          # includes bandit and pip-audit
pip install semgrep                          # SAST #2 (optional locally)

flake8 app tests                                                   # lint
pytest -v --junitxml=reports/junit.xml --cov=app --cov-report=term-missing   # unit tests
bandit -c security/bandit.yaml -r app -ll -ii                      # SAST
semgrep scan --config p/python --config p/flask --config security/semgrep.yml --error app   # SAST
pip-audit -r requirements.txt --strict --desc                      # SCA
trivy --config security/trivy.yaml fs .                            # SCA (needs trivy)
gitleaks detect --no-git --source . --config security/gitleaks.toml -v   # secret scan (needs gitleaks)
docker build -t session17-devsecops-api:local .                    # image
trivy --config security/trivy.yaml image session17-devsecops-api:local   # image scan
./build.sh                                                         # package
```

### Unit tests

Output (captured 2026-10-07):

```text
$ pytest -v --junitxml=reports/junit.xml --cov=app --cov-report=term-missing --cov-report=xml:reports/coverage.xml
============================= test session starts ==============================
platform darwin -- Python 3.12.0, pytest-9.1.1, pluggy-1.6.0 -- .venv/bin/python
cachedir: .pytest_cache
rootdir: .../homework/session17-devsecops
configfile: pytest.ini
testpaths: tests
plugins: cov-6.0.0, platformdirs-4.12.3, anyio-4.15.1
collecting ... collected 23 items

tests/test_api.py::test_index PASSED                                     [  4%]
tests/test_api.py::test_health PASSED                                    [  8%]
tests/test_api.py::test_status PASSED                                    [ 13%]
tests/test_api.py::test_calc_add PASSED                                  [ 17%]
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

- generated xml file: .../homework/session17-devsecops/reports/junit.xml -

---------- coverage: platform darwin, python 3.12.0-final-0 ----------
Name                Stmts   Miss  Cover   Missing
-------------------------------------------------
app/__init__.py         0      0   100%
app/calculator.py      22      6    73%   42-47
app/main.py            46      1    98%   103
-------------------------------------------------
TOTAL                  68      7    90%
Coverage XML written to file reports/coverage.xml

============================== 23 passed in 0.18s ==============================
```

### Bandit (SAST)

Output (captured 2026-10-07):

```text
$ bandit -c security/bandit.yaml -r app -ll -ii
[main]	INFO	using config: security/bandit.yaml
[main]	INFO	running on Python 3.12.0
Run started:2026-10-07 17:02:52.844834

Test results:
	No issues identified.

Code scanned:
	Total lines of code: 110
	Total lines skipped (#nosec): 0
	Total potential issues skipped due to specifically being disabled (e.g., #nosec BXXX): 0

Run metrics:
	Total issues (by severity):
		Undefined: 0
		Low: 0
		Medium: 0
		High: 0
	Total issues (by confidence):
		Undefined: 0
		Low: 0
		Medium: 0
		High: 0
Files skipped (0):
```

### Semgrep (SAST) – a real finding and the fix

The first run of the `p/flask` ruleset against my app reported a blocking finding.

Output (captured 2026-10-07, before the fix):

```text
$ semgrep scan --config p/python --config p/flask --config security/semgrep.yml --error app
┌─────────────────┐
│ 2 Code Findings │
└─────────────────┘
    app/main.py
   ❯❯❱ python.flask.security.injection.nan-injection.nan-injection
          ❰❰ Blocking ❱❱
          Found user input going directly into typecast for bool(), float(), or complex(). This allows an
          attacker to inject Python's not-a-number (NaN) into the typecast. This results in undefind behavior,
          particularly when doing comparisons. Either cast to a different type, or add a guard checking for
          all capitalizations of the string 'nan'.
          Details: https://sg.run/e598
           68┆ a = float(request.args["a"])
            ⋮┆----------------------------------------
           69┆ b = float(request.args["b"])
```

I observed that `float("nan")` is valid Python, so `/api/calc?a=nan&b=1` would have returned
`NaN` as a result. I added `_parse_number()` in `app/main.py` that rejects `nan`/`inf`, plus a
parametrised regression test (`test_calc_rejects_nan_and_inf`). This is exactly what a SAST
gate is for: the pipeline would have stopped at job 3 and never built the image.

Output (captured 2026-10-07, after the fix):

```text
$ semgrep scan --config p/python --config p/flask --config security/semgrep.yml --error app
✅ Scan completed successfully.
 • Findings: 0 (0 blocking)
 • Rules run: 155
 • Targets scanned: 3
 • Parsed lines: ~100.0%
Ran 155 rules on 3 files: 0 findings.
```

To prove the custom rules work I scanned a deliberately bad file (`eval(input())`,
`API_KEY = "..."`, `app.run(debug=True)`):

```text
Ran 4 rules on 1 file: 3 findings.
   ❯❯❱ security.no-eval-or-exec
    ❯❱ security.hardcoded-secret-assignment
   ❯❯❱ security.flask-debug-enabled
```

### pip-audit (SCA)

Output (captured 2026-10-07):

```text
$ pip-audit -r requirements.txt --strict --desc
No known vulnerabilities found
```

Expected output when a vulnerable pin exists (for illustration, if `flask==2.2.0` were pinned):

```text
Found 1 known vulnerability in 1 package
Name  Version ID                  Fix Versions Description
----- ------- ------------------- ------------ -----------------------------------------------------
flask 2.2.0   GHSA-m2qf-hxjv-5gpq 2.3.2,2.2.5  Flask ... may disclose the session cookie to clients via Vary: Cookie ...
```

### Trivy filesystem and image scan – a real gate failure and the fix

**Filesystem scan (SCA + misconfig + secrets).** Output (captured 2026-10-08):

```text
$ trivy --config security/trivy.yaml fs .
2026-10-08T02:27:51+05:30	INFO	Loaded	file_path="security/trivy.yaml"
2026-10-08T02:27:51+05:30	INFO	[vuln] Vulnerability scanning is enabled
2026-10-08T02:27:51+05:30	INFO	[misconfig] Misconfiguration scanning is enabled
2026-10-08T02:27:52+05:30	INFO	[secret] Secret scanning is enabled
2026-10-08T02:27:52+05:30	INFO	Number of language-specific files	num=1
2026-10-08T02:27:52+05:30	INFO	[pip] Detecting vulnerabilities...
2026-10-08T02:27:52+05:30	INFO	Detected config files	num=3

Report Summary

┌─────────────────────┬────────────┬─────────────────┬─────────┬───────────────────┐
│       Target        │    Type    │ Vulnerabilities │ Secrets │ Misconfigurations │
├─────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ requirements.txt    │    pip     │        0        │    -    │         -         │
├─────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ Dockerfile          │ dockerfile │        -        │    -    │         0         │
├─────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ k8s/deployment.yaml │ kubernetes │        -        │    -    │         0         │
├─────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ k8s/service.yaml    │ kubernetes │        -        │    -    │         0         │
└─────────────────────┴────────────┴─────────────────┴─────────┴───────────────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)
$ echo $?
0
```

The pinned dependencies are clean, and the Dockerfile and both manifests pass Trivy's
misconfiguration checks (non-root user, no `latest` tag, resource limits, probes, read-only
filesystem, dropped capabilities).

**Image scan – first run (the gate fired).** Output (captured 2026-10-07, before the fix):

```text
$ docker build -t session17-devsecops-api:local .
$ trivy --config security/trivy.yaml image session17-devsecops-api:local
2026-10-07T22:43:25+05:30	INFO	Detected OS	family="debian" version="13.7"
2026-10-07T22:43:25+05:30	INFO	[debian] Detecting vulnerabilities...	os_version="13" pkg_num=87
2026-10-07T22:43:25+05:30	INFO	[python-pkg] Detecting vulnerabilities...

Report Summary

┌──────────────────────────────────────────────────────────────────────────────┬────────────┬─────────────────┬─────────┬───────────────────┐
│                                    Target                                    │    Type    │ Vulnerabilities │ Secrets │ Misconfigurations │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ session17-devsecops-api:local (debian 13.7)                                  │   debian   │       44        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/flask-3.1.3.dist-info/METADATA        │ python-pkg │        0        │    -    │         -         │
│ ... (blinker, click, gunicorn, itsdangerous, jinja2, markupsafe, packaging, pip, werkzeug: all 0)                                         │
└──────────────────────────────────────────────────────────────────────────────┴────────────┴─────────────────┴─────────┴───────────────────┘

session17-devsecops-api:local (debian 13.7)
===========================================
Total: 44 (HIGH: 44, CRITICAL: 0)

┌───────────────┬────────────────┬──────────┬──────────────┬───────────────────────────────────┬───────────────┬─────────────────────────────────────────────────────────────┐
│    Library    │ Vulnerability  │ Severity │    Status    │         Installed Version         │ Fixed Version │                            Title                            │
├───────────────┼────────────────┼──────────┼──────────────┼───────────────────────────────────┼───────────────┼─────────────────────────────────────────────────────────────┤
│ bsdutils      │ CVE-2026-76642 │ HIGH     │ affected     │ 1:2.41.5-0+deb13u1                │               │ util-linux: failed external mount helper still ...          │
│               │ CVE-2026-78408 │          │              │                                   │               │ util-linux: nsenter --join-cgroup leaks root ...            │
│               │ CVE-2026-78409 │          │              │                                   │               │ util-linux: X-mount.subdir detached-tree ...                │
│               │ CVE-2026-78410 │          │              │                                   │               │ util-linux: restricted bind mounts do not pin ...           │
│ libacl1       │ CVE-2026-54369 │          │              │ 2.3.2-2+b1                        │               │ acl: Symlink traversal privilege escalation via libacl      │
│ libblkid1 / liblastlog2-2 / libmount1 / libsmartcols1 / libuuid1 / login / mount / util-linux │ (the same four util-linux CVEs)      │
│ libncursesw6 / libtinfo6 / ncurses-base │ CVE-2025-69720 │ affected │ 6.5+20250216-2 │        │ ncurses: Buffer overflow vulnerability may lead to ...      │
│ libsystemd0 / libudev1 │ CVE-2026-16742 │ affected │ 257.13-1~deb13u1 │                      │ systemd: systemd-homed: Local privilege escalation via ...  │
│ perl-base     │ CVE-2026-9538  │          │ fix_deferred │ 5.40.1-6+deb13u1                  │               │ perl-Archive-Tar: Denial of Service via ...                 │
└───────────────┴────────────────┴──────────┴──────────────┴───────────────────────────────────┴───────────────┴─────────────────────────────────────────────────────────────┘
$ echo $?
1
```

So the gate did what a gate must do: exit 1, 44 HIGH findings, nothing would be published.
Analysing the table I observed two things:

1. Every finding has an **empty `Fixed Version`** column and status `affected` or
   `fix_deferred` – Debian 13 has no patched package yet. `apt-get upgrade` in the Dockerfile
   cannot help here (I compared `libc6`, `perl-base` and `util-linux` versions with the
   Session 16 image that does *not* upgrade: identical), and `python:3.12-slim` was already the
   newest digest (built 2026-10-06), so bumping the base image does not help either.
2. My policy (`SECURITY.md`) says such findings must **not** block: `ignore-unfixed: true` is in
   `security/trivy.yaml`. Yet Trivy did not apply it. The same image scanned with the CLI flag
   `--ignore-unfixed` gives `0` findings. The reason is the config-file layout: Trivy expects the
   key under the `vulnerability:` section; at the top level it is silently ignored. The
   pipeline would *not* have been affected because `trivy-action` is given `ignore-unfixed: true`
   as an explicit input (lines 162 and 275), but the documented local reproduction of the gate was
   wrong, so I fixed `security/trivy.yaml`:

```yaml
# before (ignored by Trivy)          # after
ignore-unfixed: true                 vulnerability:
                                       ignore-unfixed: true
```

**Image scan – after the fix.** Output (captured 2026-10-08):

```text
$ trivy --config security/trivy.yaml image session17-devsecops-api:local
2026-10-08T02:27:50+05:30	INFO	Loaded	file_path="security/trivy.yaml"
2026-10-08T02:27:50+05:30	INFO	[vuln] Vulnerability scanning is enabled
2026-10-08T02:27:50+05:30	INFO	[misconfig] Misconfiguration scanning is enabled
2026-10-08T02:27:51+05:30	INFO	[secret] Secret scanning is enabled
2026-10-08T02:27:51+05:30	INFO	Detected OS	family="debian" version="13.7"
2026-10-08T02:27:51+05:30	INFO	[debian] Detecting vulnerabilities...	os_version="13" pkg_num=87
2026-10-08T02:27:51+05:30	INFO	Number of language-specific files	num=1
2026-10-08T02:27:51+05:30	INFO	[python-pkg] Detecting vulnerabilities...

Report Summary

┌──────────────────────────────────────────────────────────────────────────────┬────────────┬─────────────────┬─────────┬───────────────────┐
│                                    Target                                    │    Type    │ Vulnerabilities │ Secrets │ Misconfigurations │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ session17-devsecops-api:local (debian 13.7)                                  │   debian   │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/blinker-1.9.0.dist-info/METADATA      │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/click-8.5.0.dist-info/METADATA        │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/flask-3.1.3.dist-info/METADATA        │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/gunicorn-23.0.0.dist-info/METADATA    │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/itsdangerous-2.2.0.dist-info/METADATA │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/jinja2-3.1.6.dist-info/METADATA       │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/markupsafe-3.0.4.dist-info/METADATA   │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/packaging-26.3.dist-info/METADATA     │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/pip-25.0.1.dist-info/METADATA         │ python-pkg │        0        │    -    │         -         │
├──────────────────────────────────────────────────────────────────────────────┼────────────┼─────────────────┼─────────┼───────────────────┤
│ usr/local/lib/python3.12/site-packages/werkzeug-3.1.9.dist-info/METADATA     │ python-pkg │        0        │    -    │         -         │
└──────────────────────────────────────────────────────────────────────────────┴────────────┴─────────────────┴─────────┴───────────────────┘
Legend:
- '-': Not scanned
- '0': Clean (no security findings detected)
$ echo $?
0
```

The 44 unfixed HIGH CVEs are not gone – `trivy image --severity CRITICAL,HIGH
session17-devsecops-api:local` (no `ignore-unfixed`) still lists all of them – they just do not
block, because nobody can act on them today. Note that both Trivy steps in job 7 pass
`ignore-unfixed: true`, so the CI log hides them as well; to review the unfixed backlog, run
the command above locally or temporarily drop that input from the *informational* step only. When Debian publishes the fixed `util-linux`, `ncurses`, `systemd`, `acl` and `perl`
packages, the `apt-get upgrade` layer picks them up on the next build. If a fixable HIGH/CRITICAL
CVE appears, the table lists its `Fixed Version`, the command exits 1 and the `image-scan` job
(and therefore the gate) fails.

### Gitleaks

Locally I scanned the working tree of this project (`--no-git` scans the files instead of the
commit history; the CI action scans the full history of the whole fork).

Output (captured 2026-10-07):

```text
$ gitleaks detect --no-git --source . --config security/gitleaks.toml -v

    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

10:42PM INF scanned ~27041 bytes (27.04 KB) in 23.9ms
10:42PM INF no leaks found
$ echo $?
0
```

To prove that the scanner and my custom rule actually fire, I wrote a throw-away file *outside*
the repository with fake credentials (the AWS pair is the well-known documentation example
`AKIAIOSFODNN7EXAMPLE`, plus a token in the course `DEMO_TOKEN_` format) and scanned that
directory with the same config. Output (captured 2026-10-07):

```text
$ printf 'AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
token = "DEMO_TOKEN_abcdef1234567890XYZ"
' > /tmp/leak-demo/config.py
$ gitleaks detect --no-git --source /tmp/leak-demo --config security/gitleaks.toml -v

Finding:     token = "DEMO_TOKEN_abcdef1234567890XYZ
Secret:      DEMO_TOKEN_abcdef1234567890XYZ
RuleID:      course-demo-token
Entropy:     4.706891
Tags:        [demo token]
File:        /tmp/leak-demo/config.py
Line:        3
Fingerprint: /tmp/leak-demo/config.py:course-demo-token:3

10:42PM INF scanned ~151 bytes (151 bytes) in 11.8ms
10:42PM WRN leaks found: 1
$ echo $?
1
```

I observed that my `course-demo-token` rule fired and the exit code became 1 (this is what fails
job 5). The AWS example key was *not* reported: Gitleaks' default rule set allowlists the
`...EXAMPLE` keys from the AWS documentation precisely because they are not real – a reminder
that a passing secret scan is only as good as its rules, which is why the config extends the
defaults instead of replacing them. In CI each finding also prints `Commit` and `Author`.

### Build script and API

Output (captured 2026-10-07):

```text
$ ./build.sh
=================================
Starting Application Build
=================================

Build files:
build/app/__init__.py
build/app/calculator.py
build/app/main.py
build/build-info.txt
build/requirements.txt

Application: Session 17 DevSecOps API
Git SHA:     8376590
Build Date:  2026-10-07T17:02:58Z
Build Status: SUCCESS

Build completed successfully.

$ gunicorn --bind 127.0.0.1:8000 --workers 1 app.main:app &
$ curl -s localhost:8000/health
{"status":"ok"}
$ curl -s localhost:8000/api/status
{"app":"session17-devsecops-api","git_sha":"abc1234","platform":"Darwin","python_version":"3.12.0","uptime_seconds":0.45,"version":"1.0.0"}
$ curl -s 'localhost:8000/api/calc?a=6&b=7&op=mul'
{"a":6.0,"b":7.0,"op":"mul","result":42.0}
```

### Kubernetes (manual deploy of the rendered manifests)

The GHCR image only exists after job 9 has pushed it, so for the local test on my k3s cluster
I pushed the locally built (and scanned) image to a throw-away registry and rendered
`__IMAGE__` to it – exactly the `sed` that job 10 runs:

```bash
docker run -d -p 5001:5000 --name s16-registry registry:2
docker tag session17-devsecops-api:local localhost:5001/session17-devsecops-api:local
docker push localhost:5001/session17-devsecops-api:local

IMAGE=localhost:5001/session17-devsecops-api:local      # pipeline: ghcr.io/<owner>/session17-devsecops-api:<sha>
kubectl create namespace s17
sed "s|__IMAGE__|$IMAGE|" k8s/deployment.yaml | kubectl -n s17 apply -f -
kubectl -n s17 apply -f k8s/service.yaml
kubectl -n s17 rollout status deployment/session17-devsecops-api --timeout=120s
kubectl -n s17 get pods,svc -o wide
curl -s http://localhost:30080/health                     # NodePort
kubectl -n s17 exec <pod> -- id                           # non-root
kubectl -n s17 exec <pod> -- touch /app/probe-file        # read-only root filesystem
```

Output (captured 2026-10-08):

```text
namespace/s17 created
deployment.apps/session17-devsecops-api created
service/session17-devsecops-api created
Waiting for deployment "session17-devsecops-api" rollout to finish: 0 of 2 updated replicas are available...
Waiting for deployment "session17-devsecops-api" rollout to finish: 1 of 2 updated replicas are available...
deployment "session17-devsecops-api" successfully rolled out

$ kubectl -n s17 get pods,svc -o wide
NAME                                          READY   STATUS    RESTARTS   AGE   IP           NODE     NOMINATED NODE   READINESS GATES
pod/session17-devsecops-api-5f5d974b9-jzrxx   1/1     Running   0          12s   10.42.0.85   colima   <none>           <none>
pod/session17-devsecops-api-5f5d974b9-m4qp6   1/1     Running   0          12s   10.42.0.86   colima   <none>           <none>

NAME                              TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)        AGE   SELECTOR
service/session17-devsecops-api   NodePort   10.43.13.210   <none>        80:30080/TCP   12s   app=session17-devsecops-api

$ kubectl -n s17 describe pod session17-devsecops-api-5f5d974b9-jzrxx | sed -n '/^Events:/,$p'
Events:
  Type    Reason     Age   From               Message
  ----    ------     ----  ----               -------
  Normal  Scheduled  11s   default-scheduler  Successfully assigned s17/session17-devsecops-api-5f5d974b9-jzrxx to colima
  Normal  Pulling    11s   kubelet            spec.containers{api}: Pulling image "localhost:5001/session17-devsecops-api:local"
  Normal  Pulled     11s   kubelet            spec.containers{api}: Successfully pulled image "localhost:5001/session17-devsecops-api:local" in 125ms (125ms including waiting). Image size: 45698792 bytes.
  Normal  Created    11s   kubelet            spec.containers{api}: Container created
  Normal  Started    11s   kubelet            spec.containers{api}: Container started

$ curl -s http://localhost:30080/health
{"status":"ok"}
$ kubectl -n s17 port-forward svc/session17-devsecops-api 8102:80 &
$ curl -s localhost:8102/api/status
{"app":"session17-devsecops-api","git_sha":"8376590","platform":"Linux","python_version":"3.12.15","uptime_seconds":10973.44,"version":"1.0.0"}
$ curl -s 'localhost:8102/api/calc?a=6&b=7&op=mul'
{"a":6.0,"b":7.0,"op":"mul","result":42.0}

$ kubectl -n s17 exec session17-devsecops-api-5f5d974b9-jzrxx -- id
uid=10001(app) gid=10001 groups=10001
$ kubectl -n s17 exec session17-devsecops-api-5f5d974b9-jzrxx -- touch /app/probe-file
touch: cannot touch '/app/probe-file': Read-only file system
command terminated with exit code 1
```

I observed that the hardened `securityContext` really applies: the process runs as uid/gid
10001 (`runAsUser`/`runAsGroup` from the pod spec, which is also why the kubelet's
`runAsNonRoot` check passes even though the Dockerfile uses the user *name*), and writing to
the image filesystem is refused because of `readOnlyRootFilesystem: true` – only the `/tmp`
`emptyDir` is writable. Clean-up: `kubectl delete namespace s17`, `docker rm -f s16-registry`.

## 4. Repository setup

1. Workflow at repo root `.github/workflows/session17-devsecops.yml`.
2. **Settings → Code security → Code scanning**: enable so the SARIF uploads from Semgrep and Trivy show up (free for public repos).
3. `GITHUB_TOKEN` is automatic; job-level `permissions` grant `security-events: write` (SARIF) and `packages: write` (GHCR).
4. Optional secrets (**Settings → Secrets and variables → Actions**): `KUBE_CONFIG` = `base64 < ~/.kube/config | tr -d '\n'` for a reachable cluster; `GITLEAKS_LICENSE` only for organisation repos.
5. Package `ghcr.io/<owner>/session17-devsecops-api` appears under Profile → Packages after the first push to `main`; set it to public or add an `imagePullSecrets` to the Deployment.

## 5. Expected pipeline output

```text
Session 17 - DevSecOps Pipeline   #1   main   push
├── ✓ 1. Build                         20s   build-output artifact
├── ✓ 2. Unit Test                     30s   "23 passed", coverage 90%
├── ✓ 3. SAST (Bandit + Semgrep)       50s   "No issues identified." / "Ran 155 rules on 3 files: 0 findings."
├── ✓ 4. SCA (pip-audit + Trivy fs)    40s   "No known vulnerabilities found" / "Total: 0 (HIGH: 0, CRITICAL: 0)"
├── ✓ 5. Secret Scan (Gitleaks)        15s   "no leaks found"
├── ✓ 6. Docker Build                  1m    uid=10001(app) ...
├── ✓ 7. Image Scan (Trivy)            45s   "Total: 0 (HIGH: 0, CRITICAL: 0)"
├── ✓ 8. Security Gate                 3s    "Security gate PASSED - image may be published."
├── ✓ 9. Push Image (GHCR)             25s   "Pushed ghcr.io/<owner>/session17-devsecops-api:a1b2c3d"
└── ✓ 10. Deploy to Kubernetes         10s   "KUBE_CONFIG secret not set - deployment will be simulated." (or rollout output)

Artifacts: build-output, test-report, sast-reports, sca-reports, docker-image, k8s-manifests
Security → Code scanning: 0 open alerts (categories semgrep, trivy-image)
```

Failure scenario (for example `eval()` added to `app/main.py`): `3. SAST` ✗, jobs 6, 7
skipped, `8. Security Gate` ✗ with the table showing `sast | failure`, jobs 9 and 10 skipped –
nothing is pushed.

## Screenshots

To capture from the GitHub UI after pushing the fork; the captured terminal blocks above are
the stand-ins until then.

| # | Screenshot | Must show | Stand-in |
|---|---|---|---|
| 1 | Run summary graph | 10 jobs in the Code→Build→…→Deploy order, all green, 6 artifacts | section 5 |
| 2 | `3. SAST` log | Bandit "No issues identified" and Semgrep "0 findings" | captured Bandit/Semgrep output in section 3 |
| 3 | `4. SCA` log | pip-audit "No known vulnerabilities found" and the Trivy fs table | captured pip-audit output |
| 4 | `5. Secret Scan` log | Gitleaks "no leaks found" with commit count | captured Gitleaks output (plus the planted-leak demo) in section 3 |
| 5 | `7. Image Scan` log | Trivy table with `0` vulnerabilities | captured Trivy image scan (before/after the config fix) in section 3 |
| 6 | `8. Security Gate` job summary | the results table, all `success` | – |
| 7 | Security → Code scanning | alerts page (empty) with Semgrep and Trivy categories | – |
| 8 | Profile → Packages | `session17-devsecops-api` with `:<sha>` and `:latest` | – |
| 9 | A failing run | red SAST job, gate failed, push/deploy skipped | the "before the fix" Semgrep output |
| 10 | `kubectl get pods` after manual apply | two `Running` pods | captured kubectl output in section 3 |

## Deliverables

* Application – `app/main.py`, `app/calculator.py`, `tests/` (23 tests).
* Dockerfile – `Dockerfile` (hardened: apt upgrade, non-root uid 10001, healthcheck), `.dockerignore`, `build.sh`.
* GitHub Actions workflow – root `/.github/workflows/session17-devsecops.yml` (copy in `.github/workflows/`), 10 jobs in the required order.
* Security tools configuration – `security/bandit.yaml`, `security/semgrep.yml`, `security/pip-audit.md`, `security/trivy.yaml`, `security/.trivyignore`, `security/gitleaks.toml`, policy in `SECURITY.md`.
* Kubernetes manifests – `k8s/deployment.yaml` (probes, security context), `k8s/service.yaml`.
* Successful pipeline output – captured local scanner outputs (section 3) and expected Actions output (section 5).
* Screenshots – `## Screenshots` section.
* Complete README.md – this file.
