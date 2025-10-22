# =================================================================================================================================
# Configuration/Setup Resources - Terraform-Native Approach
# This file contains configuration management resources for GenAI IDP Terraform deployment:
#
# Lambda Functions (3):
# 1. ConfigurationCopyFunction - Copies configuration files from artifact bucket to configuration bucket
# 2. UpdateConfigurationFunction - Manages configuration in DynamoDB (works with Terraform and CloudFormation)
# 3. LookupFunction - Queries document processing status
#
# Native Terraform Resources:
# 4. concurrency_counter (aws_dynamodb_table_item) - Initializes workflow counter (replaces Lambda approach)
#
# Design: Uses Terraform-native resources where possible instead of Lambda Custom Resources
# =================================================================================================================================

# ============================================================================
# Configuration Bucket - Stores configuration files for patterns
# ============================================================================

module "config_bucket" {
  source = "./modules/s3"

  bucket_name       = "${var.stack_name}-configuration"
  kms_key_arn       = var.kms_key_id
  enable_versioning = var.enable_s3_versioning
  force_destroy     = var.s3_force_destroy

  lifecycle_rules = [
    {
      id                                 = "delete-old-configs"
      enabled                            = true
      transitions                        = []
      expiration_days                    = var.data_retention_days
      noncurrent_version_expiration_days = 365
    }
  ]

  tags = local.common_tags
}

# Enable EventBridge notifications for configuration bucket
resource "aws_s3_bucket_notification" "config_bucket_notifications" {
  bucket      = module.config_bucket.bucket_id
  eventbridge = true
}

# CORS configuration for web UI access to configuration bucket
resource "aws_s3_bucket_cors_configuration" "config_bucket_cors" {
  bucket = module.config_bucket.bucket_id

  cors_rule {
    allowed_headers = ["Content-Type", "x-amz-content-sha256", "x-amz-date", "Authorization", "x-amz-security-token"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag", "x-amz-server-side-encryption"]
    max_age_seconds = var.cors_max_age_seconds
  }
}

# ============================================================================
# Lambda Function Packages - Configuration/Setup Functions
# ============================================================================

# 1. ConfigurationCopyFunction package (inline code extracted)
data "archive_file" "configuration_copy_package" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_src/configuration_copy_function"
  output_path = "${path.module}/lambda_packages/configuration_copy_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo"]
}

# 2. UpdateConfigurationFunction package
data "archive_file" "update_configuration_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/update_configuration"
  output_path = "${path.module}/lambda_packages/update_configuration_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

# 3. InitializeConcurrencyTableLambda - REMOVED
# No longer needed - using native Terraform aws_dynamodb_table_item instead
# See concurrency_counter resource below for replacement

# 4. LookupFunction package
data "archive_file" "lookup_function_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/lookup_function"
  output_path = "${path.module}/lambda_packages/lookup_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

# ============================================================================
# Lambda Functions - Configuration/Setup
# ============================================================================

# 1. ConfigurationCopyFunction - Copies configuration files during deployment
module "configuration_copy_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-ConfigurationCopyFunction"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 300
  memory_size   = 256

  # Code
  source_code_zip  = data.archive_file.configuration_copy_package.output_path
  source_code_hash = data.archive_file.configuration_copy_package.output_base64sha256

  # Lambda layers
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Environment variables
  environment_variables = {
    LOG_LEVEL = var.log_level
  }

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions
  s3_read_buckets = [
    var.artifact_bucket_name # Read from artifact bucket
  ]
  s3_write_buckets = [
    module.config_bucket.bucket_id # Write to configuration bucket
  ]

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  tags = local.common_tags

  depends_on = [
    module.config_bucket
  ]
}

# 2. UpdateConfigurationFunction - Manages DynamoDB configuration
module "update_configuration_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-UpdateConfigurationFunction"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 30
  memory_size   = 256

  # Code
  source_code_zip  = data.archive_file.update_configuration_package.output_path
  source_code_hash = data.archive_file.update_configuration_package.output_base64sha256

  # Lambda layers
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Environment variables
  environment_variables = {
    LOG_LEVEL                = var.log_level
    CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
  }

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions - Read from artifact, config, and optional custom config buckets
  s3_read_buckets = concat(
    [module.config_bucket.bucket_id],
    var.artifact_bucket_name != "" ? [var.artifact_bucket_name] : [],
    var.custom_config_bucket_name != "" ? [var.custom_config_bucket_name] : []
  )

  # DynamoDB Permissions - Write to configuration table
  dynamodb_tables = [
    module.configuration_table.table_name
  ]

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  tags = local.common_tags

  depends_on = [
    module.configuration_table,
    module.config_bucket
  ]
}

# 3. InitializeConcurrencyTableLambda - REMOVED
# Replaced with native Terraform aws_dynamodb_table_item resource
# See concurrency_counter resource below for simpler, more reliable approach

# 4. LookupFunction - Queries document processing status
module "lookup_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-LookupFunction"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 30
  memory_size   = 256

  # Code
  source_code_zip  = data.archive_file.lookup_function_package.output_path
  source_code_hash = data.archive_file.lookup_function_package.output_base64sha256

  # Tracking table (auto-injects TRACKING_TABLE env var)
  tracking_table_name = module.tracking_table.table_name

  # Environment variables
  environment_variables = {
    LOG_LEVEL = var.log_level
  }

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # DynamoDB Permissions - Read-only from tracking table
  dynamodb_tables = [
    module.tracking_table.table_name
  ]
  dynamodb_read_only = true

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  # Additional IAM permissions - Step Functions access
  additional_policy_statements = [
    {
      Effect = "Allow"
      Action = [
        "states:DescribeExecution",
        "states:GetExecutionHistory"
      ]
      # Permissions for all pattern state machines
      Resource = "arn:${local.partition}:states:${var.aws_region}:${local.account_id}:execution:${var.stack_name}-*"
    }
  ]

  tags = local.common_tags

  depends_on = [
    module.tracking_table
  ]
}

# ============================================================================
# Custom Resource Invocations - DISABLED
# ============================================================================
# These automatic configuration invocations are commented out because:
# 1. config_library/pattern-X/default/ directories don't exist in repository
# 2. Manual configuration loading via load_config.py is more flexible
# 3. Allows users to choose appropriate configuration for their use case
# 4. See terraform/README.md "Configuration Management" section for instructions
# ============================================================================

# DISABLED: Invoke ConfigurationCopyFunction to copy config files
# This fails because default config files don't exist in config_library/
# Use manual loading instead: cd terraform/testing && python3 load_config.py
#
# data "aws_lambda_invocation" "copy_configuration_files" {
#   function_name = module.configuration_copy_function.function_name
#
#   input = jsonencode({
#     RequestType = "Create"
#     ResourceProperties = {
#       SourceBucket = var.artifact_bucket_name
#       SourcePrefix = "${var.artifact_prefix}/config_library"
#       TargetBucket = module.config_bucket.bucket_id
#       TargetPrefix = "config_library"
#       FileList = [
#         "pattern-1/default/config.yaml",
#         "pattern-1/default/config.json",
#         "pattern-2/default/config.yaml",
#         "pattern-2/default/config.json",
#         "pattern-3/default/config.yaml",
#         "pattern-3/default/config.json"
#       ]
#     }
#   })
#
#   depends_on = [
#     module.configuration_copy_function,
#     module.config_bucket
#   ]
# }

# DISABLED: Output for debugging configuration copy results
# output "config_copy_result" {
#   value       = jsondecode(data.aws_lambda_invocation.copy_configuration_files.result)
#   description = "Result of configuration files copy operation"
#   sensitive   = true
# }

# ============================================================================
# Initialize concurrency counter in DynamoDB
# Using native Terraform resource instead of Lambda Custom Resource
# This avoids cfnresponse dependency and is more reliable
# ============================================================================
resource "aws_dynamodb_table_item" "concurrency_counter" {
  table_name = module.concurrency_table.table_name
  hash_key   = "counter_id"

  item = jsonencode({
    counter_id = {
      S = "workflow_counter"
    }
    active_count = {
      N = "0"
    }
  })

  # Use lifecycle to prevent replacement on updates
  lifecycle {
    ignore_changes = [item]
  }

  depends_on = [
    module.concurrency_table
  ]
}

# DISABLED: Update configuration in DynamoDB
# This is disabled because it depends on S3 config files that don't exist
# Use manual loading instead: cd terraform/testing && python3 load_config.py
#
# data "aws_lambda_invocation" "update_configuration" {
#   function_name = module.update_configuration_function.function_name
#
#   input = jsonencode({
#     RequestType = "Create"
#     ResourceProperties = {
#       Schema = "s3://${module.config_bucket.bucket_id}/config_library/pattern-1/default/config.json"
#       Default = {
#         classification = {
#           model = "anthropic.claude-3-sonnet-20240229-v1:0"
#         }
#         extraction = {
#           model = "anthropic.claude-3-sonnet-20240229-v1:0"
#         }
#       }
#       Custom = {
#         Info = "Custom inference settings"
#       }
#       CustomClassificationModelARN = ""
#       CustomExtractionModelARN     = ""
#     }
#     StackId           = "terraform-stack"
#     LogicalResourceId = "ConfigurationUpdate"
#   })
#
#   depends_on = [
#     module.update_configuration_function,
#     module.configuration_table,
#     # data.aws_lambda_invocation.copy_configuration_files  # Also disabled
#   ]
# }

# DISABLED: Output for debugging configuration update results
# output "config_update_result" {
#   value       = jsondecode(data.aws_lambda_invocation.update_configuration.result)
#   description = "Result of DynamoDB configuration update operation"
#   sensitive   = true
# }
