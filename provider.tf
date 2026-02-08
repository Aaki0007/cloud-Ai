terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
  }
  required_version = ">= 1.0.0"

  # Remote State Configuration
  # Uncomment the backend block below after creating the S3 bucket and DynamoDB table
  # See README.md "Remote State Setup" section for prerequisites
  #
  # backend "s3" {
  #   bucket         = "terraform-state-<ACCOUNT_ID>"
  #   key            = "ai-chatbot/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = "us-east-1"
  # AWS Academy credentials are read from ~/.aws/credentials
  # or environment variables AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN
}
