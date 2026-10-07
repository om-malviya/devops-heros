# 04 – VPC (Virtual Private Cloud) – Networking

Student: Om Malviya | Enrollment No: 24BCS10448

## What is VPC?

A VPC is my own logically isolated network inside an AWS region. I choose the IP range, split it
into subnets across Availability Zones, decide how traffic is routed (Internet Gateway, NAT
Gateway, VPN, peering) and what is allowed in and out (security groups, network ACLs). Every EC2
instance, RDS database, Lambda-in-VPC or EKS node lives in a subnet of some VPC.

```text
 Region ap-south-1                                  Internet
 ┌─────────────────────────────────────────────────────┬────┐
 │ VPC 10.0.0.0/16                                     │IGW │
 │                                                     └─┬──┘
 │  AZ ap-south-1a                 AZ ap-south-1b        │
 │  ┌────────────────────────┐    ┌────────────────────┐ │
 │  │ Public subnet          │    │ Public subnet      │ │   route table "public":
 │  │ 10.0.1.0/24            │    │ 10.0.2.0/24        │◄┘   10.0.0.0/16 → local
 │  │  web EC2   NAT GW      │    │  web EC2           │     0.0.0.0/0   → igw-xxx
 │  └──────┬─────────┬───────┘    └────────────────────┘
 │         │         │ outbound only
 │  ┌──────▼─────────▼───────┐    ┌────────────────────┐     route table "private":
 │  │ Private subnet         │    │ Private subnet     │     10.0.0.0/16 → local
 │  │ 10.0.11.0/24           │    │ 10.0.12.0/24       │     0.0.0.0/0   → nat-xxx
 │  │  RDS primary           │    │  RDS standby       │
 │  └────────────────────────┘    └────────────────────┘
 └───────────────────────────────────────────────────────────┘
```

Every region comes with a **default VPC** (172.31.0.0/16, all subnets public) so beginners can
launch instances immediately; real projects create their own.

## CIDR

CIDR (Classless Inter-Domain Routing) notation `a.b.c.d/N` means "the first N bits are the network,
the remaining 32-N bits are hosts".

| CIDR | Hosts (2^(32-N)) | Usable in an AWS subnet (minus 5) | Typical use |
|---|---|---|---|
| /16 | 65,536 | – | Whole VPC (maximum allowed) |
| /20 | 4,096 | 4,091 | Large subnet |
| /24 | 256 | 251 | Standard subnet |
| /28 | 16 | 11 | Smallest allowed subnet (e.g. for NAT GW) |
| /32 | 1 | – | A single host, e.g. `203.0.113.10/32` in a security group |
| /0 | all | – | `0.0.0.0/0` = "anywhere" |

AWS reserves 5 addresses in every subnet: network address (.0), VPC router (.1), DNS (.2),
future use (.3) and broadcast (.255). VPC ranges should come from RFC 1918 private space
(`10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`) and must not overlap with networks I may later
peer or VPN to. A VPC can have one primary and up to four secondary CIDR blocks.

```bash
# quick check from a shell (python)
python3 -c "import ipaddress; n=ipaddress.ip_network('10.0.1.0/24'); print(n.num_addresses, list(n.hosts())[0], list(n.hosts())[-1])"
```

```text
256 10.0.1.1 10.0.1.254
```

## Subnets

A subnet is a slice of the VPC CIDR that lives in **exactly one Availability Zone**. Resources get
their private IP from the subnet. Design pattern: one public and one private subnet per AZ, at
least two AZs for high availability.

```bash
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-vpc}]'
aws ec2 modify-vpc-attribute --vpc-id vpc-0abc --enable-dns-hostnames
aws ec2 create-subnet --vpc-id vpc-0abc --cidr-block 10.0.1.0/24 --availability-zone ap-south-1a
aws ec2 modify-subnet-attribute --subnet-id subnet-0abc --map-public-ip-on-launch
aws ec2 describe-subnets --filters Name=vpc-id,Values=vpc-0abc \
  --query 'Subnets[].{Id:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch}' --output table
```

Expected output:

```text
-----------------------------------------------------------------------
|                           DescribeSubnets                           |
+--------------+--------------+----------+----------------------------+
|      AZ      |    Cidr      | Public   |            Id              |
+--------------+--------------+----------+----------------------------+
|  ap-south-1a |  10.0.1.0/24 |  True    |  subnet-0a1b2c3d4e5f67890  |
|  ap-south-1a |  10.0.11.0/24|  False   |  subnet-0f9e8d7c6b5a43210  |
+--------------+--------------+----------+----------------------------+
```

## Route tables

A route table is a list of `destination → target` rules; every subnet is associated with exactly
one route table (the VPC's **main** route table if I do not associate a custom one). The most
specific matching route wins.

| Destination | Target | Meaning |
|---|---|---|
| 10.0.0.0/16 | `local` | Always present, cannot be removed – traffic inside the VPC |
| 0.0.0.0/0 | `igw-…` | Internet via Internet Gateway (public subnet) |
| 0.0.0.0/0 | `nat-…` | Internet via NAT Gateway (private subnet) |
| 10.1.0.0/16 | `pcx-…` | VPC peering connection |
| 192.168.0.0/16 | `vgw-…` / `tgw-…` | On-premises via VPN or Transit Gateway |
| S3 prefix list | `vpce-…` | Gateway endpoint (S3/DynamoDB without internet) |

```bash
aws ec2 create-route-table --vpc-id vpc-0abc
aws ec2 create-route --route-table-id rtb-0abc --destination-cidr-block 0.0.0.0/0 --gateway-id igw-0abc
aws ec2 associate-route-table --route-table-id rtb-0abc --subnet-id subnet-0abc
aws ec2 describe-route-tables --route-table-ids rtb-0abc --query 'RouteTables[].Routes[].{Dest:DestinationCidrBlock,Target:GatewayId}'
```

## Internet Gateway

The IGW is a horizontally scaled, redundant VPC component that lets resources with a **public or
Elastic IP** talk to the internet in both directions. It performs 1:1 NAT between the public IP
and the instance's private IP. One IGW per VPC; attaching it does nothing by itself – a subnet
becomes public only when its route table points `0.0.0.0/0` at the IGW.

```bash
aws ec2 create-internet-gateway
aws ec2 attach-internet-gateway --internet-gateway-id igw-0abc --vpc-id vpc-0abc
```

Checklist for an instance to be reachable from the internet:

1. IGW attached to the VPC
2. Route `0.0.0.0/0 → igw` in the subnet's route table
3. Instance has a public IP or Elastic IP
4. Security group allows the inbound port
5. Network ACL allows the inbound port **and** the ephemeral return ports (1024–65535)

## NAT Gateway

A NAT Gateway lets instances in **private** subnets reach the internet (updates, APIs) while the
internet cannot start connections to them. It sits in a public subnet with an Elastic IP, and the
private route table sends `0.0.0.0/0` to it. It is AZ-specific – for HA put one in each AZ.

| | Internet Gateway | NAT Gateway |
|---|---|---|
| Direction | Inbound + outbound | Outbound only (and replies) |
| Placed in | Attached to the VPC | A public subnet, per AZ |
| Needs | Public IP on the instance | Elastic IP on the NAT GW |
| Cost | Free | ~$0.045/h + $0.045/GB processed – the most common surprise bill |
| Alternative | – | NAT instance (cheap, self-managed), VPC endpoints for AWS services |

```bash
aws ec2 allocate-address --domain vpc
aws ec2 create-nat-gateway --subnet-id subnet-public --allocation-id eipalloc-0abc
aws ec2 create-route --route-table-id rtb-private --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-0abc
```

For IPv6 the equivalent outbound-only component is the **egress-only internet gateway**.

## Security Groups

Security groups are **stateful** firewalls attached to ENIs (instances, RDS, load balancers,
Lambda). Only allow rules; return traffic is automatically permitted. Rules can reference CIDRs
or other security groups.

```text
 web-sg:  in  tcp/80  from 0.0.0.0/0
          in  tcp/22  from 203.0.113.10/32
          out all     to  0.0.0.0/0
 db-sg:   in  tcp/3306 from sg-web   ◄── reference the web SG, not an IP range
```

See `../02-ec2/README.md` for the CLI commands and full table.

## Network ACLs

A network ACL is a **stateless** firewall at the **subnet** boundary. Rules are numbered and
evaluated lowest first; both inbound and outbound must be allowed explicitly, including the
ephemeral port range for replies. The default NACL allows everything; custom NACLs deny
everything until rules are added.

| Rule # | Type | Protocol | Port | Source | Allow/Deny |
|---|---|---|---|---|---|
| 100 | Inbound | TCP | 80 | 0.0.0.0/0 | ALLOW |
| 110 | Inbound | TCP | 22 | 203.0.113.0/24 | ALLOW |
| 120 | Inbound | TCP | 1024–65535 | 0.0.0.0/0 | ALLOW (return traffic) |
| 130 | Inbound | ALL | ALL | 198.51.100.7/32 | DENY (block a bad actor) |
| * | Inbound | ALL | ALL | 0.0.0.0/0 | DENY (implicit) |

| | Security group | Network ACL |
|---|---|---|
| Scope | Instance / ENI | Subnet |
| State | Stateful | Stateless |
| Rules | Allow only | Allow and Deny |
| Evaluation | All rules | Lowest number first |
| Typical use | Primary control, per app | Coarse guardrail, block IPs |

```bash
aws ec2 create-network-acl --vpc-id vpc-0abc
aws ec2 create-network-acl-entry --network-acl-id acl-0abc --ingress --rule-number 130 \
  --protocol -1 --cidr-block 198.51.100.7/32 --rule-action deny
```

## Public vs private subnet

The difference is **only the route table**, nothing in the subnet itself:

| | Public subnet | Private subnet |
|---|---|---|
| Route `0.0.0.0/0` | → Internet Gateway | → NAT Gateway (or none) |
| `map_public_ip_on_launch` | usually true | false |
| Inbound from internet | Possible (if SG allows) | Impossible |
| Outbound to internet | Direct | Via NAT GW |
| Place here | Load balancers, bastion, NAT GW, web tier in small labs | App servers, databases, caches, EKS nodes |

```text
 Internet ──► IGW ──► public subnet (ALB / web)  ──► private subnet (app) ──► private subnet (RDS)
                        ▲ NAT GW ◄──────────── outbound only ────────────┘
```

## Terraform snippet

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "lab-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "ap-south-1a"
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
```

The Session 19 project (`../../../session19-cloud-terraform/terraform-aws-infra/`) implements the
public half of this and launches an EC2 web server in it.

## Common use cases

| Use case | VPC design |
|---|---|
| Three-tier web application | Public subnets (ALB), private app subnets, isolated DB subnets, 2–3 AZs |
| Secure database that never touches the internet | Private subnet, SG referencing app SG, no NAT route |
| Hybrid cloud | VPN or Direct Connect to on-prem through a Virtual Private Gateway / Transit Gateway |
| Multi-account organisation | One VPC per account, connected with Transit Gateway, non-overlapping CIDRs |
| Private access to S3/DynamoDB without NAT cost | Gateway VPC endpoints |
| Kubernetes (EKS) | Large /16, private node subnets, public subnets only for load balancers |
| Learning lab (this course) | One VPC, one public subnet, IGW, one SG, one t3.micro |

## Summary in my own words

The VPC is the box, the CIDR is its address space, subnets split it per AZ, route tables decide
where packets go, the IGW opens two-way internet access for public IPs, the NAT Gateway gives
private subnets one-way access, security groups filter per instance (stateful) and NACLs filter
per subnet (stateless). "Public" or "private" is decided entirely by whether the route table has
a `0.0.0.0/0 → igw` entry.
