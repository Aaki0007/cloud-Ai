# AWS Telegram Chatbot with Self-Hosted AI

## Project Overview

A serverless Telegram chatbot deployed on AWS using Terraform. Users choose an
AI model (Llama 3.2 or Qwen 2.5) and chat via Ollama on EC2. The bot manages
sessions, archives conversations, and integrates a self-hosted LLM as an
external HTTP API.

**Tech Stack:** Terraform, Python 3.9, AWS (Lambda, API Gateway, DynamoDB, S3,
EC2, CloudWatch)

- - -
## Architecture

```
┌─────────────┐       ┌─────────────────┐       ┌────────────────┐       ┌─────────────────┐
│   Telegram  │──────>│   API Gateway   │──────>│     Lambda     │──────>│   EC2 (Ollama)  │
│    User     │<──────│   (webhook)     │<──────│  (handler.py)  │<──────│  AI inference   │
└─────────────┘       └─────────────────┘       └────────────────┘       └─────────────────┘
                                                      │                         │
                              ┌────────────────────────┴──────────┐             │
                              v                                   v             v
                     ┌─────────────────┐                ┌──────────────────────────────┐
                     │    DynamoDB     │                │             S3               │
                     │(active sessions)│                │ (archived chats + AI models) │
                     └─────────────────┘                └──────────────────────────────┘
                                                              │
                                                    ┌─────────────────┐
                                                    │   CloudWatch    │
                                                    │ (logs + alarm)  │
                                                    └─────────────────┘
```
**Flow:**

1.  User sends a message to the Telegram bot
2.  Telegram POSTs the update to API Gateway webhook URL
3.  API Gateway triggers Lambda function
4.  Lambda processes the message (command or chat)
5.  For chat messages, Lambda calls Ollama on EC2 over HTTP for AI response
6.  Session data is stored/retrieved from DynamoDB
7.  Archived sessions are stored in S3
8.  Lambda sends response back to Telegram

- - -
## Live Demo: Bot Commands


|\#|Command            |What It Shows                                                            |
|--|-------------------|-------------------------------------------------------------------------|
|1 |`/start`           |Initialize bot, show greeting + available models                         |
|2 |`/newsession`      |Show available AI models to choose from                                  |
|3 |`/newsession 1`    |Create session with Llama 3.2 (model selection + DynamoDB write)         |
|4 |`/newsession 2`    |Create session with Qwen 2.5 (different model)                           |
|5 |Send a chat message|AI responds via Ollama (external API call), "Thinking..." indicator shown|
|6 |`/switch 1`        |Switch between sessions/models (DynamoDB update)                         |
|7 |`/listsessions`    |List all sessions with model names                                       |
|8 |`/history`         |Show recent messages (DynamoDB read)                                     |
|9 |`/archive 1`       |Archive a session to S3 (S3 upload)                                      |
|10|`/listarchives`    |List archives (S3 list)                                                  |
|11|`/export 1`        |Download archive as JSON file (S3 retrieve)                              |
|12|`/status`          |Shows Ollama connection, model name, session info                        |

13 commands total. Additional: `/help`, `/echo`, file import.

- - -
## DynamoDB Integration

**Table:** `chatbot-sessions` (PAY_PER_REQUEST billing)


|Key           |Type  |Purpose                         |
|--------------|------|--------------------------------|
|`pk` (partition)|Number|Telegram user ID                |
|`sk` (sort)   |String|`MODEL#llama3.2:1b#SESSION#{uuid}`|

**Operations used:**


|Operation  |Where                                         |
|-----------|----------------------------------------------|
|`put_item` |Create sessions, save messages, dedup tracking|
|`get_item` |Retrieve sessions, duplicate update check     |
|`query`    |List user sessions with KeyConditionExpression|
|`update_item`|Switch active session, deactivate old ones    |

**Global Secondary Indexes:** `model_index` (query by model), `
active_sessions_index`

**Security:** Server-side encryption enabled, point-in-time recovery enabled

- - -
## S3 Integration

**Bucket:** `chatbot-conversations-{ACCOUNT_ID}`

**Structure:**

```
archives/
  {user_id}/
    {session_id_1}.json
    {session_id_2}.json
```
**Operations used:**


|Operation      |Where                          |
|---------------|-------------------------------|
|`put_object`   |Archive session, import archive|
|`list_objects_v2`|List user archives (paginated) |
|`get_object`   |Retrieve archive for export    |

**Security:** Public access fully blocked, AES256 server-side encryption,
versioning enabled

**Lifecycle rules:** Standard IA at 90 days, Glacier at 180 days, noncurrent
version expiration

- - -
## External API Integration: Ollama

**What:** Self-hosted LLM inference server running on EC2 t3.large (CPU-only)

**Available Models:**


|\#|Model                       |Description                         |Size  |
|-|----------------------------|------------------------------------|------|
|1|`llama3.2:1b`               |Meta Llama 3.2, fast general-purpose|1.3 GB|
|2|`qwen2.5:1.5b-instruct-q4_K_M`|Alibaba Qwen 2.5, instruction-tuned |986 MB|

Users select a model when creating a session via `/newsession \<number>`.
Sessions using removed models show a warning and prompt the user to create a
new session.

**Endpoint:** `POST http://\<Elastic_IP>:11434/api/chat`

**Request:**

```json
{
  "model": "llama3.2:1b",
  "messages": [{"role": "user", "content": "hello"}],
  "stream": false
}
```
**Response:**

```json
{
  "message": {"content": "Hi! How can I help you today?"}
}
```
**Privacy:** No conversation history stored on EC2 (`OLLAMA_NOHISTORY=true`)

### Error Handling


|Scenario           |Handling                                                         |
|-------------------|-----------------------------------------------------------------|
|Instance down      |3-second health check, fast fail with "AI service is unreachable"|
|Connection timeout |22-second timeout on HTTP request                                |
|Non-200 status code|Smart retry on fast failures (\<5s), then user-friendly error    |
|Connection error   |try/except catches all exceptions, retry once if fast            |
|Ollama unreachable |Bot stays functional, returns fallback message                   |
|All failures       |Structured ERROR logs with stack traces to CloudWatch            |

### Rate Limiting and Guardrails


|Guard                |Description                                                       |
|---------------------|------------------------------------------------------------------|
|Pending request check|Responds "Please wait, still generating..." while AI is processing|
|Message length limit |4000-character maximum                                            |
|Context window       |Last 10 messages sent to Ollama (prevents CPU timeout)            |
|Duplicate detection  |update_id tracked in DynamoDB to prevent Telegram webhook retries |

### User Experience

- Bot sends "Thinking..." immediately when a message is received
- Message is edited in-place with the AI response once ready
- If user sends another message while AI is processing, they get a "please
  wait" warning

- - -
## Secrets Management

All secrets passed as Lambda environment variables via Terraform. Nothing
hardcoded in source code.


|Secret        |Source          |How Set                                             |
|--------------|----------------|----------------------------------------------------|
|`TELEGRAM_TOKEN`|User-provided   |`var.telegram_token` in terraform.tfvars (gitignored)|
|`OLLAMA_URL`  |Terraform output|`module.ec2_ollama.ollama_url`                      |
|`OLLAMA_API_KEY`|Auto-generated  |`random_password` resource (32-char, no special chars)|
|`S3_BUCKET_NAME`|Terraform output|`module.s3.bucket_name`                             |

**Additional protections:**

- API key validated by nginx reverse proxy on EC2 (returns HTTP 401 without
  valid key)
- Ollama binds to localhost only (127.0.0.1:11435), not externally accessible
- Sensitive Terraform outputs marked `sensitive = true`
- `.gitignore` excludes `\*.pem`, `\*.key`, `.env`, `\*.secret`, `
  terraform.tfvars`

- - -
## Terraform Structure

### Modules (6 total)

```
modules/
  s3/            - Bucket, versioning, lifecycle, encryption, public access block
  dynamodb/      - Table, GSIs, TTL, server-side encryption, point-in-time recovery
  lambda/        - Function, CloudWatch log group, environment variables
  api_gateway/   - REST API, POST method, Lambda integration, deployment stage
  monitoring/    - CloudWatch metric filter + alarm
  ec2/           - Ollama instance, Elastic IP, security group, user_data template
```
### Configuration Files


|File        |Purpose                                                                    |
|------------|---------------------------------------------------------------------------|
|`variables.tf`|Input variables with validation (ARN regex, env enum, log retention values)|
|`locals.tf` |Naming convention (`{project}-{resource}-{env}`), common tags              |
|`provider.tf`|AWS + archive + random providers, remote state backend config              |
|`main.tf`   |Module instantiation, data sources, dependencies                           |
|`outputs.tf`|Terraform outputs (sensitive values masked)                                |

### Remote State

- `backend-setup/` directory creates S3 bucket + DynamoDB lock table
- Backend block in `provider.tf` ready to uncomment after setup
- State locking via DynamoDB for team collaboration
- State encrypted at rest in S3

### Variables and Locals

**Variables** with validation:

```hcl
variable "lab_role_arn" {
  validation {
    condition = can(regex("^arn:aws:iam::", var.lab_role_arn))
  }
}

variable "environment" {
  validation {
    condition = contains(["dev", "staging", "prod"], var.environment)
  }
}
```
**Common tags** applied to all resources via `merge()`:

```hcl
common_tags = {
  Project     = "AI-Chatbot"
  Team        = "CloudDev"
  Environment = var.environment
  ManagedBy   = "Terraform"
  Repository  = "github.com/Man2Dev/cloud-Ai"
}
```
- - -
## CloudWatch Observability

### Structured JSON Logging

Every log entry is structured JSON with consistent fields:

```json
{
  "level": "INFO",
  "timestamp": "2026-02-08T22:12:00.000000+00:00",
  "action": "call_ollama",
  "outcome": "success",
  "message": "Response length 142 chars",
  "request_id": "abc-123-def",
  "user_id": 123456789,
  "chat_id": 123456789
}
```
On errors, `error` and `stack_trace` fields are added automatically.

### Metric Filter

- Pattern: `{ $.level = "ERROR" }` (matches structured JSON)
- Namespace: `TelegramBot`
- Metric: `telegram-bot-error-count`

### Alarm

- Triggers on 1 or more errors in a 5-minute window
- Auto-resolves when errors drop to 0
- Missing data treated as "not breaching"

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
```
- - -
## Security Summary


|Layer            |Measure                                                                           |
|-----------------|----------------------------------------------------------------------------------|
|Ollama API       |Nginx reverse proxy with API key authentication (32-char, auto-generated)         |
|Ollama binding   |Localhost only (127.0.0.1:11435), not externally accessible                       |
|SSH access       |Restricted to configurable CIDR (`ssh_allowed_cidr` variable)                     |
|S3               |Public access fully blocked, AES256 server-side encryption, versioning            |
|DynamoDB         |Server-side encryption enabled, point-in-time recovery enabled                    |
|Secrets          |Lambda environment variables via Terraform, never in source code                  |
|Terraform outputs|Sensitive values masked (`sensitive = true`)                                      |
|Git              |`.gitignore` excludes keys, secrets, tfvars, state files                          |
|IAM              |LabRole (Academy constraint); least-privilege policy documented in GAP_ANALYSIS.md|
|Privacy          |`OLLAMA_NOHISTORY=true` — no conversation history stored on EC2                   |
|Input validation |4000-char message limit, variable validation rules in Terraform                   |

- - -
## Limitations and Trade-offs


|Trade-off                   |Reasoning                                                                                                                                     |
|----------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|
|CPU-only inference (no GPU) |t3.large is the largest instance type allowed in Academy; Llama 3.2 (1B) and Qwen 2.5 (1.5B) run adequately on CPU                            |
|Port 11434 open to 0.0.0.0/0|Lambda egress IPs are unpredictable and change on every invocation; mitigated by API key authentication and only running EC2 during active use|
|Small model sizes (1-1.5B)  |Smaller, simpler responses than larger models; adequate for demonstrating the integration and fit within Academy instance limits              |
|API Gateway 29s timeout     |REST API hard limit; mitigated with 22s timeout + 3s health check + update_id deduplication in DynamoDB                                       |
|No custom IAM role          |AWS Academy restricts IAM role creation; LabRole used, production least-privilege policy documented                                           |
|EC2 cost when running       |t3.large ~$0.083/hr; managed via start/stop script to minimize runtime; EBS ~$2.40/mo                                                         |

- - -
## Deploy and Destroy

### Deploy

```bash
# 1. Configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with token and LabRole ARN

# 2. Build Lambda package
pip install -r requirements.txt -t ./package
cp handler.py package/

# 3. Deploy infrastructure
terraform init
terraform apply -auto-approve

# 4. Set up Telegram webhook
./scripts/setup-webhook.sh

# 5. Start Ollama EC2 instance
./scripts/manage-ollama.sh start
```
### Verify

```bash
./scripts/manage-ollama.sh status    # Check EC2 and Ollama API health
./scripts/view-data.sh               # View DynamoDB and S3 data
aws logs tail /aws/lambda/telegram-bot --follow  # Watch live logs
```
### Destroy

```bash
./scripts/manage-ollama.sh stop      # Stop EC2 instance first
terraform destroy -auto-approve      # Remove all AWS resources
```
All resources are created and destroyed cleanly via Terraform.

- - -
## Requirements Checklist


|Requirement                |Status|Details                                                      |
|---------------------------|------|-------------------------------------------------------------|
|Deploy with `terraform apply`|Done  |Single command deploys all 6 modules                         |
|3+ bot commands            |Done  |13 commands implemented                                      |
|DynamoDB create/read       |Done  |put_item, get_item, query, update_item                       |
|S3 upload/list/retrieve    |Done  |put_object, list_objects_v2, get_object                      |
|CloudWatch logs            |Done  |Structured JSON logging, 14-day retention                    |
|External API call          |Done  |Lambda calls Ollama POST /api/chat on EC2                    |
|Error/timeout handling     |Done  |3s health check, 22s timeout, smart retry, structured logging|
|Secrets out of code        |Done  |All via Lambda env vars from Terraform                       |
|Rate limits/guardrails     |Done  |Pending request guard, message limit, context window, dedup  |
|Architecture walkthrough   |Done  |Diagram + 6 modules explained                                |
|Terraform quality          |Done  |Modules, validated variables, locals, remote state           |
|`terraform destroy`        |Done  |Clean teardown documented                                    |
|Monitoring/alerting        |Done  |Metric filter + alarm on ERROR logs                          |
|Tagging                    |Done  |5 common tags on all resources                               |
|Documentation              |Done  |700+ line README with all required sections                  |

