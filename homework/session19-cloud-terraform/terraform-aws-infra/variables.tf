variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name used as a prefix for resource names and tags."
  type        = string
  default     = "session19-infra"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block of the public subnet (must be inside vpc_cidr)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "availability_zone" {
  description = "Availability Zone for the public subnet."
  type        = string
  default     = "ap-south-1a"
}

variable "instance_type" {
  description = "EC2 instance type for the web server."
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH (port 22) into the instance. Use <your-public-ip>/32, never 0.0.0.0/0 in real life."
  type        = string
  default     = "203.0.113.10/32" # placeholder documentation IP - replace with your own
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH. Leave null to launch without a key pair."
  type        = string
  default     = null
}

variable "bucket_prefix" {
  description = "Prefix for the S3 bucket name; a random suffix is appended."
  type        = string
  default     = "session19-infra"
}

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Owner       = "Om Malviya"
  }
}
