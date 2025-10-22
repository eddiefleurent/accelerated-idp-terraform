#!/bin/bash
# test-idp.sh - Comprehensive IDP Pattern Testing Script
#
# Tests the deployed GenAI IDP solution by uploading documents
# and monitoring their processing through Step Functions workflows.
#
# Usage:
#   ./test-idp.sh [document_name] [region]
#
# Examples:
#   ./test-idp.sh                                 # Test Pattern 2 with default document
#   ./test-idp.sh lending_package.pdf             # Test Pattern 2 with specific document

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SAMPLE_FILE=${1:-"lending_package.pdf"}
AWS_REGION=${2:-"us-east-1"}
SAMPLES_DIR="../../samples"
TERRAFORM_DIR=".."
POLL_INTERVAL=10  # seconds between execution status checks
MAX_POLLS=60      # maximum number of polls (10 minutes total)

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║        GenAI IDP Testing Script (Pattern 2)                ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Configuration:${NC}"
echo "  Document:   $SAMPLE_FILE"
echo "  Region:     $AWS_REGION"
echo "  Samples:    $SAMPLES_DIR"
echo ""

# Check if we're in the terraform/testing directory
if [ ! -f "$TERRAFORM_DIR/outputs.tf" ]; then
    echo -e "${RED}❌ Error: Must run from terraform/testing/ directory${NC}"
    echo -e "${RED}   Cannot find terraform outputs.tf${NC}"
    exit 1
fi

# Check if sample file exists
if [ ! -f "$SAMPLES_DIR/$SAMPLE_FILE" ]; then
    echo -e "${RED}❌ Error: Sample file not found: $SAMPLES_DIR/$SAMPLE_FILE${NC}"
    echo ""
    echo "Available samples:"
    ls -lh "$SAMPLES_DIR"/*.pdf 2>/dev/null || echo "No PDF files found"
    exit 1
fi

# Function to get terraform output
get_output() {
    local output_name=$1
    (cd "$TERRAFORM_DIR" && terraform output -raw "$output_name" 2>/dev/null) || echo ""
}

# Function to wait for state machine execution
wait_for_execution() {
    local sm_arn=$1
    local pattern_name=$2
    local execution_arn=""
    local status=""
    local poll_count=0

    echo ""
    echo -e "${YELLOW}⏳ Waiting for execution to start...${NC}"
    sleep 5

    # Get the most recent execution
    execution_arn=$(aws stepfunctions list-executions \
        --state-machine-arn "$sm_arn" \
        --max-results 1 \
        --region "$AWS_REGION" \
        --query 'executions[0].executionArn' \
        --output text 2>/dev/null || echo "")

    if [ -z "$execution_arn" ] || [ "$execution_arn" = "None" ]; then
        echo -e "${RED}❌ No execution found${NC}"
        return 1
    fi

    echo -e "${GREEN}✓ Found execution${NC}"
    echo "  ARN: $execution_arn"
    echo ""
    echo -e "${YELLOW}⏳ Monitoring execution status...${NC}"

    # Poll for completion
    while [ $poll_count -lt $MAX_POLLS ]; do
        status=$(aws stepfunctions describe-execution \
            --execution-arn "$execution_arn" \
            --region "$AWS_REGION" \
            --query 'status' \
            --output text 2>/dev/null || echo "")

        case "$status" in
            "SUCCEEDED")
                echo -e "${GREEN}✓ Execution SUCCEEDED${NC}"
                echo ""
                echo "Output:"
                aws stepfunctions describe-execution \
                    --execution-arn "$execution_arn" \
                    --region "$AWS_REGION" \
                    --query 'output' \
                    --output text 2>/dev/null | jq '.' 2>/dev/null || echo "(No output available)"
                return 0
                ;;
            "FAILED"|"TIMED_OUT"|"ABORTED")
                echo -e "${RED}❌ Execution $status${NC}"
                echo ""
                echo "Error details:"
                aws stepfunctions describe-execution \
                    --execution-arn "$execution_arn" \
                    --region "$AWS_REGION" \
                    --query '{cause: cause, error: error}' \
                    --output json 2>/dev/null | jq '.'
                return 1
                ;;
            "RUNNING")
                echo -ne "\r  Status: RUNNING (${poll_count}/${MAX_POLLS} checks)  "
                ;;
            *)
                echo -ne "\r  Status: $status (${poll_count}/${MAX_POLLS} checks)  "
                ;;
        esac

        sleep $POLL_INTERVAL
        ((poll_count++))
    done

    echo ""
    echo -e "${YELLOW}⚠ Timeout reached. Execution still running.${NC}"
    echo "Check console: https://console.aws.amazon.com/states/home?region=$AWS_REGION#/executions/details/$execution_arn"
    return 2
}

# Function to test a pattern
test_pattern() {
    local pattern=$1
    local bucket_output=$2
    local sm_output=$3
    local pattern_name=$4

    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Testing $pattern_name${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"

    # Get infrastructure details
    local input_bucket=$(get_output "$bucket_output")
    local state_machine=$(get_output "$sm_output")

    if [ -z "$input_bucket" ]; then
        echo -e "${RED}❌ $pattern_name not deployed (no input bucket)${NC}"
        echo "   Expected output: $bucket_output"
        return 1
    fi

    if [ -z "$state_machine" ]; then
        echo -e "${RED}❌ $pattern_name not deployed (no state machine)${NC}"
        echo "   Expected output: $sm_output"
        return 1
    fi

    echo -e "${GREEN}✓ Infrastructure found${NC}"
    echo "  Input Bucket:    $input_bucket"
    echo "  State Machine:   ${state_machine##*/}"
    echo ""

    # Upload document
    echo -e "${YELLOW}📤 Uploading document to S3...${NC}"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local s3_key="test-${timestamp}-${SAMPLE_FILE}"

    if aws s3 cp "$SAMPLES_DIR/$SAMPLE_FILE" "s3://$input_bucket/$s3_key" \
        --region "$AWS_REGION" 2>&1 | grep -q "upload:"; then
        echo -e "${GREEN}✓ Upload successful${NC}"
        echo "  S3 URI: s3://$input_bucket/$s3_key"
    else
        echo -e "${RED}❌ Upload failed${NC}"
        return 1
    fi

    # Wait for execution and monitor
    wait_for_execution "$state_machine" "$pattern_name"
    local result=$?

    if [ $result -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✅ $pattern_name TEST PASSED${NC}"
    elif [ $result -eq 1 ]; then
        echo ""
        echo -e "${RED}❌ $pattern_name TEST FAILED${NC}"
    else
        echo ""
        echo -e "${YELLOW}⚠ $pattern_name TEST TIMEOUT (may still succeed)${NC}"
    fi

    return $result
}

# Main testing logic
echo -e "${YELLOW}🔍 Checking deployed infrastructure...${NC}"

# Test Pattern 2 (Textract+Bedrock)
test_pattern "pattern2" "input_bucket_name" "pattern2_state_machine_arn" "Pattern 2 (Textract+Bedrock)"
PATTERN2_RESULT=$?

# Summary
echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ ${PATTERN2_RESULT:-1} -eq 0 ]; then
    echo -e "Pattern 2: ${GREEN}✅ PASSED${NC}"
else
    echo -e "Pattern 2: ${RED}❌ FAILED${NC}"
fi

echo ""
echo -e "${YELLOW}📊 View CloudWatch Dashboard:${NC}"
dashboard_url=$(get_output "pattern2_dashboard_url")
if [ -n "$dashboard_url" ]; then
    echo "  $dashboard_url"
fi

echo ""
echo -e "${YELLOW}📝 View Lambda Logs:${NC}"
echo "  aws logs tail /aws/lambda/<function-name> --follow --region $AWS_REGION"
echo ""

# Exit with test result code
exit ${PATTERN2_RESULT:-1}
