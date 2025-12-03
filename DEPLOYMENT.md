# Hermes Deployment Guide

## Overview

Hermes is deployed to AWS (Madrid region - eu-south-2) using:
- **Infrastructure**: Terraform for IaC
- **Compute**: EC2 instances with Docker
- **Load Balancing**: Application Load Balancer with HTTPS
- **Database**: External managed PostgreSQL (outside AWS)
- **CI/CD**: Manual deployment or GitHub Actions
- **State**: Local Terraform state (or git-based)

## Architecture

```
Internet
    ↓
[Route53 DNS]
    ↓
[Application Load Balancer] (HTTPS)
    ↓
[EC2 Instances] (private subnets)
    ↓
[External PostgreSQL Database]
```

## Prerequisites Checklist

### AWS Resources
- [ ] AWS Account with admin access
- [ ] AWS CLI configured locally
- [ ] S3 bucket for Terraform state
- [ ] DynamoDB table for Terraform locks
- [ ] ACM Certificate for your domain (in eu-south-2)
- [ ] EC2 Key Pair for SSH access

### External Services
- [ ] Managed PostgreSQL database (external to AWS)
- [ ] Database connection URL in ecto format
- [ ] Domain name and DNS access

### Secrets
- [ ] `SECRET_KEY_BASE` - Phoenix secret key
- [ ] `ANTHROPIC_API_KEY` - Claude API key
- [ ] `DATABASE_URL` - Database connection string
- [ ] EC2 SSH private key

### Local Tools
- [ ] Terraform >= 1.0
- [ ] AWS CLI v2
- [ ] Docker (for local testing)
- [ ] Git

## Step-by-Step Deployment

### 1. Prepare AWS Infrastructure

#### Create Terraform State Backend

First, create S3 and DynamoDB for Terraform state management:

```bash
# Create S3 bucket for Terraform state
aws s3api create-bucket \
  --bucket hermes-terraform-state \
  --region eu-south-2 \
  --create-bucket-configuration LocationConstraint=eu-south-2

# Enable versioning
aws s3api put-bucket-versioning \
  --bucket hermes-terraform-state \
  --versioning-configuration Status=Enabled

# Enable encryption
aws s3api put-bucket-encryption \
  --bucket hermes-terraform-state \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      }
    }]
  }'

# Block public access
aws s3api put-public-access-block \
  --bucket hermes-terraform-state \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name hermes-terraform-locks \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-south-2
```

#### Create SSL Certificate

```bash
# Request ACM certificate
aws acm request-certificate \
  --domain-name hermes.yourdomain.com \
  --subject-alternative-names '*.hermes.yourdomain.com' \
  --validation-method DNS \
  --region eu-south-2

# Note the CertificateArn from output
# Add the DNS validation records to your domain
# Wait for certificate validation to complete
```

#### Create EC2 Key Pair

```bash
# Create key pair
aws ec2 create-key-pair \
  --key-name hermes-production \
  --region eu-south-2 \
  --query 'KeyMaterial' \
  --output text > ~/.ssh/hermes-production.pem

# Set proper permissions
chmod 400 ~/.ssh/hermes-production.pem
```


### 2. Configure GitHub Secrets

Add these secrets to your GitHub repository (Settings → Secrets and variables → Actions):

```
AWS_ROLE_ARN              - IAM role ARN for GitHub Actions
DATABASE_URL              - ecto://user:pass@host:5432/hermes_production
SECRET_KEY_BASE           - mix phx.gen.secret output
ANTHROPIC_API_KEY         - Your Claude API key
ACM_CERTIFICATE_ARN       - ARN from ACM certificate
EC2_KEY_NAME              - hermes-production
EC2_SSH_PRIVATE_KEY       - Contents of hermes-production.pem
```

#### Create GitHub OIDC Provider in AWS

```bash
# Create OIDC provider for GitHub Actions
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Create IAM role for GitHub Actions
cat > github-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/hermes:*"
        }
      }
    }
  ]
}
EOF

aws iam create-role \
  --role-name GitHubActionsDeployRole \
  --assume-role-policy-document file://github-trust-policy.json

# Attach necessary policies
aws iam attach-role-policy \
  --role-name GitHubActionsDeployRole \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess
```

### 3. Configure Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
aws_region         = "eu-south-2"
environment        = "production"

vpc_cidr           = "10.0.0.0/16"
availability_zones = ["eu-south-2a", "eu-south-2b", "eu-south-2c"]

instance_type      = "t3.small"
instance_count     = 2
key_name           = "hermes-production"

certificate_arn    = "arn:aws:acm:eu-south-2:ACCOUNT_ID:certificate/CERT_ID"
```

**Note**: Do NOT add secrets to this file. They will be passed via GitHub Actions.

### 4. Deploy Infrastructure Manually (First Time)

```bash
# Initialize Terraform
cd terraform
terraform init

# Create execution plan
terraform plan \
  -var="database_url=ecto://user:pass@host:5432/hermes_production" \
  -var="secret_key_base=YOUR_SECRET_KEY" \
  -var="anthropic_api_key=YOUR_API_KEY"

# Apply infrastructure
terraform apply \
  -var="database_url=ecto://user:pass@host:5432/hermes_production" \
  -var="secret_key_base=YOUR_SECRET_KEY" \
  -var="anthropic_api_key=YOUR_API_KEY"

# Note the outputs
terraform output
```

### 5. Configure DNS

```bash
# Get ALB DNS name
ALB_DNS=$(terraform output -raw alb_dns_name)

# Add CNAME or A record to your DNS provider
# Example: hermes.yourdomain.com → [ALB_DNS]
```

### 6. Deploy Application via GitHub Actions

#### Option A: Push to Main Branch

```bash
git add .
git commit -m "Add deployment infrastructure"
git push origin main
```

The CD pipeline will automatically:
1. Build Docker image
2. Push to ECR
3. Deploy infrastructure with Terraform
4. Deploy application to EC2 instances

#### Option B: Manual Trigger

Go to GitHub Actions → CD workflow → Run workflow

### 7. Verify Deployment

```bash
# Check application health
curl https://hermes.yourdomain.com/health

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(terraform output -raw alb_target_group_arn)

# SSH to instance (if needed)
ssh -i ~/.ssh/hermes-production.pem ec2-user@PRIVATE_IP

# View application logs
ssh -i ~/.ssh/hermes-production.pem ec2-user@PRIVATE_IP \
  "cd /opt/hermes && docker-compose logs -f"
```

## Continuous Deployment Workflow

### Automatic Deployment

Every push to `main` branch triggers:
1. **CI Pipeline** (from ci.yml)
   - Run tests
   - Check code formatting
   - Build assets
   - Run security checks

2. **CD Pipeline** (from cd.yml) - Rolling Deployment Strategy
   - Build Docker image (ARM64 for Graviton instances)
   - Push to ECR
   - Update infrastructure with Terraform
   - Upload static assets to S3/CloudFront
   - Run database migrations
   - Rolling deployment to instances:
     - For each instance: deregister from ALB → deploy → health check → re-register
     - Ensures zero-downtime with single instance (brief interruption) or multiple instances
   - Health check verification

### Manual Deployment

Use GitHub Actions workflow dispatch to deploy specific commits or branches.

### Rolling Deployment Benefits

- **Cost efficient**: Only need 1 instance running (vs 2 for blue-green)
- **Simple architecture**: Single target group, no traffic switching
- **Zero-downtime** (with 2+ instances): One instance always serves traffic
- **Automatic recovery**: Failed instances are re-registered for recovery

## Database Migrations

Migrations are automatically run during deployment via the CD pipeline:

```bash
docker-compose run --rm app /app/bin/hermes eval "Hermes.Release.migrate"
```

To run manually:

```bash
ssh -i ~/.ssh/hermes-production.pem ec2-user@PRIVATE_IP
cd /opt/hermes
docker-compose run --rm app /app/bin/hermes eval "Hermes.Release.migrate"
```

## Rollback Procedure

### Rollback via Git Revert (Recommended)

```bash
# Revert to previous commit
git revert HEAD
git push origin main

# CD pipeline will deploy the reverted version using rolling deployment
```

### Rollback via Manual Re-deploy of Previous Image

```bash
# Get previous image tags from ECR
aws ecr describe-images --repository-name hermes \
  --query 'imageDetails[*].imageTags' \
  --region eu-south-2

# Manually trigger workflow with specific commit SHA
# Go to GitHub Actions → CD workflow → Run workflow
# Or redeploy via SSM command to instances
```

### Emergency Rollback via SSM

```bash
# Get instance IDs
INSTANCE_IDS=$(terraform output -json instance_ids | jq -r '.[]')

# Deploy previous image version to each instance
for INSTANCE_ID in $INSTANCE_IDS; do
  aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters commands="[
      \"docker stop hermes || true\",
      \"docker rm hermes || true\",
      \"docker run -d --name hermes --restart unless-stopped -p 4000:4000 --env-file /opt/hermes/.env ACCOUNT_ID.dkr.ecr.eu-south-2.amazonaws.com/hermes:PREVIOUS_SHA\"
    ]"
done
```

## Monitoring

### CloudWatch Logs

```bash
# View application logs
aws logs tail /aws/ec2/production/hermes --follow --region eu-south-2
```

### Instance Health

```bash
# Check EC2 instance status
aws ec2 describe-instance-status \
  --instance-ids $(terraform output -json ec2_instance_ids | jq -r '.[]') \
  --region eu-south-2
```

### Application Metrics

Visit AWS CloudWatch Console:
- EC2 instance CPU/Memory
- ALB metrics (request count, latency, target health)
- Application logs

## Scaling

### Vertical Scaling (Larger Instances)

1. Update `instance_type` in `terraform.tfvars`
2. Run `terraform apply`
3. Terraform will replace instances with new type

### Horizontal Scaling (More Instances)

1. Update `instance_count` in `terraform.tfvars`
2. Run `terraform apply`
3. New instances will be added to ALB automatically

## Troubleshooting

### Application Won't Start

```bash
# SSH to instance
ssh -i ~/.ssh/hermes-production.pem ec2-user@PRIVATE_IP

# Check Docker status
cd /opt/hermes
docker-compose ps
docker-compose logs

# Check systemd service
sudo systemctl status hermes
sudo journalctl -u hermes -f

# Verify environment variables
cat /opt/hermes/.env
```

### Database Connection Issues

```bash
# Test database connectivity from EC2
docker exec -it hermes_app_1 sh
wget -O - $DATABASE_URL  # Should fail but test network

# Check if external database allows AWS IPs
```

### Health Checks Failing

```bash
# Check health endpoint locally on instance
curl http://localhost:4000/health

# Check security group rules
aws ec2 describe-security-groups \
  --filters Name=group-name,Values=production-app-sg \
  --region eu-south-2
```

### SSL/Certificate Issues

```bash
# Verify certificate is valid
aws acm describe-certificate \
  --certificate-arn YOUR_CERT_ARN \
  --region eu-south-2

# Check ALB listener configuration
aws elbv2 describe-listeners \
  --load-balancer-arn $(terraform output -raw alb_arn)
```

## Maintenance

### Update Application Code

1. Commit and push changes to `main` branch
2. CD pipeline automatically deploys
3. Zero-downtime deployment via ALB health checks

### Update Infrastructure

1. Modify Terraform files
2. Commit and push
3. CD pipeline applies Terraform changes

### Update Dependencies

```bash
# Update mix dependencies
mix deps.update --all

# Rebuild Docker image
git commit -am "Update dependencies"
git push origin main
```

## Security Best Practices

1. **Rotate Secrets** regularly (SECRET_KEY_BASE, database passwords)
2. **Update AMIs** - Periodically update to latest Amazon Linux 2023
3. **Security Groups** - Keep as restrictive as possible
4. **Database SSL** - Always use SSL for database connections
5. **VPC Flow Logs** - Enable for network traffic analysis
6. **CloudTrail** - Enable for API audit logging
7. **WAF** - Consider adding AWS WAF to ALB for additional protection

## Cost Estimation

### Optimized Configuration (Current Setup - Rolling Deployment)

Monthly costs in Madrid region (eu-south-2):
- **EC2 (2x t4g.small ARM)**: ~$24/month ($0.0168/hour × 2 × 730 hours)
- **Application Load Balancer**: ~$23/month ($16 fixed + ~$7 LCU charges)
- **NAT Gateway (1x)**: ~$32/month ($0.045/hour × 730 hours)
- **Data Transfer**: ~$5-10/month (first 100GB free, then $0.09/GB)
- **CloudWatch Logs**: ~$2-5/month
- **S3 + DynamoDB (Terraform state)**: <$1/month (minimal usage)

**Total: ~$86-95/month** (excluding external database)

Note: With rolling deployments you still get zero-downtime deploys with 2 instances, but you no longer need 4 instances (2 blue + 2 green) like blue-green deployment required. This saves ~$24/month compared to blue-green.

### Cost Comparison vs Alternatives

| Service | Monthly Cost | Notes |
|---------|--------------|-------|
| **AWS Madrid (Current)** | **$86-94** | **Lowest latency for Spain users (~1-5ms)** |
| Fly.io Frankfurt | $12-20 | Higher latency (~20-30ms to Madrid) |
| Fly.io Paris | $12-20 | Higher latency (~15-25ms to Madrid) |

**Value proposition**: Extra $66-74/month for **15-25ms better latency** - worth it for interactive applications with Spain-based users.

### Further Cost Optimization Options

1. **Use Reserved Instances** (1-year commitment):
   - Save 30-40% on EC2: ~$24/month → ~$16/month
   - **New total: ~$78-86/month**

2. **Use Compute Savings Plans** (flexible):
   - Save 20-30% on EC2: ~$24/month → ~$18/month
   - Can change instance types/sizes
   - **New total: ~$80-88/month**

3. **Start with 1 instance** (for low traffic):
   - EC2: ~$24 → ~$12/month
   - Risk: No redundancy
   - **New total: ~$74-82/month**

4. **Use t4g.micro** initially (512MB RAM):
   - EC2: ~$24 → ~$12/month (2x t4g.micro)
   - Test if this is sufficient for your load
   - **New total: ~$74-82/month**

### Why AWS Madrid vs Fly.io?

✅ **AWS Madrid is the right choice because:**
- Fly.io has NO Madrid/Spain region for VMs
- Closest Fly.io regions: Frankfurt (~20-30ms), Paris (~15-25ms)
- For Spain-based users, **latency matters**
- 15-25ms better response time = better UX
- Extra ~$70-80/month is reasonable for local presence

### Architecture Cost Breakdown

The largest costs are:
1. **NAT Gateway (36%)**: $32/month
   - Required for private instances to reach internet
   - Already optimized (1 gateway instead of 3)
   - Alternative: NAT Instance (~$3/month) but requires maintenance

2. **ALB (26%)**: $23/month
   - Provides HTTPS termination, health checks, zero-downtime deploys
   - No good alternative for production

3. **EC2 (27%)**: $24/month
   - Already using ARM (Graviton2) for 20% savings
   - Can reduce with Reserved Instances

4. **Data Transfer + Other (11%)**: ~$10/month
   - Hard to reduce, depends on traffic

## Support and Contacts

- **Documentation**: See `/terraform/README.md` for detailed infrastructure docs
- **CI/CD Pipeline**: `.github/workflows/ci.yml` and `.github/workflows/cd.yml`
- **Infrastructure Code**: `terraform/` directory
