# 03 – S3 (Simple Storage Service) – Storage

Student: Om Malviya | Enrollment No: 24BCS10448

## What is S3?

S3 is AWS's object storage: a flat key/value store for files of any type, accessed over HTTPS,
designed for 99.999999999 % (11 nines) durability by storing every object redundantly across at
least three Availability Zones. There are no disks to size and no servers to patch – I pay per GB
stored, per request and per GB transferred out.

```text
  s3://om-session18-demo-dev-3f9a1c7e/            ◄── bucket (globally unique name, lives in one region)
      ├── reports/2026/10/sales.csv                ◄── object key (the "path" is just part of the name)
      ├── reports/2026/10/sales.csv  (version 2)   ◄── versioning keeps older copies
      └── images/logo.png
```

It is **not** a file system (no real folders, no in-place edits – an object is replaced as a whole),
but it is the backbone of backups, data lakes, static websites and Terraform remote state.

## Buckets

A bucket is the top-level container. Rules:

- Name is **globally unique** across all AWS accounts, 3–63 chars, lowercase letters, digits,
  dots and hyphens, must start with a letter/digit, no `_`, no IP-address look-alikes.
- Created in one **region**; data stays there unless I replicate it.
- Soft limit of 100 buckets per account (can be raised to 1,000s); unlimited objects per bucket.
- Deleting a bucket requires it to be empty (Terraform's `force_destroy = true` handles this).

```bash
aws s3 mb s3://om-session18-demo-dev-3f9a1c7e --region ap-south-1
aws s3 ls                                 # list buckets
aws s3api get-bucket-location --bucket om-session18-demo-dev-3f9a1c7e
aws s3 rb s3://om-session18-demo-dev-3f9a1c7e --force   # delete bucket + contents
```

Expected output of `get-bucket-location`:

```text
{
    "LocationConstraint": "ap-south-1"
}
```

## Objects

An object = **key** (name, up to 1,024 bytes) + **value** (data, 0 B to 5 TB) + **metadata**
(Content-Type, custom `x-amz-meta-*`) + **version ID** + tags. Objects larger than 100 MB should be
uploaded with multipart upload (the CLI does it automatically for files >8 MB).

```bash
aws s3 cp report.csv s3://om-session18-demo-dev-3f9a1c7e/reports/2026/10/report.csv
aws s3 cp s3://om-session18-demo-dev-3f9a1c7e/reports/2026/10/report.csv ./report.csv
aws s3 ls s3://om-session18-demo-dev-3f9a1c7e/reports/ --recursive --human-readable
aws s3 sync ./site s3://om-session18-demo-dev-3f9a1c7e/site --delete
aws s3api head-object --bucket om-session18-demo-dev-3f9a1c7e --key reports/2026/10/report.csv
aws s3 presign s3://om-session18-demo-dev-3f9a1c7e/reports/2026/10/report.csv --expires-in 3600
```

Expected `head-object`:

```text
{
    "LastModified": "2026-10-07T10:12:45+00:00",
    "ContentLength": 20480,
    "ETag": "\"9b2cf535f27731c974343645a3985328\"",
    "VersionId": "3HL4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY",
    "ContentType": "text/csv",
    "ServerSideEncryption": "AES256"
}
```

Consistency: since Dec 2020 S3 is **strongly read-after-write consistent** for all operations.

## Storage classes

| Class | Availability / design | Min storage duration | Retrieval | Best for |
|---|---|---|---|---|
| S3 Standard | 99.99 %, 3+ AZ | none | ms | Frequently accessed data (default) |
| S3 Intelligent-Tiering | auto-moves between tiers | none | ms | Unknown or changing access patterns |
| S3 Standard-IA | 99.9 %, 3+ AZ | 30 days | ms, retrieval fee per GB | Backups, older data accessed monthly |
| S3 One Zone-IA | 99.5 %, **1 AZ** | 30 days | ms | Re-creatable data, secondary copies |
| S3 Glacier Instant Retrieval | archive, ms access | 90 days | ms | Archives needing instant access quarterly |
| S3 Glacier Flexible Retrieval | archive | 90 days | minutes to 12 h | Yearly archives, free bulk retrieval |
| S3 Glacier Deep Archive | cheapest (~$1/TB/month) | 180 days | 12–48 h | Compliance, 7–10 year retention |
| S3 Express One Zone | single-AZ, directory bucket | – | sub-ms | Latency-sensitive ML/analytics |

Class is set per object (`--storage-class STANDARD_IA`) or changed automatically by lifecycle rules.

## Versioning

Versioning keeps every version of an object instead of overwriting. Once enabled it can only be
*suspended*, never disabled. A `DELETE` on a versioned object does not remove data – it adds a
**delete marker**; deleting the marker "undeletes" the object.

```bash
aws s3api put-bucket-versioning --bucket om-session18-demo-dev-3f9a1c7e \
  --versioning-configuration Status=Enabled
aws s3api list-object-versions --bucket om-session18-demo-dev-3f9a1c7e --prefix reports/
aws s3api get-object --bucket om-session18-demo-dev-3f9a1c7e --key reports/2026/10/report.csv \
  --version-id 3HL4kqtJlcpXroDTDmJ+rmSpXd3dIbrHY old-report.csv
```

Why I enable it: protection against accidental deletes/overwrites, and it is required for
replication and for safe Terraform remote state. Downside: storage cost grows, so pair it with a
lifecycle rule for non-current versions.

## Lifecycle policies

Lifecycle rules automate transitions between storage classes and expirations. Example: move
reports to Standard-IA after 30 days, Glacier after 90, delete after 365, and clean up old
versions and abandoned multipart uploads.

```json
{
  "Rules": [
    {
      "ID": "reports-tiering",
      "Status": "Enabled",
      "Filter": { "Prefix": "reports/" },
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" }
      ],
      "Expiration": { "Days": 365 },
      "NoncurrentVersionTransitions": [ { "NoncurrentDays": 30, "StorageClass": "STANDARD_IA" } ],
      "NoncurrentVersionExpiration": { "NoncurrentDays": 90 },
      "AbortIncompleteMultipartUpload": { "DaysAfterInitiation": 7 }
    }
  ]
}
```

```bash
aws s3api put-bucket-lifecycle-configuration --bucket om-session18-demo-dev-3f9a1c7e \
  --lifecycle-configuration file://lifecycle.json
aws s3api get-bucket-lifecycle-configuration --bucket om-session18-demo-dev-3f9a1c7e
```

Rules run once a day; transitions have minimum-duration constraints (e.g. 30 days before IA).

## Encryption

| Type | Keys managed by | How to request | Notes |
|---|---|---|---|
| SSE-S3 (`AES256`) | S3 | header `x-amz-server-side-encryption: AES256` | **Default for all new objects since Jan 2023**, free |
| SSE-KMS (`aws:kms`) | AWS KMS (AWS- or customer-managed CMK) | `--server-side-encryption aws:kms --ssekms-key-id ...` | Audit trail in CloudTrail, key policies, small per-request cost; enable S3 Bucket Keys to cut cost |
| DSSE-KMS | KMS, two layers | `aws:kms:dsse` | Compliance requiring double encryption |
| SSE-C | Customer, sent with every request | headers with the key | S3 does not store the key |
| Client-side | Application, before upload | SDK encryption client | S3 only sees ciphertext |

In transit everything is TLS; a bucket policy can refuse plain HTTP (`aws:SecureTransport = false`).

```bash
aws s3api put-bucket-encryption --bucket om-session18-demo-dev-3f9a1c7e \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api get-bucket-encryption --bucket om-session18-demo-dev-3f9a1c7e
```

## Bucket policies

A bucket policy is a **resource-based IAM policy** attached to the bucket. It is the right tool to
grant access to other accounts, to services (CloudFront), or to add guardrails such as "TLS only".
Together with **Block Public Access** (account- and bucket-level switch that overrides any policy
or ACL that would make data public) it controls who can reach the data.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontRead",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e/*",
      "Condition": {
        "StringEquals": { "AWS:SourceArn": "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE" }
      }
    },
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e",
        "arn:aws:s3:::om-session18-demo-dev-3f9a1c7e/*"
      ],
      "Condition": { "Bool": { "aws:SecureTransport": "false" } }
    }
  ]
}
```

```bash
aws s3api put-bucket-policy --bucket om-session18-demo-dev-3f9a1c7e --policy file://policy.json
aws s3api put-public-access-block --bucket om-session18-demo-dev-3f9a1c7e \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

ACLs are legacy; new buckets have "Object Ownership = Bucket owner enforced", which disables ACLs
so bucket policies and IAM are the only access controls.

## Terraform snippet

```hcl
resource "aws_s3_bucket" "demo" {
  bucket        = "om-session18-demo-dev-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_versioning" "demo" {
  bucket = aws_s3_bucket.demo.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "demo" {
  bucket = aws_s3_bucket.demo.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

resource "aws_s3_bucket_public_access_block" "demo" {
  bucket                  = aws_s3_bucket.demo.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

The full version of this is in `../../terraform-s3-demo/`.

## Common use cases

| Use case | Features used |
|---|---|
| Backups and disaster recovery | Versioning, lifecycle to Glacier, cross-region replication |
| Static website / SPA hosting | Website hosting or CloudFront + OAC, bucket policy |
| Data lake for analytics | Prefix partitioning, Athena/Glue, Parquet, Intelligent-Tiering |
| Application file uploads (images, documents) | Presigned URLs, SSE-KMS, event notifications to Lambda |
| Log archive (CloudTrail, ALB, VPC Flow Logs) | Bucket policies for AWS services, lifecycle expiry |
| Terraform remote state | Versioning + encryption + DynamoDB lock table |
| Software artifact / container layer storage | Standard class, replication to other regions |
| Big data input/output (EMR, Spark, ML datasets) | High throughput, Express One Zone for low latency |

## Summary in my own words

S3 is where everything that is "a file" goes in AWS. I create a uniquely named bucket in a region,
put objects in it under keys, keep history with versioning, let lifecycle rules push old data to
cheaper classes, keep it encrypted (AES256 by default) and private (Block Public Access), and open
it up only through explicit bucket policies. In Task 1 of this session I built exactly that bucket
with Terraform.
