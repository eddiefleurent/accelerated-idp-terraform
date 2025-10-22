# GenAI IDP Testing Guide

Complete guide for testing the Terraform-deployed IDP solution. Tests validate the system works correctly using the cheapest Bedrock model (Amazon Nova Lite).

---

## Quick Start (5 Minutes)

```bash
# From repo root, navigate to testing directory
cd terraform/testing

# Run test for Pattern 2 (recommended)
./test-idp.sh pattern2

# Expected: ✅ Pattern 2 TEST PASSED (in ~2-3 minutes)
```

**What this does:**
- Uploads `lending_package.pdf` (2.5MB) to S3 input bucket
- Triggers Pattern 2 workflow: OCR → Classification → Extraction
- Uses Amazon Nova Lite (cheapest Bedrock model)
- Monitors execution and reports success/failure

---

## Prerequisites

### 1. Deploy Infrastructure (If Not Already Deployed)

```bash
cd terraform

# Check if deployed
terraform show | head -5

# If empty or error, deploy it
./deploy.sh
# Wait ~5-10 minutes
```

### 2. Configure AWS CLI

```bash
# Verify credentials
aws sts get-caller-identity

# Should show your AWS account ID and IAM principal
```

### 3. Enable Bedrock Model Access

**Amazon Nova Lite** is the cheapest model and sufficient for testing.

**Option A: AWS CLI (Recommended)**
```bash
# Check current access
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query 'modelSummaries[?contains(modelId, `nova-lite`)].{ID:modelId,Name:modelName}' \
  --output table

# If no results, you need to request access via console
```

**Option B: AWS Console**
1. Go to Bedrock console: https://console.aws.amazon.com/bedrock/home?region=us-east-1
2. Navigate to "Foundation models" or "Model access" section
3. Find "Amazon Nova Lite" and request access
4. Wait ~2-5 minutes for approval

**Note:** The Bedrock console UI has changed. Look for sections like:
- "Foundation models" → "Base models" → Filter for "Nova"
- "Bedrock configurations" → "Model access"
- "Get started" → "Request model access"

The model ID we need is: `amazon.nova-lite-v1:0`

### 4. Load Configuration into DynamoDB (Required)

**The IDP system requires configuration to be loaded into DynamoDB before processing documents.**

```bash
cd terraform/testing

# Load default lending-package configuration (recommended for first deployment)
python3 load_config.py \
  --config-file ../../config_library/pattern-2/lending-package-sample/config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --region us-west-2

# Verify configuration was loaded
CONFIG_TABLE=$(cd .. && terraform output -raw configuration_table_name)
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --query 'Item.model_config' \
  --output json
```

**Why is this required?**
- Terraform deploys infrastructure but does not load document-specific configurations
- Configuration defines classification prompts, extraction schemas, and model settings
- Different use cases require different configurations (lending vs. invoices vs. bank statements)

**Available configurations in `config_library/pattern-2/`:**
- `lending-package-sample/` - Mortgage/loan documents ⭐ Recommended
- `bank-statement-sample/` - Bank statement processing
- `rvl-cdip-package-sample/` - General document classification
- `criteria-validation/` - Compliance validation

**See [Configuration Management](#configuration-details) section below for advanced usage.**

### 5. Verify Sample Documents

```bash
# From repo root
ls -lh samples/

# Should see:
# - lending_package.pdf (2.5M) - Default test document
# - bank-statement-multipage.pdf (242K) - Fastest
# - insurance_package.pdf (5.1M) - Most complex
```

---

## Pattern Comparison

### Pattern 1: Bedrock Data Automation (BDA)

**Requirements:**
- ❌ Must create BDA project in AWS Console first
- ❌ Must provide BDA project ARN in `terraform.tfvars`
- ❌ More complex setup

**Best For:** Generic document processing when you already have BDA projects configured

### Pattern 2: Textract + Bedrock (Recommended) ✅

**Requirements:**
- ✅ Only needs Bedrock model access
- ⚠️ Configuration must be loaded manually with `load_config.py` (see step 4 above)
- ✅ Simpler to test and verify

**Best For:** First-time testing, structured field extraction, custom workflows

**Pattern 2 is recommended** because it's easier to set up and test.

---

## Running Tests

### Test Pattern 2 (Recommended)

```bash
cd terraform/testing

# Default test (uses lending_package.pdf)
./test-idp.sh pattern2

# Test with specific document
./test-idp.sh pattern2 bank-statement-multipage.pdf

# Test with different AWS region
./test-idp.sh pattern2 lending_package.pdf us-west-2
```

**Expected output:**
```
╔════════════════════════════════════════════════════════════╗
║        GenAI IDP Pattern Testing Script                    ║
╚════════════════════════════════════════════════════════════╝

Configuration:
  Pattern:    pattern2
  Document:   lending_package.pdf
  Region:     us-east-1

════════════════════════════════════════════════════════════
  Testing Pattern 2 (Textract+Bedrock)
════════════════════════════════════════════════════════════

✓ Infrastructure found
  Input Bucket:    idp-dev-input-bucket-abc123
  State Machine:   Pattern2DocumentProcessing

📤 Uploading document to S3...
✓ Upload successful

⏳ Waiting for execution to start...
✓ Found execution

⏳ Monitoring execution status...
  Status: RUNNING (5/60 checks)
✓ Execution SUCCEEDED

✅ Pattern 2 TEST PASSED
```

### Test Pattern 1 (Advanced)

Only test Pattern 1 if you have a BDA project already configured.

```bash
# 1. Create BDA project in AWS Console (one-time)
# - Navigate to Bedrock → Data Automation
# - Create new project with appropriate blueprints
# - Copy project ARN

# 2. Update terraform.tfvars
cd terraform
echo 'bedrock_bda_project_arn = "arn:aws:bedrock:us-east-1:123456789012:bda-project/abc123"' >> terraform.tfvars

# 3. Re-deploy
terraform apply

# 4. Run test
cd testing
./test-idp.sh pattern1
```

### Test Both Patterns

```bash
./test-idp.sh both
```

---

## Verifying Results

### Check S3 Output

```bash
cd terraform

# Get output bucket name
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)

# List processed documents
aws s3 ls s3://$OUTPUT_BUCKET/ --recursive | tail -10

# Download latest result
aws s3 cp s3://$OUTPUT_BUCKET/results/<document-id>.json ./result.json

# View extracted data
cat result.json | jq '.Sections[0].Attributes'
```

**Expected output structure:**
```json
{
  "Sections": [
    {
      "Id": "section_1",
      "PageIds": ["page_1"],
      "Class": "invoice",
      "Attributes": {
        "invoice_number": "INV-12345",
        "invoice_date": "2025-10-20",
        "total_amount": "1500.00",
        "vendor_name": "ACME Corp"
      }
    }
  ],
  "PageCount": 1,
  "ProcessingTimeMs": 12345
}
```

### Check DynamoDB Tracking

```bash
# Get table name
TRACKING_TABLE=$(terraform output -raw tracking_table_name)

# View recent documents
aws dynamodb scan \
  --table-name $TRACKING_TABLE \
  --max-items 5 \
  --query 'Items[*].{ID:document_id.S,Status:status.S,Time:timestamp.S}' \
  --output table
```

### View CloudWatch Dashboard

```bash
# Get dashboard URL
terraform output pattern2_dashboard_url

# Copy URL and open in browser
```

The dashboard shows:
- Document processing metrics
- Lambda function invocations
- Error rates
- Processing duration

### Check Lambda Logs

```bash
# OCR function
aws logs tail /aws/lambda/$(terraform output -raw ocr_function_name) --follow --region us-east-1

# Classification function
aws logs tail /aws/lambda/$(terraform output -raw classification_function_name) --follow --region us-east-1

# Extraction function
aws logs tail /aws/lambda/$(terraform output -raw extraction_function_name) --follow --region us-east-1
```

### View Step Functions Execution

```bash
# Get state machine ARN
STATE_MACHINE=$(terraform output -raw pattern2_state_machine_arn)

# List recent executions
aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE \
  --max-results 5 \
  --query 'executions[*].{Name:name,Status:status,Start:startDate}' \
  --output table

# Get detailed execution info
EXECUTION_ARN=$(aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE \
  --max-results 1 \
  --query 'executions[0].executionArn' \
  --output text)

aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --query '{Status:status,Input:input,Output:output}' \
  --output json | jq '.'
```

---

## Troubleshooting

### "Pattern not deployed" Error

**Symptom:**
```
❌ Pattern 2 not deployed (no input bucket)
```

**Solution:**
```bash
cd terraform

# Verify Terraform state exists
terraform show | head -5

# If empty, deploy infrastructure
./deploy.sh
```

### "Access Denied" When Uploading to S3

**Symptom:**
```
upload failed: An error occurred (AccessDenied) when calling the PutObject operation
```

**Solutions:**

1. Check AWS credentials:
```bash
aws sts get-caller-identity
```

2. Verify KMS key permissions:
```bash
# Your IAM principal needs kms:Decrypt and kms:GenerateDataKey
# Update terraform.tfvars:
kms_key_administrators = ["arn:aws:iam::123456789012:user/your-user"]

terraform apply
```

3. Check S3 bucket policy:
```bash
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
aws s3api get-bucket-policy --bucket $INPUT_BUCKET
```

### "ModelNotFound" or "ModelAccessDeniedException"

**Symptom:**
```
ValidationException: Could not find model identifier amazon.nova-lite-v1:0
```

**Solution:**

Request access to Amazon Nova Lite:
1. Go to Bedrock console (UI varies by console version):
   - Look for "Foundation models" or "Model access"
   - Find "Amazon Nova Lite"
   - Click "Request access" or "Enable"
2. Wait ~2-5 minutes for approval
3. Verify access:
```bash
aws bedrock list-foundation-models \
  --region us-east-1 \
  --query 'modelSummaries[?modelId==`amazon.nova-lite-v1:0`]'
```

### Step Functions Execution Fails

**Symptom:**
```
❌ Execution FAILED
```

**Debug steps:**

1. Check execution details:
```bash
STATE_MACHINE=$(terraform output -raw pattern2_state_machine_arn)
EXECUTION_ARN=$(aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE \
  --max-results 1 \
  --query 'executions[0].executionArn' \
  --output text)

aws stepfunctions describe-execution \
  --execution-arn $EXECUTION_ARN \
  --query '{Status:status,Cause:cause,Error:error}' \
  --output json | jq '.'
```

2. Check Lambda logs:
```bash
# View recent errors
for func in $(terraform output -json | jq -r 'to_entries[] | select(.key | endswith("_function_name")) | .value'); do
  echo "=== $func ==="
  aws logs tail /aws/lambda/$func --since 10m --filter-pattern "ERROR" | head -20
done
```

3. Common errors and fixes:

| Error | Cause | Solution |
|-------|-------|----------|
| `BucketAccessDenied` | Lambda IAM role missing S3 permissions | Re-run `terraform apply` |
| `ModelNotFound` | Bedrock model access not granted | Request model access in console |
| `InvalidConfiguration` | Missing DynamoDB config | Check configuration table exists |
| `ThrottlingException` | Too many requests | Wait and retry, or increase quotas |

### Test Timeout (10+ Minutes)

**Symptom:**
```
⚠ Timeout reached. Execution still running.
```

**Possible causes:**
- Large document (5MB+) taking longer than expected
- Human-in-the-Loop (HITL) enabled and waiting for review
- Lambda cold start delays

**Check execution manually:**
```bash
STATE_MACHINE=$(terraform output -raw pattern2_state_machine_arn)
EXECUTION_ARN=$(aws stepfunctions list-executions \
  --state-machine-arn $STATE_MACHINE \
  --max-results 1 \
  --query 'executions[0].executionArn' \
  --output text)

# View current status
aws stepfunctions describe-execution --execution-arn $EXECUTION_ARN

# Open in console
echo "https://console.aws.amazon.com/states/home?region=us-east-1#/executions/details/$EXECUTION_ARN"
```

---

## What the Test Does

### Pattern 2 End-to-End Workflow

1. **S3 Upload** → Document uploaded to input bucket
2. **Event Detection** → EventBridge detects upload, sends notification to SQS
3. **Queue Processing** → QueueProcessor Lambda reads SQS, starts Step Functions
4. **OCR (Textract)** → Extract text and layout from document pages
5. **Classification (Bedrock)** → Identify document type(s) using Amazon Nova Lite
6. **Extraction (Bedrock)** → Extract structured fields using Amazon Nova Lite
7. **Assessment** → (Optional) Quality scoring against baseline
8. **Process Results** → Aggregate and save to S3 output bucket
9. **Tracking** → Update DynamoDB with processing status
10. **Complete** → Return results

**Expected Duration:** 2-5 minutes (depends on document size and complexity)

**Cost Per Test:** ~$0.01-0.05 using Nova Lite (cheapest Bedrock model)

---

## Configuration Management

### Overview

The IDP solution uses a **DynamoDB-based configuration system** that separates infrastructure deployment from document-specific processing logic.

**Key Concepts:**
- **Storage**: DynamoDB table with `Configuration` as partition key
- **Merge Strategy**: System combines `Default` + `Custom` configurations at runtime
- **Source Files**: YAML files in `config_library/pattern-2/`
- **Loading Scripts**: `load_config.py` and `json_to_dynamodb.py`

### Configuration Records

**Three types of configuration records:**

1. **Default** - Base configuration with classification prompts, extraction schemas, and model settings
2. **Custom** - Optional user overrides (merged with Default at runtime)
3. **Schema** - JSON schema defining valid configuration structure

### Loading Configuration (Step-by-Step)

**Method 1: Load from YAML (Recommended)**

```bash
cd terraform/testing

# Load lending-package configuration
python3 load_config.py \
  --config-file ../../config_library/pattern-2/lending-package-sample/config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --region us-west-2
```

**Method 2: Load from JSON**

```bash
# Convert YAML to JSON first
python3 -c "import yaml, json; print(json.dumps(yaml.safe_load(open('../../config_library/pattern-2/lending-package-sample/config.yaml'))))" > config.json

# Load into DynamoDB
python3 json_to_dynamodb.py \
  --json-file config.json \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --config-type Default \
  --region us-west-2
```

**Method 3: Direct AWS CLI**

```bash
# For simple updates (e.g., just change model)
CONFIG_TABLE=$(cd .. && terraform output -raw configuration_table_name)

aws dynamodb update-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --update-expression "SET model_config.modelId = :model, model_config.temperature = :temp" \
  --expression-attribute-values '{":model": {"S": "amazon.nova-lite-v1:0"}, ":temp": {"N": "0.1"}}'
```

### Available Sample Configurations

| Configuration | Use Case | Document Types | Best For |
|--------------|----------|----------------|----------|
| `lending-package-sample/` | Mortgage/Loan Processing | Loan apps, statements, pay stubs | ⭐ First deployment |
| `bank-statement-sample/` | Financial Documents | Bank statements, transaction records | Financial services |
| `rvl-cdip-package-sample/` | General Classification | Mixed document types | Generic workflows |
| `criteria-validation/` | Compliance Checking | Documents requiring validation | Regulatory use cases |

### Viewing Current Configuration

```bash
CONFIG_TABLE=$(cd .. && terraform output -raw configuration_table_name)

# View entire Default configuration
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --output json | jq '.Item'

# View just the model config
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --query 'Item.model_config' \
  --output json | jq '.'

# List all configurations
aws dynamodb scan \
  --table-name $CONFIG_TABLE \
  --projection-expression "Configuration" \
  --output table
```

### Creating Custom Overrides

**To customize without modifying Default:**

```bash
# Create custom.yaml with only fields you want to override
cat > custom-config.yaml <<EOF
model_config:
  modelId: anthropic.claude-3-5-sonnet-20241022-v2:0
  temperature: 0.2
  maxTokens: 8000
EOF

# Load as Custom configuration
python3 load_config.py \
  --config-file custom-config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --config-type Custom \
  --region us-west-2
```

At runtime: `Final Config = Default + Custom` (Custom overrides Default)

### Configuration File Structure

```yaml
# Classification prompt (Jinja2 template)
classification_prompt_template: |
  Analyze this document and classify it into categories:
  - invoice
  - bank_statement
  - loan_application

# Extraction schema (JSON Schema format)
extraction_schema:
  type: object
  properties:
    invoice_number:
      type: string
      description: "Invoice or reference number"
    invoice_date:
      type: string
      description: "Date in YYYY-MM-DD format"
    total_amount:
      type: number
      description: "Total amount due"

# Model settings
model_config:
  modelId: amazon.nova-lite-v1:0
  temperature: 0.1
  maxTokens: 4096
  topP: 0.9

# Optional: Few-shot examples
few_shot_examples:
  - document_type: invoice
    text: "Example invoice content..."
    expected_output:
      invoice_number: "INV-001"
      total_amount: 1500.00
```

### Troubleshooting Configuration Issues

**Problem: "Configuration not found" errors**

```bash
# Check if any configuration exists
CONFIG_TABLE=$(cd .. && terraform output -raw configuration_table_name)
aws dynamodb scan --table-name $CONFIG_TABLE

# If empty, load default
cd terraform/testing
python3 load_config.py \
  --config-file ../../config_library/pattern-2/lending-package-sample/config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name)
```

**Problem: Wrong model being used**

```bash
# Verify current model
CONFIG_TABLE=$(cd .. && terraform output -raw configuration_table_name)
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --query 'Item.model_config.modelId.S' \
  --output text

# Update if incorrect
aws dynamodb update-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --update-expression "SET model_config.modelId = :model" \
  --expression-attribute-values '{":model": {"S": "amazon.nova-lite-v1:0"}}'
```

**Problem: UpdateConfigurationFunction fails during deployment**

This is expected behavior. The Lambda function is designed for CloudFormation Custom Resources and expects S3 URIs to config files that don't exist in the Terraform deployment.

**Solution**: Use the manual `load_config.py` script instead (documented above).

---

## Testing Configuration

### Default Bedrock Model

Tests use **Amazon Nova Lite** (`amazon.nova-lite-v1:0`) by default.

**Why Nova Lite?**
- ✅ Cheapest Bedrock model for text/image processing
- ✅ Sufficient for validation testing
- ✅ Fast inference (lower latency)
- ✅ Good accuracy for common document types

**Pricing (as of Oct 2024):**
- Input: $0.00006/1K tokens
- Output: $0.00024/1K tokens
- Typical test: ~5K tokens = ~$0.002 per document

### Model Configuration Location

Configuration is stored in DynamoDB:

```bash
# View current config
CONFIG_TABLE=$(terraform output -raw configuration_table_name)
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --query 'Item.model_config' \
  --output json | jq '.'
```

**Default model config:**
```json
{
  "modelId": "amazon.nova-lite-v1:0",
  "temperature": 0.1,
  "maxTokens": 4096
}
```

### Changing Model (Optional)

To use a different model (e.g., Claude for higher accuracy):

```bash
# Update configuration
CONFIG_TABLE=$(terraform output -raw configuration_table_name)

aws dynamodb update-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --update-expression "SET model_config.modelId = :model" \
  --expression-attribute-values '{":model": {"S": "anthropic.claude-3-sonnet-20240229-v1:0"}}'

# Re-run test
cd testing
./test-idp.sh pattern2
```

---

## Test Documents

Available sample documents (in `../samples/`):

| Document | Size | Pages | Complexity | Test Time |
|----------|------|-------|------------|-----------|
| `bank-statement-multipage.pdf` | 242 KB | 3 | Low | ~1-2 min |
| `lending_package.pdf` | 2.5 MB | 5 | Medium | ~2-3 min ⭐ |
| `lending_package-long.pdf` | 4.4 MB | 10 | High | ~4-6 min |
| `insurance_package.pdf` | 5.1 MB | 15 | High | ~5-8 min |

⭐ = Recommended for first test

### Testing Different Documents

```bash
cd terraform/testing

# Fast test (simple document)
./test-idp.sh pattern2 bank-statement-multipage.pdf

# Standard test (recommended)
./test-idp.sh pattern2 lending_package.pdf

# Comprehensive test (complex document)
./test-idp.sh pattern2 insurance_package.pdf
```

---

## Success Indicators

### ✅ Test Passed

**Console output shows:**
```
✓ Infrastructure found
✓ Upload successful
✓ Found execution
✓ Execution SUCCEEDED
✅ Pattern 2 TEST PASSED
```

**Verify in AWS:**

1. **S3 results exist:**
```bash
aws s3 ls s3://$(terraform output -raw output_bucket_name)/ --recursive | grep results/
```

2. **DynamoDB has tracking records:**
```bash
aws dynamodb scan --table-name $(terraform output -raw tracking_table_name) --max-items 1
```

3. **Step Functions execution succeeded:**
```bash
aws stepfunctions list-executions \
  --state-machine-arn $(terraform output -raw pattern2_state_machine_arn) \
  --status-filter SUCCEEDED \
  --max-results 1
```

### ❌ Test Failed

**Check these in order:**

1. Is infrastructure deployed?
```bash
terraform show | head -5
```

2. Do you have Bedrock model access?
```bash
aws bedrock list-foundation-models --region us-east-1 | grep nova-lite
```

3. Can you upload to S3?
```bash
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
echo "test" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://$INPUT_BUCKET/test.txt
```

4. Check Lambda logs for errors:
```bash
aws logs tail /aws/lambda/$(terraform output -raw ocr_function_name) --since 10m
```

---

## Cleanup

### After Testing

```bash
# Results remain in S3 for analysis
# To clean up test documents:
INPUT_BUCKET=$(terraform output -raw input_bucket_name)
aws s3 rm s3://$INPUT_BUCKET/ --recursive --exclude "*" --include "test-*"

# Leave infrastructure running for more tests
```

### Full Teardown

```bash
cd terraform
./destroy.sh

# Type: DELETE EVERYTHING
# Wait ~5-10 minutes for complete cleanup
```

---

## Next Steps

### After Successful Test

1. **Review extracted data:**
```bash
OUTPUT_BUCKET=$(terraform output -raw output_bucket_name)
aws s3 cp s3://$OUTPUT_BUCKET/results/ ./results/ --recursive
jq '.Sections[0].Attributes' results/*.json
```

2. **View monitoring dashboard:**
```bash
terraform output pattern2_dashboard_url
# Open URL in browser
```

3. **Set up alerts (optional):**
```bash
# Subscribe to SNS topic for CloudWatch alarms
ALERTS_TOPIC=$(terraform output -raw alerts_topic_arn)
aws sns subscribe \
  --topic-arn $ALERTS_TOPIC \
  --protocol email \
  --notification-endpoint your-email@example.com
```

4. **Test additional document types:**
```bash
# Try different documents from samples/ folder
for doc in ../samples/*.pdf; do
  echo "Testing: $(basename $doc)"
  ./test-idp.sh pattern2 $(basename $doc)
  sleep 30
done
```

### For Production Use

1. Update `terraform.tfvars` with production settings
2. Configure monitoring and alerting
3. Set up CI/CD pipeline integration
4. Document operational procedures
5. Train team on monitoring/troubleshooting

---

## Resources

**Project Documentation:**
- Terraform README: `../README.md`
- Status and progress: `../STATUS.md`
- Architecture docs: `../../docs/architecture.md`
- Pattern 2 details: `../../docs/pattern-2.md`

**AWS Console Links:**
```bash
# Step Functions
terraform output pattern2_state_machine_console_url

# CloudWatch Dashboard
terraform output pattern2_dashboard_url

# Lambda Functions
echo "https://console.aws.amazon.com/lambda/home?region=$(terraform output -raw aws_region)#/functions"
```

**AWS Service Documentation:**
- [AWS Bedrock](https://docs.aws.amazon.com/bedrock/)
- [Amazon Textract](https://docs.aws.amazon.com/textract/)
- [AWS Step Functions](https://docs.aws.amazon.com/step-functions/)

---

## Support

**For deployment/testing issues:**
1. Check CloudWatch Logs for Lambda functions
2. Review Step Functions execution history
3. Verify IAM permissions and KMS key access
4. Check Bedrock model access status

**For AWS service issues:**
- Contact AWS Support
- Check AWS Service Health Dashboard

**For solution bugs/features:**
- Open GitHub issue
- Review project documentation
