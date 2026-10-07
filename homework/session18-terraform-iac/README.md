# Session 18 – Terraform & Infrastructure as Code

Student: Om Malviya | Enrollment No: 24BCS10448

Infrastructure as Code means describing cloud resources in version-controlled files and letting a
tool (Terraform) create, change and delete them. In this session I wrote a small Terraform project
that creates an S3 bucket and researched the five core AWS services I will keep meeting
(IAM, EC2, S3, VPC, DynamoDB/RDS).

```text
homework/session18-terraform-iac/
├── README.md                      # this index
├── terraform-s3-demo/             # Task 1 – Terraform project + full workflow README
│   ├── main.tf  variables.tf  outputs.tf  provider.tf  terraform.tfvars
│   ├── README.md  .gitignore  .terraform.lock.hcl
└── aws-services/                  # Task 2 – research notes
    ├── 01-iam/README.md
    ├── 02-ec2/README.md
    ├── 03-s3/README.md
    ├── 04-vpc/README.md
    └── 05-dynamodb-rds/README.md
```

## Task 1: Terraform S3 Demo

Project: [`terraform-s3-demo/`](terraform-s3-demo/) – creates one S3 bucket in `ap-south-1` named
`<bucket_prefix>-<environment>-<random hex>`, with versioning enabled, AES256 server-side encryption,
all public access blocked and tags from a variable. Five resources in total
(`random_id` + bucket + versioning + encryption + public access block).

| File | Content |
|---|---|
| `provider.tf` | `terraform {}` with `required_version >= 1.6.0`, `hashicorp/aws ~> 5.0`, `hashicorp/random ~> 3.6`; `provider "aws"` with region + `default_tags` |
| `variables.tf` | `aws_region` (ap-south-1), `bucket_prefix`, `environment` (validated), `tags` |
| `main.tf` | `random_id.suffix`, `aws_s3_bucket.demo`, `aws_s3_bucket_versioning`, `aws_s3_bucket_server_side_encryption_configuration`, `aws_s3_bucket_public_access_block` |
| `outputs.tf` | `bucket_name`, `bucket_arn`, `bucket_region`, `bucket_domain_name` |
| `terraform.tfvars` | the values I use |
| `README.md` | the complete workflow, each command with explanation and output |

The workflow I performed/documented, in the order the spec asks:

```bash
cd terraform-s3-demo
terraform init -backend=false      # captured – downloads aws 5.100.0 + random 3.9.1, writes lock file
terraform fmt -check -recursive    # captured – exit 0, nothing to reformat
terraform validate                 # captured – "Success! The configuration is valid."
terraform plan -out=tfplan         # expected – Plan: 5 to add, 0 to change, 0 to destroy.
terraform apply tfplan             # expected – Apply complete! Resources: 5 added ...
terraform show                     # expected – full state of the 5 resources
terraform output                   # expected – bucket_name / bucket_arn / bucket_region
terraform destroy                  # expected – Destroy complete! Resources: 5 destroyed.
```

Output (captured 2026-10-07) – summary of the offline steps:

```text
$ terraform version
Terraform v1.16.5
on darwin_arm64

$ terraform init -backend=false
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/random versions matching "~> 3.6"...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
- Installing hashicorp/random v3.9.1...
- Installed hashicorp/random v3.9.1 (signed by HashiCorp)
Terraform has created a lock file .terraform.lock.hcl ...
Terraform has been successfully initialized!

$ terraform fmt -check -recursive; echo "exit=$?"
exit=0

$ terraform validate
Success! The configuration is valid.
```

Because this machine has no AWS credentials, `plan`, `apply`, `show`, `output` and `destroy` are
written as *Expected output* in the project README, in the real format the AWS provider prints
(resource blocks with `(known after apply)`, `Plan: 5 to add`, `Creating...`/`Creation complete`,
`Destroy complete! Resources: 5 destroyed.`). The README also explains `terraform.tfstate` versus
`.terraform.lock.hcl` and why only the latter is committed.

Full details: [`terraform-s3-demo/README.md`](terraform-s3-demo/README.md).

## Task 2: AWS Services Research

One README per service. Each covers every bullet from the spec with a short explanation, a table,
AWS CLI examples, a JSON policy where relevant, a small Terraform snippet, and common use cases.

| # | Service | Bullets covered | File |
|---|---|---|---|
| 01 | IAM – Governance | What is IAM, Users, Groups, Roles, Policies (JSON example), Permissions evaluation, Least privilege, Best practices, Use cases | [`aws-services/01-iam/README.md`](aws-services/01-iam/README.md) |
| 02 | EC2 – Compute | What is EC2, AMI, Instance types, Key pairs, Security Groups, EBS, Public vs private IP, Instance lifecycle, Use cases | [`aws-services/02-ec2/README.md`](aws-services/02-ec2/README.md) |
| 03 | S3 – Storage | What is S3, Buckets, Objects, Storage classes, Versioning, Lifecycle policies (JSON), Encryption, Bucket policies (JSON), Use cases | [`aws-services/03-s3/README.md`](aws-services/03-s3/README.md) |
| 04 | VPC – Networking | What is VPC, CIDR, Subnets, Route tables, Internet Gateway, NAT Gateway, Security Groups, Network ACLs, Public vs private subnet | [`aws-services/04-vpc/README.md`](aws-services/04-vpc/README.md) |
| 05 | DynamoDB & RDS | DynamoDB: NoSQL, Tables, Items, Attributes, Partition key, Sort key, Use cases. RDS: Relational DB, Engines, DB instances, Security, Backups, Multi-AZ, Read replicas, Use cases | [`aws-services/05-dynamodb-rds/README.md`](aws-services/05-dynamodb-rds/README.md) |

What I took away from the research, in one line each:

- **IAM**: everything is denied until allowed, explicit deny wins, use roles instead of access keys.
- **EC2**: AMI + instance type + EBS + security group + key pair; public IP changes on stop/start.
- **S3**: globally unique bucket names, versioning + lifecycle + AES256 + Block Public Access is the safe default.
- **VPC**: a subnet is public only because its route table sends `0.0.0.0/0` to an Internet Gateway.
- **DynamoDB vs RDS**: key-based access at any scale without servers vs SQL with managed HA (Multi-AZ) and read scaling (replicas).

## Screenshots

| Screenshot the spec would expect | Stand-in |
|---|---|
| `terraform init` / `fmt` / `validate` succeeding | Captured text blocks in this README and in `terraform-s3-demo/README.md` |
| `terraform plan` / `apply` / `show` / `output` / `destroy` | Expected output blocks in `terraform-s3-demo/README.md` (no AWS credentials available) |
| Bucket in the S3 console | `terraform show` expected block and `aws s3api get-bucket-*` expected output |

## Deliverables

- `terraform-s3-demo/` – Terraform project (main.tf, variables.tf, outputs.tf, provider.tf, terraform.tfvars, README.md, .gitignore, .terraform.lock.hcl); `terraform validate` passes.
- `aws-services/01-iam/README.md` – IAM research notes.
- `aws-services/02-ec2/README.md` – EC2 research notes.
- `aws-services/03-s3/README.md` – S3 research notes.
- `aws-services/04-vpc/README.md` – VPC research notes.
- `aws-services/05-dynamodb-rds/README.md` – DynamoDB and RDS research notes.
- `README.md` – this index.
