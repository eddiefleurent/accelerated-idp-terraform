#!/bin/bash
#
# Deployment Script for GenAI IDP Terraform Infrastructure
# This script deploys the complete Terraform stack to AWS
#
set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  GenAI IDP Terraform Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 1. Check Prerequisites
echo -e "${YELLOW}[1/6] Checking prerequisites...${NC}"

# Check for required tools
if ! command -v terraform &> /dev/null; then
    echo -e "${RED}ERROR: Terraform is not installed${NC}"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured${NC}"
    exit 1
fi

# Display AWS account info
AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")
echo -e "${GREEN}✓ AWS Account: ${AWS_ACCOUNT}${NC}"
echo -e "${GREEN}✓ AWS Region: ${AWS_REGION}${NC}"
echo ""

# Check for terraform.tfvars
if [ ! -f "terraform.tfvars" ]; then
    echo -e "${RED}ERROR: terraform.tfvars not found${NC}"
    echo -e "${YELLOW}Please create terraform.tfvars from terraform.tfvars.example${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites check passed${NC}"
echo ""

# Check and fix KMS key state
KMS_KEY_ID=$(grep "kms_key_id" terraform.tfvars | cut -d'"' -f2 | awk -F'key/' '{print $2}')
if [ ! -z "$KMS_KEY_ID" ]; then
    echo -e "${YELLOW}Checking KMS key state...${NC}"
    KMS_STATE=$(aws kms describe-key --key-id "$KMS_KEY_ID" --query 'KeyMetadata.KeyState' --output text 2>/dev/null || echo "NOT_FOUND")

    case "$KMS_STATE" in
        "Enabled")
            echo -e "${GREEN}✓ KMS key is enabled and ready${NC}"
            ;;
        "Disabled")
            echo -e "${YELLOW}⚠ KMS key is disabled, enabling...${NC}"
            aws kms enable-key --key-id "$KMS_KEY_ID"
            echo -e "${GREEN}✓ KMS key enabled${NC}"
            ;;
        "PendingDeletion")
            echo -e "${YELLOW}⚠ KMS key is pending deletion, canceling and enabling...${NC}"
            aws kms cancel-key-deletion --key-id "$KMS_KEY_ID"
            aws kms enable-key --key-id "$KMS_KEY_ID"
            echo -e "${GREEN}✓ KMS key recovered and enabled${NC}"
            ;;
        "NOT_FOUND")
            echo -e "${RED}ERROR: KMS key not found!${NC}"
            echo -e "${YELLOW}Please create a KMS key and update terraform.tfvars${NC}"
            exit 1
            ;;
        *)
            echo -e "${YELLOW}⚠ KMS key in unexpected state: $KMS_STATE${NC}"
            ;;
    esac
    echo ""
fi

# 2. Initialize Terraform
echo -e "${YELLOW}[2/6] Initializing Terraform...${NC}"
terraform init
echo -e "${GREEN}✓ Terraform initialized${NC}"
echo ""

# 3. Validate Configuration
echo -e "${YELLOW}[3/6] Validating Terraform configuration...${NC}"
terraform validate
echo -e "${GREEN}✓ Configuration valid${NC}"
echo ""

# 4. Format Check
echo -e "${YELLOW}[4/6] Checking Terraform formatting...${NC}"
terraform fmt -check || {
    echo -e "${YELLOW}Formatting issues found. Auto-formatting...${NC}"
    terraform fmt -recursive
    echo -e "${GREEN}✓ Formatting applied${NC}"
}
echo ""

# 5. Plan Deployment
echo -e "${YELLOW}[5/6] Planning deployment...${NC}"
echo -e "${YELLOW}This will show you what resources will be created.${NC}"
echo ""

terraform plan -out=tfplan
echo ""

# 6. Apply Deployment
echo -e "${YELLOW}[6/6] Deploying infrastructure${NC}"
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}WARNING: This will create AWS resources that may incur costs${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Resources to be created:"
echo "  - 212 Terraform resources (Pattern 2 + Main Stack Core)"
echo "  - 18 Lambda Functions"
echo "  - 7 S3 Buckets"
echo "  - 4 DynamoDB Tables"
echo "  - 1 Step Functions State Machine"
echo "  - Multiple IAM roles, CloudWatch logs, alarms, etc."
echo ""
echo "Estimated deployment time: 5-10 minutes"
echo ""

echo -e "${YELLOW}Applying Terraform plan...${NC}"
terraform apply -auto-approve tfplan
rm -f tfplan

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Deployment Complete! 🎉${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Review outputs above for resource ARNs and names"
echo "2. To view outputs again: terraform output"
echo "3. To upload documents: aws s3 cp document.pdf s3://\$(terraform output -raw input_bucket_name)/"
echo "4. Monitor processing: Check Step Functions console"
echo "5. View logs: Check CloudWatch Logs"
echo ""
echo -e "${YELLOW}Important: To destroy all resources and avoid costs:${NC}"
echo -e "${YELLOW}  Run: ./destroy.sh${NC}"
echo ""
echo -e "${GREEN}Deployment successful!${NC}"
