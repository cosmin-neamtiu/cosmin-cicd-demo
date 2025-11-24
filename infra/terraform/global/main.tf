terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# S3 Artifacts Bucket (Global)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "artifacts" {
  # Naming convention: project-artifacts-account-region
  bucket = "cosmin-cicd-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # Allows deletion even if full (good for demos)
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}