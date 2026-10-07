# terraform-aws-infra – quick start

Student: Om Malviya | Enrollment No: 24BCS10448

End-to-end Terraform project for Session 19: VPC → public subnet → Internet Gateway → route table →
security group → EC2 (Amazon Linux 2023 + nginx) → S3 bucket. The full write-up (architecture,
every concept, expected plan/apply/destroy output) is in [`../README.md`](../README.md).

```bash
cp terraform.tfvars.example terraform.tfvars   # set allowed_ssh_cidr to <your ip>/32 and key_name
make init        # terraform init
make plan        # fmt + validate + plan -out=tfplan
make apply       # terraform apply tfplan
make output      # terraform output
curl "$(terraform output -raw http_url)"
make destroy     # terraform destroy  (do not forget – EC2 costs money)
```

| File | Purpose |
|---|---|
| `versions.tf` | required_version, aws ~> 5.0, random ~> 3.6 |
| `provider.tf` | aws provider, region + default_tags |
| `variables.tf` | region, project_name, vpc_cidr, public_subnet_cidr, availability_zone, instance_type, allowed_ssh_cidr, key_name, bucket_prefix, tags |
| `main.tf` | all resources in dependency order |
| `outputs.tf` | vpc_id, public_subnet_id, security_group_id, ami_id, instance_id, instance_public_ip, http_url, bucket_name |
| `user_data.sh` | first-boot script: installs nginx and writes the hello page |
| `terraform.tfvars.example` | sample variable values (copy to terraform.tfvars) |
| `Makefile` | init / fmt / validate / plan / apply / output / destroy / clean |
| `.gitignore` | .terraform/, state, tfplan, terraform.tfvars |
| `.terraform.lock.hcl` | provider versions pinned by `terraform init` |
