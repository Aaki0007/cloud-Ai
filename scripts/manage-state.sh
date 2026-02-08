#!/bin/bash
set -euo pipefail

###############################################
# State Management Script
# Switch between local and remote Terraform state
#
# Usage:
#   ./scripts/manage-state.sh remote   # Switch to S3 remote state
#   ./scripts/manage-state.sh local    # Switch to local state
#   ./scripts/manage-state.sh status   # Show current backend
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROVIDER_FILE="$PROJECT_DIR/provider.tf"
BACKEND_SETUP_DIR="$PROJECT_DIR/backend-setup"

# Check if backend block is currently commented out
is_local() {
    grep -q '# *backend "s3"' "$PROVIDER_FILE"
}

show_status() {
    if is_local; then
        echo "Current backend: LOCAL"
        echo "State file: terraform.tfstate"
    else
        echo "Current backend: REMOTE (S3)"
        BUCKET=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) && \
            echo "State bucket: terraform-state-$BUCKET" || \
            echo "State bucket: terraform-state-<unable to detect account>"
    fi
}

enable_remote() {
    echo "=== Switching to REMOTE state ==="
    echo ""

    # 1. Check AWS credentials
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        echo "ERROR: AWS credentials are not valid."
        echo "  1. Go to AWS Academy -> AWS Details -> Show"
        echo "  2. Copy credentials to ~/.aws/credentials"
        echo "  3. Re-run this script"
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    BUCKET_NAME="terraform-state-$ACCOUNT_ID"

    # 2. Check if backend infrastructure exists
    echo "Checking backend infrastructure..."
    if aws s3api head-bucket --bucket "$BUCKET_NAME" 2>/dev/null; then
        echo "  S3 bucket exists: $BUCKET_NAME"
    else
        echo "  S3 bucket not found. Creating backend infrastructure..."
        echo ""
        cd "$BACKEND_SETUP_DIR"
        terraform init -input=false
        terraform apply -auto-approve
        cd "$PROJECT_DIR"
        echo ""
        echo "  Backend infrastructure created."
    fi

    if aws dynamodb describe-table --table-name terraform-locks > /dev/null 2>&1; then
        echo "  DynamoDB lock table exists: terraform-locks"
    else
        echo "  DynamoDB table not found. Creating backend infrastructure..."
        echo ""
        cd "$BACKEND_SETUP_DIR"
        terraform init -input=false
        terraform apply -auto-approve
        cd "$PROJECT_DIR"
        echo ""
        echo "  Backend infrastructure created."
    fi

    # 3. Already remote?
    if ! is_local; then
        echo ""
        echo "Backend is already set to REMOTE."
        echo "Re-initializing..."
        cd "$PROJECT_DIR"
        terraform init -reconfigure \
            -backend-config="bucket=$BUCKET_NAME"
        echo ""
        echo "Done. Remote state is active."
        return
    fi

    # 4. Uncomment the backend block
    echo ""
    echo "Enabling backend block in provider.tf..."
    sed -i 's|^  # backend "s3" {|  backend "s3" {|' "$PROVIDER_FILE"
    sed -i 's|^  #   key |    key |' "$PROVIDER_FILE"
    sed -i 's|^  #   region |    region |' "$PROVIDER_FILE"
    sed -i 's|^  #   encrypt |    encrypt |' "$PROVIDER_FILE"
    sed -i 's|^  #   dynamodb_table |    dynamodb_table |' "$PROVIDER_FILE"
    sed -i 's|^  # }$|  }|' "$PROVIDER_FILE"

    # 5. Migrate state
    echo "Migrating state to S3..."
    echo ""
    cd "$PROJECT_DIR"
    terraform init -migrate-state \
        -backend-config="bucket=$BUCKET_NAME"

    echo ""
    echo "=== Remote state is now active ==="
    echo "  Bucket: $BUCKET_NAME"
    echo "  Key:    ai-chatbot/terraform.tfstate"
    echo "  Lock:   terraform-locks"
}

enable_local() {
    echo "=== Switching to LOCAL state ==="
    echo ""

    # Already local?
    if is_local; then
        echo "Backend is already set to LOCAL."
        return
    fi

    # Comment out the backend block
    echo "Disabling backend block in provider.tf..."
    sed -i 's|^  backend "s3" {|  # backend "s3" {|' "$PROVIDER_FILE"
    sed -i 's|^    key |  #   key |' "$PROVIDER_FILE"
    sed -i 's|^    region |  #   region |' "$PROVIDER_FILE"
    sed -i 's|^    encrypt |  #   encrypt |' "$PROVIDER_FILE"
    sed -i 's|^    dynamodb_table |  #   dynamodb_table |' "$PROVIDER_FILE"
    # Match closing brace that's part of the backend block (line after dynamodb_table)
    # Use a targeted approach: find the first standalone "  }" after the backend comment
    python3 -c "
import re
with open('$PROVIDER_FILE', 'r') as f:
    content = f.read()
# Find the uncommented closing brace right after dynamodb_table line
content = re.sub(
    r'(#   dynamodb_table.*\n)(  \})',
    r'\1  # }',
    content,
    count=1
)
with open('$PROVIDER_FILE', 'w') as f:
    f.write(content)
"

    # Migrate state back to local
    echo "Migrating state to local..."
    echo ""
    cd "$PROJECT_DIR"
    terraform init -migrate-state

    echo ""
    echo "=== Local state is now active ==="
    echo "  State file: terraform.tfstate"
}

# Main
case "${1:-}" in
    remote)
        enable_remote
        ;;
    local)
        enable_local
        ;;
    status)
        show_status
        ;;
    *)
        echo "Usage: $0 {remote|local|status}"
        echo ""
        echo "  remote  - Switch to S3 remote state (auto-creates backend if needed)"
        echo "  local   - Switch to local state file"
        echo "  status  - Show current backend configuration"
        exit 1
        ;;
esac
