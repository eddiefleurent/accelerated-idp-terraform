# Terraform Infrastructure for GenAI IDP

This directory contains Terraform configurations for deploying the GenAI Intelligent Document Processing accelerator.

## Status

✅ **v0.3.20 Base:** Rebased on AWS GenAI IDP v0.3.20 (latest release)
✅ **Complete:** Pattern 2 (Textract + Bedrock) + Main Stack Core
✅ **Tested:** End-to-end workflow validated successfully in multiple regions

**See** `STATUS.md` for deployment details and `TASKS.md` for future phases.

---

## Version 0.3.20 Features

### ✅ Supported with Terraform Deployment

**IDP CLI Tool** - Command-line interface for batch processing and stack management:
- Deploy/update/delete stacks programmatically
- Batch document processing from local directories or S3
- Selective reprocessing with `rerun-inference` command
- Live progress monitoring with rich terminal UI
- Evaluation workflow for accuracy testing
- Works seamlessly with Terraform-deployed stacks

**Error Analyzer** - AI-powered troubleshooting for failed documents:
- Natural language query interface for diagnosing failures
- Root cause analysis using Claude Sonnet 4 and Strands agent framework
- Multi-source data correlation (CloudWatch, DynamoDB, Step Functions)
- Accessible via Web UI "Troubleshoot" button
- Works with both CloudFormation and Terraform deployments

**Extraction Results in Summarization** - Context-aware document summaries referencing extracted fields

**Lambda Cost Metering** - Complete cost visibility tracking invocation and GB-seconds costs

**Enhanced Models** - Claude Sonnet 4.5, Nova models, and all v0.3.20 model additions

### ❌ Not Available (Docker Deployment Required)

**Agentic Extraction with Strands** - Experimental feature requiring Docker deployment:
- **Why Not Available:** Package size exceeds 250MB ZIP limit (Strands dependencies ~500MB+)
- **Terraform Deployment:** Uses ZIP + Lambda Layer approach (250MB limit)
- **CloudFormation Deployment:** Uses Docker containers (10GB limit) via CodeBuild
- **Impact:** Traditional Bedrock extraction remains fully functional
- **Alternative:** Use CloudFormation deployment for Strands/Agentic features

### Deployment Method Comparison

| Feature | Terraform (ZIP) | CloudFormation (Docker) |
|---------|-----------------|-------------------------|
| Traditional Extraction | ✅ Fully supported | ✅ Fully supported |
| IDP CLI Tool | ✅ Fully supported | ✅ Fully supported |
| Error Analyzer | ✅ Fully supported | ✅ Fully supported |
| Agentic/Strands Extraction | ❌ Package too large | ✅ Supported (experimental) |
| Lambda Code Visibility | ✅ Viewable in AWS Console | ❌ Container images not viewable |
| Package Size Limit | 250MB (ZIP) | 10GB (Docker) |
| Build Complexity | Simpler (ZIP files) | More complex (Docker + CodeBuild) |
| Iteration Speed | Faster | Slower |

---

## IDP CLI Integration

The IDP CLI tool works seamlessly with Terraform-deployed stacks for batch processing and configuration iteration.

### Installation

```bash
cd idp_cli
pip install -e .
```

### Using CLI with Terraform Stacks

```bash
# Get stack name from Terraform output
STACK_NAME=$(cd terraform && terraform output -raw stack_name)

# Process documents from local directory
idp-cli process \
  --stack-name $STACK_NAME \
  --source ./my-documents/ \
  --download-results ./results/

# Rerun classification/extraction after config changes (cost optimization!)
idp-cli rerun-inference \
  --stack-name $STACK_NAME \
  --document-ids doc-123 doc-456 \
  --step classification

# Check processing status
idp-cli status --stack-name $STACK_NAME

# Deploy or update Terraform-managed stack (optional - use terraform directly)
idp-cli deploy --stack-name $STACK_NAME --pattern-2
```

### CLI Workflow for Configuration Iteration

The CLI's `rerun-inference` command enables rapid configuration testing:

1. Deploy infrastructure with Terraform
2. Load initial configuration: `python3 testing/load_config.py ...`
3. Process test documents: `idp-cli process --stack-name $STACK_NAME --source ./docs/`
4. Review results in Web UI or locally
5. Update configuration in DynamoDB
6. **Rerun extraction ONLY** (skips expensive OCR): `idp-cli rerun-inference --step extraction`
7. Compare results and iterate

**Cost Savings:** Rerunning only extraction/classification reuses existing OCR data, avoiding Textract API costs.

### Evaluation Workflow with CLI

```bash
# 1. Process documents
idp-cli process --stack-name $STACK_NAME --source ./test-docs/

# 2. Manually validate and correct results in Web UI

# 3. Mark corrected documents as baselines
idp-cli baseline create --document-ids doc-1 doc-2 doc-3

# 4. Reprocess with updated config
idp-cli rerun-inference --step classification

# 5. Evaluate against baseline
idp-cli evaluate --stack-name $STACK_NAME

# 6. View evaluation metrics
idp-cli evaluate report --format markdown
```

See `idp_cli/README.md` for complete CLI documentation.

---

## Quick Start

### Prerequisites

**Development Tools:**
- Terraform >= 1.5.0
- AWS CLI configured with appropriate credentials
- Git (for version control)

**AWS Resources Required:**
- **KMS Key** - For encryption at rest (provide ARN in tfvars)
- **Bedrock Data Automation Project** - Must be created separately (provide ARN)
- **Bedrock Model Access** - Request access to required models (see main README)

**Optional Resources:**
- **SageMaker A2I Flow Definition** - For Human-in-the-Loop review
- **AppSync API** - For document tracking (provide URL and ARN)
- **Evaluation Baseline Bucket** - Pre-existing S3 bucket or create new

### Deploy POC

```bash
# 1. Navigate to terraform directory
cd terraform

# 2. Configure variables (if not already done)
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Deploy infrastructure
./deploy.sh
```

The `deploy.sh` script will:
1. Check prerequisites (terraform, aws cli, credentials)
2. Initialize Terraform
3. Validate configuration
4. Check formatting
5. Create execution plan
6. Deploy infrastructure (with confirmation)

Expected deployment time: 5-10 minutes for 212 resources (includes IAM policies, CloudWatch alarms, and supporting infrastructure)

### Load Configuration (Required Post-Deployment Step)

After infrastructure deployment completes, load the default configuration:

```bash
cd testing

# Load lending-package configuration (recommended for first deployment)
python3 load_config.py \
  --config-file ../config_library/pattern-2/lending-package-sample/config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --region us-west-2
```

**See [Configuration Management](#configuration-management) section for details.**

### Destroy Infrastructure

```bash
cd terraform
./destroy.sh
```

The `destroy.sh` script will:
1. Empty all S3 buckets (to allow deletion)
2. Clean up CloudWatch log groups
3. Run `terraform destroy`
4. Verify cleanup of any stragglers
5. Schedule KMS key for deletion (7-day waiting period)

**⚠️ Important:** The destroy script requires typing `DELETE EVERYTHING` to confirm deletion

---

## What Gets Deployed

### Pattern 2: Bedrock Classification + Extraction (26 CFN → 90 TF resources)

**Lambda Functions (9):**
- OCRFunction - Textract integration for OCR
- ClassificationFunction - Bedrock document classification
- ExtractionFunction - Bedrock field extraction
- AssessmentFunction - Quality scoring
- ProcessResultsFunction - Result aggregation
- HITLWaitFunction - Check HITL status
- HITLStatusUpdateFunction - Update HITL status
- HITLProcessLambdaFunction - Process HITL completion
- SummarizationFunction - Document summarization

**Infrastructure:**
- 1 Step Functions State Machine (OCR → Classification → Extraction → HITL → Summarization)
- 3 EventBridge Resources (HITL event rule + target + permission)
- 1 CloudWatch Dashboard (15 metrics widgets)
- 2 Configuration Custom Resources (schema + default config in DynamoDB)
- 9 IAM Roles, 10 CloudWatch Log Groups

**Features:**
- Textract OCR integration
- Bedrock classification and extraction
- Human-in-the-Loop via SageMaker A2I
- Multi-modal classification (text + image)
- Comprehensive monitoring dashboard

---

### Main Stack: Core Infrastructure (31 CFN → 80 TF resources)

**Lambda Functions (9):**

*Queue/Workflow (3):*
- QueueSenderFunction - S3 → SQS event routing
- QueueProcessorFunction - SQS → Step Functions orchestration
- WorkflowTrackerFunction - Metrics and monitoring

*Configuration/Setup (4):*
- ConfigurationCopyFunction - Copy config files to S3
- UpdateConfigurationFunction - Manage DynamoDB config
- InitializeConcurrencyTableLambda - Initialize counters
- LookupFunction - Document status queries

*Data/Reporting (2):*
- SaveReportingDataFunction - Analytics data storage
- EvaluationFunction - Baseline comparison

**Infrastructure:**
- 3 S3 Buckets (Configuration, EvaluationBaseline, WebUI)
- 2 DynamoDB Tables (ConcurrencyTable, ConfigurationTable)
- 4 SQS Queues with DLQs
- 3 EventBridge Rules
- 1 SNS Topic (CloudWatch alarms with optional email)
- 1 Lambda Layer (idp_common shared code)
- 8 Glue Resources (database, 4 tables, crawler, security config, IAM role)
- 3 Custom Resource Invocations (via null_resource)

**Features:**
- Event-driven document processing pipeline
- Configuration management with DynamoDB merge strategy
- Glue Data Catalog for Athena analytics
- Dead letter queues for error handling
- KMS encryption throughout
- SNS notifications for CloudWatch alarms

---

## What You Can Do

### Supported Use Cases ✅

**Pattern 2 (Textract/Bedrock) Workflow:**
- Upload documents to input bucket
- Textract OCR extraction
- Bedrock document classification
- Bedrock field extraction
- Quality assessment
- Human-in-the-Loop review (if A2I configured)
- Document summarization
- Results stored in S3 + DynamoDB

**System Features:**
- Configuration management (DynamoDB with merge strategy)
- Document status lookup (via LookupFunction)
- Glue Data Catalog for analytics (Athena queries)
- CloudWatch monitoring and dashboards
- Cost tracking and metering analysis

**Access Methods:**
- AWS CLI / SDK
- Direct S3 uploads
- Lambda invocations
- Step Functions console

**Status:** ✅ Deployed and tested in us-west-2

---

### Not Yet Available ❌

**Full Solution Components (Not Converted):**
- ❌ Web UI for document upload/management
- ❌ User authentication (Cognito)
- ❌ GraphQL API for real-time tracking (AppSync)
- ❌ CloudFront CDN for web hosting
- ❌ WAF for security

**Deferred:**
- ⚪ Pattern 3 SageMaker UDOP endpoints (advanced ML)

**See** `TASKS.md` for future phases

---

## Project Structure

```
terraform/
├── README.md                    # This file - deployment guide
├── TASKS.md                     # Remaining work and future phases
├── STATUS.md                    # Current progress and completed work
├── main.tf                      # Root module - orchestrates all resources
├── variables.tf                 # Input variables
├── outputs.tf                   # Output values (147 outputs)
├── terraform.tfvars.example     # Example variable values
├── terraform.tfvars             # Your configuration (gitignored)
├── backend.tf                   # Remote state configuration
├── versions.tf                  # Terraform and provider constraints
├── configuration_functions.tf   # Configuration management resources
├── deploy.sh                    # Deployment automation script
├── destroy.sh                   # Teardown automation script
└── modules/
    ├── s3/                      # S3 bucket with KMS encryption
    ├── dynamodb/                # DynamoDB table configuration
    ├── lambda/                  # Lambda function with IAM roles
    ├── step_functions/          # Step Functions state machine
    └── glue/                    # Glue Data Catalog resources
```

---

## State Management

### Local State (Default)
By default, Terraform state is stored locally in `terraform.tfstate`. Suitable for:
- Development and testing
- Single-user deployments
- POC environments

**Note**: Local state files contain sensitive information and are excluded via `.gitignore`

### Remote State (Recommended for Production)
For team environments and production deployments, configure remote state in `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "your-terraform-state-bucket"
    key            = "genai-idp/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-locks"
    kms_key_id     = "arn:aws:kms:us-west-2:ACCOUNT_ID:key/KEY_ID"
  }
}
```

Benefits: State locking, encryption, collaboration, versioning

---

## Post-Deployment

After successful deployment, Terraform outputs important resource information:

**S3 Buckets:**
- Input bucket name and ARN (upload documents here)
- Output bucket name and ARN (retrieve results here)
- Working bucket, Discovery bucket, Configuration bucket

**Lambda Functions:**
- All Lambda function ARNs and names
- IAM role ARNs

**Step Functions:**
- State machine ARN and console URL for Pattern 2
- Monitor document processing executions

**DynamoDB:**
- Table names for tracking, configuration, metadata

**CloudWatch:**
- Dashboard name and URL for Pattern 2
- Log group names for all Lambda functions

**Use these outputs to:**
- Upload documents to input bucket
- Monitor executions in Step Functions console
- Query metadata from DynamoDB tables
- View operational metrics in CloudWatch dashboards
- Review logs in CloudWatch

---

## Configuration Management

The IDP solution uses a **DynamoDB-based configuration system** with a merge strategy that combines default and custom settings. This section explains how to load, manage, and customize configurations.

### Understanding the Configuration System

**Architecture:**
- **Storage**: DynamoDB table (`ConfigurationTable`) with primary key `Configuration`
- **Merge Strategy**: `Default` + `Custom` = Final runtime configuration
- **Schema Validation**: Separate `Schema` record defines valid configuration structure
- **Source Files**: YAML configurations in `config_library/pattern-2/`

**Configuration Records in DynamoDB:**
- `Default` - Base configuration for classification/extraction prompts and models
- `Custom` - User overrides and customizations (optional)
- `Schema` - JSON schema defining configuration structure

### Initial Configuration Loading

**After deploying infrastructure, you need to load configuration into DynamoDB:**

```bash
cd terraform/testing

# Method 1: Load from config_library YAML (Recommended)
python3 load_config.py \
  ../../config_library/pattern-2/lending-package-sample/config.yaml \
  $(cd .. && terraform output -raw configuration_table_name) \
  us-west-2

# Method 2: Load from custom JSON
python3 json_to_dynamodb.py \
  --json-file my-custom-config.json \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --config-type Default \
  --region us-west-2
```

**Available Sample Configurations:**
- `lending-package-sample/` - Mortgage/loan document processing ⭐ Recommended
- `bank-statement-sample/` - Bank statement field extraction
- `rvl-cdip-package-sample/` - General document classification
- `criteria-validation/` - Compliance criteria validation

### Configuration File Structure

Sample configuration includes:

```yaml
# Classification settings
classification_prompt_template: |
  Analyze this document and classify it into one of these categories:
  - invoice
  - bank_statement
  - loan_application
  ...

# Extraction schema (JSON Schema format)
extraction_schema:
  type: object
  properties:
    invoice_number:
      type: string
      description: Invoice or document number
    ...

# Model configuration
model_config:
  modelId: amazon.nova-lite-v1:0
  temperature: 0.1
  maxTokens: 4096

# Few-shot examples (optional)
few_shot_examples:
  - document_type: invoice
    example: "..."
```

### Viewing Current Configuration

```bash
# Get table name from Terraform
CONFIG_TABLE=$(terraform output -raw configuration_table_name)

# View Default configuration
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --output json | jq '.Item'

# View Custom configuration (if exists)
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Custom"}}' \
  --output json | jq '.Item'

# View Schema
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Schema"}}' \
  --output json | jq '.Item'
```

### Updating Configuration

**Option 1: Re-run load_config.py**
```bash
cd terraform/testing

# Edit YAML file in config_library/
vim ../../config_library/pattern-2/lending-package-sample/config.yaml

# Reload into DynamoDB
python3 load_config.py \
  --config-file ../../config_library/pattern-2/lending-package-sample/config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name) \
  --region us-west-2
```

**Option 2: Direct DynamoDB Update**
```bash
CONFIG_TABLE=$(terraform output -raw configuration_table_name)

# Update model
aws dynamodb update-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --update-expression "SET model_config.modelId = :model" \
  --expression-attribute-values '{":model": {"S": "anthropic.claude-3-sonnet-20240229-v1:0"}}'

# Update temperature
aws dynamodb update-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' \
  --update-expression "SET model_config.temperature = :temp" \
  --expression-attribute-values '{":temp": {"N": "0.2"}}'
```

### Creating Custom Configurations

**To override defaults without modifying the Default record:**

```bash
# Create custom.yaml with only overrides
cat > custom.yaml <<EOF
model_config:
  modelId: anthropic.claude-3-5-sonnet-20241022-v2:0
  temperature: 0.2
  maxTokens: 8000
EOF

# Load as Custom configuration
python3 load_config.py \
  custom.yaml \
  $(terraform output -raw configuration_table_name) \
  us-west-2 \
  Custom
```

**At runtime, the system merges**: `Default` + `Custom` = Final configuration

### Configuration Deployment Notes

**UpdateConfigurationFunction Lambda:**
- Deployed with infrastructure but requires S3-based config files (not included)
- **Current workaround**: Use manual `load_config.py` script instead
- Function designed for CloudFormation Custom Resource pattern
- Terraform uses direct invocation via `null_resource` (experimental)

**Artifact Bucket vs. Manual Loading:**

The solution supports two configuration approaches:

1. **CloudFormation Approach (Not Used in Terraform)**:
   - Copies config files from `config_library/` to artifact S3 bucket during build
   - UpdateConfigurationFunction reads from S3 URIs during stack creation
   - Automatic but tightly coupled to CloudFormation Custom Resource lifecycle

2. **Terraform Approach (Current)**:
   - Configuration files remain in `config_library/` directory
   - User manually runs `load_config.py` script after infrastructure deployment
   - Loads YAML directly into DynamoDB without intermediate S3 storage
   - More flexible, allows choosing appropriate config for use case

**Note**: The artifact bucket (if configured via tfvars) is used for deployment artifacts and working storage, but NOT for configuration loading in the Terraform deployment.

**Why Manual Loading?**
The Terraform deployment does **not** automatically load configuration because:
- Avoids coupling infrastructure deployment to specific document types
- Allows users to choose which sample configuration fits their use case
- Provides flexibility for custom configurations
- Simpler than CloudFormation's S3-based approach

**Future Enhancement:** The UpdateConfigurationFunction could be enhanced to handle missing config files gracefully or accept inline YAML/JSON instead of S3 URIs.

### Troubleshooting Configuration

**Issue: "No configuration found" errors in Lambda logs**

Solution: Load default configuration
```bash
cd terraform/testing
python3 load_config.py \
  --config-file ../../config_library/pattern-2/lending-package-sample/config.yaml \
  --table-name $(cd .. && terraform output -raw configuration_table_name)
```

**Issue: "InvalidConfiguration" during extraction**

Check configuration is valid:
```bash
CONFIG_TABLE=$(terraform output -raw configuration_table_name)
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' | jq '.Item.extraction_schema'
```

**Issue: Wrong model being used**

Verify model configuration:
```bash
CONFIG_TABLE=$(terraform output -raw configuration_table_name)
aws dynamodb get-item \
  --table-name $CONFIG_TABLE \
  --key '{"Configuration": {"S": "Default"}}' | jq '.Item.model_config'
```

**Issue: UpdateConfigurationFunction fails during deployment**

This is expected - see "Configuration Deployment Notes" above. Use manual `load_config.py` instead.

---

## Terraform Variables

### Key Variables

**Required:**
- `stack_name` - Unique name for your deployment
- `aws_region` - AWS region (ensure Bedrock available)
- `aws_account_id` - Your AWS account ID
- `kms_key_arn` - KMS key for encryption

**Optional:**
- `bedrock_bda_project_arn` - Bedrock Data Automation project
- `appsync_graphql_url` - AppSync API URL (if available)
- `appsync_graphql_arn` - AppSync API ARN (if available)
- `sagemaker_a2i_flow_definition_arn` - For HITL support
- `enable_evaluation_baseline` - Enable evaluation feature
- `alerts_email` - Email for CloudWatch alarms
- `post_processing_lambda_arn` - Custom post-processing hook

**See** `terraform.tfvars.example` for full list and defaults

---

## Design Decisions

### KMS Encryption for All S3 Buckets

**Decision:** All 7 S3 buckets use KMS encryption, including WebUI assets bucket.

**Rationale:**
- **Consistency:** Single encryption strategy across all buckets
- **Security:** Centralized key management, rotation, and access control
- **Auditability:** All S3 access logged in CloudTrail via KMS key usage
- **Simplicity:** No special-case logic for different encryption types

**Trade-offs:**
- Minimal cost increase (~$0.03 per 10K requests for KMS API calls)
- Negligible performance impact
- Deviation from CloudFormation template (which uses AES256 for WebUI)

---

## Pattern Selection

### Design Decision: Single Pattern Deployment

**Current Scope:** Pattern 2 only (Textract + Bedrock Classification/Extraction)

**Rationale:**
- AWS SAM design deploys one pattern per stack using CloudFormation conditionals
- Original `queue_processor` Python code has single `STATE_MACHINE_ARN` environment variable
- Multi-pattern POC testing required Python modifications not in original AWS codebase
- Single pattern aligns with AWS design, maintains code compatibility

**Deployment Strategy:**
- **Pattern 2 Selected:** Best for general document processing with OCR + AI
- **Pattern 1:** Would require separate Terraform workspace/deployment
- **Pattern 3:** Deferred (SageMaker ML endpoints)

**Alternative Approaches Evaluated:**
1. Single pattern per deployment ✅ **CHOSEN** - Matches AWS design
2. Multi-pattern with Python routing - Requires modifying AWS-supported code
3. Multi-pattern with infrastructure routing - Added complexity (multiple queues)

**See:** `docs/human-review.md:42` references "deploying multiple patterns" via separate stacks

---

## CloudFormation → Terraform Conversion Notes

### Key Mappings

| CloudFormation | Terraform |
|----------------|-----------|
| `AWS::Serverless::Function` | `aws_lambda_function` + `aws_iam_role` + logs |
| `AWS::DynamoDB::Table` | `aws_dynamodb_table` |
| `AWS::S3::Bucket` | `aws_s3_bucket` + `aws_s3_bucket_*` resources |
| `AWS::Logs::LogGroup` | `aws_cloudwatch_log_group` |
| SAM Policies | Explicit IAM policy documents |
| `!Ref`, `!Sub`, `!GetAtt` | Terraform interpolation (`${resource.attribute}`) |
| Conditions | `count` or `for_each` with conditional logic |

### Key Differences

1. **SAM Transform**: CloudFormation auto-generates resources. Terraform explicitly defines each.
2. **IAM Policies**: SAM provides managed policies. Terraform requires explicit documents.
3. **Intrinsic Functions**: CloudFormation intrinsics become Terraform interpolation.
4. **Conditionals**: CloudFormation conditions become Terraform count/for_each logic.

---

## Best Practices Applied

- **Modular Design**: Resources organized into reusable modules
- **Variable Validation**: Input validation with clear error messages
- **Tagging Strategy**: Consistent tagging across all resources
- **Security**: Encryption at rest, least privilege IAM
- **Observability**: CloudWatch Logs with retention policies
- **State Management**: Local state for POC, remote state for production
- **Automation**: deploy.sh and destroy.sh scripts for repeatable workflows

---

## Architecture Decisions

### Terraform-Native Initialization (2025-10-20)

**Design:** This Terraform deployment uses Terraform-native resources instead of CloudFormation Custom Resources for initialization.

**Changes from CloudFormation:**

1. **Concurrency Counter Initialization**
   - **CloudFormation:** `InitializeConcurrencyTableLambda` Lambda Custom Resource
   - **Terraform:** Native `aws_dynamodb_table_item` resource
   - **File:** `terraform/configuration_functions.tf:384-405`
   - **Benefits:** No Lambda needed, simpler, more reliable, idempotent

2. **Configuration Initialization**
   - **Lambda Function:** Modified `UpdateConfigurationFunction` to work without `cfnresponse` dependency
   - **File:** `src/lambda/update_configuration/index.py`
   - **Approach:** Function detects deployment method and adapts (CloudFormation or Terraform)
   - **Benefits:** Works for Terraform without CloudFormation-specific dependencies

3. **DynamoDB Schema Alignment**
   - **Issue:** CloudFormation and Terraform must use identical DynamoDB schema
   - **Solution:** Both deployments use `'Configuration'` as the primary key
   - **Files Using Standard Key:**
     - `terraform/main.tf` - DynamoDB table definition uses `'Configuration'` as hash_key
     - `src/lambda/update_configuration/index.py` - Lambda operations use `'Configuration'` key
     - `lib/idp_common_pkg/idp_common/config/__init__.py` - Configuration reader uses `'Configuration'` key
     - `lib/idp_common_pkg/idp_common/config/configuration_manager.py` - Configuration manager uses `'Configuration'` key
   - **Impact:** All Lambda functions work identically across CloudFormation and Terraform deployments
   - **Region Support:** Added `region_name` parameter and switched to boto3 client API for better cross-region support

**Why Not Use CloudFormation Custom Resources?**
- `cfnresponse` module only available in CloudFormation execution environment
- Terraform Lambda invocations are direct calls, not custom resource events
- Native Terraform resources are simpler and more reliable

**Migration Note:** If you're migrating from CloudFormation to Terraform, the DynamoDB schema is identical, ensuring seamless compatibility. Both deployment methods use the same `'Configuration'` primary key, allowing direct migration without data transformation.

---

## Troubleshooting

### S3 Bucket Name Conflicts

**Issue:** Bucket names must be globally unique across all AWS accounts
**Solution:** Ensure `stack_name` prefix is unique, or customize bucket names in tfvars

### Bedrock Model Access Denied

**Issue:** Lambda functions cannot invoke Bedrock models
**Solution:** Request access to required models in Bedrock console (see main project README)

### KMS Key Permissions

**Issue:** Services cannot use KMS key
**Solution:** Ensure KMS key policy allows CloudWatch Logs, S3, DynamoDB, SQS, and Lambda

### Lambda Package Size Too Large

**Issue:** Lambda deployment fails due to package size
**Solution:** Use targeted idp_common extras in requirements.txt (see main project CLAUDE.md)

### Missing Pattern 2/3 Features

**Issue:** Trying to use Pattern 2 or Pattern 3 features
**Status:** Pattern 2 is deployed! Pattern 3 deferred (see `TASKS.md` for roadmap)

### Missing Web UI

**Issue:** No web interface available
**Status:** Web UI components not yet converted (see `TASKS.md`)

---

## Testing

```bash
# Validate configuration
terraform validate

# Format code
terraform fmt -recursive

# View execution plan
terraform plan

# Security scanning (optional)
tfsec .
checkov -d .
```

---

## Cleanup

```bash
# Automated teardown with bucket cleanup
./destroy.sh

# Or manual destroy
terraform destroy
```

**Note:** The destroy script handles S3 bucket cleanup automatically and schedules KMS key deletion.

---

## Conversion Progress

| Component | Resources | Status | Scope |
|-----------|-----------|--------|-------|
| **Pattern 2** | 26 | ✅ 100% | **ACTIVE** |
| **Main Stack Core** | 31 | ✅ 100% | **ACTIVE** |
| **Pattern 2 Deployment** | **57** | **✅ 100%** | **Ready** |
| Pattern 1 (BDA) | 28 | ⚪ Available | Separate workspace |
| Cognito Auth | 7 | ❌ 0% | Future |
| AppSync API | 41 | ❌ 0% | Future |
| AppSync Functions | 13 | ❌ 0% | Future |
| CloudFront/WAF | 4 | ❌ 0% | Future |
| Additional Infra | ~30 | ❌ 0% | Future |
| Pattern 3 (SageMaker) | ~25 | ⚪ Deferred | Optional |

**Excluded:** Agent infrastructure (7 resources) - optional Q&A feature

---

## Support

**For issues or questions:**
- `TASKS.md` - Remaining work and roadmap
- `STATUS.md` - Current state and capabilities
- Original CloudFormation templates in `/patterns/`
- Main project documentation in `/docs/`
- CloudWatch Logs for Lambda errors

---

## License

This project follows the same license as the parent GenAI IDP project.
