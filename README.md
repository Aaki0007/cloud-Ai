# AWS Telegram Chatbot Infrastructure

This project deploys a **Telegram chatbot** on AWS using Infrastructure as Code (Terraform). It provisions **S3 buckets** for storing archived chat history, **DynamoDB tables** for managing user sessions, **Lambda** for serverless processing, and **API Gateway** for real-time webhook integration with Telegram.

> **⚠️ Status**: Currently in development. Ollama AI integration (backend models) is not yet implemented. Session management, commands, archive features, and Telegram connectivity are fully functional.

---

## Table of Contents

* [Overview](#overview)
* [Architecture](#architecture)
* [Features](#features)
* [Prerequisites](#prerequisites)
* [AWS Academy Setup](#aws-academy-setup)
* [Remote State Setup](#remote-state-setup)
* [Deployment](#deployment)
* [Telegram Webhook Setup](#telegram-webhook-setup)
* [Bot Commands](#bot-commands)
* [Project Structure](#project-structure)
* [Module Structure](#module-structure)
* [Data Storage](#data-storage)
* [Observability](#observability)
* [Verification](#verification)
* [Troubleshooting](#troubleshooting)
* [Cleanup](#cleanup)
* [License](#license)

---

## Overview

This project creates a serverless Telegram bot running on AWS. When users send messages to the bot, Telegram forwards them to an API Gateway endpoint, which triggers a Lambda function to process the message and respond.

**Key Features:**
- ✅ Real-time message handling via API Gateway webhook
- ✅ User session creation and management
- ✅ Command handling (`/help`, `/newsession`, `/listsessions`, `/switch`, `/history`, `/echo`)
- ✅ Archive system (`/archive`, `/listarchives`, `/export`, file import)
- ✅ DynamoDB for live session storage
- ✅ S3 for archived session storage
- ⏳ Ollama AI integration (planned for next phase)

---

## Architecture

```
┌─────────────┐       ┌─────────────────┐       ┌────────────────┐
│   Telegram  │─────▶│   API Gateway   │─────▶│     Lambda     │
│    User     │◀─────│   (webhook)     │◀─────│  (handler.py)  │
└─────────────┘       └─────────────────┘       └────────────────┘
                                                      │
                              ┌───────────────────────┴───────────────────────┐
                              ▼                                               ▼
                     ┌─────────────────┐                             ┌─────────────────┐
                     │    DynamoDB     │                             │       S3        │
                     │(active sessions)│                             │ (archived chats)│
                     └─────────────────┘                             └─────────────────┘
```

**Flow:**
1. User sends a message to the Telegram bot
2. Telegram POSTs the update to API Gateway webhook URL
3. API Gateway triggers Lambda function
4. Lambda processes the message (command or chat)
5. Active session data is stored/retrieved from **DynamoDB**
6. Archived sessions are stored in **S3**
7. Lambda sends response back to Telegram

---

## Features

### Bot Commands

| Command | Purpose | Status |
|---------|---------|--------|
| `/start` or `/hello` | Initialize and greet user | ✅ Working |
| `/help` | Show available commands | ✅ Working |
| `/newsession` | Create a new chat session | ✅ Working |
| `/listsessions` | List all user sessions | ✅ Working |
| `/switch <number>` | Switch to a different session | ✅ Working |
| `/history` | Show recent messages in session | ✅ Working |
| `/archive` | List sessions available to archive | ✅ Working |
| `/archive <number>` | Archive a specific session to S3 | ✅ Working |
| `/listarchives` | List archived sessions | ✅ Working |
| `/export <number>` | Export archive as JSON file | ✅ Working |
| Send JSON file | Import archive from file | ✅ Working |
| `/status` | Check bot status | ✅ Working |
| `/echo <text>` | Echo back text (test command) | ✅ Working |
| Chat messages | Send to AI model | ⏳ Not implemented |

---

## Prerequisites

- **AWS Academy** Learner Lab access (or AWS account)
- **Terraform** >= 1.0.0
- **AWS CLI** configured with credentials
- **Python 3.9+** with pip
- **Telegram Bot Token** (from [@BotFather](https://t.me/botfather))

---

## AWS Academy Setup

### 1. Start the Lab

1. Open AWS Academy and navigate to **"Launch AWS Academy Learner Lab"**
2. Click **Start Lab** and wait for the status to turn green
3. Click **AWS Details** to view credentials

### 2. Configure AWS CLI

Click **Show** next to "AWS CLI" in AWS Details and copy the credentials:

```bash
# Edit credentials file
nano ~/.aws/credentials
```

Paste the credentials:
```ini
[default]
aws_access_key_id=ASIA...
aws_secret_access_key=...
aws_session_token=FwoGZX...
```

### 3. Verify Authentication

```bash
aws sts get-caller-identity
```

### 4. Get LabRole ARN

```bash
aws iam get-role --role-name LabRole --query 'Role.Arn' --output text
```

Output: `arn:aws:iam::ACCOUNT_ID:role/LabRole`

---

## Remote State Setup

Remote state stores your Terraform state in S3 with DynamoDB locking, enabling team collaboration and state protection.

A management script handles everything automatically — no manual file editing or hardcoding needed.

### Switch to Remote State

```bash
./scripts/manage-state.sh remote
```

This will:
- Verify AWS credentials
- Create the S3 bucket and DynamoDB lock table if they don't exist
- Uncomment the backend block in `provider.tf`
- Auto-detect your account ID from active credentials
- Migrate existing local state to S3

### Switch to Local State

```bash
./scripts/manage-state.sh local
```

This will:
- Comment out the backend block in `provider.tf`
- Migrate remote state back to a local `terraform.tfstate` file

### Check Current Backend

```bash
./scripts/manage-state.sh status
```

### AWS Academy Note

In AWS Academy environments, the backend S3 bucket and DynamoDB table may need to be recreated each session since resources are deleted when labs end. For persistent setups, consider using a personal AWS account.

---

## Deployment

### 1. Clone and Configure

```bash
git clone https://github.com/Man2Dev/cloud-Ai.git
cd cloud-Ai

# Create configuration file
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:
```hcl
telegram_token = "YOUR_TELEGRAM_BOT_TOKEN"
lab_role_arn   = "arn:aws:iam::YOUR_ACCOUNT_ID:role/LabRole"
```

### 2. Build Lambda Package

```bash
# Clean previous builds
rm -rf package/ lambda_function.zip

# Create package directory
mkdir -p package

# Install dependencies
pip install -r requirements.txt -t ./package

# Copy handler
cp handler.py package/
```

### 3. Deploy with Terraform

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy
terraform apply -auto-approve
```

### 4. Note the Outputs

After deployment, Terraform will output:
- `api_gateway_url` - Your webhook URL
- `s3_bucket_name` - S3 bucket for archives
- `dynamodb_table_name` - DynamoDB table name
- `lambda_function_name` - Lambda function name

---

## Telegram Webhook Setup

### Automated Setup (Recommended)

Run the webhook setup script - it reads your token from `terraform.tfvars` and configures everything automatically:

```bash
./scripts/setup-webhook.sh
```

The script will:
1. Read your bot token from `terraform.tfvars` (keeps it private)
2. Get the API Gateway URL from Terraform outputs
3. Register the webhook with Telegram
4. Verify the configuration
5. Test bot connectivity

### Manual Setup

If you prefer to set up manually, replace `YOUR_BOT_TOKEN` and use the `api_gateway_url` from Terraform output:

```bash
# Get your API Gateway URL
terraform output api_gateway_url

# Set the webhook
curl "https://api.telegram.org/botYOUR_BOT_TOKEN/setWebhook?url=YOUR_API_GATEWAY_URL"
```

Example:
```bash
curl "https://api.telegram.org/bot123456:ABC-DEF/setWebhook?url=https://abc123.execute-api.us-east-1.amazonaws.com/prod/webhook"
```

### Verify Webhook

```bash
curl "https://api.telegram.org/botYOUR_BOT_TOKEN/getWebhookInfo"
```

Expected response:
```json
{
  "ok": true,
  "result": {
    "url": "https://abc123.execute-api.us-east-1.amazonaws.com/prod/webhook",
    "has_custom_certificate": false,
    "pending_update_count": 0
  }
}
```

### Test the Bot

1. Open Telegram and find your bot
2. Send `/start` or `/help`
3. The bot should respond instantly!

### Troubleshooting Webhook Issues

If the bot stops responding after redeployment:
- The API Gateway URL may have changed
- Run `./scripts/setup-webhook.sh` to update the webhook

---

## Project Structure

```
.
├── provider.tf                 # AWS provider + backend configuration
├── variables.tf                # Variable definitions with validation
├── locals.tf                   # Local values for naming/tags
├── main.tf                     # Module calls and data sources
├── outputs.tf                  # Terraform outputs (from modules)
├── modules/                    # Reusable Terraform modules
│   ├── s3/                     # S3 bucket module
│   ├── dynamodb/               # DynamoDB table module
│   ├── lambda/                 # Lambda function module
│   ├── api_gateway/            # API Gateway module
│   └── monitoring/             # CloudWatch metric filter + alarm
├── backend-setup/              # Remote state infrastructure
│   └── main.tf                 # S3 bucket + DynamoDB for state
├── terraform.tfvars.example    # Example configuration
├── terraform.tfvars            # Your configuration (gitignored)
├── requirements.txt            # Python dependencies
├── handler.py                  # Lambda function code
├── package/                    # Lambda deployment package (generated)
├── scripts/
│   ├── setup-webhook.sh        # Telegram webhook setup
│   ├── view-data.sh            # View S3/DynamoDB contents
│   ├── test-observability.sh   # Verify logging, metrics, alarms
│   └── manage-state.sh         # Switch between local/remote state
├── docs/
│   ├── GAP_ANALYSIS.md         # Best practices analysis
│   └── DEMO_CHEATSHEET.md      # Demo commands reference
├── .github/workflows/
│   ├── terraform-validate.yml  # CI: Terraform validation
│   ├── pr-check.yml            # CI: PR validation
│   └── deploy.yml              # CD: AWS deployment
├── CONTRIBUTING.md             # Branch strategy & guidelines
├── CHANGELOG.md                # Project changelog
├── .gitignore                  # Git ignore rules
├── LICENSE                     # GPL v3 License
└── README.md                   # This documentation
```

---

## Module Structure

The infrastructure is organized into reusable modules:

### S3 Module (`modules/s3/`)

Creates an S3 bucket with versioning and lifecycle rules.

| Variable | Description | Default |
|----------|-------------|---------|
| `bucket_name` | Name of the bucket | Required |
| `versioning_enabled` | Enable versioning | `true` |
| `enable_lifecycle_rules` | Enable archival rules | `true` |
| `transition_to_ia_days` | Days before IA transition | `90` |
| `transition_to_glacier_days` | Days before Glacier | `180` |

### DynamoDB Module (`modules/dynamodb/`)

Creates a DynamoDB table with GSIs and TTL support.

| Variable | Description | Default |
|----------|-------------|---------|
| `table_name` | Name of the table | Required |
| `billing_mode` | PAY_PER_REQUEST or PROVISIONED | `PAY_PER_REQUEST` |
| `hash_key` | Partition key name | Required |
| `global_secondary_indexes` | List of GSI configurations | `[]` |
| `ttl_enabled` | Enable TTL | `false` |

### Lambda Module (`modules/lambda/`)

Creates a Lambda function with CloudWatch log group.

| Variable | Description | Default |
|----------|-------------|---------|
| `function_name` | Name of the function | Required |
| `filename` | Path to deployment package | Required |
| `handler` | Function handler | `handler.lambda_handler` |
| `runtime` | Lambda runtime | `python3.9` |
| `role_arn` | IAM role ARN | Required |

### API Gateway Module (`modules/api_gateway/`)

Creates a REST API with Lambda integration.

| Variable | Description | Default |
|----------|-------------|---------|
| `api_name` | Name of the API | Required |
| `resource_path` | API path (e.g., webhook) | `webhook` |
| `lambda_invoke_arn` | Lambda invoke ARN | Required |
| `stage_name` | Deployment stage | `dev` |

---

## Data Storage

### DynamoDB (Active Sessions)

**Table:** `chatbot-sessions`

| Attribute | Type | Purpose |
|-----------|------|---------|
| `pk` | Number | Telegram user ID (partition key) |
| `sk` | String | Session identifier (sort key) |
| `model_name` | String | Selected AI model |
| `session_id` | String | UUID for the session |
| `conversation` | List | Array of messages |
| `is_active` | Number | 1 = active, 0 = inactive |
| `last_message_ts` | Number | Unix timestamp |

**Global Secondary Indexes:**
- `model_index` - Query by model across users
- `active_sessions_index` - Query active sessions

### S3 (Archived Sessions)

**Bucket:** `chatbot-conversations-{ACCOUNT_ID}`

**Structure:**
```
chatbot-conversations-123456789/
└── archives/
    └── {user_id}/
        ├── {session_id_1}.json
        └── {session_id_2}.json
```

---

## Observability

### Log Format

All Lambda logs use structured JSON with consistent fields:

```json
{
  "level": "INFO|WARNING|ERROR",
  "timestamp": "2025-01-20T12:00:00.000000+00:00",
  "action": "handle_command",
  "outcome": "success|failure|warning",
  "message": "Human-readable description",
  "request_id": "lambda-request-id",
  "user_id": 123456789,
  "message_id": 100,
  "chat_id": 123456789
}
```

On errors, `error` and `stack_trace` fields are included automatically.

### Log Retention

- CloudWatch log group: `/aws/lambda/telegram-bot`
- Retention: **14 days** (configurable via `log_retention_days` variable)
- Managed by Terraform in the Lambda module

### Metric Filter and Alarm

- **Metric filter**: Captures `{ $.level = "ERROR" }` from structured JSON logs
- **Metric namespace**: `TelegramBot`
- **Alarm**: Triggers when **1 or more errors** occur within a **5-minute** window
- Alarm auto-resolves (returns to OK) when no errors in the next period

### Viewing Logs and Alarm State

```bash
# Tail live logs
aws logs tail /aws/lambda/telegram-bot --follow

# Filter for errors only
aws logs filter-log-events \
  --log-group-name /aws/lambda/telegram-bot \
  --filter-pattern '{ $.level = "ERROR" }'

# Check alarm state
aws cloudwatch describe-alarms \
  --alarm-names "telegram-bot-error-alarm" \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'

# View metric datapoints (last hour)
aws cloudwatch get-metric-statistics \
  --namespace TelegramBot \
  --metric-name telegram-bot-error-count \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum
```

---

## Verification

### View Stored Data

Use the data viewer script to inspect what's stored in S3 and DynamoDB:

```bash
# Show summary of all data
./scripts/view-data.sh

# Show full content (verbose mode)
./scripts/view-data.sh -v

# Show only DynamoDB sessions
./scripts/view-data.sh dynamodb

# Show only S3 archives
./scripts/view-data.sh s3
```

### CLI Verification

```bash
# Check Lambda
aws lambda get-function --function-name telegram-bot

# Check DynamoDB
aws dynamodb describe-table --table-name chatbot-sessions

# Check S3
aws s3 ls

# Check API Gateway
aws apigateway get-rest-apis

# View Lambda logs
aws logs tail /aws/lambda/telegram-bot --follow
```

### AWS Console Verification

Access the console through AWS Academy:
1. Click **AWS** button (green dot) in Vocareum
2. Navigate to Lambda, DynamoDB, S3, API Gateway services

---

## Troubleshooting

### Authentication Errors
- Session tokens expire every few hours
- Refresh credentials from AWS Academy → AWS Details

### "AccessDenied" for IAM
- AWS Academy restricts IAM role creation
- Use the pre-existing `LabRole` via `lab_role_arn` variable

### Lambda Not Responding
- Check CloudWatch logs: `aws logs tail /aws/lambda/telegram-bot --follow`
- Verify environment variables are set

### Webhook Not Working
- Verify API Gateway URL is correct
- Test Lambda directly: `aws lambda invoke --function-name telegram-bot out.json`
- Check webhook info: `curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"`

### S3 Bucket Name Conflict
- Bucket names must be globally unique
- The template uses `chatbot-conversations-{ACCOUNT_ID}` for uniqueness

---

## Cleanup

### Remove All Resources

```bash
terraform destroy -auto-approve
```

### Remove Telegram Webhook

```bash
curl "https://api.telegram.org/botYOUR_BOT_TOKEN/deleteWebhook"
```

---

## Quick Reference

```bash
# Deploy
terraform init && terraform apply -auto-approve

# Setup webhook (automated - recommended)
./scripts/setup-webhook.sh

# Or manually:
# Get webhook URL
terraform output api_gateway_url
# Set webhook
curl "https://api.telegram.org/bot<TOKEN>/setWebhook?url=<URL>"

# Check webhook
curl "https://api.telegram.org/bot<TOKEN>/getWebhookInfo"

# View stored data (S3 + DynamoDB)
./scripts/view-data.sh
./scripts/view-data.sh -v  # verbose

# View logs
aws logs tail /aws/lambda/telegram-bot --follow

# Destroy
terraform destroy -auto-approve
```

---

## License

This project is licensed under **GNU General Public License v3.0 or later (GPLv3+)**. See [LICENSE](LICENSE) for details.
