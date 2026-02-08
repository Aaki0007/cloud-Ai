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
  - `modules/ec2/` - EC2 instance running Ollama for AI inference
- **Ollama AI Integration**: Self-hosted LLM on EC2 (external API)
  - EC2 instance (t3.large) running Ollama with tinyllama model
  - Lambda calls `POST /api/chat` for AI-powered chat responses
  - Elastic IP for stable endpoint across stop/start cycles
  - Model persistence: S3 sync on shutdown, restore on boot
  - Lifecycle management script: `scripts/manage-ollama.sh`
  - Error handling with timeouts, structured logging, graceful fallback
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
- **handler.py**: Replaced placeholder with actual Ollama AI integration, updated `/status` and `/help`
- **main.tf**: Migrated from inline resources to module calls, added monitoring and EC2 modules
- **outputs.tf**: Updated outputs to reference module outputs, added monitoring and EC2 outputs
- **Lambda timeout**: Increased from 30s to 60s to accommodate AI inference
- **provider.tf**: Added remote state backend configuration (commented)

### Security
- **Ollama API Key Auth**: Nginx reverse proxy on EC2 validates `X-API-Key` header (auto-generated 32-char key)
  - Ollama binds to localhost only (`127.0.0.1:11435`), nginx proxies on port 11434
  - Requests without valid API key receive HTTP 401
- **S3 Hardening**: Added public access block (all 4 settings) and AES256 server-side encryption
- **DynamoDB Hardening**: Enabled server-side encryption and point-in-time recovery
- **Sensitive Outputs**: Marked `api_gateway_url`, `ollama_public_ip`, `ollama_url`, `webhook_setup_command` as sensitive
- **Input Validation**: Added 4000-char max message length check in handler.py
- **Conversation Context Limit**: Limited Ollama context to last 10 messages to prevent CPU inference timeouts
- **.gitignore**: Added `*.pem`, `*.key`, `*.crt`, `.env`, `*.secret` patterns
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
