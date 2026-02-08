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
  - `modules/monitoring/` - CloudWatch metric filter and error alarm
- **Observability**: Added structured logging and monitoring
  - Structured JSON logging in `handler.py` (level, timestamp, action, outcome, request_id)
  - CloudWatch metric filter for ERROR-level logs (`{ $.level = "ERROR" }`)
  - CloudWatch alarm triggers on >=1 error in 5-minute window
  - 14-day log retention managed via Terraform
- **Verification Script**: `scripts/test-observability.sh`
  - Automated PASS/FAIL checks for log group, metric filter, alarm, structured logs
  - Triggers success and error Lambda events and verifies log output
- **Remote State Backend**: Added S3 + DynamoDB backend configuration
  - `backend-setup/` directory with Terraform to create state infrastructure
  - Commented backend block in `provider.tf` ready for activation
  - State locking via DynamoDB for team collaboration
- **Documentation**: Added observability and remote state sections to README

### Changed
- **handler.py**: Replaced all `print()` calls with `StructuredLogger` for JSON-formatted logs
- **main.tf**: Migrated from inline resources to module calls, added monitoring module
- **outputs.tf**: Updated outputs to reference module outputs, added monitoring outputs
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
