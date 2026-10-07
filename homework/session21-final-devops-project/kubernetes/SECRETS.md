# Secrets handling

* `02-secret.yaml` contains obviously fake values so that the demo can be applied to a local kind cluster.
* `02-secret.example.yaml` is the template that would be committed in a real repository; the real
  secret is created with `kubectl create secret` or by an operator (External Secrets, Sealed Secrets).
* Gitleaks (see `../security/.gitleaks.toml`) scans the repository; the demo values are allow-listed
  by path so the gate still catches any real credential that is committed by mistake.
* The backend only receives `DATABASE_URL` through `secretKeyRef`, it is never baked into the image.
