# Security Policy – session17-devsecops-api

## Supported versions

| Version | Supported |
|---|---|
| `main` (latest image tag `latest`) | yes |
| any other git SHA tag | only for rollback, no fixes |

## Reporting a vulnerability

Open a private security advisory on the repository (**Security → Advisories → Report a
vulnerability**) or e-mail the maintainer listed in the repository profile. Do not open a
public issue for security problems. Expect an acknowledgement within 3 working days and a fix
or mitigation plan within 14 days for HIGH/CRITICAL findings.

## What the pipeline enforces on every change

| Control | Tool | Blocking threshold |
|---|---|---|
| SAST | Bandit (`security/bandit.yaml`), Semgrep (`p/python`, `p/flask`, `security/semgrep.yml`) | any MEDIUM+ Bandit finding, any Semgrep ERROR |
| SCA | pip-audit (`--strict`), Trivy filesystem scan (`security/trivy.yaml`) | any known vulnerability in pinned deps; CRITICAL/HIGH with a fix |
| Secret scanning | Gitleaks (`security/gitleaks.toml`) | any detected secret |
| Image scanning | Trivy image scan | CRITICAL/HIGH with a fix available |
| Security gate | `security-gate` job | fails if any scanner job did not succeed |

Exceptions must be recorded in `security/.trivyignore`, `security/bandit.yaml` (`skips`),
the Gitleaks allowlist or a `--ignore-vuln` flag, each with a justification and an expiry date.

## If a real secret is ever committed

1. Revoke / rotate the credential immediately – treat it as compromised.
2. Remove it from the code and, if required, from git history.
3. Check the provider's audit log for unauthorized use.
4. Store the replacement in GitHub Actions secrets or a secret manager, never in code.
