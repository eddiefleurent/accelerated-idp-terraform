#!/bin/bash
#
# Cleanup/Destroy Script for GenAI IDP Terraform Infrastructure
# This script ensures COMPLETE removal of all AWS resources to avoid costs
#
# Usage:
#   ./destroy.sh           - Production mode: schedules KMS key for deletion
#   ./destroy.sh --dev     - Dev mode: disables KMS key for quick re-enable
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

# Check for dev mode flag
DEV_MODE=false
if [[ "$1" == "--dev" ]]; then
    DEV_MODE=true
fi

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  GenAI IDP Infrastructure Destruction${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}ERROR: AWS credentials not configured${NC}"
    exit 1
fi

AWS_ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region || echo "us-east-1")

echo -e "${YELLOW}AWS Account: ${AWS_ACCOUNT}${NC}"
echo -e "${YELLOW}AWS Region: ${AWS_REGION}${NC}"
echo ""

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}  ⚠️  WARNING: DESTRUCTIVE OPERATION  ⚠️${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "This script will PERMANENTLY DELETE all resources:"
echo ""
echo "  • All S3 buckets and their contents"
echo "  • All DynamoDB tables and data"
echo "  • All Lambda functions"
echo "  • All IAM roles and policies"
echo "  • All CloudWatch logs and alarms"
echo "  • All Step Functions state machines"
echo "  • All EventBridge rules"
echo "  • All SQS queues and messages"
echo "  • KMS key (will be scheduled for deletion)"
echo ""
echo -e "${RED}This action CANNOT be undone!${NC}"
echo ""

read -p "Type 'DELETE EVERYTHING' to confirm: " -r
echo ""

if [[ ! $REPLY == "DELETE EVERYTHING" ]]; then
    echo -e "${GREEN}Destruction cancelled - resources are safe${NC}"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting destruction process...${NC}"
echo ""

# Function to empty S3 buckets before Terraform destroy
empty_s3_buckets() {
    echo -e "${YELLOW}[1/4] Emptying S3 buckets...${NC}"

    # Get bucket names from Terraform state if it exists
    if [ -f "terraform.tfstate" ]; then
        BUCKETS=$(terraform output -json 2>/dev/null | jq -r '.. | select(.bucket_name? != null) | .bucket_name' 2>/dev/null || echo "")

        # Also try to get buckets from tfvars
        if [ -f "terraform.tfvars" ]; then
            TFVARS_BUCKETS=$(grep "_bucket_name" terraform.tfvars | grep -v "^#" | cut -d'"' -f2 | grep -v "^$" || echo "")
            BUCKETS="$BUCKETS $TFVARS_BUCKETS"
        fi

        # Remove duplicates and empty buckets
        for BUCKET in $(echo "$BUCKETS" | tr ' ' '\n' | sort -u); do
            if [ ! -z "$BUCKET" ]; then
                echo -e "${YELLOW}  Checking bucket: ${BUCKET}${NC}"

                # Check if bucket exists
                if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
                    echo -e "${YELLOW}  Emptying bucket: ${BUCKET}${NC}"

                    # Delete all object versions (if versioning enabled)
                    aws s3api list-object-versions --bucket "$BUCKET" --output json 2>/dev/null | \
                    jq -r '.Versions[]?, .DeleteMarkers[]? | "\(.Key) \(.VersionId)"' 2>/dev/null | \
                    while read -r key versionId; do
                        if [ ! -z "$key" ]; then
                            aws s3api delete-object --bucket "$BUCKET" --key "$key" --version-id "$versionId" 2>/dev/null || true
                        fi
                    done

                    # Delete all objects (current versions)
                    aws s3 rm "s3://${BUCKET}" --recursive 2>/dev/null || true

                    echo -e "${GREEN}  ✓ Bucket emptied: ${BUCKET}${NC}"
                else
                    echo -e "${BLUE}  Bucket does not exist or already deleted: ${BUCKET}${NC}"
                fi
            fi
        done
    fi

    echo -e "${GREEN}✓ S3 buckets emptied${NC}"
    echo ""
}

# Function to delete CloudWatch log groups that might not be in Terraform state
cleanup_log_groups() {
    echo -e "${YELLOW}[2/4] Cleaning up CloudWatch log groups...${NC}"

    LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/genai-idp-test" --query 'logGroups[].logGroupName' --output text 2>/dev/null || echo "")

    for LOG_GROUP in $LOG_GROUPS; do
        if [ ! -z "$LOG_GROUP" ]; then
            echo -e "${YELLOW}  Deleting log group: ${LOG_GROUP}${NC}"
            aws logs delete-log-group --log-group-name "$LOG_GROUP" 2>/dev/null || true
        fi
    done

    echo -e "${GREEN}✓ Log groups cleaned up${NC}"
    echo ""
}

# Function to run Terraform destroy
run_terraform_destroy() {
    echo -e "${YELLOW}[3/4] Running Terraform destroy...${NC}"
    echo ""

    if [ ! -f "terraform.tfstate" ]; then
        echo -e "${BLUE}No Terraform state found - infrastructure may not be deployed${NC}"
        echo ""
        return
    fi

    # Run destroy
    terraform destroy -auto-approve

    echo ""
    echo -e "${GREEN}✓ Terraform destroy complete${NC}"
    echo ""
}

# Function to verify and cleanup any remaining resources
verify_cleanup() {
    echo -e "${YELLOW}[4/4] Verifying cleanup and removing stragglers...${NC}"
    echo ""

    # Check and delete remaining S3 buckets
    echo -e "${YELLOW}Checking for S3 buckets...${NC}"
    REMAINING_BUCKETS=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `genai-idp-test`)].Name' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING_BUCKETS" ]; then
        echo -e "${GREEN}✓ No S3 buckets found${NC}"
    else
        for BUCKET in $REMAINING_BUCKETS; do
            echo -e "${YELLOW}  Deleting remaining bucket: ${BUCKET}${NC}"
            aws s3 rb "s3://${BUCKET}" --force 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Deleted remaining S3 buckets${NC}"
    fi

    # Check and delete remaining Lambda functions
    echo -e "${YELLOW}Checking for Lambda functions...${NC}"
    REMAINING_LAMBDAS=$(aws lambda list-functions --query 'Functions[?contains(FunctionName, `genai-idp-test`)].FunctionName' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING_LAMBDAS" ]; then
        echo -e "${GREEN}✓ No Lambda functions found${NC}"
    else
        for LAMBDA in $REMAINING_LAMBDAS; do
            echo -e "${YELLOW}  Deleting Lambda function: ${LAMBDA}${NC}"
            aws lambda delete-function --function-name "$LAMBDA" 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Deleted remaining Lambda functions${NC}"
    fi

    # Check and delete remaining DynamoDB tables
    echo -e "${YELLOW}Checking for DynamoDB tables...${NC}"
    REMAINING_TABLES=$(aws dynamodb list-tables --query 'TableNames[?contains(@, `genai-idp-test`)]' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING_TABLES" ]; then
        echo -e "${GREEN}✓ No DynamoDB tables found${NC}"
    else
        for TABLE in $REMAINING_TABLES; do
            echo -e "${YELLOW}  Deleting DynamoDB table: ${TABLE}${NC}"
            aws dynamodb delete-table --table-name "$TABLE" 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Deleted remaining DynamoDB tables${NC}"
    fi

    # Check and delete remaining Step Functions state machines
    echo -e "${YELLOW}Checking for Step Functions state machines...${NC}"
    REMAINING_SFN=$(aws stepfunctions list-state-machines --query 'stateMachines[?contains(name, `genai-idp-test`)].stateMachineArn' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING_SFN" ]; then
        echo -e "${GREEN}✓ No Step Functions found${NC}"
    else
        for SFN_ARN in $REMAINING_SFN; do
            SFN_NAME=$(echo "$SFN_ARN" | awk -F: '{print $NF}')
            echo -e "${YELLOW}  Deleting Step Functions state machine: ${SFN_NAME}${NC}"
            aws stepfunctions delete-state-machine --state-machine-arn "$SFN_ARN" 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Deleted remaining Step Functions${NC}"
    fi

    # Check and delete remaining SQS queues
    echo -e "${YELLOW}Checking for SQS queues...${NC}"
    REMAINING_QUEUES=$(aws sqs list-queues --queue-name-prefix "genai-idp-test" --query 'QueueUrls[]' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING_QUEUES" ]; then
        echo -e "${GREEN}✓ No SQS queues found${NC}"
    else
        for QUEUE_URL in $REMAINING_QUEUES; do
            QUEUE_NAME=$(echo "$QUEUE_URL" | awk -F/ '{print $NF}')
            echo -e "${YELLOW}  Deleting SQS queue: ${QUEUE_NAME}${NC}"
            aws sqs delete-queue --queue-url "$QUEUE_URL" 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Deleted remaining SQS queues${NC}"
    fi

    # Check and delete remaining IAM roles
    echo -e "${YELLOW}Checking for IAM roles...${NC}"
    REMAINING_ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `genai-idp-test`)].RoleName' --output text 2>/dev/null || echo "")
    if [ -z "$REMAINING_ROLES" ]; then
        echo -e "${GREEN}✓ No IAM roles found${NC}"
    else
        for ROLE in $REMAINING_ROLES; do
            echo -e "${YELLOW}  Deleting IAM role: ${ROLE}${NC}"

            # First detach managed policies
            ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
            for POLICY_ARN in $ATTACHED_POLICIES; do
                aws iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" 2>/dev/null || true
            done

            # Delete inline policies
            INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE" --query 'PolicyNames[]' --output text 2>/dev/null || echo "")
            for POLICY_NAME in $INLINE_POLICIES; do
                aws iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY_NAME" 2>/dev/null || true
            done

            # Delete the role
            aws iam delete-role --role-name "$ROLE" 2>/dev/null || true
        done
        echo -e "${GREEN}✓ Deleted remaining IAM roles${NC}"
    fi

    echo ""
}

# Function to validate KMS key ID format (UUID or ARN)
validate_kms_key_id() {
    local key_id="$1"

    # Check if it's a valid UUID format (with or without hyphens)
    if [[ "$key_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 0
    fi

    # Check if it's a valid KMS key ARN
    if [[ "$key_id" =~ ^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        return 0
    fi

    return 1
}

# Function to handle KMS key deletion
cleanup_kms_key() {
    echo -e "${YELLOW}Handling KMS key...${NC}"
    echo ""

    # Try to extract KMS key ID from terraform.tfvars
    local extracted_key_id=$(grep "kms_key_id" terraform.tfvars 2>/dev/null | cut -d'"' -f2 | awk -F'key/' '{print $2}')

    # Use environment variable if extraction failed
    if [ -z "$extracted_key_id" ]; then
        KMS_KEY_ID="$KMS_KEY_ID"
    else
        KMS_KEY_ID="$extracted_key_id"
    fi

    # Fail fast if no KMS key ID is available
    if [ -z "$KMS_KEY_ID" ]; then
        echo -e "${RED}ERROR: KMS key ID not found${NC}"
        echo ""
        echo "The KMS key ID could not be extracted from terraform.tfvars."
        echo "Please provide the KMS key ID using one of these methods:"
        echo ""
        echo "  1. Set the KMS_KEY_ID environment variable:"
        echo "     export KMS_KEY_ID='your-key-id-or-arn'"
        echo "     ./destroy.sh"
        echo ""
        echo "  2. Ensure terraform.tfvars contains a valid kms_key_id entry:"
        echo "     kms_key_id = \"arn:aws:kms:region:account:key/key-id\""
        echo ""
        echo "The key ID should be either:"
        echo "  - A UUID: 6311c30f-3397-420e-904b-fa960edbac3c"
        echo "  - A full ARN: arn:aws:kms:us-east-1:123456789012:key/6311c30f-3397-420e-904b-fa960edbac3c"
        echo ""
        exit 1
    fi

    # Validate the KMS key ID format
    if ! validate_kms_key_id "$KMS_KEY_ID"; then
        echo -e "${RED}ERROR: Invalid KMS key ID format${NC}"
        echo ""
        echo "The provided KMS key ID does not match expected formats:"
        echo "  Provided: $KMS_KEY_ID"
        echo ""
        echo "Expected formats:"
        echo "  - UUID: 6311c30f-3397-420e-904b-fa960edbac3c"
        echo "  - ARN: arn:aws:kms:us-east-1:123456789012:key/6311c30f-3397-420e-904b-fa960edbac3c"
        echo ""
        echo "Please verify the key ID and try again."
        exit 1
    fi

    if [ "$DEV_MODE" = true ]; then
        echo -e "${BLUE}Dev Mode: Disabling KMS key (fast re-enable for testing)...${NC}"
        echo -e "${BLUE}Key ID: $KMS_KEY_ID${NC}"
        aws kms disable-key --key-id "$KMS_KEY_ID" 2>/dev/null && {
            echo -e "${GREEN}✓ KMS key disabled${NC}"
            echo -e "${YELLOW}Note: Use './deploy.sh' to automatically re-enable${NC}"
        } || {
            echo -e "${BLUE}KMS key may already be disabled or doesn't exist${NC}"
        }
    else
        echo -e "${YELLOW}Production Mode: Scheduling KMS key for deletion (7-day waiting period)...${NC}"
        echo -e "${YELLOW}Key ID: $KMS_KEY_ID${NC}"
        aws kms schedule-key-deletion --key-id "$KMS_KEY_ID" --pending-window-in-days 7 2>/dev/null && {
            echo -e "${GREEN}✓ KMS key scheduled for deletion${NC}"
            echo -e "${YELLOW}Note: KMS keys have a mandatory 7-day waiting period before deletion${NC}"
            echo -e "${YELLOW}The key will be deleted automatically after 7 days${NC}"
        } || {
            echo -e "${BLUE}KMS key may already be scheduled for deletion or doesn't exist${NC}"
        }
    fi
    echo ""
}

# Main execution
echo -e "${YELLOW}Beginning destruction sequence...${NC}"
echo ""

# Execute cleanup steps
empty_s3_buckets
cleanup_log_groups
run_terraform_destroy
verify_cleanup
cleanup_kms_key

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Destruction Complete! ✓${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}Summary:${NC}"
echo "  • All Terraform-managed resources destroyed"
echo "  • S3 buckets emptied and deleted"
echo "  • CloudWatch logs cleaned up"
if [ "$DEV_MODE" = true ]; then
    echo "  • KMS key disabled (can re-enable quickly)"
else
    echo "  • KMS key scheduled for deletion (7 days)"
fi
echo ""
echo -e "${GREEN}No ongoing AWS costs from this deployment!${NC}"
echo ""
echo -e "${YELLOW}Note: You may want to check the AWS Console to verify:${NC}"
echo "  • S3: https://s3.console.aws.amazon.com/s3/buckets?region=${AWS_REGION}"
echo "  • Lambda: https://console.aws.amazon.com/lambda/home?region=${AWS_REGION}"
echo "  • DynamoDB: https://console.aws.amazon.com/dynamodbv2/home?region=${AWS_REGION}"
echo ""
