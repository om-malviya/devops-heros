variable "aws_region" {
  description = "AWS region where the S3 bucket is created."
  type        = string
  default     = "ap-south-1"
}

variable "bucket_prefix" {
  description = "Prefix for the bucket name. A random suffix is appended to keep the name globally unique."
  type        = string
  default     = "om-session18-demo"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.bucket_prefix))
    error_message = "bucket_prefix must be lowercase letters, digits or hyphens (S3 naming rules)."
  }
}

variable "environment" {
  description = "Environment name used in the bucket name and tags."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "test", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, test, staging, prod."
  }
}

variable "tags" {
  description = "Common tags applied to all resources through provider default_tags."
  type        = map(string)
  default = {
    Project   = "session18-terraform-iac"
    ManagedBy = "Terraform"
    Owner     = "Om Malviya"
  }
}
