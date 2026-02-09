#!/bin/bash
set -euo pipefail

###############################################
# Ollama EC2 Lifecycle Management
# Usage: ./scripts/manage-ollama.sh [start|stop|status|ssh]
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEY_NAME="ollama-key"
KEY_PATH="$HOME/.ssh/${KEY_NAME}.pem"

ensure_ssh_key() {
    if [ -f "$KEY_PATH" ]; then
        return 0
    fi
    echo "SSH key not found at $KEY_PATH"
    echo "Creating EC2 key pair '$KEY_NAME'..."
    if aws ec2 describe-key-pairs --key-names "$KEY_NAME" > /dev/null 2>&1; then
        echo "Key pair '$KEY_NAME' exists in AWS but private key is missing locally."
        echo "Deleting old key pair and creating a new one..."
        aws ec2 delete-key-pair --key-name "$KEY_NAME" > /dev/null
    fi
    mkdir -p "$HOME/.ssh"
    aws ec2 create-key-pair --key-name "$KEY_NAME" \
        --query 'KeyMaterial' --output text > "$KEY_PATH"
    chmod 600 "$KEY_PATH"
    echo "Key saved to $KEY_PATH"
    echo ""
    echo "NOTE: Instance must use this key pair. If it doesn't, run:"
    echo "  terraform apply -var 'ec2_key_pair_name=$KEY_NAME'"
    echo ""
}

get_instance_id() {
    cd "$PROJECT_DIR"
    terraform output -raw ollama_instance_id 2>/dev/null
}

get_public_ip() {
    cd "$PROJECT_DIR"
    terraform output -raw ollama_public_ip 2>/dev/null
}

get_api_key() {
    cd "$PROJECT_DIR"
    terraform show -json 2>/dev/null | python3 -c "
import sys, json
state = json.load(sys.stdin)
for r in state.get('values',{}).get('root_module',{}).get('resources',[]):
    if r.get('type') == 'random_password':
        print(r['values']['result'])
        break
" 2>/dev/null
}

cmd_start() {
    local instance_id
    instance_id=$(get_instance_id)
    echo "Starting Ollama instance: $instance_id"
    aws ec2 start-instances --instance-ids "$instance_id" > /dev/null
    echo "Waiting for instance to be running..."
    aws ec2 wait instance-running --instance-ids "$instance_id"

    local ip
    ip=$(get_public_ip)
    echo "Instance running at $ip"
    echo "Waiting for Ollama API (may take 1-2 minutes on first boot)..."

    local api_key
    api_key=$(get_api_key)
    for i in $(seq 1 60); do
        if curl -sf -H "X-API-Key: $api_key" "http://$ip:11434/api/tags" > /dev/null 2>&1; then
            echo "Ollama API is ready!"
            echo "Endpoint: http://$ip:11434"
            return 0
        fi
        sleep 5
    done
    echo "WARNING: Ollama API not responding after 5 minutes."
    echo "Check setup logs: ssh ec2-user@$ip 'cat /var/log/ollama-setup.log'"
}

cmd_stop() {
    local instance_id
    instance_id=$(get_instance_id)
    echo "Stopping Ollama instance: $instance_id"
    echo "(Models will sync to S3 on shutdown)"
    aws ec2 stop-instances --instance-ids "$instance_id" > /dev/null
    echo "Waiting for instance to stop..."
    aws ec2 wait instance-stopped --instance-ids "$instance_id"
    echo "Instance stopped. No compute charges while stopped."
}

cmd_status() {
    local instance_id ip state
    instance_id=$(get_instance_id)
    ip=$(get_public_ip)

    state=$(aws ec2 describe-instances --instance-ids "$instance_id" \
        --query 'Reservations[0].Instances[0].State.Name' --output text)

    echo "Instance:  $instance_id"
    echo "State:     $state"
    echo "Elastic IP: $ip"

    if [ "$state" = "running" ]; then
        local api_key
        api_key=$(get_api_key)
        echo "Ollama URL: http://$ip:11434"
        if curl -sf -H "X-API-Key: $api_key" "http://$ip:11434/api/tags" > /dev/null 2>&1; then
            echo "Ollama API: RESPONDING (authenticated)"
            echo ""
            echo "Models:"
            curl -s -H "X-API-Key: $api_key" "http://$ip:11434/api/tags" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for m in data.get('models', []):
    size_gb = m.get('size', 0) / 1e9
    print(f\"  - {m['name']} ({size_gb:.1f} GB)\")
" 2>/dev/null || echo "  (unable to parse)"
        else
            echo "Ollama API: NOT RESPONDING (may still be starting)"
        fi
    fi
}

cmd_ssh() {
    ensure_ssh_key
    local ip
    ip=$(get_public_ip)
    echo "Connecting to ec2-user@$ip..."
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no "ec2-user@$ip"
}

case "${1:-help}" in
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    ssh)    cmd_ssh ;;
    *)
        echo "Usage: $0 {start|stop|status|ssh}"
        echo ""
        echo "  start   - Start the Ollama EC2 instance"
        echo "  stop    - Stop the instance (syncs models to S3)"
        echo "  status  - Show instance state and Ollama API health"
        echo "  ssh     - SSH into the instance"
        exit 1
        ;;
esac
