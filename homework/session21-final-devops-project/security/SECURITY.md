# DevSecOps gates

Every push and pull request runs five independent security jobs. The image build/push job `needs` all of
them, so a failing gate blocks the image from ever reaching the registry or the cluster.

| Gate | Tool | What it checks | Fails the pipeline when | Config |
|------|------|----------------|-------------------------|--------|
| SAST | Bandit | Python code for insecure patterns (shell injection, weak crypto, hard-coded passwords, assert in prod code) | any finding of MEDIUM+ severity | `bandit.yaml` |
| SAST | Semgrep | `p/python`, `p/owasp-top-ten` rulesets + project rules (hard-coded DB URLs, CORS misconfig, XSS, eval) | any ERROR/WARNING match | `semgrep.yml` |
| SCA | pip-audit | `requirements.txt` against the PyPI advisory DB (OSV) | any known vulnerability (`--strict`) | - |
| SCA | npm audit | frontend dependency tree | any HIGH/CRITICAL advisory | - |
| Secret scanning | Gitleaks | working tree **and** full git history for tokens, keys, connection strings | any leak not explicitly allow-listed | `.gitleaks.toml` |
| Image scanning | Trivy | OS packages + Python/Node libraries inside both images, plus embedded secrets and Dockerfile misconfig | HIGH/CRITICAL CVE **with a fix available** | `trivy.yaml`, `.trivyignore` |

Design decisions

* `ignore-unfixed: true` for Trivy: a CVE in Debian's `libc` with no patched package would otherwise block
  every build forever; we gate on what we can actually fix (rebuild with a newer base image).
* Accepted risks go into `.trivyignore` with a reason and a re-evaluation date - never silently.
* Secret scanning uses `fetch-depth: 0`: a secret that was committed and then removed is still in history.
* The demo credentials (`changeme-demo-password`, `taskboard-local-only`) are allow-listed by value and path
  so the scanner still catches a *real* password pasted in the same file.
* The images run as non-root (uid 10001 / nginx-unprivileged uid 101) and drop all capabilities in Kubernetes,
  limiting the blast radius if a vulnerability is exploited anyway.

## Run the gates locally

```bash
cd homework/session21-final-devops-project
python3 -m venv .venv && source .venv/bin/activate
pip install -r application/backend/requirements.txt -r application/backend/requirements-dev.txt semgrep

ruff check application/backend/app application/backend/tests
bandit -c security/bandit.yaml -r application/backend/app
semgrep scan --config p/python --config security/semgrep.yml application/backend
pip-audit -r application/backend/requirements.txt --strict
(cd application/frontend && npm install --package-lock-only && npm audit --audit-level=high)

brew install gitleaks trivy
gitleaks detect --source . --config security/.gitleaks.toml --verbose
docker build -f docker/backend.Dockerfile -t taskboard-backend:local application/backend
trivy image --config security/trivy.yaml --ignorefile security/.trivyignore --exit-code 1 taskboard-backend:local
```

## What happened on this submission

`pip-audit` initially reported 8 known vulnerabilities in the reference `requirements.txt`
(starlette 0.41.3 pulled in by fastapi 0.115.6, and pytest 8.3.4). Upgrading to fastapi 0.142.2 / starlette 1.7.0
and pytest 9.1.1 made the scan clean and the tests still pass - exactly the feedback loop the SCA gate is for.

## What happened on the first real run of the gates (2026-10-08, Docker available)

| Gate | Result | Root cause | Fix |
|------|--------|-----------|-----|
| Trivy image, backend | 44 HIGH, exit 1 | every CVE unfixed in Debian 13.7; `ignore-unfixed: true` sat at the top level of `trivy.yaml` where Trivy ignores it (config-file key is `vulnerability.ignore-unfixed`) | moved the key; 0 findings, exit 0 |
| Trivy image, frontend | 40 HIGH + 2 CRITICAL (openssl, musl, zlib, libxml2, ...), all with fixed versions | `nginx-unprivileged:1.27-alpine` = Alpine 3.21 built 2025-06 | `FROM nginxinc/nginx-unprivileged:1.30-alpine` (Alpine 3.24.2); rebuilt, 0 findings |
| Trivy misconfig (`trivy fs --scanners misconfig`) | DS-0002 no USER in frontend Dockerfile; KSV-0014 no readOnlyRootFilesystem on backend/frontend/postgres; KSV-0118 postgres without securityContext | hardening gaps | `USER 101`; `readOnlyRootFilesystem: true` + emptyDir volumes for `/tmp`, `/etc/nginx/conf.d` (nginx) and `/var/run/postgresql`, `/tmp` (postgres); postgres runs as uid 70 with capabilities dropped - in `kubernetes/`, the Helm chart and `troubleshooting/` |
| Gitleaks | 3 "leaks" (all documented demo placeholders), exit 1 | the project rule had a capturing group `(\+psycopg)?`; Gitleaks reports group 1 as the secret, so the allow-list regexes were matched against `+psycopg` | non-capturing group `(?:\+psycopg)?` and `regexTarget = "line"` on the allow-list; `no leaks found` |
| Semgrep (project rules) | 0 findings | - | - |
| Trivy fs (SCA on requirements.txt) | 0 findings | - | - |

No gate was relaxed: `.trivyignore` is still empty and the severities/exit codes are unchanged. Before/after
transcripts are in the main README, Task 5.
