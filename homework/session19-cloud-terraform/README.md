# Session 19 – Cloud & Terraform in Action

Student: Om Malviya | Enrollment No: 24BCS10448

## Task: Build an end-to-end cloud infrastructure project using Terraform

The project in [`terraform-aws-infra/`](terraform-aws-infra/) creates a complete, working piece of
AWS infrastructure from nothing: a VPC with a public subnet connected to the internet, a security
group, an EC2 web server running nginx, and an S3 bucket – and tears it all down again with one
command. It demonstrates every bullet from the spec: providers, variables, resources, outputs,
dependencies, AWS infrastructure, state, plan, apply, destroy.

```text
homework/session19-cloud-terraform/
├── README.md                       # this write-up
└── terraform-aws-infra/
    ├── versions.tf                 # terraform {} + required_providers (aws ~> 5.0, random ~> 3.6)
    ├── provider.tf                 # provider "aws" { region, default_tags }
    ├── variables.tf                # 10 input variables
    ├── main.tf                     # VPC, subnet, IGW, route table, association, SG, AMI data, EC2, S3
    ├── outputs.tf                  # 8 outputs
    ├── user_data.sh                # cloud-init script: install nginx + hello page
    ├── terraform.tfvars.example    # copy to terraform.tfvars
    ├── Makefile                    # make init / plan / apply / destroy
    ├── README.md                   # quick start
    ├── .gitignore                  # .terraform/, *.tfstate*, tfplan, terraform.tfvars
    └── .terraform.lock.hcl         # created by the captured terraform init
```

## Architecture diagram

```text
                                 Internet
                                    │
                          ┌─────────▼──────────┐
                          │  Internet Gateway  │  aws_internet_gateway.main
                          └─────────┬──────────┘
 ┌────────────────────────────────── │ ────────────────────────────────────┐
 │ VPC 10.0.0.0/16  (aws_vpc.main)   │        region ap-south-1            │
 │                                   │                                     │
 │   Route table "public"  (aws_route_table.public)                        │
 │     10.0.0.0/16 → local                                                 │
 │     0.0.0.0/0   → igw  ◄──────────┘                                     │
 │          │ aws_route_table_association.public                           │
 │   ┌──────▼──────────────────────────────────────────────────────────┐   │
 │   │ Public subnet 10.0.1.0/24  AZ ap-south-1a  (aws_subnet.public)  │   │
 │   │ map_public_ip_on_launch = true                                  │   │
 │   │                                                                 │   │
 │   │   ┌─────────────────────────────────────────────────────┐       │   │
 │   │   │ Security group web-sg (aws_security_group.web)      │       │   │
 │   │   │  in  tcp/22  from allowed_ssh_cidr                  │       │   │
 │   │   │  in  tcp/80  from 0.0.0.0/0                         │       │   │
 │   │   │  out all     to   0.0.0.0/0                         │       │   │
 │   │   │   ┌───────────────────────────────────────────┐     │       │   │
 │   │   │   │ EC2 t3.micro  (aws_instance.web)          │     │       │   │
 │   │   │   │ AMI: latest Amazon Linux 2023 (data src)  │     │       │   │
 │   │   │   │ user_data: dnf install nginx, hello page  │     │       │   │
 │   │   │   │ private 10.0.1.x  public 13.x.x.x         │     │       │   │
 │   │   │   └───────────────────────────────────────────┘     │       │   │
 │   │   └─────────────────────────────────────────────────────┘       │   │
 │   └─────────────────────────────────────────────────────────────────┘   │
 └─────────────────────────────────────────────────────────────────────────┘

                  ┌──────────────────────────────────────────────┐
   (regional)     │ S3 bucket  session19-infra-<random hex>      │  aws_s3_bucket.data
                  │   versioning Enabled   SSE AES256            │  + versioning / encryption /
                  │   public access blocked                      │    public_access_block
                  └──────────────────────────────────────────────┘
```

Terraform resource graph (output of `terraform graph`, arrows = "depends on"):

```text
aws_subnet.public ──────────────► aws_vpc.main
aws_internet_gateway.main ──────► aws_vpc.main
aws_security_group.web ─────────► aws_vpc.main
aws_route_table.public ─────────► aws_internet_gateway.main
aws_route_table_association.public ─► aws_route_table.public, aws_subnet.public
aws_instance.web ───────────────► data.aws_ami.al2023, aws_subnet.public,
                                  aws_security_group.web, aws_internet_gateway.main (explicit)
aws_s3_bucket.data ─────────────► random_id.bucket_suffix
aws_s3_bucket_versioning.data / _server_side_encryption_configuration.data /
  _public_access_block.data ────► aws_s3_bucket.data
```

## Concepts demonstrated (one subsection per spec bullet)

### Terraform providers

`versions.tf` pins Terraform itself and declares the two providers; `provider.tf` configures the
AWS one. A provider is the plugin that translates my HCL into API calls – `hashicorp/aws` for
everything in AWS, `hashicorp/random` for the bucket suffix.

```hcl
terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws    = { source = "hashicorp/aws", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags { tags = merge(var.tags, { Project = var.project_name }) }
}
```

`~> 5.0` means "any 5.x, never 6.0". `default_tags` makes every taggable resource carry
`Environment`, `ManagedBy`, `Owner` and `Project` without repeating them. Credentials are **not** in
the code – the provider reads `~/.aws/credentials`, environment variables or an assumed role.

Output (captured 2026-10-07) of `terraform providers`:

```text
Providers required by configuration:
.
├── provider[registry.terraform.io/hashicorp/random] ~> 3.6
└── provider[registry.terraform.io/hashicorp/aws] ~> 5.0
```

### Variables

`variables.tf` makes the project reusable: the same code deploys to another region, CIDR or
instance size by changing `terraform.tfvars`, not the code.

| Variable | Type | Default | Used by |
|---|---|---|---|
| `aws_region` | string | `ap-south-1` | provider |
| `project_name` | string | `session19-infra` | names and tags of every resource |
| `vpc_cidr` | string | `10.0.0.0/16` | `aws_vpc.main` |
| `public_subnet_cidr` | string | `10.0.1.0/24` | `aws_subnet.public` |
| `availability_zone` | string | `ap-south-1a` | `aws_subnet.public` |
| `instance_type` | string | `t3.micro` | `aws_instance.web` |
| `allowed_ssh_cidr` | string | `203.0.113.10/32` (placeholder – replace with my IP) | SG port 22 rule |
| `key_name` | string | `null` (no key pair) | `aws_instance.web` |
| `bucket_prefix` | string | `session19-infra` | `aws_s3_bucket.data` |
| `tags` | map(string) | Environment/ManagedBy/Owner | provider default_tags |

Precedence I rely on: defaults in `variables.tf` < `terraform.tfvars` < `-var` / `TF_VAR_*`.
`terraform.tfvars` is git-ignored (it holds my IP and key name); `terraform.tfvars.example` is the
template that is committed.

### Resources

`main.tf` declares 12 managed resources plus one data source, in the order they are built:

| # | Resource address | AWS object | Key arguments |
|---|---|---|---|
| 1 | `aws_vpc.main` | VPC | `cidr_block`, DNS support + hostnames |
| 2 | `aws_subnet.public` | Subnet in ap-south-1a | `vpc_id`, `cidr_block`, `map_public_ip_on_launch = true` |
| 3 | `aws_internet_gateway.main` | IGW attached to VPC | `vpc_id` |
| 4 | `aws_route_table.public` | Route table with `0.0.0.0/0 → igw` | `route { gateway_id }` |
| 5 | `aws_route_table_association.public` | Links subnet ↔ route table | `subnet_id`, `route_table_id` |
| 6 | `aws_security_group.web` | Firewall | ingress 22 (allowed cidr), 80 (anywhere), egress all |
| – | `data.aws_ami.al2023` | Lookup, not created | `most_recent`, owner amazon, name `al2023-ami-2023.*-x86_64` |
| 7 | `aws_instance.web` | EC2 t3.micro | ami, subnet, SG, public IP, `user_data`, gp3 root, `depends_on` IGW |
| 8 | `random_id.bucket_suffix` | 4 random bytes (in state only) | `byte_length = 4` |
| 9 | `aws_s3_bucket.data` | Bucket `session19-infra-<hex>` | `force_destroy = true` |
| 10 | `aws_s3_bucket_versioning.data` | Versioning | `status = "Enabled"` |
| 11 | `aws_s3_bucket_server_side_encryption_configuration.data` | SSE | `AES256` |
| 12 | `aws_s3_bucket_public_access_block.data` | Block public access | all four flags true |

The web server content comes from `user_data.sh`, injected with `file("${path.module}/user_data.sh")`.
cloud-init runs it once on first boot: `dnf install -y nginx`, write `/usr/share/nginx/html/index.html`,
`systemctl enable --now nginx`.

### Outputs

`outputs.tf` exposes the values I need after apply, so I do not have to open the console:

| Output | Value |
|---|---|
| `vpc_id` | `aws_vpc.main.id` |
| `public_subnet_id` | `aws_subnet.public.id` |
| `security_group_id` | `aws_security_group.web.id` |
| `ami_id` | AMI the data source selected |
| `instance_id` | `aws_instance.web.id` |
| `instance_public_ip` | `aws_instance.web.public_ip` |
| `http_url` | `"http://${aws_instance.web.public_ip}"` – paste into a browser / curl |
| `bucket_name` | `aws_s3_bucket.data.bucket` |

### Dependencies (implicit vs explicit)

Terraform builds a dependency graph and creates resources in parallel wherever the graph allows.

**Implicit dependency** – created automatically whenever one resource references another's
attribute. `aws_subnet.public` uses `aws_vpc.main.id`, so the VPC is always created first and
destroyed last. Almost every edge in the graph above is implicit.

**Explicit dependency** – `depends_on`, used when the relationship exists in the real world but
not in the code. The EC2 instance does not reference the Internet Gateway anywhere, yet its
`user_data` needs internet access to download nginx. Without `depends_on`, Terraform could
launch the instance before the IGW is attached and the `dnf install` would fail:

```hcl
resource "aws_instance" "web" {
  # ...
  depends_on = [aws_internet_gateway.main]
}
```

Output (captured 2026-10-07) – relevant lines from `terraform graph` (no credentials needed):

```text
  "aws_instance.web" -> "data.aws_ami.al2023";
  "aws_instance.web" -> "aws_internet_gateway.main";
  "aws_instance.web" -> "aws_security_group.web";
  "aws_instance.web" -> "aws_subnet.public";
  "aws_internet_gateway.main" -> "aws_vpc.main";
  "aws_route_table.public" -> "aws_internet_gateway.main";
  "aws_route_table_association.public" -> "aws_route_table.public";
  "aws_route_table_association.public" -> "aws_subnet.public";
  "aws_s3_bucket.data" -> "random_id.bucket_suffix";
  "aws_s3_bucket_public_access_block.data" -> "aws_s3_bucket.data";
  "aws_s3_bucket_server_side_encryption_configuration.data" -> "aws_s3_bucket.data";
  "aws_s3_bucket_versioning.data" -> "aws_s3_bucket.data";
  "aws_security_group.web" -> "aws_vpc.main";
  "aws_subnet.public" -> "aws_vpc.main";
```

The `aws_instance.web -> aws_internet_gateway.main` edge exists only because of `depends_on`.
Destroy walks the graph in reverse: instance and bucket settings first, VPC last.

### AWS infrastructure

What exists in the account after `apply` (and why each piece is needed for `curl` to work):

1. **VPC** – private address space `10.0.0.0/16` with DNS hostnames enabled.
2. **Public subnet** `10.0.1.0/24` in `ap-south-1a`; new instances get a public IPv4.
3. **Internet Gateway** attached to the VPC – two-way internet access for public IPs.
4. **Route table** with `0.0.0.0/0 → igw`, **associated** to the subnet – this is what makes the subnet "public".
5. **Security group** – SSH only from my IP, HTTP from the world, all outbound.
6. **EC2 t3.micro** running Amazon Linux 2023 with nginx, public IP, 8 GiB gp3 root volume.
7. **S3 bucket** with a random suffix, versioning, AES256 encryption, public access blocked.

### Terraform state

After `apply`, `terraform.tfstate` records the mapping from each address in `main.tf` to the real
IDs (`vpc-0a1b…`, `i-0c3d…`) and every attribute. `plan` diffs configuration ↔ state ↔ real world.
It is local in this project (fine for a single student), git-ignored (contains IDs, IPs and could
contain secrets), and the dependency lock file `.terraform.lock.hcl` *is* committed so that
everyone gets `aws 5.100.0` / `random 3.9.1`. For a team I would move it to an S3 backend with a
DynamoDB lock table (the bucket from Session 18 is exactly that kind of bucket).

```bash
terraform state list
```

Expected output:

```text
data.aws_ami.al2023
aws_instance.web
aws_internet_gateway.main
aws_route_table.public
aws_route_table_association.public
aws_s3_bucket.data
aws_s3_bucket_public_access_block.data
aws_s3_bucket_server_side_encryption_configuration.data
aws_s3_bucket_versioning.data
aws_security_group.web
aws_subnet.public
aws_vpc.main
random_id.bucket_suffix
```

## Full workflow

### 0. Prepare

```bash
cd homework/session19-cloud-terraform/terraform-aws-infra
cp terraform.tfvars.example terraform.tfvars
# edit: allowed_ssh_cidr = "$(curl -s https://checkip.amazonaws.com)/32", key_name = "om-session19-key"
aws sts get-caller-identity
```

### 1. `terraform init` (make init)

```bash
terraform init -backend=false     # -backend=false only because I have no AWS access here
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

### 2. `terraform fmt` and `terraform validate` (make validate)

```bash
terraform fmt -check -recursive; echo "exit=$?"
terraform validate
```

Output (captured 2026-10-07):

```text
exit=0
Success! The configuration is valid.
```

### 3. `terraform plan` (make plan)

```bash
terraform plan -out=tfplan
```

Expected output (abridged – the full plan prints every attribute of all 12 resources):

```text
data.aws_ami.al2023: Reading...
data.aws_ami.al2023: Read complete after 1s [id=ami-0f5ee92e2d63afc18]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + ami                                  = "ami-0f5ee92e2d63afc18"
      + associate_public_ip_address          = true
      + availability_zone                    = (known after apply)
      + id                                   = (known after apply)
      + instance_type                        = "t3.micro"
      + private_ip                           = (known after apply)
      + public_ip                            = (known after apply)
      + subnet_id                            = (known after apply)
      + user_data                            = "e3c1b2d9f0a4c7e8b5d6a1f2c3e4d5b6a7f8c9d0"
      + vpc_security_group_ids               = (known after apply)
      + tags                                 = {
          + "Name" = "session19-infra-web"
        }
      + tags_all                             = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "session19-infra-web"
          + "Owner"       = "Om Malviya"
          + "Project"     = "session19-infra"
        }

      + root_block_device {
          + delete_on_termination = true
          + volume_size           = 8
          + volume_type           = "gp3"
          ...
        }
    }

  # aws_internet_gateway.main will be created
  + resource "aws_internet_gateway" "main" {
      + arn      = (known after apply)
      + id       = (known after apply)
      + owner_id = (known after apply)
      + vpc_id   = (known after apply)
      + tags     = { + "Name" = "session19-infra-igw" }
    }

  # aws_route_table.public will be created
  + resource "aws_route_table" "public" {
      + id     = (known after apply)
      + route  = [
          + {
              + cidr_block = "0.0.0.0/0"
              + gateway_id = (known after apply)
            },
        ]
      + vpc_id = (known after apply)
    }

  # aws_route_table_association.public will be created
  # aws_s3_bucket.data will be created
  # aws_s3_bucket_public_access_block.data will be created
  # aws_s3_bucket_server_side_encryption_configuration.data will be created
  # aws_s3_bucket_versioning.data will be created

  # aws_security_group.web will be created
  + resource "aws_security_group" "web" {
      + name        = "session19-infra-web-sg"
      + description = "Allow SSH from a trusted CIDR and HTTP from anywhere"
      + ingress     = [
          + { cidr_blocks = ["0.0.0.0/0"],       from_port = 80, to_port = 80, protocol = "tcp", description = "HTTP from anywhere" },
          + { cidr_blocks = ["203.0.113.10/32"], from_port = 22, to_port = 22, protocol = "tcp", description = "SSH from allowed CIDR" },
        ]
      + egress      = [
          + { cidr_blocks = ["0.0.0.0/0"], from_port = 0, to_port = 0, protocol = "-1", description = "Allow all outbound traffic" },
        ]
      + vpc_id      = (known after apply)
    }

  # aws_subnet.public will be created
  + resource "aws_subnet" "public" {
      + availability_zone       = "ap-south-1a"
      + cidr_block              = "10.0.1.0/24"
      + id                      = (known after apply)
      + map_public_ip_on_launch = true
      + vpc_id                  = (known after apply)
    }

  # aws_vpc.main will be created
  + resource "aws_vpc" "main" {
      + arn                  = (known after apply)
      + cidr_block           = "10.0.0.0/16"
      + enable_dns_hostnames = true
      + enable_dns_support   = true
      + id                   = (known after apply)
      + tags                 = { + "Name" = "session19-infra-vpc" }
    }

  # random_id.bucket_suffix will be created
  + resource "random_id" "bucket_suffix" {
      + byte_length = 4
      + hex         = (known after apply)
      + id          = (known after apply)
    }

Plan: 12 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + ami_id             = "ami-0f5ee92e2d63afc18"
  + bucket_name        = (known after apply)
  + http_url           = (known after apply)
  + instance_id        = (known after apply)
  + instance_public_ip = (known after apply)
  + public_subnet_id   = (known after apply)
  + security_group_id  = (known after apply)
  + vpc_id             = (known after apply)

Saved the plan to: tfplan

To perform exactly these actions, run the following command to apply:
    terraform apply "tfplan"
```

Note that `ami_id` is already known at plan time because data sources are read during plan.

### 4. `terraform apply` (make apply)

```bash
terraform apply tfplan
```

Expected output:

```text
random_id.bucket_suffix: Creating...
random_id.bucket_suffix: Creation complete after 0s [id=qL3eZw]
aws_vpc.main: Creating...
aws_s3_bucket.data: Creating...
aws_s3_bucket.data: Creation complete after 3s [id=session19-infra-a8bdde67]
aws_s3_bucket_versioning.data: Creating...
aws_s3_bucket_public_access_block.data: Creating...
aws_s3_bucket_server_side_encryption_configuration.data: Creating...
aws_s3_bucket_public_access_block.data: Creation complete after 1s [id=session19-infra-a8bdde67]
aws_s3_bucket_server_side_encryption_configuration.data: Creation complete after 1s [id=session19-infra-a8bdde67]
aws_s3_bucket_versioning.data: Creation complete after 2s [id=session19-infra-a8bdde67]
aws_vpc.main: Creation complete after 12s [id=vpc-0a1b2c3d4e5f67890]
aws_internet_gateway.main: Creating...
aws_subnet.public: Creating...
aws_security_group.web: Creating...
aws_internet_gateway.main: Creation complete after 1s [id=igw-0123456789abcdef0]
aws_route_table.public: Creating...
aws_subnet.public: Creation complete after 1s [id=subnet-0f1e2d3c4b5a69788]
aws_route_table.public: Creation complete after 1s [id=rtb-0abcdef1234567890]
aws_route_table_association.public: Creating...
aws_route_table_association.public: Creation complete after 1s [id=rtbassoc-0fedcba9876543210]
aws_security_group.web: Creation complete after 3s [id=sg-0123abcd4567ef890]
aws_instance.web: Creating...
aws_instance.web: Still creating... [10s elapsed]
aws_instance.web: Creation complete after 14s [id=i-0abc12345def67890]

Apply complete! Resources: 12 added, 0 changed, 0 destroyed.

Outputs:

ami_id = "ami-0f5ee92e2d63afc18"
bucket_name = "session19-infra-a8bdde67"
http_url = "http://13.233.45.67"
instance_id = "i-0abc12345def67890"
instance_public_ip = "13.233.45.67"
public_subnet_id = "subnet-0f1e2d3c4b5a69788"
security_group_id = "sg-0123abcd4567ef890"
vpc_id = "vpc-0a1b2c3d4e5f67890"
```

The log shows the graph in action: `random_id` and the VPC start together; the bucket resources
and the networking proceed in parallel; the instance starts only after subnet, SG **and** IGW
exist.

### 5. Verify

nginx needs 30–60 seconds after "Creation complete" because user_data runs after the instance boots.

```bash
terraform output
curl -s "$(terraform output -raw http_url)"
ssh -i ~/.ssh/om-session19-key.pem ec2-user@"$(terraform output -raw instance_public_ip)" \
  'systemctl is-active nginx; sudo tail -n 3 /var/log/cloud-init-output.log'
aws ec2 describe-instances --instance-ids "$(terraform output -raw instance_id)" \
  --query 'Reservations[].Instances[].{State:State.Name,Public:PublicIpAddress,Private:PrivateIpAddress}'
aws s3api get-bucket-versioning --bucket "$(terraform output -raw bucket_name)"
```

Expected output:

```text
<!DOCTYPE html>
<html>
<head><title>Session 19 - Terraform on AWS</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 10%;">
  <h1>Hello from Terraform!</h1>
  <p>Session 19 - Cloud &amp; Terraform in Action</p>
  <p>Student: Om Malviya</p>
  <p>Host: ip-10-0-1-23.ap-south-1.compute.internal</p>
</body>
</html>

active
Cloud-init v. 22.2.2 finished at Tue, 07 Oct 2026 10:21:14 +0000. Up 38.51 seconds.

[
    {
        "State": "running",
        "Public": "13.233.45.67",
        "Private": "10.0.1.23"
    }
]
{
    "Status": "Enabled"
}
```

If `curl` hangs: check the security group has port 80 from `0.0.0.0/0`, the route table has
`0.0.0.0/0 → igw`, and wait for cloud-init to finish. If `ssh` is refused: `allowed_ssh_cidr`
must be my current public IP `/32` and `key_name` must be set.

### 6. `terraform destroy` (make destroy)

```bash
terraform plan -destroy    # review
terraform destroy
```

Expected output:

```text
data.aws_ami.al2023: Reading...
random_id.bucket_suffix: Refreshing state... [id=qL3eZw]
aws_vpc.main: Refreshing state... [id=vpc-0a1b2c3d4e5f67890]
aws_s3_bucket.data: Refreshing state... [id=session19-infra-a8bdde67]
...
aws_instance.web: Refreshing state... [id=i-0abc12345def67890]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  - destroy

Terraform will perform the following actions:

  # aws_instance.web will be destroyed
  # aws_internet_gateway.main will be destroyed
  # aws_route_table.public will be destroyed
  # aws_route_table_association.public will be destroyed
  # aws_s3_bucket.data will be destroyed
  # aws_s3_bucket_public_access_block.data will be destroyed
  # aws_s3_bucket_server_side_encryption_configuration.data will be destroyed
  # aws_s3_bucket_versioning.data will be destroyed
  # aws_security_group.web will be destroyed
  # aws_subnet.public will be destroyed
  # aws_vpc.main will be destroyed
  # random_id.bucket_suffix will be destroyed

Plan: 0 to add, 0 to change, 12 to destroy.

Changes to Outputs:
  - ami_id             = "ami-0f5ee92e2d63afc18" -> null
  - bucket_name        = "session19-infra-a8bdde67" -> null
  - http_url           = "http://13.233.45.67" -> null
  - instance_id        = "i-0abc12345def67890" -> null
  - instance_public_ip = "13.233.45.67" -> null
  - public_subnet_id   = "subnet-0f1e2d3c4b5a69788" -> null
  - security_group_id  = "sg-0123abcd4567ef890" -> null
  - vpc_id             = "vpc-0a1b2c3d4e5f67890" -> null

Do you really want to destroy all resources?
  Terraform will destroy all your managed infrastructure, as shown above.
  There is no undo. Only 'yes' will be accepted to confirm.

  Enter a value: yes

aws_route_table_association.public: Destroying... [id=rtbassoc-0fedcba9876543210]
aws_s3_bucket_versioning.data: Destroying... [id=session19-infra-a8bdde67]
aws_s3_bucket_public_access_block.data: Destroying... [id=session19-infra-a8bdde67]
aws_s3_bucket_server_side_encryption_configuration.data: Destroying... [id=session19-infra-a8bdde67]
aws_instance.web: Destroying... [id=i-0abc12345def67890]
aws_route_table_association.public: Destruction complete after 1s
aws_route_table.public: Destroying... [id=rtb-0abcdef1234567890]
aws_s3_bucket_public_access_block.data: Destruction complete after 0s
aws_s3_bucket_server_side_encryption_configuration.data: Destruction complete after 0s
aws_s3_bucket_versioning.data: Destruction complete after 1s
aws_s3_bucket.data: Destroying... [id=session19-infra-a8bdde67]
aws_route_table.public: Destruction complete after 1s
aws_s3_bucket.data: Destruction complete after 1s
random_id.bucket_suffix: Destroying... [id=qL3eZw]
random_id.bucket_suffix: Destruction complete after 0s
aws_instance.web: Still destroying... [id=i-0abc12345def67890, 10s elapsed]
aws_instance.web: Still destroying... [id=i-0abc12345def67890, 20s elapsed]
aws_instance.web: Still destroying... [id=i-0abc12345def67890, 30s elapsed]
aws_instance.web: Destruction complete after 31s
aws_subnet.public: Destroying... [id=subnet-0f1e2d3c4b5a69788]
aws_security_group.web: Destroying... [id=sg-0123abcd4567ef890]
aws_internet_gateway.main: Destroying... [id=igw-0123456789abcdef0]
aws_subnet.public: Destruction complete after 1s
aws_security_group.web: Destruction complete after 1s
aws_internet_gateway.main: Destruction complete after 2s
aws_vpc.main: Destroying... [id=vpc-0a1b2c3d4e5f67890]
aws_vpc.main: Destruction complete after 1s

Destroy complete! Resources: 12 destroyed.
```

Verify nothing is left:

```bash
terraform state list            # prints nothing
aws ec2 describe-vpcs --filters Name=tag:Project,Values=session19-infra --query 'Vpcs[].VpcId'   # []
```

## Cost note and cleanup

| Resource | Cost while running (ap-south-1, approx.) |
|---|---|
| t3.micro | $0.0116/h – free tier 750 h/month for the first 12 months |
| 8 GiB gp3 root volume | ~$0.70/month – free tier 30 GiB |
| Public IPv4 address | $0.005/h (~$3.60/month) – **not** free tier since 2024 |
| VPC, subnet, IGW, route table, SG | free |
| S3 bucket (empty) | free; storage $0.025/GB/month |

The only way to stop the meter is `terraform destroy` (or `make destroy`). `force_destroy = true`
on the bucket means destroy works even if I uploaded test objects. I run `terraform state list`
afterwards to be sure nothing is left.

## Makefile

```bash
make init      # terraform init
make fmt       # terraform fmt -recursive
make validate  # fmt + terraform validate
make plan      # validate + terraform plan -out=tfplan
make apply     # terraform apply tfplan
make output    # terraform output
make destroy   # terraform destroy
make clean     # rm -rf .terraform tfplan
```

## What I observed

- `init`, `fmt`, `validate` and `graph` all work offline; everything from `plan` on needs
  credentials because `plan` reads the AMI data source and refreshes state.
- The AWS provider splits S3 settings into separate resources, so "one bucket" is 4 resources and
  the whole project is 12 managed resources + 1 data source.
- `depends_on` is needed only once, for the EC2 → IGW relationship; every other ordering comes for
  free from attribute references.
- A random suffix in the bucket name avoids the "BucketAlreadyExists" error that a fixed name
  would give when a classmate applies the same code.

## Screenshots

| Screenshot the spec would expect | Stand-in |
|---|---|
| Terraform project structure | Tree at the top of this README |
| Architecture diagram | ASCII diagram and `terraform graph` edges above |
| `terraform init` / `validate` | Captured output blocks (2026-10-07) |
| `terraform plan` | Expected output block (`Plan: 12 to add`) |
| `terraform apply` and outputs | Expected output block (`Apply complete! Resources: 12 added`) |
| nginx page in browser / curl | Expected `curl` output in "Verify" |
| EC2 / VPC / S3 in the AWS console | Expected `aws ec2 describe-instances` and `aws s3api` output |
| `terraform destroy` | Expected output block (`Destroy complete! Resources: 12 destroyed`) |

## Deliverables

- `terraform-aws-infra/versions.tf`, `provider.tf` – Terraform/provider configuration (aws ~> 5.0, random ~> 3.6).
- `terraform-aws-infra/variables.tf`, `terraform.tfvars.example` – 10 input variables and sample values.
- `terraform-aws-infra/main.tf` – VPC, subnet, IGW, route table + association, security group, AMI data source, EC2, S3 (12 resources).
- `terraform-aws-infra/outputs.tf` – 8 outputs including `http_url` and `instance_public_ip`.
- `terraform-aws-infra/user_data.sh` – nginx bootstrap script.
- `terraform-aws-infra/Makefile` – init/fmt/validate/plan/apply/output/destroy/clean targets.
- `terraform-aws-infra/.gitignore`, `.terraform.lock.hcl` – ignore state/plugins, pin provider versions.
- `terraform-aws-infra/README.md` – quick start.
- `README.md` – this write-up: architecture diagram, all concepts, full workflow with captured init/validate and expected plan/apply/destroy output, verification, cost and cleanup.
