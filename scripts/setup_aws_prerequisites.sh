#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
AWS_REGION="eu-south-2"
# Get account ID early for unique bucket naming
ACCOUNT_ID_FOR_BUCKET=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")
S3_BUCKET="hermes-terraform-state-${ACCOUNT_ID_FOR_BUCKET}"
DYNAMODB_TABLE="hermes-terraform-locks"
KEY_NAME="hermes-production"
DOMAIN_NAME="${DOMAIN_NAME:-hermes.yourdomain.com}"

echo -e "${GREEN}=== Hermes AWS Prerequisites Setup ===${NC}\n"

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI first:"
    echo "  macOS: brew install awscli"
    echo "  Linux: curl 'https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip' -o 'awscliv2.zip' && unzip awscliv2.zip && sudo ./aws/install"
    echo "  Windows: https://awscli.amazonaws.com/AWSCLIV2.msi"
    exit 1
fi

echo -e "${GREEN}✓ AWS CLI is installed${NC}"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not configured${NC}"
    echo "Please configure AWS CLI first:"
    echo "  aws configure"
    echo ""
    echo "You'll need:"
    echo "  - AWS Access Key ID"
    echo "  - AWS Secret Access Key"
    echo "  - Default region: eu-south-2"
    exit 1
fi

echo -e "${GREEN}✓ AWS CLI is configured${NC}"

# Get account info
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
CURRENT_USER=$(aws sts get-caller-identity --query Arn --output text)
echo -e "Account ID: ${YELLOW}${ACCOUNT_ID}${NC}"
echo -e "Current user: ${YELLOW}${CURRENT_USER}${NC}\n"

# Function to check if resource exists
resource_exists() {
    local resource_type=$1
    local resource_name=$2

    case $resource_type in
        "s3")
            aws s3api head-bucket --bucket "$resource_name" --region "$AWS_REGION" 2>/dev/null
            ;;
        "dynamodb")
            aws dynamodb describe-table --table-name "$resource_name" --region "$AWS_REGION" 2>/dev/null
            ;;
        "keypair")
            aws ec2 describe-key-pairs --key-names "$resource_name" --region "$AWS_REGION" 2>/dev/null
            ;;
    esac
}

# 1. Create S3 bucket for Terraform state
echo -e "${YELLOW}[1/5] Setting up S3 bucket for Terraform state...${NC}"
if resource_exists "s3" "$S3_BUCKET"; then
    echo -e "${GREEN}✓ S3 bucket already exists: $S3_BUCKET${NC}"
else
    echo "Creating S3 bucket..."
    aws s3api create-bucket \
        --bucket "$S3_BUCKET" \
        --region "$AWS_REGION" \
        --create-bucket-configuration LocationConstraint="$AWS_REGION"

    echo "Enabling versioning..."
    aws s3api put-bucket-versioning \
        --bucket "$S3_BUCKET" \
        --versioning-configuration Status=Enabled \
        --region "$AWS_REGION"

    echo "Enabling encryption..."
    aws s3api put-bucket-encryption \
        --bucket "$S3_BUCKET" \
        --server-side-encryption-configuration '{
            "Rules": [{
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }]
        }' \
        --region "$AWS_REGION"

    echo "Blocking public access..."
    aws s3api put-public-access-block \
        --bucket "$S3_BUCKET" \
        --public-access-block-configuration \
            "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region "$AWS_REGION"

    echo -e "${GREEN}✓ S3 bucket created successfully${NC}"
fi

# 2. Create DynamoDB table for Terraform locks
echo -e "\n${YELLOW}[2/5] Setting up DynamoDB table for Terraform locks...${NC}"
if resource_exists "dynamodb" "$DYNAMODB_TABLE"; then
    echo -e "${GREEN}✓ DynamoDB table already exists: $DYNAMODB_TABLE${NC}"
else
    echo "Creating DynamoDB table..."
    aws dynamodb create-table \
        --table-name "$DYNAMODB_TABLE" \
        --attribute-definitions AttributeName=LockID,AttributeType=S \
        --key-schema AttributeName=LockID,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --region "$AWS_REGION"

    echo "Waiting for table to be active..."
    aws dynamodb wait table-exists \
        --table-name "$DYNAMODB_TABLE" \
        --region "$AWS_REGION"

    echo -e "${GREEN}✓ DynamoDB table created successfully${NC}"
fi

# 3. Create EC2 Key Pair
echo -e "\n${YELLOW}[3/5] Setting up EC2 key pair...${NC}"
if resource_exists "keypair" "$KEY_NAME"; then
    echo -e "${GREEN}✓ EC2 key pair already exists: $KEY_NAME${NC}"
    echo -e "${YELLOW}Note: If you don't have the private key file, you'll need to delete this key pair and create a new one${NC}"
else
    KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"

    echo "Creating EC2 key pair..."
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --region "$AWS_REGION" \
        --query 'KeyMaterial' \
        --output text > "$KEY_FILE"

    chmod 400 "$KEY_FILE"

    echo -e "${GREEN}✓ EC2 key pair created successfully${NC}"
    echo -e "Private key saved to: ${YELLOW}$KEY_FILE${NC}"
fi

# 4. Request ACM Certificate
echo -e "\n${YELLOW}[4/5] Setting up ACM certificate...${NC}"
echo -e "${YELLOW}Note: Certificate creation requires manual DNS validation${NC}"
read -p "Enter your domain name (e.g., hermes.yourdomain.com) or press Enter to skip: " INPUT_DOMAIN
DOMAIN_NAME="${INPUT_DOMAIN:-$DOMAIN_NAME}"

if [ "$DOMAIN_NAME" != "hermes.yourdomain.com" ]; then
    # Check if certificate already exists
    EXISTING_CERT=$(aws acm list-certificates \
        --region "$AWS_REGION" \
        --query "CertificateSummaryList[?DomainName=='$DOMAIN_NAME'].CertificateArn" \
        --output text)

    if [ -n "$EXISTING_CERT" ]; then
        echo -e "${GREEN}✓ Certificate already exists for $DOMAIN_NAME${NC}"
        echo -e "Certificate ARN: ${YELLOW}$EXISTING_CERT${NC}"
        CERTIFICATE_ARN="$EXISTING_CERT"
    else
        echo "Requesting ACM certificate for $DOMAIN_NAME..."
        CERTIFICATE_ARN=$(aws acm request-certificate \
            --domain-name "$DOMAIN_NAME" \
            --validation-method DNS \
            --region "$AWS_REGION" \
            --query 'CertificateArn' \
            --output text)

        echo -e "${GREEN}✓ Certificate requested successfully${NC}"
        echo -e "Certificate ARN: ${YELLOW}$CERTIFICATE_ARN${NC}"
        echo -e "\n${RED}IMPORTANT: You need to validate the certificate via DNS${NC}"
        echo "Run the following command to get validation details:"
        echo -e "${YELLOW}aws acm describe-certificate --certificate-arn $CERTIFICATE_ARN --region $AWS_REGION${NC}"
        echo "Add the provided DNS records to your domain's DNS configuration"
    fi
else
    echo -e "${YELLOW}Skipped - using placeholder domain${NC}"
    CERTIFICATE_ARN="arn:aws:acm:eu-south-2:ACCOUNT_ID:certificate/CERT_ID"
fi

# 5. Create GitHub OIDC Provider for GitHub Actions
echo -e "\n${YELLOW}[5/5] Setting up GitHub OIDC provider...${NC}"

# Check if OIDC provider exists
OIDC_PROVIDER=$(aws iam list-open-id-connect-providers \
    --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
    --output text)

if [ -n "$OIDC_PROVIDER" ]; then
    echo -e "${GREEN}✓ GitHub OIDC provider already exists${NC}"
else
    echo "Creating GitHub OIDC provider..."
    aws iam create-open-id-connect-provider \
        --url https://token.actions.githubusercontent.com \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

    echo -e "${GREEN}✓ GitHub OIDC provider created successfully${NC}"
fi

# Create IAM role for GitHub Actions
echo "Setting up IAM role for GitHub Actions..."
read -p "Enter your GitHub repository (format: username/repo-name): " GITHUB_REPO

if [ -n "$GITHUB_REPO" ]; then
    ROLE_NAME="GitHubActionsDeployRole"

    # Check if role exists
    if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
        echo -e "${GREEN}✓ IAM role already exists: $ROLE_NAME${NC}"
    else
        # Create trust policy
        cat > /tmp/github-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:${GITHUB_REPO}:*"
        }
      }
    }
  ]
}
EOF

        echo "Creating IAM role..."
        aws iam create-role \
            --role-name "$ROLE_NAME" \
            --assume-role-policy-document file:///tmp/github-trust-policy.json

        echo "Attaching policies..."
        aws iam attach-role-policy \
            --role-name "$ROLE_NAME" \
            --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

        rm /tmp/github-trust-policy.json

        echo -e "${GREEN}✓ IAM role created successfully${NC}"
    fi

    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"
    echo -e "Role ARN: ${YELLOW}$ROLE_ARN${NC}"
else
    echo -e "${YELLOW}Skipped - no GitHub repository provided${NC}"
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/GitHubActionsDeployRole"
fi

# Generate summary
echo -e "\n${GREEN}=== Setup Complete ===${NC}\n"
echo -e "${GREEN}Summary of created resources:${NC}"
echo "1. S3 Bucket: $S3_BUCKET"
echo "2. DynamoDB Table: $DYNAMODB_TABLE"
echo "3. EC2 Key Pair: $KEY_NAME"
if [ "$DOMAIN_NAME" != "hermes.yourdomain.com" ]; then
    echo "4. ACM Certificate: $CERTIFICATE_ARN"
fi
if [ -n "$GITHUB_REPO" ]; then
    echo "5. GitHub OIDC Provider: configured"
    echo "6. IAM Role: $ROLE_ARN"
fi

# Generate terraform.tfvars
echo -e "\n${YELLOW}Generating terraform.tfvars...${NC}"
cat > terraform/terraform.tfvars << EOF
# AWS Configuration
aws_region         = "$AWS_REGION"
environment        = "production"

# Network Configuration
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["${AWS_REGION}a", "${AWS_REGION}b", "${AWS_REGION}c"]

# EC2 Configuration
instance_type      = "t4g.small"  # ARM-based Graviton2 - 20% cheaper
instance_count     = 2
key_name           = "$KEY_NAME"

# SSL Certificate
certificate_arn    = "$CERTIFICATE_ARN"

# Secrets (DO NOT COMMIT - pass via environment variables or -var flags)
# database_url      = "ecto://user:pass@host:5432/hermes_production"
# secret_key_base   = "run: mix phx.gen.secret"
# anthropic_api_key = "sk-ant-..."
EOF

echo -e "${GREEN}✓ terraform.tfvars created${NC}"

# Generate GitHub secrets checklist
echo -e "\n${YELLOW}GitHub Secrets to Configure:${NC}"
echo "Go to: https://github.com/$GITHUB_REPO/settings/secrets/actions"
echo ""
echo "Add these secrets:"
echo "  AWS_ROLE_ARN          = $ROLE_ARN"
echo "  DATABASE_URL          = ecto://user:pass@host:5432/hermes_production"
echo "  SECRET_KEY_BASE       = (run: mix phx.gen.secret)"
echo "  ANTHROPIC_API_KEY     = sk-ant-..."
echo "  ACM_CERTIFICATE_ARN   = $CERTIFICATE_ARN"
echo "  EC2_KEY_NAME          = $KEY_NAME"
if [ -f "$HOME/.ssh/${KEY_NAME}.pem" ]; then
    echo "  EC2_SSH_PRIVATE_KEY   = (contents of $HOME/.ssh/${KEY_NAME}.pem)"
fi

# Next steps
echo -e "\n${GREEN}=== Next Steps ===${NC}"
echo "1. If you requested an ACM certificate, validate it via DNS"
echo "2. Configure GitHub secrets (see above)"
echo "3. Generate SECRET_KEY_BASE: mix phx.gen.secret"
echo "4. Update DATABASE_URL with your external database details"
echo "5. Review and update terraform/terraform.tfvars"
echo "6. Run: cd terraform && terraform init"
echo "7. Run: terraform plan (to preview changes)"
echo "8. Run: terraform apply (to create infrastructure)"
echo ""
echo -e "${YELLOW}For GitHub Actions deployment:${NC}"
echo "- Push to main branch to trigger automatic deployment"
echo "- Or manually trigger workflow from GitHub Actions tab"
