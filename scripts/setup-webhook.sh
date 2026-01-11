#!/bin/bash
#
# Telegram Webhook Setup Script
# This script configures the Telegram bot webhook to point to your AWS API Gateway
#
# Usage: ./scripts/setup-webhook.sh
#
# Prerequisites:
#   - terraform.tfvars with telegram_token configured
#   - Terraform infrastructure deployed (terraform apply)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

echo "==================================="
echo "  Telegram Webhook Setup Script"
echo "==================================="
echo ""

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "ERROR: terraform.tfvars not found!"
    echo "Please copy terraform.tfvars.example to terraform.tfvars and configure it."
    exit 1
fi

# Extract token from terraform.tfvars (without exposing it in logs)
TOKEN=$(grep telegram_token terraform.tfvars | sed 's/.*"\(.*\)".*/\1/')

if [ -z "$TOKEN" ] || [ "$TOKEN" == "YOUR_TELEGRAM_BOT_TOKEN" ]; then
    echo "ERROR: telegram_token not configured in terraform.tfvars"
    exit 1
fi

# Mask token for display (show first 4 and last 4 chars)
MASKED_TOKEN="${TOKEN:0:4}...${TOKEN: -4}"
echo "Bot token: $MASKED_TOKEN"

# Get API Gateway URL from Terraform output
echo "Fetching API Gateway URL from Terraform..."
API_URL=$(terraform output -raw api_gateway_url 2>/dev/null)

if [ -z "$API_URL" ]; then
    echo "ERROR: Could not get API Gateway URL from Terraform outputs."
    echo "Make sure you have run 'terraform apply' first."
    exit 1
fi

echo "API Gateway URL: $API_URL"
echo ""

# Set the webhook
echo "Setting Telegram webhook..."
RESULT=$(curl -s "https://api.telegram.org/bot${TOKEN}/setWebhook?url=${API_URL}")

if echo "$RESULT" | grep -q '"ok":true'; then
    echo "Webhook set successfully!"
else
    echo "ERROR: Failed to set webhook"
    echo "$RESULT" | jq 2>/dev/null || echo "$RESULT"
    exit 1
fi

echo ""

# Verify the webhook
echo "Verifying webhook configuration..."
WEBHOOK_INFO=$(curl -s "https://api.telegram.org/bot${TOKEN}/getWebhookInfo")

echo ""
echo "Webhook Info:"
echo "$WEBHOOK_INFO" | jq 2>/dev/null || echo "$WEBHOOK_INFO"

# Check for errors
if echo "$WEBHOOK_INFO" | grep -q '"last_error_message"'; then
    echo ""
    echo "WARNING: There are webhook errors. Check the message above."
fi

echo ""

# Test bot connectivity
echo "Testing bot connectivity..."
BOT_INFO=$(curl -s "https://api.telegram.org/bot${TOKEN}/getMe")

if echo "$BOT_INFO" | grep -q '"ok":true'; then
    BOT_NAME=$(echo "$BOT_INFO" | jq -r '.result.username' 2>/dev/null)
    echo "Bot @$BOT_NAME is online and ready!"
else
    echo "WARNING: Could not verify bot connectivity"
fi

echo ""
echo "==================================="
echo "  Setup Complete!"
echo "==================================="
echo ""
echo "Your bot should now respond automatically to Telegram messages."
echo "Test it by sending /start or /help to your bot."
echo ""
