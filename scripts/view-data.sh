#!/bin/bash
#
# View Data Script
# Shows contents of S3 bucket and DynamoDB table
#
# Usage:
#   ./scripts/view-data.sh           # Show summary of all data
#   ./scripts/view-data.sh -v        # Verbose - show full content
#   ./scripts/view-data.sh dynamodb  # Show only DynamoDB data
#   ./scripts/view-data.sh s3        # Show only S3 data
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

VERBOSE=false
SHOW_DYNAMODB=true
SHOW_S3=true

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        dynamodb|db)
            SHOW_S3=false
            shift
            ;;
        s3)
            SHOW_DYNAMODB=false
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [-v|--verbose] [dynamodb|s3]"
            echo ""
            echo "Options:"
            echo "  -v, --verbose    Show full content of items"
            echo "  dynamodb, db     Show only DynamoDB data"
            echo "  s3               Show only S3 data"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Get resource names from Terraform
echo "Fetching resource names from Terraform..."
S3_BUCKET=$(terraform output -raw s3_bucket_name 2>/dev/null)
DYNAMODB_TABLE=$(terraform output -raw dynamodb_table_name 2>/dev/null)

if [ -z "$S3_BUCKET" ] || [ -z "$DYNAMODB_TABLE" ]; then
    echo "ERROR: Could not get resource names from Terraform outputs."
    echo "Make sure you have run 'terraform apply' first."
    exit 1
fi

echo ""

# ============================================
# DynamoDB Section
# ============================================
if [ "$SHOW_DYNAMODB" = true ]; then
    echo "==========================================="
    echo "  DynamoDB Table: $DYNAMODB_TABLE"
    echo "==========================================="
    echo ""

    # Get item count
    ITEM_COUNT=$(aws dynamodb scan \
        --table-name "$DYNAMODB_TABLE" \
        --select "COUNT" \
        --query "Count" \
        --output text 2>/dev/null)

    echo "Total items: $ITEM_COUNT"
    echo ""

    if [ "$ITEM_COUNT" -gt 0 ]; then
        echo "Sessions:"
        echo "---------"

        # Scan and display items
        ITEMS=$(aws dynamodb scan \
            --table-name "$DYNAMODB_TABLE" \
            --output json 2>/dev/null)

        if [ "$VERBOSE" = true ]; then
            # Show full items
            echo "$ITEMS" | jq '.Items[] | {
                user_id: .pk.N,
                session_key: .sk.S,
                model: (.model_name.S // "N/A"),
                session_id: (.session_id.S // "N/A"),
                is_active: (.is_active.N // "N/A"),
                message_count: ((.conversation.L // []) | length),
                last_message: (.last_message_ts.N // "N/A")
            }'
        else
            # Show summary table
            echo "$ITEMS" | jq -r '.Items[] | [
                .pk.N,
                (.sk.S | split("#") | .[1] // "N/A"),
                ((.conversation.L // []) | length | tostring),
                (if .is_active.N == "1" then "active" else "inactive" end)
            ] | @tsv' | column -t -N "USER_ID,MODEL,MESSAGES,STATUS"
        fi

        if [ "$VERBOSE" = true ]; then
            echo ""
            echo "Full conversation data:"
            echo "-----------------------"
            echo "$ITEMS" | jq '.Items[] | {
                user_id: .pk.N,
                session_id: .session_id.S,
                conversation: [.conversation.L[]?.M | {
                    role: .role.S,
                    content: (.content.S | if length > 100 then .[0:100] + "..." else . end),
                    timestamp: .ts.N
                }]
            }'
        fi
    else
        echo "No sessions found in DynamoDB."
    fi

    echo ""
fi

# ============================================
# S3 Section
# ============================================
if [ "$SHOW_S3" = true ]; then
    echo "==========================================="
    echo "  S3 Bucket: $S3_BUCKET"
    echo "==========================================="
    echo ""

    # List all objects
    OBJECTS=$(aws s3api list-objects-v2 \
        --bucket "$S3_BUCKET" \
        --query "Contents[*].{Key:Key,Size:Size,LastModified:LastModified}" \
        --output json 2>/dev/null)

    if [ "$OBJECTS" = "null" ] || [ -z "$OBJECTS" ] || [ "$OBJECTS" = "[]" ]; then
        echo "No archived sessions found in S3."
    else
        OBJECT_COUNT=$(echo "$OBJECTS" | jq 'length')
        echo "Total archived files: $OBJECT_COUNT"
        echo ""

        echo "Archives:"
        echo "---------"
        echo "$OBJECTS" | jq -r '.[] | [.Key, (.Size | tostring) + " bytes", .LastModified] | @tsv' | column -t -N "PATH,SIZE,LAST_MODIFIED"

        if [ "$VERBOSE" = true ]; then
            echo ""
            echo "Archive contents:"
            echo "-----------------"

            # Download and display each archive
            for KEY in $(echo "$OBJECTS" | jq -r '.[].Key'); do
                echo ""
                echo "File: $KEY"
                echo "---"
                aws s3 cp "s3://$S3_BUCKET/$KEY" - 2>/dev/null | jq '.' 2>/dev/null || echo "(Could not parse as JSON)"
            done
        fi
    fi

    echo ""
fi

echo "==========================================="
echo "  Done"
echo "==========================================="
echo ""
echo "Tips:"
echo "  - Use -v or --verbose to see full content"
echo "  - Use 'dynamodb' or 's3' to filter output"
echo ""
