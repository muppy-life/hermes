#!/bin/bash
set -e

# ECS-optimized AMI already has Docker, CloudWatch agent, and SSM agent installed
# Just need to configure the application

# Stop ECS agent since we're not using ECS
systemctl stop ecs || true
systemctl disable ecs || true

# Ensure Docker is running
systemctl start docker
systemctl enable docker

# Install AWS CLI (not included in ECS-optimized AMI by default)
yum install -y awscli unzip

# Create app directory
mkdir -p /opt/hermes
cd /opt/hermes

# Create environment file
cat > /opt/hermes/.env << EOF
DATABASE_URL=${database_url}
SECRET_KEY_BASE=${secret_key_base}
ANTHROPIC_API_KEY=${anthropic_api_key}
PHX_HOST=${phx_host}
PHX_SERVER=true
PORT=4000
MIX_ENV=prod
EOF

# Configure CloudWatch agent for Docker logs
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CW_EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/lib/docker/containers/*/*.log",
            "log_group_name": "/aws/ec2/${environment}/hermes",
            "log_stream_name": "{instance_id}/docker",
            "timezone": "UTC"
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "Hermes/${environment}",
    "metrics_collected": {
      "cpu": {
        "measurement": ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60
      },
      "mem": {
        "measurement": ["mem_used_percent"],
        "metrics_collection_interval": 60
      },
      "disk": {
        "measurement": ["disk_used_percent"],
        "metrics_collection_interval": 60,
        "resources": ["/"]
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
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json || true

echo "EC2 instance setup complete"
