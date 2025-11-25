# AWS Setup Quick Start

This guide will help you set up AWS prerequisites for deploying Hermes to production.

## Prerequisites

1. **AWS Account** with admin access
2. **AWS CLI v2** installed
3. **Terraform** >= 1.0 installed

## Step 1: Install AWS CLI (if not already installed)

### macOS
```bash
brew install awscli
```

### Linux
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

### Windows
Download and install: https://awscli.amazonaws.com/AWSCLIV2.msi

## Step 2: Configure AWS CLI

```bash
aws configure
```

You'll need:
- **AWS Access Key ID**: Get from AWS Console → IAM → Users → Security credentials
- **AWS Secret Access Key**: Shown when creating access key
- **Default region**: `eu-south-2` (Madrid)
- **Default output format**: `json`

## Step 3: Run Automated Setup Script

We've created a comprehensive setup script that will:
1. Create S3 bucket for Terraform state
2. Create DynamoDB table for Terraform locks
3. Create EC2 key pair for SSH access
4. Request ACM certificate for HTTPS
5. Set up GitHub OIDC provider for CI/CD

```bash
./scripts/setup_aws_prerequisites.sh
```

The script will:
- Check if AWS CLI is installed and configured
- Create all necessary AWS resources
- Generate `terraform/terraform.tfvars` with your configuration
- Provide GitHub secrets that need to be configured
- Give you next steps

## Step 4: Manual Steps After Running Script

### 1. Validate ACM Certificate

If you provided a domain name, you need to validate the certificate:

```bash
# Get certificate validation details
aws acm describe-certificate \
  --certificate-arn YOUR_CERTIFICATE_ARN \
  --region eu-south-2 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

Add the DNS record to your domain's DNS configuration.

### 2. Generate Phoenix Secret Key

```bash
mix phx.gen.secret
```

Copy this value - you'll need it for GitHub secrets and Terraform.

### 3. Configure GitHub Secrets

Go to your GitHub repository: Settings → Secrets and variables → Actions

Add these secrets:
- `AWS_ROLE_ARN` - IAM role ARN (provided by setup script)
- `DATABASE_URL` - Your external database URL (format: `ecto://user:pass@host:5432/hermes_production`)
- `SECRET_KEY_BASE` - Output from `mix phx.gen.secret`
- `ANTHROPIC_API_KEY` - Your Claude API key
- `ACM_CERTIFICATE_ARN` - Certificate ARN (provided by setup script)
- `EC2_KEY_NAME` - Key pair name (default: `hermes-production`)
- `EC2_SSH_PRIVATE_KEY` - Contents of `~/.ssh/hermes-production.pem`

### 4. Review terraform.tfvars

The setup script generated `terraform/terraform.tfvars`. Review and update if needed:

```bash
cat terraform/terraform.tfvars
```

### 5. Initialize Terraform

```bash
cd terraform
terraform init
```

This will configure Terraform to use the S3 backend for state management.

## Step 5: Deploy Infrastructure

### Option A: Manual Deployment

```bash
cd terraform

# Preview changes
terraform plan \
  -var="database_url=$DATABASE_URL" \
  -var="secret_key_base=$SECRET_KEY_BASE" \
  -var="anthropic_api_key=$ANTHROPIC_API_KEY"

# Apply changes
terraform apply \
  -var="database_url=$DATABASE_URL" \
  -var="secret_key_base=$SECRET_KEY_BASE" \
  -var="anthropic_api_key=$ANTHROPIC_API_KEY"
```

### Option B: GitHub Actions Deployment

Once GitHub secrets are configured:

```bash
# Push to main branch
git add .
git commit -m "Add AWS infrastructure"
git push origin main
```

The CD pipeline will automatically deploy.

## Step 6: Configure DNS

After infrastructure is deployed, point your domain to the ALB:

```bash
# Get ALB DNS name
cd terraform
terraform output alb_dns_name

# Add CNAME or Alias record to your DNS
# Example: hermes.yourdomain.com → your-alb-dns-name.eu-south-2.elb.amazonaws.com
```

## Verification

After deployment, verify everything is working:

```bash
# Check application health
curl https://your-domain.com/health

# Check ALB target health
aws elbv2 describe-target-health \
  --target-group-arn $(cd terraform && terraform output -raw alb_target_group_arn) \
  --region eu-south-2
```

## Troubleshooting

### AWS CLI not configured
```bash
aws configure
```

### Permission denied on setup script
```bash
chmod +x scripts/setup_aws_prerequisites.sh
```

### Terraform backend not initialized
```bash
cd terraform
terraform init -reconfigure
```

### Certificate validation pending
Check your DNS provider has the validation records. It can take up to 30 minutes.

### GitHub Actions failing
1. Verify all GitHub secrets are set correctly
2. Check the workflow logs in GitHub Actions tab
3. Ensure IAM role has correct permissions

## Cost Estimate

Your infrastructure will cost approximately **$86-95/month**:
- EC2 (2x t4g.small): ~$24/month
- ALB: ~$23/month
- NAT Gateway: ~$32/month
- Data Transfer: ~$5-10/month
- CloudWatch: ~$2-5/month
- S3 + DynamoDB: <$1/month

External database costs are separate.

## Security Notes

- Keep your AWS credentials secure
- Never commit `terraform.tfvars` with secrets
- Use environment variables or AWS Secrets Manager in production
- The EC2 key pair private key is saved to `~/.ssh/hermes-production.pem` - keep it safe
- Consider using AWS Systems Manager Session Manager instead of SSH

## Next Steps

After successful deployment:
1. Set up monitoring and alerts in CloudWatch
2. Configure backup strategy for database
3. Set up log aggregation
4. Configure autoscaling if needed
5. Review security groups and IAM policies

For detailed documentation, see:
- `DEPLOYMENT.md` - Complete deployment guide
- `terraform/README.md` - Infrastructure details
