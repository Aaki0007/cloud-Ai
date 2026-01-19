# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- **Terraform Modules**: Refactored infrastructure into reusable modules
  - `modules/s3/` - S3 bucket with versioning and lifecycle rules
  - `modules/dynamodb/` - DynamoDB table with GSI and TTL support
  - `modules/lambda/` - Lambda function with CloudWatch log group
  - `modules/api_gateway/` - API Gateway REST API with Lambda integration
- **Remote State Backend**: Added S3 + DynamoDB backend configuration
  - `backend-setup/` directory with Terraform to create state infrastructure
  - Commented backend block in `provider.tf` ready for activation
  - State locking via DynamoDB for team collaboration
- **Documentation**: Added remote state setup instructions to README

### Changed
- **main.tf**: Migrated from inline resources to module calls
- **outputs.tf**: Updated outputs to reference module outputs
- **provider.tf**: Added remote state backend configuration (commented)

### Security
- **IAM**: Documented least-privilege policy in `docs/GAP_ANALYSIS.md`
  - Note: AWS Academy LabRole used due to environment constraints
  - Production policy template provided for non-Academy deployments

### Infrastructure
- All resources maintain consistent tagging (Project, Environment, ManagedBy, Repository)
- Module-based structure enables reuse across environments
- Variables and locals used for all configurable values

## [1.0.0] - 2025-01-19

### Added
- Initial Telegram chatbot infrastructure
- Lambda function for message handling
- API Gateway webhook endpoint
- DynamoDB for session storage with GSIs
- S3 for conversation archival with lifecycle policies
- CloudWatch logging
- CI/CD with GitHub Actions
- Comprehensive documentation (README, CONTRIBUTING, GAP_ANALYSIS)
