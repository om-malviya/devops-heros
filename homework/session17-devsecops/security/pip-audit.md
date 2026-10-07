# pip-audit (SCA) usage

pip-audit checks every installed/declared Python package against the Python Packaging
Advisory Database (PyPA) and OSV.

```bash
pip install pip-audit

# Audit exactly what ships in the image (what the pipeline runs)
pip-audit -r requirements.txt --strict --desc

# Audit the whole dev environment
pip-audit

# Machine-readable output for an artifact
pip-audit -r requirements.txt -f json -o reports/pip-audit.json
```

Flags used in CI:

| Flag | Why |
|---|---|
| `-r requirements.txt` | resolve the pinned runtime dependencies in an isolated environment |
| `--strict` | also fail when a dependency cannot be resolved/audited |
| `--desc` | print the advisory description so the log is self-explanatory |

Making a finding advisory (accepted risk) - always with a comment and an expiry:

```bash
pip-audit -r requirements.txt --ignore-vuln GHSA-xxxx-xxxx-xxxx   # reason: not reachable, review 2026-12
```

Remediation flow: finding -> identify package/version -> check fixed version in the advisory ->
bump the pin in `requirements.txt` -> run `pytest` -> run `pip-audit` again.
