# 02 – EC2 (Elastic Compute Cloud) – Compute

Student: Om Malviya | Enrollment No: 24BCS10448

## What is EC2?

EC2 provides resizable virtual machines (**instances**) in the AWS cloud. It is the classic
IaaS building block: AWS owns the hardware, hypervisor and network; I pick the OS image (AMI),
the hardware size (instance type), storage (EBS), network placement (VPC/subnet), firewall
(security group) and SSH key, then pay per second while the instance runs.

```text
            ┌────────────────────────── EC2 instance ──────────────────────────┐
  AMI ────► │ OS + packages        instance type: t3.micro (2 vCPU, 1 GiB)     │
  key pair ►│ ~/.ssh/authorized_keys                                           │
  user_data►│ first-boot script (install nginx)                                │
            │   root EBS volume (gp3 8 GiB) ──── extra EBS volumes             │
            │   ENI: private IP 10.0.1.23  + public IP 13.233.x.x              │
            └──────────────── security group: 22 from me, 80 from all ─────────┘
                                   inside subnet 10.0.1.0/24, AZ ap-south-1a
```

## AMI (Amazon Machine Image)

An AMI is the template an instance boots from: root volume snapshot (OS + installed software),
launch permissions, and block device mapping. Important facts:

- AMI IDs are **regional**: the Amazon Linux 2023 AMI in `ap-south-1` has a different ID than in `us-east-1`.
- Sources: AWS-provided (Amazon Linux, Ubuntu, Windows), Marketplace, community, or my own
  ("golden image" built with Packer after installing my app).
- Creating an AMI from a running instance = backup of the whole machine that can launch clones.

Finding the latest Amazon Linux 2023 AMI:

```bash
# via SSM public parameter (always current)
aws ssm get-parameter --region ap-south-1 \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameter.Value' --output text

# via describe-images
aws ec2 describe-images --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023.*-x86_64" "Name=state,Values=available" \
  --query 'sort_by(Images,&CreationDate)[-1].{Id:ImageId,Name:Name}'
```

Expected output:

```text
ami-0f5ee92e2d63afc18
```

In Terraform the same thing is a `data "aws_ami"` block with `most_recent = true` (used in Session 19).

## Instance types

Naming: `family` + `generation` + `attributes` `.` `size`, e.g. `t3.micro`, `m6g.large` (g = Graviton/ARM).

| Family | Optimised for | Examples | Typical use |
|---|---|---|---|
| T (burstable) | Cheap baseline + CPU credits | t3.micro, t4g.small | Dev/test, small web apps, this course |
| M | General purpose, balanced | m6i.large, m7g.xlarge | App servers, small DBs |
| C | Compute | c6i.xlarge, c7g | Batch, CI runners, game servers |
| R / X | Memory | r6i.large, x2idn | In-memory caches, big databases |
| I / D | Storage (local NVMe) | i4i, d3 | NoSQL, data warehouses |
| P / G / Inf | GPU / accelerators | p4d, g5, inf2 | ML training/inference, rendering |

`t3.micro`: 2 vCPU, 1 GiB RAM, free tier eligible (750 h/month for 12 months), about USD 0.0116/h
in Mumbai. Instances can be resized by stopping, changing the type, and starting again.

```bash
aws ec2 describe-instance-types --instance-types t3.micro \
  --query 'InstanceTypes[].{vCPU:VCpuInfo.DefaultVCpus,MemMiB:MemoryInfo.SizeInMiB}'
```

Purchasing options: On-Demand (default), Reserved / Savings Plans (1–3 year commitment, up to 72 %
cheaper), Spot (spare capacity, up to 90 % cheaper, can be interrupted with 2 minutes notice),
Dedicated Hosts (compliance/licensing).

## Key pairs

A key pair is an SSH public/private key. AWS keeps the **public** key and injects it into
`~/.ssh/authorized_keys` of the default user (`ec2-user` on Amazon Linux, `ubuntu` on Ubuntu) at
first boot. I keep the private key; AWS never stores it and cannot recover it.

```bash
aws ec2 create-key-pair --key-name om-session19-key --key-type ed25519 \
  --query 'KeyMaterial' --output text > ~/.ssh/om-session19-key.pem
chmod 400 ~/.ssh/om-session19-key.pem

ssh -i ~/.ssh/om-session19-key.pem ec2-user@13.233.45.67
```

Alternatives that avoid opening port 22 at all: **EC2 Instance Connect** (temporary key pushed via
API) and **SSM Session Manager** (needs an instance role with `AmazonSSMManagedInstanceCore`,
no inbound rule required). Windows instances use the key pair to decrypt the Administrator password.

## Security Groups

A security group is a **stateful virtual firewall** attached to the instance's network interface.

| Property | Security group |
|---|---|
| Level | Instance / ENI |
| Rules | Allow only (no deny rules) |
| Stateful | Yes – reply traffic is automatically allowed |
| Default inbound | Deny everything |
| Default outbound | Allow everything |
| Sources | CIDR, another security group ID, prefix list |

Typical web-server group:

| Direction | Protocol | Port | Source/Destination | Purpose |
|---|---|---|---|---|
| Inbound | TCP | 22 | my IP `/32` | SSH |
| Inbound | TCP | 80 | 0.0.0.0/0 | HTTP |
| Inbound | TCP | 443 | 0.0.0.0/0 | HTTPS |
| Outbound | All | All | 0.0.0.0/0 | Updates, package install |

```bash
aws ec2 create-security-group --group-name web-sg --description "web" --vpc-id vpc-0abc123
aws ec2 authorize-security-group-ingress --group-id sg-0abc123 --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-0abc123 --protocol tcp --port 22 --cidr 203.0.113.10/32
```

Referencing another security group as the source (e.g. database SG allows 3306 only from web SG)
is cleaner than CIDRs because it follows the instances wherever their IPs are.

## EBS (Elastic Block Store)

EBS is network-attached block storage – the virtual hard disk of the instance. It lives in one
AZ and persists independently of the instance (unless `DeleteOnTermination` is true, which is the
default for root volumes).

| Volume type | Kind | Baseline | Use |
|---|---|---|---|
| gp3 | SSD | 3,000 IOPS / 125 MB/s, scalable independently of size | Default for everything (cheaper than gp2) |
| gp2 | SSD | 3 IOPS per GiB | Legacy default |
| io1 / io2 | SSD provisioned IOPS | up to 64k–256k IOPS | Databases needing guaranteed latency |
| st1 | HDD throughput | 500 MB/s | Big sequential workloads, logs, ETL |
| sc1 | HDD cold | 250 MB/s | Rarely accessed data |

Operations I should know:

```bash
aws ec2 create-volume --availability-zone ap-south-1a --size 20 --volume-type gp3
aws ec2 attach-volume --volume-id vol-0abc --instance-id i-0abc --device /dev/sdf
# inside the instance: lsblk, sudo mkfs -t xfs /dev/nvme1n1, mount, add to /etc/fstab
aws ec2 create-snapshot --volume-id vol-0abc --description "before upgrade"
aws ec2 modify-volume --volume-id vol-0abc --size 40        # grow online, then growpart + xfs_growfs
```

Snapshots are incremental, stored in S3 (not visible as objects), and are the basis of AMIs and
cross-region/cross-account copies. **Instance store** volumes are the opposite: local NVMe,
very fast, but wiped on stop/terminate.

## Public vs private IP

| | Private IP | Public IP | Elastic IP |
|---|---|---|---|
| Range | From the subnet CIDR (10.0.1.23) | AWS pool (13.233.x.x) | AWS pool, allocated to my account |
| Reachable from | Inside the VPC (and peered/VPN networks) | Internet, via IGW | Internet, via IGW |
| Survives stop/start | Yes | **No – changes** | Yes |
| Cost | Free | Public IPv4 charged ~$0.005/h since Feb 2024 | Same + charged while unattached |
| Assigned by | DHCP from subnet | `map_public_ip_on_launch` / `associate_public_ip_address` | Manual association |

The public IP is **not configured on the OS** – the instance only sees its private IP. The IGW
does 1:1 NAT between them. That is why an instance needs three things to be reachable:
public/elastic IP, a route `0.0.0.0/0 → igw`, and a security group rule.

```bash
aws ec2 describe-instances --instance-ids i-0abc \
  --query 'Reservations[].Instances[].{Private:PrivateIpAddress,Public:PublicIpAddress}'
# from inside the instance (IMDSv2)
TOKEN=$(curl -sX PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4
```

## Instance lifecycle

```text
        launch                 stop                    terminate
 pending ───► running ───► stopping ───► stopped ───► shutting-down ───► terminated
                 ▲            │               │
                 │  reboot    │  start        │  hibernate (RAM saved to EBS)
                 └────────────┘               ▼
                                         (billing stops, EBS still charged)
```

| State | Billed for compute? | EBS kept? | Public IP |
|---|---|---|---|
| pending | No | – | assigning |
| running | Yes (per second, 60 s minimum) | Yes | yes |
| stopping / stopped | No (EBS storage still billed) | Yes | released (EIP kept) |
| rebooting | Yes | Yes | unchanged |
| shutting-down / terminated | No | Root deleted by default, others per flag | released |

- `reboot` = OS restart on the same host; IPs and instance store keep their data.
- `stop/start` = may move to a different physical host; public IP changes; good for resizing.
- `terminate` is permanent; enable *termination protection* on important servers.
- **user_data** runs once on first boot (cloud-init) – the standard way to bootstrap (used in Session 19 to install nginx).

```bash
aws ec2 run-instances --image-id ami-0f5ee92e2d63afc18 --instance-type t3.micro \
  --key-name om-session19-key --security-group-ids sg-0abc123 --subnet-id subnet-0abc123 \
  --user-data file://user_data.sh --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=web}]'
aws ec2 describe-instance-status --instance-ids i-0abc
aws ec2 stop-instances      --instance-ids i-0abc
aws ec2 start-instances     --instance-ids i-0abc
aws ec2 terminate-instances --instance-ids i-0abc
```

## Terraform snippet

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  key_name                    = "om-session19-key"
  associate_public_ip_address = true
  user_data                   = file("user_data.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
  }

  tags = { Name = "session19-web" }
}

output "public_ip" { value = aws_instance.web.public_ip }
```

## Common use cases

| Use case | How EC2 is used |
|---|---|
| Web/application servers | Instances behind an Application Load Balancer in an Auto Scaling group |
| Self-managed databases or caches | R-family instance + io2 volumes + snapshots |
| CI/CD runners (Jenkins agents, GitHub runners) | Spot instances started on demand |
| Batch / HPC | C-family or Spot fleets, terminated when finished |
| Lift-and-shift of on-prem VMs | Import VM as AMI, run unchanged |
| Bastion / jump host | Tiny instance in public subnet, SSH only from office IP |
| Kubernetes worker nodes | EKS node groups are just EC2 Auto Scaling groups |
| Learning / labs (this course) | t3.micro in free tier, destroyed with `terraform destroy` |

## Summary in my own words

An EC2 instance is an AMI running on an instance type, with EBS disks, a private IP from its
subnet, optionally a public IP mapped by the Internet Gateway, protected by a stateful security
group, and accessed with a key pair. I pay only while it is running, so for homework I always
stop or `terraform destroy` it at the end.
