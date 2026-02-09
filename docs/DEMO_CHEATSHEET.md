# Final Demo Cheatsheet

## Quick Reference Commands

---

## Part A: Live Demo Steps

### 1. Show Terraform Apply

```bash
# First, show the plan
terraform plan

# Then apply (already deployed, but can show)
terraform apply -auto-approve
```

**Expected Output:**
- S3 bucket: `chatbot-conversations-654654624560`
- DynamoDB table: `chatbot-sessions`
- Lambda function: `telegram-bot`
- API Gateway: `telegram-bot-api`
- EC2 instance: `ai-chatbot-ollama` (Ollama AI server)
- CloudWatch alarm: `telegram-bot-error-alarm`

### 2. Demonstrate Bot Commands (in Telegram)

| Command | What It Shows | Demo Script |
|---------|---------------|-------------|
| `/start` | Bot initialization, shows current model | Greeting + available models list |
| `/help` | Full command list + available models | Shows all commands and AI models |
| `/newsession` | Shows available AI models | Lists models with descriptions |
| `/newsession 1` | Creates session with Llama 3.2 | DynamoDB write + model selection |
| `/newsession 2` | Creates session with Qwen 2.5 | Different model, same flow |
| `/switch 1` | Switch between sessions/models | DynamoDB update |
| `/listsessions` | DynamoDB read operation | Lists all sessions with model names |
| `/history` | Conversation retrieval | Shows message history |
| `/status` | System health check | Shows bot + Ollama AI status |
| `/archive 1` | S3 write operation | Moves session to S3 |
| `/listarchives` | S3 list operation | Shows archived files |
| `/export 1` | S3 read + file send | Downloads archive as JSON |
| `/echo test` | Simple echo test | Echoes back text |
| Chat message | AI-powered response | Sends to Ollama, gets AI reply |

**Recommended Demo Flow:**
1. Send `/start` — Show greeting with current model
2. Send `/help` — Show all commands and available models
3. Send a chat message (e.g. "Hello, what can you do?") — Show AI response with "Thinking..." indicator
4. Send `/newsession` — Show available models list
5. Send `/newsession 2` — Switch to Qwen 2.5 model
6. Send a chat message — Show response from different model
7. Send `/switch 1` — Switch back to first session
8. Send `/listsessions` — Show all sessions with model names
9. Send `/history` — Show conversation retrieval
10. Send `/status` — Show Ollama connection status
11. Send `/archive` — List sessions to archive
12. Send `/archive 1` — Move to S3 (demonstrate persistence)
13. Send `/listarchives` — Show S3 listing

### 3. Demonstrate Model Switching

This is a key feature — users can choose between AI models:

```
Available Models:
1. Llama 3.2 - Meta's latest, fast (1B)
2. Qwen 2.5 - Instruction-tuned (1.5B)
```

**Demo steps:**
1. `/newsession 1` — Create session with Llama 3.2
2. Send "Explain cloud computing in 2 sentences" — Get Llama response
3. `/newsession 2` — Create session with Qwen 2.5
4. Send the same question — Compare different model's response
5. `/listsessions` — Show both sessions with different models
6. `/switch 1` — Switch back, conversation context preserved

**Unavailable model handling:**
- If a session uses a model that was removed, the bot warns the user and prompts them to create a new session

### 4. Show AI Error Handling

**When EC2 is running:**
- Chat messages get "Thinking..." indicator, then AI response
- Duplicate messages are blocked ("Please wait, still generating...")

**When EC2 is stopped:**
- Bot responds in ~3 seconds: "AI service is unreachable (instance may be stopped)"
- Fast health check prevents 22s timeout wait
- `/status` shows "unreachable (instance may be stopped)"
- Bot commands (/help, /listsessions, etc.) still work — only AI chat is affected

### 5. Show Ollama EC2 Management

```bash
# Check instance status and API health
./scripts/manage-ollama.sh status

# Stop the instance (demonstrate graceful handling)
./scripts/manage-ollama.sh stop

# Start the instance
./scripts/manage-ollama.sh start

# SSH into instance (for model management)
./scripts/manage-ollama.sh ssh
```

### 6. Show DynamoDB Persistence

```bash
# Option 1: Use our script
./scripts/view-data.sh dynamodb

# Option 2: AWS CLI
aws dynamodb scan --table-name chatbot-sessions --output table

# Show specific item
aws dynamodb get-item \
  --table-name chatbot-sessions \
  --key '{"pk": {"N": "136431476"}, "sk": {"S": "MODEL#llama3.2:1b#SESSION#..."}}' \
  | jq
```

### 7. Show S3 Integration

```bash
# Option 1: Use our script
./scripts/view-data.sh s3

# Option 2: AWS CLI - List bucket contents
aws s3 ls s3://chatbot-conversations-654654624560/ --recursive

# Download and view an archive
aws s3 cp s3://chatbot-conversations-654654624560/archives/USER_ID/SESSION_ID.json - | jq
```

### 8. Show Observability

```bash
# Run automated observability test
./scripts/test-observability.sh

# Tail live logs (structured JSON)
aws logs tail /aws/lambda/telegram-bot --follow

# Check alarm state
aws cloudwatch describe-alarms \
  --alarm-names "telegram-bot-error-alarm" \
  --query 'MetricAlarms[0].{State:StateValue,Reason:StateReason}'
```

### 9. Architecture Walkthrough

```bash
# Show Lambda function
aws lambda get-function --function-name telegram-bot | jq '.Configuration | {FunctionName, Runtime, Handler, MemorySize, Timeout}'

# Show API Gateway
aws apigateway get-rest-apis | jq '.items[] | {name, id, endpointConfiguration}'

# Show DynamoDB table structure
aws dynamodb describe-table --table-name chatbot-sessions | jq '.Table | {TableName, KeySchema, GlobalSecondaryIndexes}'

# Show S3 bucket
aws s3api get-bucket-tagging --bucket chatbot-conversations-654654624560

# Show EC2 instance
aws ec2 describe-instances --filters "Name=tag:Name,Values=ai-chatbot-ollama" \
  --query 'Reservations[0].Instances[0].{State:State.Name,Type:InstanceType,IP:PublicIpAddress}'
```

---

## Part B: Key Features Summary (for slides)

### External API Integration (Ollama)
- Self-hosted LLM on EC2 (t3.large, CPU-only)
- Lambda calls `POST /api/chat` over HTTP
- API key authentication via nginx reverse proxy
- 2 models: Llama 3.2 (1B), Qwen 2.5 (1.5B instruct)
- Users choose model per session via `/newsession <number>`
- No history stored on server (`OLLAMA_NOHISTORY=true`)

### Error Handling
- 3s health check — fast fail when instance is down
- 22s timeout for actual inference requests
- Smart retry: only retries on fast connection errors (<5s), not timeouts
- "Thinking..." indicator while AI processes
- Rate limiting: blocks duplicate requests while processing
- Update deduplication via update_id tracking
- Graceful fallback: bot remains functional without AI

### Security
- Nginx reverse proxy validates `X-API-Key` on all Ollama requests
- Ollama binds to localhost only (127.0.0.1:11435)
- S3: public access blocked, AES256 encryption
- DynamoDB: server-side encryption, point-in-time recovery
- Sensitive Terraform outputs marked `sensitive = true`
- No conversation history stored on EC2
- 4000-char max message length validation

### Infrastructure as Code
- 6 Terraform modules (s3, dynamodb, lambda, api_gateway, monitoring, ec2)
- Consistent tagging on all resources
- Variables with validation rules
- Remote state support (S3 + DynamoDB locking)
- Structured JSON logging with CloudWatch metric filter + alarm

### Gap Analysis Progress

| Gap (Mid-term) | Status (Final) |
|----------------|----------------|
| No modules | ✅ 6 reusable modules |
| No locals block | ✅ locals.tf with naming conventions |
| IAM over-permissioned | ⚠️ LabRole (Academy limitation), documented |
| No environment separation | ✅ Environment variable (dev/staging/prod) |
| No CloudWatch log retention | ✅ 14-day retention via Terraform |
| No remote state backend | ✅ S3 + DynamoDB with manage-state.sh |
| No external API | ✅ Ollama on EC2 with full error handling |

---

## Demo Verification Commands

```bash
# Verify all resources exist
echo "=== Lambda ===" && aws lambda get-function --function-name telegram-bot --query 'Configuration.FunctionName'
echo "=== DynamoDB ===" && aws dynamodb describe-table --table-name chatbot-sessions --query 'Table.TableName'
echo "=== S3 ===" && aws s3api head-bucket --bucket chatbot-conversations-654654624560 && echo "Bucket exists"
echo "=== API Gateway ===" && aws apigateway get-rest-apis --query 'items[?name==`telegram-bot-api`].name'
echo "=== EC2 ===" && aws ec2 describe-instances --filters "Name=tag:Name,Values=ai-chatbot-ollama" --query 'Reservations[0].Instances[0].State.Name' --output text
echo "=== Alarm ===" && aws cloudwatch describe-alarms --alarm-names "telegram-bot-error-alarm" --query 'MetricAlarms[0].StateValue' --output text

# Verify webhook
curl -s "https://api.telegram.org/bot$(grep telegram_token terraform.tfvars | cut -d'"' -f2)/getWebhookInfo" | jq '.result.url'

# Verify Ollama API
./scripts/manage-ollama.sh status
```

---

## Troubleshooting During Demo

### If credentials expire:
```bash
aws sts get-caller-identity
# If expired, update ~/.aws/credentials from AWS Academy
```

### If webhook not working:
```bash
./scripts/setup-webhook.sh
```

### If Ollama not responding:
```bash
./scripts/manage-ollama.sh start
# Wait 1-2 minutes for API to be ready
```

### If bot not responding at all:
```bash
# Check Lambda logs
aws logs tail /aws/lambda/telegram-bot --follow

# Redeploy Lambda
cp handler.py /tmp/lambda-build/handler.py
cd /tmp/lambda-build && zip -r ~/cloud-Ai/lambda.zip . -x '__pycache__/*' '*.pyc'
aws lambda update-function-code --function-name telegram-bot --zip-file fileb://~/cloud-Ai/lambda.zip
```

### If need to see Lambda logs:
```bash
aws logs tail /aws/lambda/telegram-bot --follow
```
