terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  # REMOTE BACKEND: GLOBAL
  backend "s3" {
    bucket         = "cosmin-cicd-artifacts-303952966154"
    key            = "terraform/global/state.tfstate"
    region         = "eu-central-1"
    encrypt        = true
  }
}

provider "aws" {
  region = "eu-central-1"
}

data "aws_caller_identity" "current" {}

# S3 Artifacts Bucket
resource "aws_s3_bucket" "artifacts" {
  bucket        = "cosmin-cicd-artifacts-303952966154"
  force_destroy = true 
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

output "artifacts_bucket_name" {
  value = aws_s3_bucket.artifacts.bucket
}