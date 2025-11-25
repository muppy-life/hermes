#!/bin/bash
set -e

# Update system
dnf update -y

# Install Docker
dnf install -y docker
systemctl start docker
systemctl enable docker

# Install Docker Compose
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Create app directory
mkdir -p /opt/hermes
cd /opt/hermes

# Create environment file
cat > /opt/hermes/.env << EOF
DATABASE_URL=${database_url}
SECRET_KEY_BASE=${secret_key_base}
ANTHROPIC_API_KEY=${anthropic_api_key}
PHX_HOST=${phx_host}
PORT=4000
MIX_ENV=prod
EOF

# Create docker-compose.yml (will be updated by CD pipeline)
cat > /opt/hermes/docker-compose.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  app:
    image: hermes:latest
    env_file: .env
    ports:
      - "4000:4000"
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
COMPOSE_EOF

# Create systemd service for the app
cat > /etc/systemd/system/hermes.service << 'SERVICE_EOF'
[Unit]
Description=Hermes Application
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/hermes
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
Restart=on-failure

[Install]
WantedBy=multi-user.target
SERVICE_EOF

# Enable and start the service (will fail initially until image is deployed)
systemctl enable hermes.service

# Install CloudWatch agent for logging (detect architecture)
ARCH=$(uname -m)
if [ "$ARCH" = "aarch64" ]; then
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm
else
  wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm
fi
rpm -U ./amazon-cloudwatch-agent.rpm

# Configure CloudWatch agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/config.json << 'CW_EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/hermes/logs/*.log",
            "log_group_name": "/aws/ec2/${environment}/hermes",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CW_EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -s \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/config.json

echo "EC2 instance setup complete"
