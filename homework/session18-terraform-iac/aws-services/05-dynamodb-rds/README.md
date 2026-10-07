# 05 – DynamoDB & RDS – Database Services

Student: Om Malviya | Enrollment No: 24BCS10448

AWS offers two very different managed database families. **DynamoDB** is a serverless NoSQL
key-value/document store; **RDS** runs classic relational engines (MySQL, PostgreSQL, …) on managed
instances. Both remove the undifferentiated work (patching, backups, replication) but they solve
different problems.

```text
   DynamoDB                                         RDS
   ┌──────────────────────────┐                     ┌──────────────────────────────┐
   │ Table "Orders"           │                     │ db.t3.micro  (MySQL 8.0)      │
   │ PK: customerId  SK: orderDate               ─► │ database "shop"               │
   │ items = JSON documents   │                     │   tables: customers, orders   │
   │ serverless, pay/request  │                     │   SQL joins, transactions     │
   │ ms latency at any scale  │                     │ Multi-AZ standby, read replica│
   └──────────────────────────┘                     └──────────────────────────────┘
```

---

## Part A – DynamoDB

### NoSQL

NoSQL databases drop the rigid relational schema and SQL joins in exchange for horizontal scale and
predictable single-digit-millisecond latency. DynamoDB is a **key-value and document** database:
data is partitioned across many servers by a hash of the key, so performance stays flat whether a
table holds 1 MB or 100 TB.

| | Relational (RDS) | DynamoDB (NoSQL) |
|---|---|---|
| Schema | Fixed columns per table | Only the key attributes are fixed; every item can differ |
| Queries | Any SQL, joins, ad-hoc | By key (and indexes); design table around access patterns |
| Scaling | Vertical (bigger instance), read replicas | Horizontal, automatic |
| Transactions | Full ACID across tables | ACID within one request (up to 100 items) |
| Pricing | Per instance-hour + storage | Per request (or provisioned capacity) + storage |
| Ops | Patching/failover managed by RDS | Fully serverless, no instances at all |

### Tables

A table is the top-level collection of items. It requires only a name and the **primary key**
definition; everything else (indexes, TTL, streams, capacity mode) is optional.

```bash
aws dynamodb create-table \
  --table-name Orders \
  --attribute-definitions AttributeName=customerId,AttributeType=S AttributeName=orderDate,AttributeType=S \
  --key-schema AttributeName=customerId,KeyType=HASH AttributeName=orderDate,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST \
  --tags Key=Project,Value=session18
aws dynamodb describe-table --table-name Orders --query 'Table.{Status:TableStatus,Items:ItemCount,Key:KeySchema}'
```

Expected output:

```text
{
    "Status": "ACTIVE",
    "Items": 0,
    "Key": [
        { "AttributeName": "customerId", "KeyType": "HASH" },
        { "AttributeName": "orderDate", "KeyType": "RANGE" }
    ]
}
```

Capacity modes: **on-demand** (pay per read/write request, no planning – good default) or
**provisioned** (set read/write capacity units, optionally with auto scaling – cheaper for steady,
predictable traffic). Tables can also be **global tables** replicated across regions.

### Items

An item is one record – the equivalent of a row – identified uniquely by its primary key. Max
size 400 KB. Items in the same table do not need the same attributes.

```bash
aws dynamodb put-item --table-name Orders --item '{
  "customerId": {"S": "C-1001"},
  "orderDate":  {"S": "2026-10-07T10:15:00Z"},
  "orderId":    {"S": "O-77231"},
  "total":      {"N": "1499.00"},
  "items":      {"L": [{"S": "keyboard"}, {"S": "mouse"}]},
  "shipped":    {"BOOL": false}
}'

aws dynamodb get-item --table-name Orders \
  --key '{"customerId":{"S":"C-1001"},"orderDate":{"S":"2026-10-07T10:15:00Z"}}'
```

### Attributes

Attributes are the name/value fields of an item. Only key attributes must be declared in the
table definition; the rest are schema-less.

| Type code | Type | Example |
|---|---|---|
| S | String | `"C-1001"` |
| N | Number (sent as string) | `"1499.00"` |
| B | Binary | base64 |
| BOOL | Boolean | `true` |
| NULL | Null | – |
| L | List | `["keyboard","mouse"]` |
| M | Map (nested document) | `{"street": "...", "city": "Indore"}` |
| SS / NS / BS | String/Number/Binary set | `{"a","b"}` |

### Partition key

The partition key (HASH key) decides **which physical partition** stores the item: DynamoDB hashes
its value and routes the item accordingly. Rules of thumb:

- Pick a key with **many distinct values and even access** (customerId, deviceId, orderId).
- Avoid low-cardinality keys (`status = "ACTIVE"`) or time-only keys that create a **hot
  partition** where all traffic lands on one server.
- With only a partition key, it must be unique per item (`GetItem` by key is O(1)).

### Sort key

The optional sort key (RANGE key) makes the primary key **composite**: partition key + sort key
must be unique together, and items with the same partition key are stored **sorted** by the sort
key. This enables range queries within one partition – "all orders of customer C-1001 in October":

```bash
aws dynamodb query --table-name Orders \
  --key-condition-expression "customerId = :c AND begins_with(orderDate, :m)" \
  --expression-attribute-values '{":c":{"S":"C-1001"},":m":{"S":"2026-10"}}'
```

Supported sort-key conditions: `=`, `<`, `<=`, `>`, `>=`, `BETWEEN`, `begins_with`. Other access
patterns are served by **Global Secondary Indexes** (different partition/sort key, eventually
consistent) and **Local Secondary Indexes** (same partition key, different sort key, must be created
with the table). `Scan` reads the whole table and should be avoided in hot paths.

### DynamoDB use cases

| Use case | Why DynamoDB fits |
|---|---|
| Shopping carts, user profiles, sessions | Key lookup by userId, millisecond latency, TTL expiry |
| IoT / telemetry ingestion | Massive write throughput, deviceId + timestamp key |
| Gaming leaderboards and player state | Low latency, global tables for multi-region |
| Serverless backends (Lambda + API Gateway) | No connection pooling problems, pay per request |
| **Terraform state locking** | `LockID` partition key table used with the S3 backend |
| Event sourcing / audit logs | Append-only items, Streams to trigger processing |

Terraform snippet (the classic Terraform lock table):

```hcl
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-state-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }

  tags = { Project = "session18" }
}
```

---

## Part B – RDS (Relational Database Service)

### Relational database

A relational database stores data in **tables with fixed columns**, enforces relationships with
primary/foreign keys, and is queried with **SQL** including joins and multi-row ACID transactions.
RDS provides this as a managed service: AWS provisions the EC2 instance and EBS storage underneath,
installs the engine, and handles OS patching, minor version upgrades, automated backups,
monitoring and failover. I still own the schema, queries, indexes and users inside the database.

What I cannot do on RDS: SSH into the host or become superuser – everything goes through the
engine's SQL interface and the RDS API.

### Supported engines

| Engine | Versions (typical) | Notes |
|---|---|---|
| MySQL | 8.0, 8.4 | Most common for web apps |
| PostgreSQL | 13–17 | Rich features, extensions (PostGIS) |
| MariaDB | 10.11, 11.4 | MySQL fork |
| Oracle | 19c, 21c | License included or BYOL |
| Microsoft SQL Server | 2017–2022 | Express/Web/Standard/Enterprise |
| Db2 | 11.5 | IBM, BYOL |
| **Amazon Aurora** (MySQL- and PostgreSQL-compatible) | – | AWS-built storage layer, 6 copies across 3 AZs, up to 15 replicas, Serverless v2 |

```bash
aws rds describe-db-engine-versions --engine mysql --query 'DBEngineVersions[-3:].EngineVersion'
```

### DB instances

A DB instance is one database server environment: engine + instance class + storage + network
placement. One instance can host many databases (schemas).

| Setting | Example | Meaning |
|---|---|---|
| Instance class | `db.t3.micro` (free tier), `db.m6g.large`, `db.r6i.xlarge` | CPU/RAM, same families as EC2 with `db.` prefix |
| Storage | gp3 20 GiB, autoscaling to 100 GiB | EBS under the hood; io1/io2 for high IOPS |
| Endpoint | `shop-db.c9akciq32.ap-south-1.rds.amazonaws.com:3306` | DNS name that survives failover |
| Subnet group | 2+ private subnets in different AZs | Where the instance (and standby) can live |
| Parameter group | `max_connections`, `time_zone` | Engine config (my.cnf / postgresql.conf) |
| Option group | Oracle TDE, SQL Server audit | Engine add-ons |

```bash
aws rds create-db-subnet-group --db-subnet-group-name shop-db-subnets \
  --db-subnet-group-description "private subnets" --subnet-ids subnet-0aaa subnet-0bbb

aws rds create-db-instance \
  --db-instance-identifier shop-db \
  --engine mysql --engine-version 8.0 \
  --db-instance-class db.t3.micro \
  --allocated-storage 20 --storage-type gp3 \
  --master-username admin --master-user-password 'FakePassword-ChangeMe-123' \
  --db-subnet-group-name shop-db-subnets \
  --vpc-security-group-ids sg-0db \
  --no-publicly-accessible \
  --backup-retention-period 7 \
  --multi-az

aws rds describe-db-instances --db-instance-identifier shop-db \
  --query 'DBInstances[].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,MultiAZ:MultiAZ}'
```

Expected output:

```text
[
    {
        "Status": "available",
        "Endpoint": "shop-db.c9akciq32xyz.ap-south-1.rds.amazonaws.com",
        "MultiAZ": true
    }
]
```

### Security

| Layer | Control |
|---|---|
| Network | Private subnets, `PubliclyAccessible = false`, security group allowing 3306/5432 **only from the app SG** |
| Authentication | Master password in **Secrets Manager** (RDS can manage/rotate it), **IAM database authentication** (15-min tokens), Kerberos for AD |
| Encryption at rest | KMS encryption of storage, snapshots, replicas (must be chosen at creation) |
| Encryption in transit | TLS with RDS CA certificate; enforce with `require_secure_transport=ON` (MySQL) / `rds.force_ssl=1` (PostgreSQL) |
| Authorization | Database users/roles with least privilege; application user ≠ admin |
| Auditing | CloudTrail for API calls, engine audit logs exported to CloudWatch Logs |
| Patching | Auto minor version upgrade in the maintenance window |

### Backups

| Type | Trigger | Retention | Restore granularity |
|---|---|---|---|
| Automated backups | Daily snapshot in backup window + transaction logs every 5 min | 0–35 days (0 = disabled; 7 default) | **Point-in-time recovery** to any second in the window |
| Manual snapshots | `create-db-snapshot` or console | Until deleted | Snapshot time; can be copied/shared cross-region/account |
| Aurora backtrack | Aurora MySQL only | Up to 72 h | Rewind in place |

Restores always create a **new** instance (new endpoint). Snapshots of encrypted instances stay
encrypted. Automated backups of Multi-AZ instances are taken from the standby, so no I/O pause.

```bash
aws rds create-db-snapshot --db-instance-identifier shop-db --db-snapshot-identifier shop-db-before-migration
aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier shop-db \
  --target-db-instance-identifier shop-db-restored --restore-time 2026-10-07T09:30:00Z
```

### Multi-AZ

Multi-AZ keeps a **synchronous standby replica** in a different Availability Zone. Every write is
committed on both before returning. The standby is **not readable** (except Multi-AZ DB *cluster*
deployments with two readable standbys). On primary failure, host failure, AZ outage or
maintenance, RDS flips the DNS endpoint to the standby in about 60–120 seconds – the application
only needs to reconnect.

```text
   app ──► shop-db.xxx.ap-south-1.rds.amazonaws.com
                    │ (DNS switches on failover)
          ┌─────────▼──────────┐   synchronous    ┌────────────────────┐
          │ primary  ap-south-1a│ ───────────────► │ standby ap-south-1b │
          └────────────────────┘   replication    └────────────────────┘
```

Purpose: **high availability and durability**, not performance. Cost: roughly 2x the single-AZ price.

### Read replicas

A read replica is an **asynchronous** copy that *is* readable. Reporting, analytics and
read-heavy traffic are pointed at the replica endpoints, taking load off the primary. Up to 15
replicas (5 for non-Aurora), in the same region, another region, or another account; a replica
can be **promoted** to a standalone primary (disaster recovery or migration).

| | Multi-AZ standby | Read replica |
|---|---|---|
| Replication | Synchronous | Asynchronous (lag in seconds) |
| Readable | No | Yes |
| Purpose | Availability / failover | Read scaling, DR, cross-region |
| Failover | Automatic DNS switch | Manual promote |
| Endpoint | Same as primary | Own endpoint per replica |

```bash
aws rds create-db-instance-read-replica --db-instance-identifier shop-db-reader \
  --source-db-instance-identifier shop-db --db-instance-class db.t3.micro
aws rds promote-read-replica --db-instance-identifier shop-db-reader
```

### RDS use cases

| Use case | Choice |
|---|---|
| Web application backend (orders, users, payments) | MySQL/PostgreSQL Multi-AZ, read replica for reports |
| Existing on-prem Oracle/SQL Server migration | RDS Oracle/SQL Server (DMS to migrate), BYOL |
| SaaS needing high availability and fast recovery | Aurora with 2+ replicas, Global Database for cross-region |
| Spiky dev/test workloads | Aurora Serverless v2 scales ACUs up and down |
| Analytics on production data without slowing it | Read replica or Aurora reader endpoint |
| Compliance (PCI, HIPAA) | KMS encryption, private subnets, IAM auth, audit logs to CloudWatch |

Terraform snippet:

```hcl
variable "db_password" {
  type      = string
  sensitive = true # supplied via TF_VAR_db_password, never in git
}

resource "aws_db_subnet_group" "shop" {
  name       = "shop-db-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_db_instance" "shop" {
  identifier              = "shop-db"
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  storage_type            = "gp3"
  storage_encrypted       = true
  db_name                 = "shop"
  username                = "admin"
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.shop.name
  vpc_security_group_ids  = [aws_security_group.db.id]
  publicly_accessible     = false
  multi_az                = true
  backup_retention_period = 7
  deletion_protection     = false # true in production
  skip_final_snapshot     = true  # false in production
}

output "db_endpoint" { value = aws_db_instance.shop.endpoint }
```

---

## Choosing between them

| Question | DynamoDB | RDS |
|---|---|---|
| Do I need joins, ad-hoc SQL, complex transactions? | No | **Yes** |
| Are access patterns known and key-based? | **Yes** | Either |
| Do I want zero servers and per-request billing? | **Yes** | No (Aurora Serverless is the middle ground) |
| Is the data model relational with many entity types? | No | **Yes** |
| Do I need millions of requests/second globally? | **Yes** | Hard |
| Does my team/framework (Django, Rails, Spring) expect SQL? | No | **Yes** |

## Summary in my own words

DynamoDB is a serverless table of JSON-like items addressed by a partition key (where the item
lives) and an optional sort key (order within that partition); I design the keys around my
queries and it scales without me touching servers. RDS is the familiar SQL database but with AWS
doing the backups, patching and failover; Multi-AZ gives me a synchronous standby for
availability, read replicas give me asynchronous readable copies for scale, and security is about
keeping it in private subnets, encrypted, with secrets outside the code.
