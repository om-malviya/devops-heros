# 01 – IAM (Identity and Access Management) – Governance

Student: Om Malviya | Enrollment No: 24BCS10448

## What is IAM?

IAM is the AWS service that answers two questions for every API call:

1. **Authentication** – *who* is making the request (a user, a role, an application)?
2. **Authorization** – *is that identity allowed* to perform this action on this resource?

It is global (not regional), free, and every other AWS service depends on it. Every request to
AWS – console click, CLI command, SDK call, Terraform apply – is signed with credentials that
belong to an IAM identity and evaluated against IAM policies.

```text
 Request: s3:GetObject on arn:aws:s3:::my-bucket/report.csv
      │
      ▼
 ┌───────────┐  who?   ┌──────────────────┐  allowed?  ┌─────────┐
 │ Principal │ ──────► │ IAM policy       │ ─────────► │  Allow  │
 │ user/role │         │ evaluation       │            │  / Deny │
 └───────────┘         └──────────────────┘            └─────────┘
```

## Users

An IAM **user** is a permanent identity for one person or one application. A user can have:

| Credential | Used for | Notes |
|---|---|---|
| Console password (+ MFA) | AWS web console | Enforce MFA with a policy or Identity Center |
| Access key ID + secret access key | CLI / SDK / Terraform | Max 2 active keys, rotate regularly |
| SSH keys / git credentials | CodeCommit | Rarely needed |

```bash
aws iam create-user --user-name om-dev
aws iam create-login-profile --user-name om-dev --password 'ChangeMe-FakePass-123!' --password-reset-required
aws iam create-access-key --user-name om-dev          # returns AccessKeyId + SecretAccessKey ONCE
aws iam list-users --query 'Users[].UserName'
```

A new user has **no permissions at all** (implicit deny) until a policy is attached to the user
or to a group the user is in.

## Groups

A **group** is a collection of users. Policies attached to a group apply to all its members. Groups
cannot be nested and cannot be a principal (you cannot assume a group).

```bash
aws iam create-group --group-name developers
aws iam attach-group-policy --group-name developers \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
aws iam add-user-to-group --group-name developers --user-name om-dev
aws iam get-group --group-name developers --query 'Users[].UserName'
```

Typical groups: `admins`, `developers`, `read-only`, `billing`. Managing permissions per group
instead of per user is the first IAM best practice.

## Roles

A **role** is an identity with permissions but **no long-term credentials**. Something *assumes*
the role and receives temporary credentials (15 minutes to 12 hours) from STS. Who may assume it
is defined by the role's **trust policy**.

| Who assumes the role | Example |
|---|---|
| AWS service | EC2 instance reading S3, Lambda writing to DynamoDB |
| IAM user in the same account | Developer switching to `admin-role` with MFA |
| Another AWS account | Cross-account access from a CI/CD account |
| External identity provider | GitHub Actions via OIDC, SAML SSO users |

Trust policy that lets EC2 assume the role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

```bash
aws iam create-role --role-name ec2-s3-reader --assume-role-policy-document file://trust.json
aws iam attach-role-policy --role-name ec2-s3-reader \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess
# EC2 needs an instance profile wrapper around the role
aws iam create-instance-profile --instance-profile-name ec2-s3-reader
aws iam add-role-to-instance-profile --instance-profile-name ec2-s3-reader --role-name ec2-s3-reader
```

The instance then gets credentials from the metadata service automatically; no access keys are
ever stored on the machine. This is why "use roles, not keys" is repeated everywhere.

## Policies

A **policy** is a JSON document that lists permissions. Each statement has:

| Element | Meaning | Example |
|---|---|---|
| `Effect` | `Allow` or `Deny` | `"Allow"` |
| `Action` | API operations | `"s3:GetObject"`, `"ec2:*"` |
| `Resource` | ARNs the statement applies to | `"arn:aws:s3:::my-bucket/*"` |
| `Condition` | Optional extra checks | `"aws:MultiFactorAuthPresent": "true"` |
| `Principal` | Only in resource/trust policies: who | `{"AWS": "arn:aws:iam::123456789012:root"}` |

Policy types:

| Type | Attached to | Example |
|---|---|---|
| AWS managed | users/groups/roles | `AmazonS3ReadOnlyAccess`, `AdministratorAccess` |
| Customer managed | users/groups/roles | your own reusable policy |
| Inline | one identity | one-off, deleted with the identity |
| Resource-based | the resource itself | S3 bucket policy, SQS queue policy, KMS key policy |
| Permissions boundary | user/role | maximum permissions an identity can ever have |
| Service control policy (SCP) | AWS Organizations OU/account | guardrail for whole accounts |

Example customer-managed policy – read-only access to one bucket:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListTheBucket",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e"
    },
    {
      "Sid": "ReadObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:GetObjectVersion"],
      "Resource": "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e/*"
    },
    {
      "Sid": "DenyWithoutTLS",
      "Effect": "Deny",
      "Action": "s3:*",
      "Resource": "*",
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

```bash
aws iam create-policy --policy-name s3-demo-readonly --policy-document file://policy.json
aws iam attach-user-policy --user-name om-dev \
  --policy-arn arn:aws:iam::123456789012:policy/s3-demo-readonly
```

## Permissions (how evaluation works)

```text
 1. Start with implicit DENY (nothing is allowed by default)
 2. Is there an explicit DENY anywhere (identity policy, resource policy, SCP, boundary)?  → DENY
 3. Is there an ALLOW in identity policy or resource policy (and within SCP/boundary limits)? → ALLOW
 4. Otherwise                                                                                → DENY
```

Key rules I remember:

- An explicit `Deny` always wins over any `Allow`.
- Permissions are the **union** of all policies attached to the user and its groups.
- For cross-account access both sides must allow it (identity policy in account A **and**
  resource policy in account B).
- A permissions boundary or SCP never grants anything; it only caps what other policies can grant.

Check effective permissions without running the real action:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789012:user/om-dev \
  --action-names s3:GetObject s3:DeleteObject \
  --resource-arns arn:aws:s3:::om-session18-demo-dev-3f9a1c7e/report.csv
```

## Least privilege

Grant only the actions, on only the resources, needed for the job, and nothing more.

Bad (what beginners do):

```json
{ "Effect": "Allow", "Action": "s3:*", "Resource": "*" }
```

Good (what the application actually needs):

```json
{
  "Effect": "Allow",
  "Action": ["s3:PutObject"],
  "Resource": "arn:aws:s3:::app-uploads-prod/incoming/*",
  "Condition": { "StringEquals": { "s3:x-amz-server-side-encryption": "AES256" } }
}
```

How I get there in practice:

1. Start with the AWS managed policy to make it work.
2. Look at **IAM Access Analyzer → Generate policy** or CloudTrail to see which actions were really used.
3. Replace with a customer-managed policy that names those actions and specific ARNs.
4. Review "last accessed" information every few months and remove unused permissions.

## IAM best practices

| # | Practice | Why |
|---|---|---|
| 1 | Do not use the root user for daily work; lock it with MFA and delete its access keys | Root cannot be restricted by any policy |
| 2 | Enable MFA for every human user (or use IAM Identity Center / SSO) | Stolen password alone is useless |
| 3 | Use roles for applications and EC2/Lambda/ECS, never embedded access keys | Temporary credentials, automatic rotation |
| 4 | Use groups to assign permissions to people | One place to change, consistent |
| 5 | Apply least privilege; prefer customer-managed over `*` policies | Limits blast radius |
| 6 | Rotate access keys (90 days) and remove unused users/keys | Credential reports show age |
| 7 | Use conditions (`aws:SourceIp`, `aws:MultiFactorAuthPresent`, `aws:PrincipalOrgID`) | Context-aware access |
| 8 | Turn on CloudTrail in all regions and Access Analyzer | Audit who did what; find public/cross-account exposure |
| 9 | Use permissions boundaries / SCPs when delegating IAM admin | Prevents privilege escalation |
| 10 | Never commit credentials to git; use env vars, `~/.aws/credentials`, or roles | Leaked keys get exploited within minutes |

```bash
aws iam generate-credential-report && aws iam get-credential-report --query Content --output text | base64 -d
aws iam get-account-summary --query 'SummaryMap.AccountMFAEnabled'
```

## Terraform snippet

```hcl
data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_s3_reader" {
  name               = "ec2-s3-reader"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}

resource "aws_iam_role_policy_attachment" "s3_readonly" {
  role       = aws_iam_role.ec2_s3_reader.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "ec2_s3_reader" {
  name = "ec2-s3-reader"
  role = aws_iam_role.ec2_s3_reader.name
}

# attach to an instance: iam_instance_profile = aws_iam_instance_profile.ec2_s3_reader.name
```

## Common use cases

| Use case | IAM feature |
|---|---|
| Give each developer console + CLI access with limited rights | Users in groups (or Identity Center), MFA |
| EC2 web server reads config from S3 | Role + instance profile |
| Lambda writes to DynamoDB and CloudWatch Logs | Execution role |
| GitHub Actions deploys with Terraform without stored keys | Role with OIDC trust policy |
| CI account deploys into prod account | Cross-account role (`sts:AssumeRole`) |
| Break-glass admin access | Role requiring MFA, logged by CloudTrail |
| Deny deleting production buckets even for admins | SCP or explicit Deny with condition |
| Share one bucket with a partner account | Bucket (resource) policy with their account as Principal |

## Summary in my own words

IAM is the gatekeeper. Users are for people, roles are for machines and for temporary elevation,
groups make user management scalable, and policies are the JSON rules that connect identities to
allowed actions. Everything is denied until allowed, an explicit deny beats everything, and the
job of a DevOps engineer is to keep every identity at the minimum permission that still works.
