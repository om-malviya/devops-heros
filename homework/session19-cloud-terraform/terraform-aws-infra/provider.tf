provider "aws" {
  region = var.aws_region

  # Every taggable resource gets these tags automatically.
  default_tags {
    tags = merge(var.tags, {
      Project = var.project_name
    })
  }
}
