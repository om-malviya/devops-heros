terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state (uncomment after creating the bucket/table once):
  # backend "s3" {
  #   bucket         = "taskboard-tfstate-<account-id>"
  #   key            = "eks/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "taskboard-tfstate-lock"
  #   encrypt        = true
  # }
}
