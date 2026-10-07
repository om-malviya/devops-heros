# terraform/ - AWS VPC + EKS for TaskBoard

> **Cost warning.** This configuration creates an EKS control plane (~0.10 USD/h), one NAT gateway (~0.05 USD/h + data)
> and two `t3.medium` nodes (~0.05 USD/h each) in `ap-south-1`: roughly **5-6 USD per day** while it exists.
> Run `terraform destroy` as soon as the demo is over and confirm in the AWS console that no EKS cluster, NAT gateway
> or EBS volume is left. No AWS credentials are stored in this folder; use `aws configure`, environment variables or SSO.

| File | Content |
|------|---------|
| `versions.tf` | Terraform >= 1.7, AWS provider ~> 5.0, commented S3/DynamoDB remote-state backend |
| `providers.tf` | region + `default_tags` (Project/Environment/ManagedBy/Owner) |
| `variables.tf` | region, cluster name/version, VPC CIDR, AZs, subnets, node group sizing, NAT mode, endpoint access |
| `main.tf` | `terraform-aws-modules/vpc` 5.8.1 (2 public + 2 private subnets, 1 NAT GW, EKS subnet tags) and `terraform-aws-modules/eks` 20.37.1 (control plane, core add-ons + EBS CSI driver, managed node group 2..4 x t3.medium) |
| `outputs.tf` | vpc id, subnets, cluster name/endpoint/SG, ready-to-copy `aws eks update-kubeconfig` command |
| `terraform.tfvars.example` | example variable values (copy to `terraform.tfvars`, which is git-ignored) |
| `.gitignore` | `.terraform/`, state files, plans, `terraform.tfvars` |

## Commands

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init                      # downloads modules + providers
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
$(terraform output -raw configure_kubectl)
kubectl get nodes
terraform destroy
```

## Validation on this machine (no AWS credentials)

```text
Output (captured 2026-10-07)
$ terraform fmt -check -recursive        # exit 0, no diff
$ terraform init -backend=false
Initializing modules...
Downloading registry.terraform.io/terraform-aws-modules/eks/aws 20.37.1 for eks...
Downloading registry.terraform.io/terraform-aws-modules/vpc/aws 5.8.1 for vpc...
Downloading registry.terraform.io/terraform-aws-modules/kms/aws 2.1.0 for eks.kms...
Initializing provider plugins...
- Installing hashicorp/aws v5.100.0...
- Installed hashicorp/aws v5.100.0 (signed by HashiCorp)
- Installing hashicorp/tls v4.4.1 ... hashicorp/time v0.14.2 ... hashicorp/cloudinit v2.4.1 ... hashicorp/null v3.3.2
Terraform has been successfully initialized!

$ terraform validate
Success! The configuration is valid.
```

## Expected `terraform plan`

```text
Expected output
Plan: 58 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + cluster_endpoint          = (known after apply)
  + cluster_name              = "taskboard-eks"
  + cluster_security_group_id = (known after apply)
  + configure_kubectl         = "aws eks update-kubeconfig --region ap-south-1 --name taskboard-eks"
  + private_subnets           = (known after apply)
  + public_subnets            = (known after apply)
  + vpc_id                    = (known after apply)
```

Main resources in the plan: `aws_vpc`, 2x `aws_subnet` public, 2x private, `aws_internet_gateway`, `aws_nat_gateway` + `aws_eip`,
route tables/associations, `aws_eks_cluster`, cluster + node IAM roles and policies, `aws_security_group` x2,
`aws_eks_node_group`, `aws_launch_template`, `aws_eks_addon` x4, `aws_kms_key` (secrets encryption), `aws_cloudwatch_log_group`.

## Expected `terraform apply`

```text
Expected output
module.vpc.aws_vpc.this[0]: Creating...
module.vpc.aws_vpc.this[0]: Creation complete after 3s [id=vpc-0a1b2c3d4e5f67890]
module.vpc.aws_nat_gateway.this[0]: Still creating... [1m30s elapsed]
module.eks.aws_eks_cluster.this[0]: Creating...
module.eks.aws_eks_cluster.this[0]: Still creating... [8m10s elapsed]
module.eks.aws_eks_cluster.this[0]: Creation complete after 8m42s [id=taskboard-eks]
module.eks.module.eks_managed_node_group["main"].aws_eks_node_group.this[0]: Creation complete after 2m55s
module.eks.aws_eks_addon.this["aws-ebs-csi-driver"]: Creation complete after 1m05s

Apply complete! Resources: 58 added, 0 changed, 0 destroyed.

Outputs:
cluster_endpoint = "https://ABCDEF1234567890.gr7.ap-south-1.eks.amazonaws.com"
cluster_name = "taskboard-eks"
configure_kubectl = "aws eks update-kubeconfig --region ap-south-1 --name taskboard-eks"
vpc_id = "vpc-0a1b2c3d4e5f67890"

$ aws eks update-kubeconfig --region ap-south-1 --name taskboard-eks
Updated context arn:aws:eks:ap-south-1:123456789012:cluster/taskboard-eks in /Users/om/.kube/config
$ kubectl get nodes
NAME                                        STATUS   ROLES    AGE   VERSION
ip-10-20-1-57.ap-south-1.compute.internal   Ready    <none>   3m    v1.31.4-eks-xxxxxxx
ip-10-20-2-23.ap-south-1.compute.internal   Ready    <none>   3m    v1.31.4-eks-xxxxxxx
```

## Expected `terraform destroy`

```text
Expected output
Plan: 0 to add, 0 to change, 58 to destroy.
module.eks.module.eks_managed_node_group["main"].aws_eks_node_group.this[0]: Destruction complete after 4m12s
module.eks.aws_eks_cluster.this[0]: Destruction complete after 2m30s
module.vpc.aws_nat_gateway.this[0]: Destruction complete after 1m05s
module.vpc.aws_vpc.this[0]: Destruction complete after 1s

Destroy complete! Resources: 58 destroyed.
```

Delete load balancers created by the ingress controller *before* `terraform destroy` (`helm uninstall ingress-nginx`),
otherwise the VPC cannot be deleted because of the ELB and its security group.
