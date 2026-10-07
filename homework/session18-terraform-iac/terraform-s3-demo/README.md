# Terraform S3 Demo (Session 18 – Task 1)

Student: Om Malviya | Enrollment No: 24BCS10448

This project creates one private, versioned, encrypted S3 bucket in `ap-south-1` with Terraform
and documents the complete `init → fmt → validate → plan → apply → show → output → destroy` workflow.

## Project structure

```text
terraform-s3-demo/
├── provider.tf          # terraform {} block (required_version, required_providers) + provider "aws"
├── variables.tf         # aws_region, bucket_prefix, environment, tags (with validation rules)
├── main.tf              # random_id + aws_s3_bucket + versioning + encryption + public access block
├── outputs.tf           # bucket_name, bucket_arn, bucket_region, bucket_domain_name
├── terraform.tfvars     # the values I actually use
├── README.md            # this file
├── .gitignore           # .terraform/, *.tfstate*, *.tfplan
└── .terraform.lock.hcl  # created by terraform init (committed on purpose)
```

## Architecture

```text
 terraform.tfvars ──► variables.tf ──► main.tf ──────────────────────────► outputs.tf
                                         │
                       provider.tf       │  random_id.suffix  (random provider)
                       hashicorp/aws ~>5 │        │
                       hashicorp/random  │        ▼
                                         │  aws_s3_bucket.demo  "om-session18-demo-dev-<hex>"
                                         │        ├── aws_s3_bucket_versioning                (Enabled)
                                         │        ├── aws_s3_bucket_server_side_encryption_configuration (AES256)
                                         │        └── aws_s3_bucket_public_access_block       (all true)
                                         ▼
                                   AWS ap-south-1
```

Why a random suffix? S3 bucket names are global across every AWS account, so `bucket_prefix`
alone could collide with someone else's bucket. `random_id` gives me 8 hex characters that make
the name unique while still being predictable from the prefix and environment.

## Prerequisites

```bash
terraform version          # >= 1.6.0
aws configure              # access key, secret, region ap-south-1
aws sts get-caller-identity
```

On this machine Terraform v1.16.5 is installed but there are **no AWS credentials**, so every step
that talks to AWS (plan/apply/show/output/destroy) is documented as *Expected output*. The steps
that work offline (init, fmt, validate) were really run and captured.

## Workflow

### 1. `terraform init`

Downloads the providers declared in `provider.tf` (`hashicorp/aws ~> 5.0`, `hashicorp/random ~> 3.6`)
into `.terraform/`, writes the dependency lock file `.terraform.lock.hcl`, and initialises the backend
(local by default, i.e. `terraform.tfstate` in this folder). I used `-backend=false` only because
there is no cloud access here; the provider download is identical.

```bash
terraform init -backend=false
```

Output (captured 2026-10-07):

```text
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/random versions matching "~> 3.6"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
- Installing hashicorp/random v3.9.1...
- Installed hashicorp/random v3.9.1 (signed by HashiCorp)

Terraform has created a lock file .terraform.lock.hcl to record the provider
selections it made above. Include this file in your version control repository
so that Terraform can guarantee to make the same selections by default when
you run "terraform init" in the future.

Terraform has been successfully initialized!

You may now begin working with Terraform. Try running "terraform plan" to see
any changes that are required for your infrastructure. All Terraform commands
should now work.
```

### 2. `terraform fmt`

Rewrites the `.tf` files into the canonical HCL style (alignment of `=`, two-space indentation).
`fmt` prints the names of files it changed; `-check` only reports and exits non-zero if anything
would change, which is what CI should use.

```bash
terraform fmt            # fix in place
terraform fmt -check -recursive; echo "exit=$?"
```

Output (captured 2026-10-07):

```text
exit=0
```

No file names were printed, so all files were already formatted.

### 3. `terraform validate`

Checks that the configuration is syntactically valid and internally consistent: every referenced
variable/resource exists, attribute names are valid for the provider schema, types match. It does
**not** contact AWS, so it works without credentials.

```bash
terraform validate
```

Output (captured 2026-10-07):

```text
Success! The configuration is valid.
```

### 4. `terraform plan`

Refreshes state, compares desired configuration against the state file and the real account, and
prints the actions it would take without doing anything. `+` = create, `~` = update in place,
`-` = destroy, `-/+` = replace. Values that are only known after creation are shown as
`(known after apply)`.

```bash
terraform plan -out=tfplan
```

Expected output:

```text
Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_s3_bucket.demo will be created
  + resource "aws_s3_bucket" "demo" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = (known after apply)
      + bucket_domain_name          = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = true
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = (known after apply)
      + request_payer               = (known after apply)
      + tags                        = {
          + "Environment" = "dev"
          + "Name"        = "om-session18-demo-dev"
        }
      + tags_all                    = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "om-session18-demo-dev"
          + "Owner"       = "Om Malviya"
          + "Project"     = "session18-terraform-iac"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)
    }

  # aws_s3_bucket_public_access_block.demo will be created
  + resource "aws_s3_bucket_public_access_block" "demo" {
      + block_public_acls       = true
      + block_public_policy     = true
      + bucket                  = (known after apply)
      + id                      = (known after apply)
      + ignore_public_acls      = true
      + restrict_public_buckets = true
    }

  # aws_s3_bucket_server_side_encryption_configuration.demo will be created
  + resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
      + bucket = (known after apply)
      + id     = (known after apply)

      + rule {
          + apply_server_side_encryption_by_default {
              + sse_algorithm = "AES256"
            }
        }
    }

  # aws_s3_bucket_versioning.demo will be created
  + resource "aws_s3_bucket_versioning" "demo" {
      + bucket = (known after apply)
      + id     = (known after apply)

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

  # random_id.suffix will be created
  + resource "random_id" "suffix" {
      + b64_std     = (known after apply)
      + b64_url     = (known after apply)
      + byte_length = 4
      + dec         = (known after apply)
      + hex         = (known after apply)
      + id          = (known after apply)
    }

Plan: 5 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + bucket_arn         = (known after apply)
  + bucket_domain_name = (known after apply)
  + bucket_name        = (known after apply)
  + bucket_region      = (known after apply)

Saved the plan to: tfplan

To perform exactly these actions, run the following command to apply:
    terraform apply "tfplan"
```

The bucket name is `(known after apply)` because it depends on `random_id.suffix.hex`.

### 5. `terraform apply`

Executes the plan. Without a saved plan it re-plans and asks for `yes`; with `tfplan` it applies
exactly what was reviewed. Resources are created in dependency order: `random_id` first, then the
bucket, then the three bucket sub-resources in parallel.

```bash
terraform apply tfplan
```

Expected output:

```text
random_id.suffix: Creating...
random_id.suffix: Creation complete after 0s [id=P5ocfg]
aws_s3_bucket.demo: Creating...
aws_s3_bucket.demo: Creation complete after 3s [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_versioning.demo: Creating...
aws_s3_bucket_public_access_block.demo: Creating...
aws_s3_bucket_server_side_encryption_configuration.demo: Creating...
aws_s3_bucket_public_access_block.demo: Creation complete after 1s [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_server_side_encryption_configuration.demo: Creation complete after 1s [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_versioning.demo: Creation complete after 2s [id=om-session18-demo-dev-3f9a1c7e]

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

bucket_arn = "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e"
bucket_domain_name = "om-session18-demo-dev-3f9a1c7e.s3.amazonaws.com"
bucket_name = "om-session18-demo-dev-3f9a1c7e"
bucket_region = "ap-south-1"
```

After apply a `terraform.tfstate` file appears in the folder (see "State" below).

### 6. `terraform show`

Prints the current state (or a saved plan file) in human-readable HCL-like form. This is how I
inspect what Terraform believes exists, including attributes AWS filled in (ARN, region, hosted
zone ID).

```bash
terraform show
terraform state list                     # just the resource addresses
terraform state show aws_s3_bucket.demo  # one resource
```

Expected output:

```text
# aws_s3_bucket.demo:
resource "aws_s3_bucket" "demo" {
    arn                         = "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e"
    bucket                      = "om-session18-demo-dev-3f9a1c7e"
    bucket_domain_name          = "om-session18-demo-dev-3f9a1c7e.s3.amazonaws.com"
    bucket_regional_domain_name = "om-session18-demo-dev-3f9a1c7e.s3.ap-south-1.amazonaws.com"
    force_destroy               = true
    hosted_zone_id              = "Z11RGJOFQNVJUP"
    id                          = "om-session18-demo-dev-3f9a1c7e"
    object_lock_enabled         = false
    region                      = "ap-south-1"
    request_payer               = "BucketOwner"
    tags                        = {
        "Environment" = "dev"
        "Name"        = "om-session18-demo-dev"
    }
    tags_all                    = {
        "Environment" = "dev"
        "ManagedBy"   = "Terraform"
        "Name"        = "om-session18-demo-dev"
        "Owner"       = "Om Malviya"
        "Project"     = "session18-terraform-iac"
    }

    server_side_encryption_configuration {
        rule {
            bucket_key_enabled = false
            apply_server_side_encryption_by_default {
                sse_algorithm = "AES256"
            }
        }
    }

    versioning {
        enabled    = true
        mfa_delete = false
    }
}

# aws_s3_bucket_public_access_block.demo:
resource "aws_s3_bucket_public_access_block" "demo" {
    block_public_acls       = true
    block_public_policy     = true
    bucket                  = "om-session18-demo-dev-3f9a1c7e"
    id                      = "om-session18-demo-dev-3f9a1c7e"
    ignore_public_acls      = true
    restrict_public_buckets = true
}

# aws_s3_bucket_server_side_encryption_configuration.demo:
resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
    bucket = "om-session18-demo-dev-3f9a1c7e"
    id     = "om-session18-demo-dev-3f9a1c7e"

    rule {
        apply_server_side_encryption_by_default {
            sse_algorithm = "AES256"
        }
    }
}

# aws_s3_bucket_versioning.demo:
resource "aws_s3_bucket_versioning" "demo" {
    bucket = "om-session18-demo-dev-3f9a1c7e"
    id     = "om-session18-demo-dev-3f9a1c7e"

    versioning_configuration {
        status = "Enabled"
    }
}

# random_id.suffix:
resource "random_id" "suffix" {
    b64_std     = "P5ocfg=="
    b64_url     = "P5ocfg"
    byte_length = 4
    dec         = "1067326590"
    hex         = "3f9a1c7e"
    id          = "P5ocfg"
}


Outputs:

bucket_arn = "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e"
bucket_domain_name = "om-session18-demo-dev-3f9a1c7e.s3.amazonaws.com"
bucket_name = "om-session18-demo-dev-3f9a1c7e"
bucket_region = "ap-south-1"
```

`terraform state list` expected output:

```text
aws_s3_bucket.demo
aws_s3_bucket_public_access_block.demo
aws_s3_bucket_server_side_encryption_configuration.demo
aws_s3_bucket_versioning.demo
random_id.suffix
```

### 7. `terraform output`

Reads the `output` blocks from state. `-raw` prints a single value without quotes (useful in
shell scripts), `-json` is for automation.

```bash
terraform output
terraform output -raw bucket_name
terraform output -json
```

Expected output:

```text
bucket_arn = "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e"
bucket_domain_name = "om-session18-demo-dev-3f9a1c7e.s3.amazonaws.com"
bucket_name = "om-session18-demo-dev-3f9a1c7e"
bucket_region = "ap-south-1"
```

```text
om-session18-demo-dev-3f9a1c7e
```

Verifying with the AWS CLI (expected):

```bash
aws s3api get-bucket-versioning --bucket "$(terraform output -raw bucket_name)"
aws s3api get-bucket-encryption --bucket "$(terraform output -raw bucket_name)"
aws s3api get-public-access-block --bucket "$(terraform output -raw bucket_name)"
```

```text
{
    "Status": "Enabled"
}
{
    "ServerSideEncryptionConfiguration": {
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                },
                "BucketKeyEnabled": false
            }
        ]
    }
}
{
    "PublicAccessBlockConfiguration": {
        "BlockPublicAcls": true,
        "IgnorePublicAcls": true,
        "BlockPublicPolicy": true,
        "RestrictPublicBuckets": true
    }
}
```

### 8. `terraform destroy`

Builds a destroy plan (everything in state gets `-`), asks for confirmation, then deletes in
reverse dependency order: the three sub-resources, then the bucket, then `random_id`.
`force_destroy = true` lets Terraform empty the bucket first; without it a non-empty bucket fails
with `BucketNotEmpty`.

```bash
terraform plan -destroy     # review first
terraform destroy
```

Expected output:

```text
random_id.suffix: Refreshing state... [id=P5ocfg]
aws_s3_bucket.demo: Refreshing state... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_versioning.demo: Refreshing state... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_public_access_block.demo: Refreshing state... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_server_side_encryption_configuration.demo: Refreshing state... [id=om-session18-demo-dev-3f9a1c7e]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # aws_s3_bucket.demo will be destroyed
  - resource "aws_s3_bucket" "demo" {
      - arn           = "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e" -> null
      - bucket        = "om-session18-demo-dev-3f9a1c7e" -> null
      - force_destroy = true -> null
      ...
    }

  # aws_s3_bucket_public_access_block.demo will be destroyed
  # aws_s3_bucket_server_side_encryption_configuration.demo will be destroyed
  # aws_s3_bucket_versioning.demo will be destroyed
  # random_id.suffix will be destroyed

Plan: 0 to add, 0 to change, 5 to destroy.

Changes to Outputs:
  - bucket_arn         = "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e" -> null
  - bucket_domain_name = "om-session18-demo-dev-3f9a1c7e.s3.amazonaws.com" -> null
  - bucket_name        = "om-session18-demo-dev-3f9a1c7e" -> null
  - bucket_region      = "ap-south-1" -> null

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

aws_s3_bucket_versioning.demo: Destroying... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_public_access_block.demo: Destroying... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_server_side_encryption_configuration.demo: Destroying... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket_public_access_block.demo: Destruction complete after 0s
aws_s3_bucket_server_side_encryption_configuration.demo: Destruction complete after 0s
aws_s3_bucket_versioning.demo: Destruction complete after 1s
aws_s3_bucket.demo: Destroying... [id=om-session18-demo-dev-3f9a1c7e]
aws_s3_bucket.demo: Destruction complete after 1s
random_id.suffix: Destroying... [id=P5ocfg]
random_id.suffix: Destruction complete after 0s

Destroy complete! Resources: 5 destroyed.
```

After destroy, `terraform state list` prints nothing and `terraform.tfstate` contains an empty
`resources: []` list (the previous version is kept in `terraform.tfstate.backup`).

## State and the lock file

**`terraform.tfstate`** is Terraform's database. It maps each resource address in my code
(`aws_s3_bucket.demo`) to the real object in AWS (bucket `om-session18-demo-dev-3f9a1c7e`) and
caches every attribute. `plan` = (configuration) vs (state) vs (refreshed real world). Without
state Terraform would not know the bucket already exists and would try to create it again.

- It is written by `apply`/`destroy`, never edited by hand; use `terraform state mv/rm/show` instead.
- It can contain secrets (DB passwords, keys) in plain text, so it is in `.gitignore`.
- In a team it belongs in a remote backend (S3 + DynamoDB lock, or Terraform Cloud) so two people
  cannot apply at the same time; a `.terraform.tfstate.lock.info` file / DynamoDB item is the
  *state lock* that prevents concurrent writes.

**`.terraform.lock.hcl`** is a different kind of lock: the *dependency lock file*. `init` records
the exact provider versions it selected (`aws 5.100.0`, `random 3.9.1`) and their checksums, so a
colleague running `init` next month gets the same versions even though `~> 5.0` would allow
5.101. It contains no secrets and **should be committed**. `terraform init -upgrade` updates it.

| File | Created by | Commit? | Purpose |
|---|---|---|---|
| `terraform.tfstate` | apply/destroy | No | Maps code to real resources, caches attributes |
| `terraform.tfstate.backup` | apply/destroy | No | Previous state version |
| `.terraform.tfstate.lock.info` | plan/apply (transient) | No | Prevents concurrent state writes |
| `.terraform.lock.hcl` | init | Yes | Pins provider versions and hashes |
| `.terraform/` | init | No | Downloaded provider binaries |

## What I observed

- `validate` and `fmt` are fully offline; only `plan` onwards needs credentials. That is why CI
  pipelines run `fmt -check` and `validate` on every push and `plan` only on pull requests.
- The newer AWS provider splits bucket settings into separate resources
  (`aws_s3_bucket_versioning`, `..._server_side_encryption_configuration`, `..._public_access_block`)
  instead of nested blocks, so one logical bucket becomes 4 Terraform resources plus `random_id` = 5.
- The random suffix is stored in state, so repeated `apply` runs keep the same bucket name;
  it only changes if `random_id.suffix` is destroyed and recreated.

## Screenshots

Terminal output blocks stand in for screenshots:

| Screenshot in spec | Stand-in in this README |
|---|---|
| terraform init | "Output (captured 2026-10-07)" under step 1 |
| terraform fmt / validate | Captured outputs under steps 2 and 3 |
| terraform plan | Expected output under step 4 (`Plan: 5 to add`) |
| terraform apply | Expected output under step 5 (`Apply complete! Resources: 5 added`) |
| terraform show / output | Expected outputs under steps 6 and 7 |
| terraform destroy | Expected output under step 8 (`Destroy complete! Resources: 5 destroyed`) |

## Deliverables

- `provider.tf` – terraform/required_providers (aws ~> 5.0, random ~> 3.6) and the aws provider with default tags.
- `variables.tf` – `aws_region`, `bucket_prefix`, `environment`, `tags` with validation.
- `main.tf` – random suffix, S3 bucket, versioning, AES256 encryption, public access block.
- `outputs.tf` – bucket name, ARN, region, domain name.
- `terraform.tfvars` – values used for this submission.
- `.gitignore` – excludes `.terraform/`, state and plan files.
- `.terraform.lock.hcl` – provider lock file created by the captured `terraform init`.
- `README.md` – this workflow document.
