# Task 2 – Secret

Student: Om Malviya | Enrollment No: 24BCS10448

A Secret is the Kubernetes object for sensitive values (passwords, tokens, keys). Values are stored
base64-encoded, injected into Pods as environment variables or files, and protected by RBAC rather
than by the encoding itself. All values in this demo are obviously fake placeholders.

Files:

| File | Purpose |
| --- | --- |
| `secret.yaml` | Secret `db-secret` (type Opaque) with base64 of fake `DB_USER`, `DB_PASSWORD`, `DB_NAME` |
| `pod.yaml` | Pod `secret-demo` consuming the Secret as env vars (`secretKeyRef`) and as files in `/etc/secrets` |

## Step 1 – Encode the sensitive values

```bash
echo -n 'demo_user' | base64
echo -n 'fake-password-123' | base64
echo -n 'demo_db' | base64
```

Output (captured 2026-10-07):

```text
ZGVtb191c2Vy
ZmFrZS1wYXNzd29yZC0xMjM=
ZGVtb19kYg==
```

The `-n` matters. The course's `troubleshooting/secret-base64-gotcha.md` describes an outage caused by
`echo` without `-n`: the encoded value silently contains a trailing `\n`, so the database receives
`password\n` and rejects the login. I reproduced the difference locally:

```bash
echo 'mypassword' | xxd
echo 'mypassword' | base64
echo -n 'mypassword' | base64
```

Output (captured 2026-10-07):

```text
00000000: 6d79 7061 7373 776f 7264 0a              mypassword.
bXlwYXNzd29yZAo=
bXlwYXNzd29yZA==
```

The `0a` byte is the newline; it shows up as the `o=` ending in the first base64 string.

Kubernetes can also do the encoding for you. This is the quickest way to get a correct manifest:

```bash
kubectl create secret generic db-secret -n s12 \
  --from-literal=DB_USER=demo_user \
  --from-literal=DB_PASSWORD=fake-password-123 \
  --from-literal=DB_NAME=demo_db \
  --dry-run=client -o yaml
```

Output (captured 2026-10-07):

```text
apiVersion: v1
data:
  DB_NAME: ZGVtb19kYg==
  DB_PASSWORD: ZmFrZS1wYXNzd29yZC0xMjM=
  DB_USER: ZGVtb191c2Vy
kind: Secret
metadata:
  name: db-secret
  namespace: s12
```

The values match my manual `echo -n` encoding exactly, which is what I put into `secret.yaml`.
(A third option is `stringData:` with plain text; the API server encodes it on save.)

## Step 2 – Create the Secret (store sensitive values)

```bash
kubectl apply -f ../namespace.yaml
kubectl apply -f secret.yaml
kubectl get secret db-secret -n s12
kubectl describe secret db-secret -n s12
```

Output (captured 2026-10-07):

```text
secret/db-secret created
NAME        TYPE     DATA   AGE
db-secret   Opaque   3      56s

Name:         db-secret
Namespace:    s12
Labels:       app=secret-demo
Annotations:  <none>

Type:  Opaque

Data
====
DB_NAME:      7 bytes
DB_PASSWORD:  17 bytes
DB_USER:      9 bytes
```

`describe` only shows sizes. But anyone with `get` permission can decode the value, which proves
base64 is not protection:

```bash
kubectl get secret db-secret -n s12 -o jsonpath='{.data.DB_PASSWORD}' | base64 --decode; echo
```

Output (captured 2026-10-07):

```text
fake-password-123
```

## Step 3 – Inject the Secret into a Pod

`pod.yaml`:

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: DB_PASSWORD
volumeMounts:
  - name: secret-volume
    mountPath: /etc/secrets
    readOnly: true
volumes:
  - name: secret-volume
    secret:
      secretName: db-secret
      defaultMode: 0400
```

```bash
kubectl apply -f pod.yaml
kubectl get pod secret-demo -n s12
```

Output (captured 2026-10-07):

```text
pod/secret-demo created
NAME          READY   STATUS    RESTARTS   AGE
secret-demo   1/1     Running   0          56s
```

## Step 4 – Verify the value inside the container

```bash
kubectl exec -n s12 secret-demo -- env | grep DB_
kubectl exec -n s12 secret-demo -- ls -l /etc/secrets/
kubectl exec -n s12 secret-demo -- cat /etc/secrets/DB_PASSWORD; echo
```

Output (captured 2026-10-07):

```text
DB_USER=demo_user
DB_PASSWORD=fake-password-123
DB_NAME=demo_db

total 0
lrwxrwxrwx    1 root     root            14 Oct  7 17:11 DB_NAME -> ..data/DB_NAME
lrwxrwxrwx    1 root     root            18 Oct  7 17:11 DB_PASSWORD -> ..data/DB_PASSWORD
lrwxrwxrwx    1 root     root            14 Oct  7 17:11 DB_USER -> ..data/DB_USER

fake-password-123
```

Inside the container the values are plain text: the application never sees base64. The secret volume
is backed by tmpfs (memory), so the values are never written to the node's disk. I confirmed this from
inside the container:

```bash
kubectl exec -n s12 secret-demo -- grep /etc/secrets /proc/mounts
```

Output (captured 2026-10-07):

```text
tmpfs /etc/secrets tmpfs ro,relatime,size=65536k,inode64,noswap 0 0
```

## Why Secrets must not be committed to Git

1. **base64 is encoding, not encryption.** `echo ZmFrZS1wYXNzd29yZC0xMjM= | base64 -d` recovers the
   password instantly. A `secret.yaml` in a repository is a plain-text password with extra steps.
2. **Git history is permanent.** Deleting the file in a later commit does not remove it from history,
   forks, clones or CI caches. Rotating the credential is the only real fix after a leak.
3. **Bots scan public repos within minutes** for AWS keys, tokens and `kind: Secret` manifests.
4. **Different people need different access.** Everyone who can read the repo gets every password;
   Kubernetes RBAC on the Secret object is bypassed.

What I would do instead:

| Approach | How it works |
| --- | --- |
| **Bitnami Sealed Secrets** | `kubeseal` encrypts the Secret with the cluster's public key into a `SealedSecret` CRD that is safe to commit; only the controller in the cluster can decrypt it. |
| **External Secrets Operator** | Commit an `ExternalSecret` that references a path in AWS Secrets Manager / Vault / GCP Secret Manager; the operator creates the real Secret in the cluster. |
| **SOPS + age/KMS** | Encrypt the `data` values of the YAML file with `sops -e`; Flux/Argo CD decrypt at deploy time. |
| **CI/CD variables** | Store the value in the pipeline's secret store and run `kubectl create secret ... --from-literal` at deploy time. |
| **Encryption at rest + RBAC** | Enable `EncryptionConfiguration` on the API server so etcd holds ciphertext; restrict `get secret` with RBAC. |

Guard-rails in the repository itself:

```gitignore
# .gitignore - never commit real secret manifests or key material
*secret*.yaml
!*sealed-secret*.yaml
*.key
*.pem
.env
```

```yaml
# .pre-commit-config.yaml - block commits that contain credentials
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

The `secret.yaml` in this folder is committed only because every value is a documented fake placeholder.

## Cleanup

```bash
kubectl delete -f pod.yaml -f secret.yaml
```

## Deliverables

- `secret.yaml` – Secret YAML with base64-encoded fake values.
- `pod.yaml` – Pod consuming the Secret as env vars and as mounted files.
- This README – encoding (captured), dry-run generation (captured), verification, and the Git section.
