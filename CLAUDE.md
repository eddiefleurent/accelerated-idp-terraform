# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GenAI Intelligent Document Processing (GenAIIDP) is a serverless AWS solution that combines OCR with generative AI to extract structured data from unstructured documents at scale. The system uses modular processing patterns backed by Step Functions, Lambda, DynamoDB, and AWS AI services (Textract, Bedrock, SageMaker).

**Current Version:** v0.3.20 (latest AWS release)

**Key Architectural Concepts:**
- **Modular Patterns**: Three processing patterns (Pattern 1: BDA, Pattern 2: Textract+Bedrock, Pattern 3: Textract+UDOP+Bedrock) deployed as nested CloudFormation stacks
- **Document-Centric Design**: All services operate on a unified `Document` object that flows through the pipeline, with large data stored in S3 and referenced via URIs
- **Serverless Event-Driven**: S3 uploads trigger Step Functions workflows orchestrating Lambda functions, with EventBridge for asynchronous processing
- **Dual Deployment**: Supports both CloudFormation (SAM with Docker) and Terraform (ZIP-based) deployment

**v0.3.20 Notable Features:**
- **IDP CLI Tool** - Batch processing and configuration iteration (`idp_cli/`)
- **Error Analyzer** - AI-powered troubleshooting for failed documents
- **Agentic Extraction** (Experimental) - Strands-based extraction (CloudFormation/Docker only, not Terraform)
- **Lambda Cost Metering** - Complete cost visibility
- **Claude Sonnet 4.5** and Nova model support

## Build and Test Commands

### Python Code Quality
```bash
# Run linting and formatting (uses ruff)
make lint

# Run only linting with auto-fix
make ruff-lint

# Format code
make format

# CI/CD checks (no modifications)
make lint-cicd

# Check CloudFormation for hardcoded ARN partitions (GovCloud compatibility)
make check-arn-partitions

# Run all tests in idp_common_pkg
make test
# Or directly:
cd lib/idp_common_pkg && pytest
```

### Web UI
```bash
cd src/ui
npm run lint        # ESLint checks
npm run build       # Production build
npm run dev         # Development server
```

### Publishing/Deployment
```bash
# Build and publish to S3 (creates deployment artifacts)
python3 publish.py <bucket_basename> <prefix> <region> [--verbose] [--clean-build]

# Example:
python3 publish.py idp-123456 idp us-east-1 --verbose

# Legacy wrapper (checks dependencies first):
./publish.sh <bucket_basename> <prefix> <region>
```

### Testing Individual Lambda Functions
```bash
cd patterns/pattern-2/  # or pattern-1, pattern-3
sam build
sam local invoke OCRFunction -e ../../testing/OCRFunction-event.json --env-vars ../../testing/env.json
```

### Terraform Deployment (Pattern 1 & Pattern 2)
```bash
cd terraform
terraform init
terraform plan
terraform apply

# See terraform/README.md for complete deployment guide
# Note: Uses ZIP packaging (250MB limit), not Docker containers
```

## Project Structure

### Core Components

**`lib/idp_common_pkg/`** - Shared Python library used by all Lambda functions
- `idp_common/models.py` - Central `Document` class with compression support for Step Functions payload limits
- `idp_common/ocr/` - Textract integration
- `idp_common/classification/` - Document classification (Bedrock or SageMaker)
- `idp_common/extraction/` - Field extraction using Bedrock
- `idp_common/evaluation/` - Accuracy assessment against baselines
- `idp_common/bda/` - Bedrock Data Automation integration
- `idp_common/appsync/` - GraphQL API client for document tracking
- `idp_common/reporting/` - Analytics data storage

**Installation:** Use extras to minimize Lambda package size:
```python
# In Lambda requirements.txt:
../../lib/idp_common_pkg[extraction]  # Only install extraction dependencies
../../lib/idp_common_pkg[all]         # Install everything
```

**`patterns/`** - Processing pattern implementations
- `pattern-1/` - Bedrock Data Automation (BDA) workflow
- `pattern-2/` - Textract → Bedrock Classification → Bedrock Extraction
- `pattern-3/` - Textract → SageMaker UDOP Classification → Bedrock Extraction

Each pattern has its own SAM `template.yaml` defining Lambda functions and Step Functions state machines.

**`src/`**
- `src/lambda/` - Common Lambda functions (e.g., queue processing, reporting)
- `src/ui/` - React web interface (TypeScript, Vite, Amplify)
- `src/api/` - AppSync GraphQL API schema

**`config_library/`** - Configuration templates defining classification prompts, extraction schemas, and few-shot examples

**`terraform/`** - Terraform deployment support (v0.3.20 base)
  - Pattern 1 (BDA) and Pattern 2 (Textract+Bedrock) fully converted
  - ZIP-based Lambda packaging (250MB limit) vs CloudFormation Docker (10GB limit)
  - IDP CLI and Error Analyzer fully compatible
  - Agentic/Strands extraction NOT available (package size limitation)
  - See `terraform/README.md` for deployment guide and feature comparison

**`idp_cli/`** - Command-line tool for batch processing and stack management
  - Works with both CloudFormation and Terraform deployments
  - Enables rapid configuration iteration via `rerun-inference` command
  - See `idp_cli/README.md` for CLI documentation

**`docs/`** - Comprehensive documentation for all features and patterns

## Key Technical Details

### Document Compression Strategy
When documents exceed Step Functions' 256KB payload limit, the system automatically:
1. Stores the full document in S3 at `s3://{working_bucket}/compressed/{step_name}/{execution_id}.json.gz`
2. Passes only metadata through Step Functions
3. Lambda functions use `Document.load_document()` to transparently handle both compressed and inline documents

```python
# Lambda handler pattern:
document = Document.load_document(
    event_data=event["document"],
    working_bucket=working_bucket,
    logger=logger
)
# ... process document ...
return {
    "document": document.serialize_document(
        working_bucket=working_bucket,
        step_name="my_step",
        logger=logger
    )
}
```

### Configuration System
Configuration is stored in DynamoDB with a merge strategy:
- `Default` record: Base configuration
- `Custom` record: User overrides
- Lambda functions call `get_config()` to retrieve merged configuration

**Config Structure:**
- `classification_prompt_template` - Jinja2 template for classification
- `extraction_schema` - JSON schema for field extraction
- `few_shot_examples` - Example documents for few-shot prompting
- `model_config` - Bedrock model settings (modelId, inference parameters)

### SAM Transform to Terraform Mapping
When converting CloudFormation to Terraform:
- `AWS::Serverless::Function` → `aws_lambda_function` + `aws_iam_role` + `aws_cloudwatch_log_group`
- SAM policies like `S3CrudPolicy` → Explicit `aws_iam_policy_document`
- `!Ref`, `!Sub`, `!GetAtt` → Terraform interpolation (`${resource.attribute}`)
- Conditions → `count` or `for_each` with conditional logic

### GovCloud Compatibility
Always use pseudo-parameters for cross-partition compatibility:
- ARNs: `arn:${AWS::Partition}:service:...` (not `arn:aws:...`)
- Service principals: `lambda.${AWS::URLSuffix}` (not `lambda.amazonaws.com`)

The `make check-arn-partitions` command validates this.

### Human-in-the-Loop (HITL)
Patterns 1 and 2 support Amazon A2I integration. When deploying multiple patterns with HITL, reuse the same private workteam ARN (AWS account limits).

## Development Patterns

### Adding a New Lambda Function
1. Create function directory in appropriate pattern: `patterns/pattern-X/src/my_function/`
2. Add `requirements.txt` with only needed idp_common extras
3. Define function in pattern's `template.yaml`:
   ```yaml
   MyFunction:
     Type: AWS::Serverless::Function
     Properties:
       Runtime: python3.12
       CodeUri: src/my_function/
       Handler: app.lambda_handler
       Environment:
         Variables:
           CONFIGURATION_TABLE_NAME: !Ref ConfigurationTable
   ```
4. Use Document-based interfaces from idp_common

### Modifying Processing Logic
Processing patterns are defined in Step Functions state machines. Lambda functions should:
1. Accept `event["document"]` as input
2. Load document: `Document.load_document(event["document"], working_bucket, logger)`
3. Process and update the Document object
4. Return serialized document: `document.serialize_document(working_bucket, step_name, logger)`

### Adding Configuration Options
1. Update config schema in `config_library/pattern-X/`
2. Modify `idp_common/config.py` if new configuration structure is needed
3. Update Lambda functions to read new config fields via `get_config()`

### Testing Changes
1. Unit tests: `pytest lib/idp_common_pkg/tests/`
2. Local Lambda tests: `sam build && sam local invoke`
3. Integration tests: Deploy to test account and use sample PDFs from `samples/`

## Important Files

- `template.yaml` - Main CloudFormation stack (orchestrates nested pattern stacks)
- `patterns/pattern-X/template.yaml` - Pattern-specific resources
- `lib/idp_common_pkg/idp_common/models.py` - Core Document model
- `publish.py` - Build orchestrator (validates, builds, publishes)
- `Makefile` - Code quality commands
- `ruff.toml` - Python linting/formatting configuration
- `VERSION` - Current version (0.3.20), used in CloudFormation descriptions

## Coding Standards

- **Python**: PEP 8 via ruff (line length 88, Python 3.9 target)
- **JavaScript/TypeScript**: ESLint configuration in `src/ui/.eslintrc`
- **Commit Messages**: Clear, descriptive messages following project conventions
- **Documentation**: Update relevant docs in `docs/` for functionality changes
- **IAM**: Request minimum necessary permissions (least privilege)

## Known Issues and Gotchas

### Bedrock Model Access
Before deployment, request access to:
- Amazon: All Nova models + Titan Text Embeddings V2
- Anthropic: Claude 3.x and 4.x models

### Lambda Package Size
Always use targeted idp_common extras in requirements.txt to avoid bloated packages:
```
# Good (only 15MB):
../../lib/idp_common_pkg[extraction]

# Bad (150MB+):
../../lib/idp_common_pkg[all]
```

### CloudFormation Nested Stack Limits
The solution uses nested stacks to work around CloudFormation's 500-resource limit. Pattern resources are in separate child stacks referenced from main stack.

## Documentation References

For detailed information:
- Architecture: `docs/architecture.md`
- Deployment: `docs/deployment.md`
- Configuration: `docs/configuration.md`
- Pattern 1 (BDA): `docs/pattern-1.md`
- Pattern 2 (Textract+Bedrock): `docs/pattern-2.md`
- Pattern 3 (UDOP): `docs/pattern-3.md`
- Classification: `docs/classification.md`
- Extraction: `docs/extraction.md`
- Evaluation: `docs/evaluation.md`
- IDP Common Library: `lib/idp_common_pkg/README.md`

## Contributing

See `CONTRIBUTING.md` for:
- Development environment setup
- Branching strategy (use `feature/`, `fix/`, `docs/` prefixes)
- Pull request process
- Security issue reporting

## Support and Contact

- Report GenAIIDP solution issues: Use GitHub Issues
- AWS Service issues: Contact AWS Support
- Security vulnerabilities: http://aws.amazon.com/security/vulnerability-reporting/
