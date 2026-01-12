#!/bin/bash
set -uo pipefail

###############################################
# CONFIGURATION
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

# Get bucket name from terraform or construct it
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
BUCKET_NAME="chatbot-conversations-${ACCOUNT_ID}"
LOG_GROUP="/aws/lambda/telegram-bot"

echo "==========================================="
echo "  Reset Script"
echo "==========================================="
echo "Account ID: ${ACCOUNT_ID:-unknown}"
echo "Bucket: $BUCKET_NAME"
echo ""

###############################################
# CLEAN UP OLD DEPLOYMENT
###############################################

# Delete CloudWatch Log Group (ignore if doesn't exist)
echo "Removing CloudWatch Log Group..."
aws logs delete-log-group --log-group-name "$LOG_GROUP" 2>/dev/null && echo "  Deleted log group" || echo "  Log group doesn't exist (skipping)"

# Delete S3 bucket with all versions
if [ -n "$ACCOUNT_ID" ]; then
    echo "Checking S3 bucket..."
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "  Deleting all object versions..."

        # Delete all versions
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'Versions[].{Key: Key, VersionId: VersionId}' --output json 2>/dev/null | \
        jq -c 'select(. != null) | {Objects: ., Quiet: true}' | \
        while read -r batch; do
            if [ "$batch" != '{"Objects":null,"Quiet":true}' ] && [ -n "$batch" ]; then
                aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$batch" 2>/dev/null || true
            fi
        done

        # Delete all delete markers
        aws s3api list-object-versions --bucket "$BUCKET_NAME" --query 'DeleteMarkers[].{Key: Key, VersionId: VersionId}' --output json 2>/dev/null | \
        jq -c 'select(. != null) | {Objects: ., Quiet: true}' | \
        while read -r batch; do
            if [ "$batch" != '{"Objects":null,"Quiet":true}' ] && [ -n "$batch" ]; then
                aws s3api delete-objects --bucket "$BUCKET_NAME" --delete "$batch" 2>/dev/null || true
            fi
        done

        echo "  S3 bucket emptied"
    else
        echo "  Bucket doesn't exist (skipping)"
    fi
else
    echo "  Skipping S3 cleanup (no AWS credentials)"
fi

# Terraform destroy
echo "Destroying Terraform infrastructure..."
terraform destroy -auto-approve 2>/dev/null || echo "  Terraform destroy completed (or nothing to destroy)"

# Clean build artifacts
echo "Cleaning old build artifacts..."
rm -rf package/ lambda_function.zip

###############################################
# REBUILD LAMBDA PACKAGE
###############################################

echo ""
echo "Rebuilding Lambda deployment package..."
mkdir -p package

echo "Installing Python dependencies..."
pip install -r requirements.txt -t ./package --quiet

echo "Copying handler.py..."
cp handler.py package/

###############################################
# TERRAFORM DEPLOY
###############################################

echo ""
echo "Initializing Terraform..."
terraform init -input=false

echo "Planning Terraform..."
terraform plan

echo "Applying Terraform..."
terraform apply -auto-approve

###############################################
# SETUP WEBHOOK
###############################################

echo ""
echo "Setting up Telegram webhook..."
"$SCRIPT_DIR/setup-webhook.sh"

echo ""
echo "==========================================="
echo "  Reset Complete!"
echo "==========================================="
