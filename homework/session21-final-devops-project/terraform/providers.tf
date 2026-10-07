provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "taskboard"
      Environment = var.environment
      ManagedBy   = "terraform"
      Owner       = "om-malviya"
    }
  }
}
