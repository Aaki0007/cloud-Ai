#!/bin/bash
set -euo pipefail
exec > /var/log/ollama-setup.log 2>&1

echo "=== Ollama Setup Starting ==="

# Install dependencies (AL2023 uses dnf)
dnf install -y zstd nginx

# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Configure Ollama to listen on localhost only (nginx handles external access)
mkdir -p /etc/systemd/system/ollama.service.d
cat > /etc/systemd/system/ollama.service.d/override.conf << 'CONF'
[Service]
Environment="OLLAMA_HOST=127.0.0.1:11435"
Environment="OLLAMA_NOHISTORY=true"
CONF

systemctl daemon-reload
systemctl enable ollama
systemctl start ollama

# Wait for Ollama to be ready
echo "Waiting for Ollama to start..."
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:11435/api/tags > /dev/null 2>&1; then
    echo "Ollama is ready"
    break
  fi
  sleep 2
done

# Configure nginx as reverse proxy with API key authentication
API_KEY="${api_key}"

cat > /etc/nginx/conf.d/ollama.conf << NGINX
map \$http_x_api_key \$api_key_valid {
    "$API_KEY" 1;
    default    0;
}

server {
    listen 11434;

    location / {
        if (\$api_key_valid = 0) {
            return 401 '{"error": "unauthorized"}';
        }

        proxy_pass http://127.0.0.1:11435;
        proxy_set_header Host localhost:11435;
        proxy_read_timeout 120s;
        proxy_send_timeout 120s;
    }
}
NGINX

systemctl enable nginx
systemctl start nginx

echo "Nginx reverse proxy configured on port 11434 with API key auth"

# Try to restore models from S3
S3_BUCKET="${s3_bucket}"
S3_PREFIX="${s3_prefix}"

if [ -n "$S3_BUCKET" ]; then
  echo "Restoring models from s3://$S3_BUCKET/$S3_PREFIX/"
  aws s3 sync "s3://$S3_BUCKET/$S3_PREFIX/" /usr/share/ollama/.ollama/models/ 2>/dev/null || true
  systemctl restart ollama
  sleep 5
fi

# Pull model if not already present
export HOME="/root"
if ! ollama list 2>/dev/null | grep -q "${ollama_model}"; then
  echo "Pulling model: ${ollama_model}"
  OLLAMA_HOST="127.0.0.1:11435" ollama pull ${ollama_model}
fi

# Sync models to S3 after pull
if [ -n "$S3_BUCKET" ]; then
  echo "Syncing models to S3..."
  aws s3 sync /usr/share/ollama/.ollama/models/ "s3://$S3_BUCKET/$S3_PREFIX/" 2>/dev/null || true
fi

# Shutdown hook: sync models to S3 before stopping
cat > /usr/local/bin/ollama-s3-sync.sh << 'SHUTDOWN'
#!/bin/bash
if [ -n "${s3_bucket}" ]; then
  aws s3 sync /usr/share/ollama/.ollama/models/ "s3://${s3_bucket}/${s3_prefix}/" 2>/dev/null || true
fi
SHUTDOWN
chmod +x /usr/local/bin/ollama-s3-sync.sh

cat > /etc/systemd/system/ollama-s3-sync.service << 'SVC'
[Unit]
Description=Sync Ollama models to S3 on shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target
After=ollama.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ollama-s3-sync.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable ollama-s3-sync.service

echo "=== Ollama Setup Complete ==="
