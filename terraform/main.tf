# Main Terraform Configuration - GenAI IDP Test Conversion
# This configuration demonstrates conversion of 3 core services from CloudFormation to Terraform

# Data sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  common_tags = merge(
    {
      Project     = "GenAI-IDP"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Stack       = var.stack_name
    },
    var.additional_tags
  )
}

# ============================================================================
# S3 Buckets
# ============================================================================

# Input Bucket - receives raw documents for processing
module "input_bucket" {
  source = "./modules/s3"

  bucket_name       = var.input_bucket_name
  kms_key_arn       = var.kms_key_id
  enable_versioning = var.enable_s3_versioning
  force_destroy     = var.s3_force_destroy # Controlled by environment

  lifecycle_rules = [
    {
      id      = "transition-old-files"
      enabled = true
      transitions = [
        {
          days          = var.s3_lifecycle_days
          storage_class = "INTELLIGENT_TIERING"
        }
      ]
      expiration_days                    = null
      noncurrent_version_expiration_days = 365
    }
  ]

  enable_intelligent_tiering = true

  tags = local.common_tags
}

# Discovery Bucket - stores documents for discovery processing
module "discovery_bucket" {
  source = "./modules/s3"

  bucket_name       = var.discovery_bucket_name
  kms_key_arn       = var.kms_key_id
  enable_versioning = var.enable_s3_versioning
  force_destroy     = var.s3_force_destroy # Controlled by environment

  lifecycle_rules = [
    {
      id      = "archive-discovery-files"
      enabled = true
      transitions = [
        {
          days          = var.s3_lifecycle_days
          storage_class = "GLACIER_IR"
        }
      ]
      expiration_days                    = null
      noncurrent_version_expiration_days = 365
    }
  ]

  tags = local.common_tags
}

# Working Bucket - for intermediate processing files
module "working_bucket" {
  source = "./modules/s3"

  bucket_name       = var.working_bucket_name
  kms_key_arn       = var.kms_key_id
  enable_versioning = var.enable_s3_versioning
  force_destroy     = var.s3_force_destroy # Controlled by environment

  lifecycle_rules = [
    {
      id      = "transition-old-versions"
      enabled = true
      transitions = [
        {
          days          = var.s3_lifecycle_days
          storage_class = "INTELLIGENT_TIERING"
        }
      ]
      expiration_days                    = null
      noncurrent_version_expiration_days = 365
    }
  ]

  enable_intelligent_tiering = true

  tags = local.common_tags
}

# Output Bucket - for final processed results
module "output_bucket" {
  source = "./modules/s3"

  bucket_name       = var.output_bucket_name
  kms_key_arn       = var.kms_key_id
  enable_versioning = var.enable_s3_versioning
  force_destroy     = var.s3_force_destroy # Controlled by environment

  lifecycle_rules = [
    {
      id      = "archive-old-results"
      enabled = true
      transitions = [
        {
          days          = var.s3_lifecycle_days
          storage_class = "GLACIER_IR"
        },
        {
          days          = var.s3_lifecycle_days * 2
          storage_class = "DEEP_ARCHIVE"
        }
      ]
      expiration_days                    = null
      noncurrent_version_expiration_days = 730
    }
  ]

  tags = local.common_tags
}

# Evaluation Baseline Bucket - stores baseline/ground truth data for accuracy evaluation (conditional)
# Create a new bucket ONLY if evaluation_baseline_bucket_name is NOT provided (empty string)
# If evaluation_baseline_bucket_name is provided, the external bucket will be used instead
module "evaluation_baseline_bucket" {
  count  = var.evaluation_baseline_bucket_name == "" ? 1 : 0 # Create if not provided
  source = "./modules/s3"

  bucket_name       = "${var.stack_name}-evaluation-baseline"
  kms_key_arn       = var.kms_key_id
  enable_versioning = true
  force_destroy     = false # Protect baseline data

  lifecycle_rules = [] # No expiration for baseline data

  tags = merge(
    local.common_tags,
    {
      Purpose = "Evaluation baseline storage"
    }
  )
}

# WebUI Bucket - stores UI assets (uses KMS encryption for consistency)
module "webui_bucket" {
  source = "./modules/s3"

  bucket_name       = var.webui_bucket_name
  kms_key_arn       = var.kms_key_id
  enable_versioning = true
  force_destroy     = var.s3_force_destroy

  lifecycle_rules = [] # No lifecycle policy for UI assets

  tags = merge(
    local.common_tags,
    {
      Purpose = "WebUI assets storage"
    }
  )
}

# ============================================================================
# DynamoDB Table
# ============================================================================

# Configuration Table - stores configuration for document processing patterns
module "configuration_table" {
  source = "./modules/dynamodb"

  table_name   = "${var.stack_name}-ConfigurationTable"
  billing_mode = var.dynamodb_billing_mode

  # Primary key - must be Configuration to match AWS SAM template
  hash_key  = "Configuration"
  range_key = null

  # Attribute definitions
  attributes = [
    {
      name = "Configuration"
      type = "S" # String
    }
  ]

  # TTL configuration
  ttl_attribute = var.dynamodb_ttl_attribute

  # Backup and recovery
  enable_point_in_time_recovery = var.enable_point_in_time_recovery

  # Encryption
  kms_key_arn = var.kms_key_id

  # Monitoring
  create_alarms = true

  tags = local.common_tags
}

# Discovery Tracking Table - tracks discovery job status and metadata
module "discovery_tracking_table" {
  source = "./modules/dynamodb"

  table_name   = "${var.stack_name}-DiscoveryTrackingTable"
  billing_mode = var.dynamodb_billing_mode

  # Primary key
  hash_key  = "id"
  range_key = null

  # Attribute definitions
  attributes = [
    {
      name = "id"
      type = "S" # String
    }
  ]

  # TTL configuration
  ttl_attribute = var.dynamodb_ttl_attribute

  # Backup and recovery
  enable_point_in_time_recovery = var.enable_point_in_time_recovery

  # Encryption
  kms_key_arn = var.kms_key_id

  # Monitoring
  create_alarms = true

  tags = local.common_tags
}

# Tracking Table - tracks document processing execution state
module "tracking_table" {
  source = "./modules/dynamodb"

  table_name   = "${var.stack_name}-TrackingTable"
  billing_mode = var.dynamodb_billing_mode

  # Primary key (composite) - Using PK/SK pattern for flexible access patterns
  hash_key  = "PK"
  range_key = "SK"

  # Attribute definitions
  attributes = [
    {
      name = "PK"
      type = "S" # String - Partition key (doc#{object_key} or list#{date}#s#{shard})
    },
    {
      name = "SK"
      type = "S" # String - Sort key (none or ts#{timestamp}#id#{timestamp})
    }
  ]

  # TTL configuration
  ttl_attribute = var.dynamodb_ttl_attribute

  # Backup and recovery
  enable_point_in_time_recovery = var.enable_point_in_time_recovery

  # Encryption
  kms_key_arn = var.kms_key_id

  # Optional: DynamoDB Streams
  stream_enabled   = false
  stream_view_type = "NEW_AND_OLD_IMAGES"

  # Monitoring
  create_alarms = true

  tags = local.common_tags
}

# Concurrency Table - tracks active workflow executions for throttling
module "concurrency_table" {
  source = "./modules/dynamodb"

  table_name = "${var.stack_name}-ConcurrencyTable"
  # Note: Using PAY_PER_REQUEST (on-demand) billing instead of var.dynamodb_billing_mode
  # because concurrency tracking has highly unpredictable, spiky access patterns during
  # workflow throttling. On-demand billing is architecturally required for this use case.
  billing_mode = "PAY_PER_REQUEST"

  # Primary key
  hash_key  = "counter_id"
  range_key = null

  # Attribute definitions
  attributes = [
    {
      name = "counter_id"
      type = "S" # String
    }
  ]

  # TTL not needed for this table
  ttl_attribute = null

  # Point-in-time recovery not required for transient concurrency tracking data
  enable_point_in_time_recovery = false

  # Encryption
  kms_key_arn = var.kms_key_id

  # Monitoring
  create_alarms = true

  tags = local.common_tags
}

# ============================================================================
# Lambda Layer - IDP Common Package
# ============================================================================

# Alerts Topic - For CloudWatch alarm notifications
resource "aws_sns_topic" "alerts_topic" {
  name              = "${var.stack_name}-AlertsTopic"
  display_name      = "Workflow Alerts"
  kms_master_key_id = var.kms_key_id

  tags = local.common_tags
}

# Optional: Email subscription for alerts
resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alerts_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts_topic.arn
  protocol  = "email"
  endpoint  = var.alerts_email
}

# ============================================================================
# Evaluation Function - Accuracy evaluation against baseline data
# ============================================================================

# Package the evaluation_function Lambda function code
data "archive_file" "evaluation_function_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/evaluation_function"
  output_path = "${path.module}/lambda_packages/evaluation_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

# Dead Letter Queue for Evaluation Function
resource "aws_sqs_queue" "evaluation_function_dlq" {
  name                       = "${var.stack_name}-EvaluationFunctionDLQ"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 days
  kms_master_key_id          = var.kms_key_id

  tags = local.common_tags
}

# Evaluation Function - Evaluates processed documents against baseline/ground truth data
module "evaluation_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-EvaluationFunction"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 900
  memory_size   = 3008

  # Code
  source_code_zip  = data.archive_file.evaluation_function_package.output_path
  source_code_hash = data.archive_file.evaluation_function_package.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Dead letter queue
  dead_letter_queue_arn = aws_sqs_queue.evaluation_function_dlq.arn

  # Environment variables matching CloudFormation
  environment_variables = merge(
    {
      LOG_LEVEL                    = var.log_level
      METRIC_NAMESPACE             = var.stack_name
      PROCESSING_OUTPUT_BUCKET     = module.output_bucket.bucket_id
      EVALUATION_OUTPUT_BUCKET     = module.output_bucket.bucket_id
      BASELINE_BUCKET              = var.evaluation_baseline_bucket_name != "" ? var.evaluation_baseline_bucket_name : module.evaluation_baseline_bucket[0].bucket_id
      CONFIGURATION_TABLE_NAME     = module.configuration_table.table_name
      WORKING_BUCKET               = module.working_bucket.bucket_id
      REPORTING_BUCKET             = var.reporting_bucket_name
      SAVE_REPORTING_FUNCTION_NAME = var.save_reporting_function_name
    },
    # Conditional AppSync variables
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions
  s3_read_buckets = concat(
    [
      module.output_bucket.bucket_id,
      module.working_bucket.bucket_id
    ],
    # Evaluation baseline bucket (conditional)
    var.evaluation_baseline_bucket_name != "" ? [
      var.evaluation_baseline_bucket_name
      ] : [
      module.evaluation_baseline_bucket[0].bucket_id
    ]
  )
  s3_write_buckets = [
    module.output_bucket.bucket_id,
    module.working_bucket.bucket_id
  ]

  # DynamoDB Permissions
  dynamodb_tables = [
    module.tracking_table.table_name,
    module.configuration_table.table_name
  ]

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  # Additional IAM permissions
  additional_policy_statements = concat(
    # Lambda invoke permissions (for SaveReportingDataFunction if configured)
    var.save_reporting_function_name != "" ? [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${var.save_reporting_function_name}"
      }
    ] : [],
    # SQS permissions for DLQ
    [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.evaluation_function_dlq.arn
      }
    ]
  )

  tags = local.common_tags

  depends_on = [
    module.output_bucket,
    module.working_bucket,
    module.tracking_table,
    module.configuration_table,
    aws_sqs_queue.evaluation_function_dlq,
    aws_lambda_layer_version.idp_common
  ]
}

# ============================================================================
# SaveReportingDataFunction - Saves analytics data to reporting bucket
# ============================================================================

# Package the SaveReportingDataFunction Lambda function code
data "archive_file" "save_reporting_data_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/save_reporting_data"
  output_path = "${path.module}/lambda_packages/save_reporting_data.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

# SaveReportingDataFunction - Saves document evaluation analytics data to reporting bucket
module "save_reporting_data_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-SaveReportingDataFunction"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 300
  memory_size   = 1024

  # Code
  source_code_zip  = data.archive_file.save_reporting_data_package.output_path
  source_code_hash = data.archive_file.save_reporting_data_package.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Environment variables matching CloudFormation
  environment_variables = {
    LOG_LEVEL                = var.log_level
    METRIC_NAMESPACE         = var.stack_name
    STACK_NAME               = var.stack_name
    CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
  }

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions
  s3_read_buckets  = [module.output_bucket.bucket_id]
  s3_write_buckets = [var.reporting_bucket_name]

  # DynamoDB Permissions (read-only)
  dynamodb_tables    = [module.configuration_table.table_name]
  dynamodb_read_only = true

  # KMS Encryption
  kms_key_arn = var.kms_key_id

  # Additional IAM policy statements for CloudWatch Metrics and Glue
  additional_policy_statements = [
    {
      Effect   = "Allow"
      Action   = ["cloudwatch:PutMetricData"]
      Resource = ["*"]
    },
    {
      Effect = "Allow"
      Action = [
        "glue:CreateTable",
        "glue:GetTable",
        "glue:UpdateTable",
        "glue:GetDatabase"
      ]
      Resource = [
        "arn:${local.partition}:glue:${var.aws_region}:${local.account_id}:catalog",
        "arn:${local.partition}:glue:${var.aws_region}:${local.account_id}:database/${lower(var.stack_name)}-reporting-db",
        "arn:${local.partition}:glue:${var.aws_region}:${local.account_id}:table/${lower(var.stack_name)}-reporting-db/document_sections_*",
        "arn:${local.partition}:glue:${var.aws_region}:${local.account_id}:table/${lower(var.stack_name)}-reporting-db/metering"
      ]
    }
  ]

  # Permissions boundary (if specified)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Monitoring
  create_alarms      = true
  log_retention_days = var.log_retention_days

  # Tags
  tags = local.common_tags

  depends_on = [
    module.output_bucket,
    module.configuration_table,
    aws_lambda_layer_version.idp_common
  ]
}

# ============================================================================
# Lambda Layer - IDP Common Package
# ============================================================================

# Build the Lambda layer using our build script
# Script location: terraform/scripts/build_lambda_layer.sh
# Expected output: terraform/lambda_layers/idp_common_layer.zip
# This script must be executable and must create the ZIP file for the layer to deploy successfully.
resource "null_resource" "build_lambda_layer" {
  triggers = {
    # Rebuild if setup.py changes (indicates package update)
    setup_py_hash = filemd5("${path.module}/../lib/idp_common_pkg/setup.py")
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -e  # Exit on any error

      # Verify build script exists and is executable
      BUILD_SCRIPT="${path.module}/scripts/build_lambda_layer.sh"
      if [ ! -f "$BUILD_SCRIPT" ]; then
        echo "ERROR: Build script not found at: $BUILD_SCRIPT"
        exit 1
      fi

      if [ ! -x "$BUILD_SCRIPT" ]; then
        echo "ERROR: Build script is not executable: $BUILD_SCRIPT"
        echo "Run: chmod +x $BUILD_SCRIPT"
        exit 1
      fi

      # Run the build script and capture exit code
      echo "Running Lambda layer build script..."
      "$BUILD_SCRIPT"
      BUILD_EXIT_CODE=$?

      if [ $BUILD_EXIT_CODE -ne 0 ]; then
        echo "ERROR: Build script failed with exit code: $BUILD_EXIT_CODE"
        exit $BUILD_EXIT_CODE
      fi

      # Verify the output ZIP was created
      OUTPUT_ZIP="${path.module}/lambda_layers/idp_common_layer.zip"
      if [ ! -f "$OUTPUT_ZIP" ]; then
        echo "ERROR: Expected output ZIP not found at: $OUTPUT_ZIP"
        echo "Build script completed but did not create the layer ZIP file"
        exit 1
      fi

      if [ ! -r "$OUTPUT_ZIP" ]; then
        echo "ERROR: Output ZIP exists but is not readable: $OUTPUT_ZIP"
        exit 1
      fi

      echo "Lambda layer build completed successfully"
      echo "Output: $OUTPUT_ZIP ($(du -h "$OUTPUT_ZIP" | cut -f1))"
    EOT

    working_dir = path.module
  }
}

# Upload Lambda layer to S3 (required for large layers >70MB)
resource "aws_s3_object" "lambda_layer" {
  bucket = module.working_bucket.bucket_id
  key    = "lambda-layers/idp_common_layer.zip"
  source = "${path.module}/lambda_layers/idp_common_layer.zip"
  etag   = filemd5("${path.module}/lambda_layers/idp_common_layer.zip")

  depends_on = [null_resource.build_lambda_layer, module.working_bucket]
}

# Lambda Layer containing idp_common package + dependencies
resource "aws_lambda_layer_version" "idp_common" {
  s3_bucket           = module.working_bucket.bucket_id
  s3_key              = aws_s3_object.lambda_layer.key
  layer_name          = "${var.stack_name}-idp-common"
  description         = "IDP Common package with all Pattern 2 dependencies (ocr, classification, extraction, docs_service, evaluation)"
  compatible_runtimes = [var.lambda_runtime]
  source_code_hash    = fileexists("${path.module}/lambda_layers/idp_common_layer.zip") ? filebase64sha256("${path.module}/lambda_layers/idp_common_layer.zip") : null

  depends_on = [aws_s3_object.lambda_layer]
}

# ============================================================================
# Document Processing Queue Infrastructure
# ============================================================================

# Processing Queue DLQ - captures failed document processing messages
resource "aws_sqs_queue" "document_processing_dlq" {
  name                       = "${var.stack_name}-DocumentProcessingDLQ"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 1209600 # 14 days
  kms_master_key_id          = var.kms_key_id

  tags = local.common_tags
}

# Document Processing Queue - receives documents from queue_sender for processing
resource "aws_sqs_queue" "document_processing_queue" {
  name                       = "${var.stack_name}-DocumentProcessingQueue"
  visibility_timeout_seconds = 900     # Match Lambda timeout
  message_retention_seconds  = 1209600 # 14 days
  kms_master_key_id          = var.kms_key_id

  # Dead letter queue configuration
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.document_processing_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.common_tags
}

# ============================================================================
# Queue Sender Lambda - Receives S3 events and queues documents
# ============================================================================

# Package the queue_sender Lambda function code
data "archive_file" "queue_sender_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/queue_sender"
  output_path = "${path.module}/lambda_packages/queue_sender_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

module "queue_sender_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-QueueSenderFunction"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 60
  memory_size   = 512

  # Code
  source_code_zip  = data.archive_file.queue_sender_package.output_path
  source_code_hash = data.archive_file.queue_sender_package.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Tracking table (auto-injects TRACKING_TABLE env var)
  tracking_table_name = module.tracking_table.table_name

  # Environment variables
  environment_variables = merge(
    {
      QUEUE_URL              = aws_sqs_queue.document_processing_queue.url
      OUTPUT_BUCKET          = module.output_bucket.bucket_id
      DATA_RETENTION_IN_DAYS = tostring(var.data_retention_days)
      LOG_LEVEL              = var.log_level
      BEDROCK_LOG_LEVEL      = var.bedrock_log_level
    },
    # Conditional AppSync variables
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL        = var.appsync_api_url
      DOCUMENT_TRACKING_MODE = "appsync"
      } : {
      DOCUMENT_TRACKING_MODE = "dynamodb"
    }
  )

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions - read from input bucket
  s3_read_buckets = [
    module.input_bucket.bucket_id
  ]

  # DynamoDB Permissions - write to tracking table
  dynamodb_tables = [
    module.tracking_table.table_name
  ]

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  # Additional IAM permissions
  additional_policy_statements = flatten([
    # SQS permissions
    [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:GetQueueUrl"
        ]
        Resource = aws_sqs_queue.document_processing_queue.arn
      }
    ],
    # AppSync permissions (conditional)
    var.appsync_api_url != "" ? [
      {
        Effect   = "Allow"
        Action   = ["appsync:GraphQL"]
        Resource = ["${var.appsync_api_arn}/types/Mutation/*"]
      }
    ] : []
  ])

  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.output_bucket,
    module.tracking_table,
    aws_sqs_queue.document_processing_queue,
    aws_lambda_layer_version.idp_common
  ]
}

# EventBridge Rule - Trigger queue_sender on S3 uploads to input bucket
resource "aws_cloudwatch_event_rule" "s3_upload_rule" {
  name        = "${var.stack_name}-S3UploadRule"
  description = "Trigger QueueSenderFunction when files are uploaded to input bucket"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [module.input_bucket.bucket_id]
      }
    }
  })

  tags = local.common_tags
}

# EventBridge Target - QueueSenderFunction
resource "aws_cloudwatch_event_target" "queue_sender_target" {
  rule      = aws_cloudwatch_event_rule.s3_upload_rule.name
  target_id = "QueueSenderFunction"
  arn       = module.queue_sender_function.function_arn

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600 # 1 hour
  }
}

# Lambda Permission - Allow EventBridge to invoke QueueSenderFunction
resource "aws_lambda_permission" "queue_sender_event_invoke" {
  statement_id  = "AllowExecutionFromS3UploadRule"
  action        = "lambda:InvokeFunction"
  function_name = module.queue_sender_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_upload_rule.arn
}

# S3 Bucket Notification - Enable EventBridge notifications for input bucket
# NOTE: This requires the S3 bucket to have EventBridge enabled
resource "aws_s3_bucket_notification" "input_bucket_notifications" {
  bucket      = module.input_bucket.bucket_id
  eventbridge = true
}

# ============================================================================
# Queue Processor Lambda - Processes documents from queue, triggers Step Functions
# ============================================================================

# Package the queue_processor Lambda function code
data "archive_file" "queue_processor_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/queue_processor"
  output_path = "${path.module}/lambda_packages/queue_processor_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

module "queue_processor_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-QueueProcessor"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 30
  memory_size   = 512

  # Code
  source_code_zip  = data.archive_file.queue_processor_package.output_path
  source_code_hash = data.archive_file.queue_processor_package.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Tracking table (auto-injects TRACKING_TABLE env var)
  tracking_table_name = module.tracking_table.table_name

  # Environment variables
  environment_variables = merge(
    {
      STATE_MACHINE_ARN = aws_sfn_state_machine.pattern2_document_processing.arn
      CONCURRENCY_TABLE = module.concurrency_table.table_name
      MAX_CONCURRENT    = tostring(var.max_concurrent_workflows)
      WORKING_BUCKET    = module.working_bucket.bucket_id
      LOG_LEVEL         = var.log_level
      BEDROCK_LOG_LEVEL = var.bedrock_log_level
    },
    # Conditional AppSync variables
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL        = var.appsync_api_url
      DOCUMENT_TRACKING_MODE = "appsync"
      } : {
      DOCUMENT_TRACKING_MODE = "dynamodb"
    }
  )

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions - read/write from working bucket
  s3_read_buckets = [
    module.working_bucket.bucket_id
  ]
  s3_write_buckets = [
    module.working_bucket.bucket_id
  ]

  # DynamoDB Permissions
  dynamodb_tables = [
    module.tracking_table.table_name,
    module.concurrency_table.table_name
  ]

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  # Additional IAM permissions
  additional_policy_statements = flatten([
    # SQS permissions for consuming from document queue
    [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.document_processing_queue.arn
      }
    ],
    # Step Functions permissions to start executions (Pattern 2 only)
    [
      {
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = aws_sfn_state_machine.pattern2_document_processing.arn
      }
    ],
    # AppSync permissions (conditional)
    var.appsync_api_url != "" ? [
      {
        Effect   = "Allow"
        Action   = ["appsync:GraphQL"]
        Resource = ["${var.appsync_api_arn}/types/Mutation/*"]
      }
    ] : []
  ])

  tags = local.common_tags

  depends_on = [
    module.working_bucket,
    module.tracking_table,
    module.concurrency_table,
    aws_sfn_state_machine.pattern2_document_processing,
    aws_sqs_queue.document_processing_queue,
    aws_lambda_layer_version.idp_common
  ]
}

# SQS Event Source Mapping for QueueProcessor
resource "aws_lambda_event_source_mapping" "queue_processor_sqs" {
  event_source_arn = aws_sqs_queue.document_processing_queue.arn
  function_name    = module.queue_processor_function.function_arn
  batch_size       = 1

  function_response_types = ["ReportBatchItemFailures"]

  depends_on = [
    module.queue_processor_function,
    aws_sqs_queue.document_processing_queue
  ]
}

# ============================================================================
# Workflow Tracker Lambda - Monitors Step Functions executions, updates status
# ============================================================================

# Package the workflow_tracker Lambda function code
data "archive_file" "workflow_tracker_package" {
  type        = "zip"
  source_dir  = "${path.module}/../src/lambda/workflow_tracker"
  output_path = "${path.module}/lambda_packages/workflow_tracker_function.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo", ".pytest_cache", "tests"]
}

# DLQ for WorkflowTracker
resource "aws_sqs_queue" "workflow_tracker_dlq" {
  name                       = "${var.stack_name}-WorkflowTrackerDLQ"
  visibility_timeout_seconds = 30
  message_retention_seconds  = 345600 # 4 days
  kms_master_key_id          = var.kms_key_id

  tags = local.common_tags
}

module "workflow_tracker_function" {
  source = "./modules/lambda"

  function_name = "${var.stack_name}-WorkflowTracker"
  handler       = "index.handler"
  runtime       = var.lambda_runtime
  timeout       = 30
  memory_size   = 512

  # Code
  source_code_zip  = data.archive_file.workflow_tracker_package.output_path
  source_code_hash = data.archive_file.workflow_tracker_package.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Dead letter queue
  dead_letter_queue_arn = aws_sqs_queue.workflow_tracker_dlq.arn

  # Environment variables
  environment_variables = merge(
    {
      CONCURRENCY_TABLE            = module.concurrency_table.table_name
      METRIC_NAMESPACE             = var.stack_name
      OUTPUT_BUCKET                = module.output_bucket.bucket_id
      WORKING_BUCKET               = module.working_bucket.bucket_id
      LOG_LEVEL                    = var.log_level
      BEDROCK_LOG_LEVEL            = var.bedrock_log_level
      REPORTING_BUCKET             = var.reporting_bucket_name
      SAVE_REPORTING_FUNCTION_NAME = var.save_reporting_function_name
    },
    # Conditional AppSync variables
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL        = var.appsync_api_url
      DOCUMENT_TRACKING_MODE = "appsync"
      } : {
      DOCUMENT_TRACKING_MODE = "dynamodb"
    }
  )

  # AWS Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id

  # S3 Permissions - read/write from working bucket
  s3_read_buckets = [
    module.working_bucket.bucket_id
  ]
  s3_write_buckets = [
    module.working_bucket.bucket_id
  ]

  # DynamoDB Permissions
  dynamodb_tables = [
    module.tracking_table.table_name,
    module.concurrency_table.table_name
  ]

  # Security
  kms_key_arn              = var.kms_key_id
  permissions_boundary_arn = var.permissions_boundary_arn

  # Logging
  log_retention_days = var.log_retention_days

  # Monitoring
  create_alarms = true

  # Additional IAM permissions
  additional_policy_statements = flatten([
    # CloudWatch permissions
    [
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ],
    # Lambda invoke permissions (for SaveReportingDataFunction if configured)
    var.save_reporting_function_name != "" ? [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = "arn:${local.partition}:lambda:${var.aws_region}:${local.account_id}:function:${var.save_reporting_function_name}"
      }
    ] : [],
    # AppSync permissions (conditional)
    var.appsync_api_url != "" ? [
      {
        Effect   = "Allow"
        Action   = ["appsync:GraphQL"]
        Resource = ["${var.appsync_api_arn}/types/Mutation/*"]
      }
    ] : [],
    # SQS permissions for DLQ
    [
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage"
        ]
        Resource = aws_sqs_queue.workflow_tracker_dlq.arn
      }
    ]
  ])

  tags = local.common_tags

  depends_on = [
    module.working_bucket,
    module.output_bucket,
    module.tracking_table,
    module.concurrency_table,
    aws_sqs_queue.workflow_tracker_dlq,
    aws_lambda_layer_version.idp_common
  ]
}

# EventBridge Rule - Trigger workflow_tracker on Pattern 2 Step Functions status change
resource "aws_cloudwatch_event_rule" "workflow_state_change_rule" {
  name        = "${var.stack_name}-WorkflowStateChangeRule"
  description = "Trigger WorkflowTracker when Pattern 2 Step Functions execution status changes"
  state       = "ENABLED"

  event_pattern = jsonencode({
    source      = ["aws.states"]
    detail-type = ["Step Functions Execution Status Change"]
    detail = {
      stateMachineArn = [aws_sfn_state_machine.pattern2_document_processing.arn]
      status = [
        "SUCCEEDED",
        "FAILED",
        "TIMED_OUT",
        "ABORTED"
      ]
    }
  })

  tags = local.common_tags
}

# EventBridge Target - WorkflowTracker
resource "aws_cloudwatch_event_target" "workflow_tracker_target" {
  rule      = aws_cloudwatch_event_rule.workflow_state_change_rule.name
  target_id = "WorkflowTrackerFunction"
  arn       = module.workflow_tracker_function.function_arn

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600 # 1 hour
  }
}

# Lambda Permission - Allow EventBridge to invoke WorkflowTracker
resource "aws_lambda_permission" "workflow_tracker_event_invoke" {
  statement_id  = "AllowExecutionFromWorkflowStateChangeRule"
  action        = "lambda:InvokeFunction"
  function_name = module.workflow_tracker_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.workflow_state_change_rule.arn
}

# ============================================================================
# Pattern 2: Textract + Bedrock Classification/Extraction Pipeline
# ============================================================================
# Pattern 2 provides Textract OCR → Bedrock Classification → Bedrock Extraction
# Source: patterns/pattern-2/template.yaml

# OCR Function - Textract document text extraction
data "archive_file" "ocr_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/ocr_function"
  output_path = "${path.module}/lambda_packages/ocr_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "ocr_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-OCRFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = 3008

  # Code
  source_code_zip  = data.archive_file.ocr_function.output_path
  source_code_hash = data.archive_file.ocr_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = merge(
    {
      METRIC_NAMESPACE         = var.stack_name
      MAX_WORKERS              = "20"
      CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
      LOG_LEVEL                = var.log_level
      TRACKING_TABLE           = module.tracking_table.table_name
      WORKING_BUCKET           = module.working_bucket.bucket_id
      DOCUMENT_TRACKING_MODE   = var.appsync_api_url != "" ? "appsync" : "dynamodb"
    },
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id]
  s3_write_buckets = [module.output_bucket.bucket_id, module.working_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.configuration_table.table_name, module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = [
    # Textract permissions for OCR
    {
      Effect = "Allow"
      Action = [
        "textract:DetectDocumentText",
        "textract:AnalyzeDocument"
      ]
      Resource = "*"
    },
    # Bedrock permissions for vision models
    {
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:${local.partition}:bedrock:*::foundation-model/*",
        "arn:${local.partition}:bedrock:*:${local.account_id}:inference-profile/*"
      ]
    }
  ]

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.output_bucket,
    module.configuration_table,
    module.tracking_table
  ]
}

# Classification Function - Bedrock document classification
data "archive_file" "classification_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/classification_function"
  output_path = "${path.module}/lambda_packages/classification_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "classification_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-ClassificationFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = 3008

  # Code
  source_code_zip  = data.archive_file.classification_function.output_path
  source_code_hash = data.archive_file.classification_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = merge(
    {
      METRIC_NAMESPACE         = var.stack_name
      MAX_WORKERS              = "20"
      CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
      LOG_LEVEL                = var.log_level
      TRACKING_TABLE           = module.tracking_table.table_name
      WORKING_BUCKET           = module.working_bucket.bucket_id
      DOCUMENT_TRACKING_MODE   = var.appsync_api_url != "" ? "appsync" : "dynamodb"
    },
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id, module.working_bucket.bucket_id]
  s3_write_buckets = [module.output_bucket.bucket_id, module.working_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.configuration_table.table_name, module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = [
    # Bedrock permissions for document classification
    {
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:${local.partition}:bedrock:*::foundation-model/*",
        "arn:${local.partition}:bedrock:*:${local.account_id}:inference-profile/*"
      ]
    }
  ]

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.output_bucket,
    module.configuration_table,
    module.tracking_table
  ]
}

# Extraction Function - Bedrock field extraction
data "archive_file" "extraction_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/extraction_function"
  output_path = "${path.module}/lambda_packages/extraction_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "extraction_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-ExtractionFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = 3008

  # Code
  source_code_zip  = data.archive_file.extraction_function.output_path
  source_code_hash = data.archive_file.extraction_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = merge(
    {
      METRIC_NAMESPACE         = var.stack_name
      MAX_WORKERS              = "20"
      CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
      LOG_LEVEL                = var.log_level
      TRACKING_TABLE           = module.tracking_table.table_name
      WORKING_BUCKET           = module.working_bucket.bucket_id
      DOCUMENT_TRACKING_MODE   = var.appsync_api_url != "" ? "appsync" : "dynamodb"
    },
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id, module.working_bucket.bucket_id]
  s3_write_buckets = [module.output_bucket.bucket_id, module.working_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.configuration_table.table_name, module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = [
    # Bedrock permissions for field extraction
    {
      Effect = "Allow"
      Action = ["bedrock:InvokeModel"]
      Resource = [
        "arn:${local.partition}:bedrock:*::foundation-model/*",
        "arn:${local.partition}:bedrock:*:${local.account_id}:inference-profile/*"
      ]
    }
  ]

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.output_bucket,
    module.configuration_table,
    module.tracking_table
  ]
}

# Assessment Function - Quality assessment and confidence scoring
data "archive_file" "assessment_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/assessment_function"
  output_path = "${path.module}/lambda_packages/assessment_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "assessment_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-AssessmentFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 1024

  # Code
  source_code_zip  = data.archive_file.assessment_function.output_path
  source_code_hash = data.archive_file.assessment_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = merge(
    {
      METRIC_NAMESPACE         = var.stack_name
      CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
      LOG_LEVEL                = var.log_level
      TRACKING_TABLE           = module.tracking_table.table_name
      WORKING_BUCKET           = module.working_bucket.bucket_id
      DOCUMENT_TRACKING_MODE   = var.appsync_api_url != "" ? "appsync" : "dynamodb"
    },
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id, module.working_bucket.bucket_id, module.output_bucket.bucket_id]
  s3_write_buckets = [module.working_bucket.bucket_id, module.output_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.configuration_table.table_name, module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = flatten([
    [
      # Bedrock permissions for assessment models
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/*",
          "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/*"
        ]
      },
      # CloudWatch metrics (custom namespace)
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ],
    # Conditional AppSync permissions
    var.appsync_api_url != "" && var.appsync_api_arn != "" ? [
      {
        Effect   = "Allow"
        Action   = ["appsync:GraphQL"]
        Resource = ["${var.appsync_api_arn}/types/Mutation/*"]
      }
    ] : []
  ])

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.configuration_table,
    module.tracking_table
  ]
}

# =============================================================================
# Pattern 2 ProcessResults Function - Aggregate and store final results
# =============================================================================

data "archive_file" "pattern2_process_results_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/processresults_function"
  output_path = "${path.module}/lambda_packages/pattern2_process_results_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "pattern2_process_results_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-Pattern2-ProcessResultsFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 1024

  # Code
  source_code_zip  = data.archive_file.pattern2_process_results_function.output_path
  source_code_hash = data.archive_file.pattern2_process_results_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = merge(
    {
      METRIC_NAMESPACE         = var.stack_name
      CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
      LOG_LEVEL                = var.log_level
      TRACKING_TABLE           = module.tracking_table.table_name
      WORKING_BUCKET           = module.working_bucket.bucket_id
      OUTPUT_BUCKET            = module.output_bucket.bucket_id
      DOCUMENT_TRACKING_MODE   = var.appsync_api_url != "" ? "appsync" : "dynamodb"
    },
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id, module.working_bucket.bucket_id]
  s3_write_buckets = [module.output_bucket.bucket_id, module.working_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.configuration_table.table_name, module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = flatten([
    [
      # CloudWatch metrics (custom namespace)
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ],
    # Conditional AppSync permissions
    var.appsync_api_url != "" && var.appsync_api_arn != "" ? [
      {
        Effect   = "Allow"
        Action   = ["appsync:GraphQL"]
        Resource = ["${var.appsync_api_arn}/types/Mutation/*"]
      }
    ] : []
  ])

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.output_bucket,
    module.configuration_table,
    module.tracking_table
  ]
}

# =============================================================================
# Pattern 2 HITL Functions - Human-in-the-Loop workflow support
# =============================================================================

# HITL Wait Function - Polls A2I human loop status
data "archive_file" "pattern2_hitl_wait_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/hitl-wait-function"
  output_path = "${path.module}/lambda_packages/pattern2_hitl_wait_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "hitl_wait_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-Pattern2-HITLWaitFunction"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = 256

  # Code
  source_code_zip  = data.archive_file.pattern2_hitl_wait_function.output_path
  source_code_hash = data.archive_file.pattern2_hitl_wait_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = {
    LOG_LEVEL                       = var.log_level
    SAGEMAKER_A2I_REVIEW_PORTAL_URL = var.sagemaker_a2i_review_portal_url
    WORKING_BUCKET                  = module.working_bucket.bucket_id
  }

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.working_bucket.bucket_id]
  s3_write_buckets = []

  # DynamoDB permissions
  dynamodb_tables    = [module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = [
    # SageMaker A2I permissions to describe human loops
    {
      Effect = "Allow"
      Action = [
        "sagemaker:DescribeHumanLoop"
      ]
      Resource = "arn:${local.partition}:sagemaker:${var.aws_region}:${local.account_id}:human-loop/*"
    }
  ]

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.working_bucket,
    module.tracking_table
  ]
}

# HITL Status Update Function - Updates document status after HITL completion
data "archive_file" "pattern2_hitl_status_update_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/hitl-status-update-function"
  output_path = "${path.module}/lambda_packages/pattern2_hitl_status_update_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "hitl_status_update_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-Pattern2-HITLStatusUpdateFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 512

  # Code
  source_code_zip  = data.archive_file.pattern2_hitl_status_update_function.output_path
  source_code_hash = data.archive_file.pattern2_hitl_status_update_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = {
    LOG_LEVEL      = var.log_level
    WORKING_BUCKET = module.working_bucket.bucket_id
  }

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.working_bucket.bucket_id]
  s3_write_buckets = [module.working_bucket.bucket_id]

  # DynamoDB permissions (none needed for this function)
  dynamodb_tables    = []
  dynamodb_read_only = true

  # Additional IAM policy statements
  additional_policy_statements = []

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.working_bucket
  ]
}

# HITL Process Function - Processes A2I completion events from EventBridge
data "archive_file" "pattern2_hitl_process_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/hitl-process-function"
  output_path = "${path.module}/lambda_packages/pattern2_hitl_process_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "hitl_process_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-Pattern2-HITLProcessLambdaFunction"
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300
  memory_size   = 128

  # Code
  source_code_zip  = data.archive_file.pattern2_hitl_process_function.output_path
  source_code_hash = data.archive_file.pattern2_hitl_process_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = {
    LOG_LEVEL = var.log_level
  }

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id, module.working_bucket.bucket_id]
  s3_write_buckets = [module.output_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = [
    # Step Functions callback permissions
    # SendTask* actions require Resource = "*" per AWS documentation
    # https://docs.aws.amazon.com/step-functions/latest/dg/callback-task-sample-sqs.html
    {
      Effect = "Allow"
      Action = [
        "states:SendTaskSuccess",
        "states:SendTaskFailure"
      ]
      Resource = "*"
    }
  ]

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.output_bucket,
    module.tracking_table
  ]
}

# Summarization Function - Generates document summaries using Bedrock
data "archive_file" "pattern2_summarization_function" {
  type        = "zip"
  source_dir  = "${path.module}/../patterns/pattern-2/src/summarization_function"
  output_path = "${path.module}/lambda_packages/pattern2_summarization_function.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests"]
}

module "summarization_function" {
  source = "./modules/lambda"

  # Basic configuration
  function_name = "${var.stack_name}-Pattern2-SummarizationFunction"
  handler       = "index.handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = 3008

  # Code
  source_code_zip  = data.archive_file.pattern2_summarization_function.output_path
  source_code_hash = data.archive_file.pattern2_summarization_function.output_base64sha256

  # Lambda layer with idp_common package
  lambda_layers = [aws_lambda_layer_version.idp_common.arn]

  # Permissions boundary (if provided)
  permissions_boundary_arn = var.permissions_boundary_arn

  # Environment variables
  environment_variables = merge(
    {
      METRIC_NAMESPACE         = var.stack_name
      CONFIGURATION_TABLE_NAME = module.configuration_table.table_name
      LOG_LEVEL                = var.log_level
      TRACKING_TABLE           = module.tracking_table.table_name
      WORKING_BUCKET           = module.working_bucket.bucket_id
      DOCUMENT_TRACKING_MODE   = var.appsync_api_url != "" ? "appsync" : "dynamodb"
    },
    var.bedrock_guardrail_id != "" && var.bedrock_guardrail_version != "" ? {
      GUARDRAIL_ID_AND_VERSION = "${var.bedrock_guardrail_id}:${var.bedrock_guardrail_version}"
    } : {},
    var.appsync_api_url != "" ? {
      APPSYNC_API_URL = var.appsync_api_url
    } : {}
  )

  # IAM Configuration
  aws_region     = var.aws_region
  aws_account_id = local.account_id
  kms_key_arn    = var.kms_key_id

  # S3 permissions
  s3_read_buckets  = [module.input_bucket.bucket_id, module.working_bucket.bucket_id]
  s3_write_buckets = [module.output_bucket.bucket_id, module.working_bucket.bucket_id]

  # DynamoDB permissions
  dynamodb_tables    = [module.configuration_table.table_name, module.tracking_table.table_name]
  dynamodb_read_only = false

  # Additional IAM policy statements
  additional_policy_statements = flatten([
    [
      # Bedrock InvokeModel permissions
      {
        Effect = "Allow"
        Action = ["bedrock:InvokeModel"]
        Resource = [
          "arn:${local.partition}:bedrock:${var.aws_region}::foundation-model/*",
          "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:inference-profile/*"
        ]
      },
      # CloudWatch metrics (custom namespace)
      {
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = "*"
      }
    ],
    # Bedrock Guardrail permissions (conditional)
    var.bedrock_guardrail_id != "" && var.bedrock_guardrail_version != "" ? [
      {
        Effect   = "Allow"
        Action   = ["bedrock:ApplyGuardrail"]
        Resource = "arn:${local.partition}:bedrock:${var.aws_region}:${local.account_id}:guardrail/${var.bedrock_guardrail_id}"
      }
    ] : [],
    # AppSync permissions (conditional)
    var.appsync_api_url != "" && var.appsync_api_arn != "" ? [
      {
        Effect   = "Allow"
        Action   = ["appsync:GraphQL"]
        Resource = ["${var.appsync_api_arn}/types/Mutation/*"]
      }
    ] : []
  ])

  # CloudWatch & monitoring
  log_retention_days = var.log_retention_days
  create_alarms      = var.create_step_functions_alarms

  # Tagging
  tags = local.common_tags

  depends_on = [
    module.input_bucket,
    module.working_bucket,
    module.output_bucket,
    module.configuration_table,
    module.tracking_table
  ]
}

# ==============================================================================
# Pattern 2: EventBridge Integration for HITL
# ==============================================================================

# EventBridge Rule - Captures A2I HumanLoop completion events
resource "aws_cloudwatch_event_rule" "pattern2_hitl_event_rule" {
  name        = "${var.stack_name}-Pattern2-HITL-EventRule"
  description = "Trigger HITL processing when A2I human review completes"

  event_pattern = jsonencode({
    source      = ["aws.sagemaker"]
    detail-type = ["SageMaker A2I HumanLoop Status Change"]
    detail = {
      humanLoopStatus = ["Completed", "Failed", "Stopped"]
    }
  })

  tags = local.common_tags
}

# EventBridge Target - Routes events to HITLProcessLambdaFunction
resource "aws_cloudwatch_event_target" "pattern2_hitl_process_target" {
  rule      = aws_cloudwatch_event_rule.pattern2_hitl_event_rule.name
  target_id = "HITLProcessTarget"
  arn       = module.hitl_process_function.function_arn

  retry_policy {
    maximum_retry_attempts       = 3
    maximum_event_age_in_seconds = 3600 # 1 hour
  }
}

# Lambda Permission - Allows EventBridge to invoke the function
resource "aws_lambda_permission" "pattern2_hitl_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge-Pattern2-HITL"
  action        = "lambda:InvokeFunction"
  function_name = module.hitl_process_function.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.pattern2_hitl_event_rule.arn
}

# ==============================================================================
# Pattern 2: Step Functions State Machine
# ==============================================================================

# CloudWatch Log Group for state machine
resource "aws_cloudwatch_log_group" "pattern2_state_machine" {
  name              = "/aws/vendedlogs/states/${var.stack_name}-Pattern2-StateMachine"
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_id

  tags = local.common_tags
}

# IAM Role for state machine
resource "aws_iam_role" "pattern2_state_machine" {
  name = "${var.stack_name}-Pattern2-StateMachineRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "states.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  tags = local.common_tags
}

# IAM Policy for state machine
resource "aws_iam_role_policy" "pattern2_state_machine" {
  name = "${var.stack_name}-Pattern2-StateMachinePolicy"
  role = aws_iam_role.pattern2_state_machine.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Lambda invocations for all 8 Pattern 2 functions
      {
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = [
          module.ocr_function.function_arn,
          module.classification_function.function_arn,
          module.extraction_function.function_arn,
          module.assessment_function.function_arn,
          module.pattern2_process_results_function.function_arn,
          module.hitl_wait_function.function_arn,
          module.hitl_status_update_function.function_arn,
          module.summarization_function.function_arn
        ]
      },
      # CloudWatch Logs for state machine logging
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
      # X-Ray tracing
      {
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords"
        ]
        Resource = "*"
      }
    ]
  })
}

# State machine - orchestrates Pattern 2 document processing workflow
resource "aws_sfn_state_machine" "pattern2_document_processing" {
  name     = "${var.stack_name}-Pattern2-StateMachine"
  role_arn = aws_iam_role.pattern2_state_machine.arn

  # Use templatefile to inject function ARNs into state machine definition
  definition = templatefile("${path.module}/state_machines/pattern2_definition.asl.json.tpl", {
    ocr_function_arn                = module.ocr_function.function_arn
    classification_function_arn     = module.classification_function.function_arn
    extraction_function_arn         = module.extraction_function.function_arn
    assessment_function_arn         = module.assessment_function.function_arn
    process_results_function_arn    = module.pattern2_process_results_function.function_arn
    hitl_wait_function_arn          = module.hitl_wait_function.function_arn
    hitl_status_update_function_arn = module.hitl_status_update_function.function_arn
    summarization_function_arn      = module.summarization_function.function_arn
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.pattern2_state_machine.arn}:*"
    include_execution_data = true
    level                  = "ALL"
  }

  tracing_configuration {
    enabled = true
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.pattern2_state_machine,
    aws_cloudwatch_log_group.pattern2_state_machine
  ]
}

# ==============================================================================
# Pattern 2: CloudWatch Dashboard
# ==============================================================================

# CloudWatch Dashboard for Pattern 2 monitoring
resource "aws_cloudwatch_dashboard" "pattern2_dashboard" {
  dashboard_name = "${var.stack_name}-${var.aws_region}-Pattern2-Subset"

  dashboard_body = jsonencode({
    widgets = [
      # Widget 1: Documents per Minute
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Documents per Minute" }],
            ["${var.stack_name}", "InputDocuments", { id = "m1", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Input Documents (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 2: Pages per Minute
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Pages per Minute" }],
            ["${var.stack_name}", "InputDocumentPages", { id = "m1", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Input Document Pages (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 3: Blank placeholder
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = []
          region  = var.aws_region
          title   = "Blank"
          view    = "timeSeries"
          period  = 60
          yAxis = {
            left = {
              label = "N/A"
            }
          }
        }
      },

      # Widget 4: Input Tokens (TPM with cache metrics)
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Tokens per Minute (TPM)" }],
            [{ expression = "m2/PERIOD(m1)*60", label = "Cache Read TPM" }],
            [{ expression = "m3/PERIOD(m1)*60", label = "Cache Write TPM" }],
            ["${var.stack_name}", "InputTokens", { id = "m1", stat = "Sum", visible = false }],
            [".", "CacheReadInputTokens", { id = "m2", stat = "Sum", visible = false }],
            [".", "CacheWriteInputTokens", { id = "m3", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Input Tokens (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 5: Output Tokens
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Tokens per Minute (TPM)" }],
            ["${var.stack_name}", "OutputTokens", { id = "m1", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Output Tokens (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 6: Total Tokens
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Tokens per Minute" }],
            ["${var.stack_name}", "TotalTokens", { id = "m1", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Total Tokens (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 7: Bedrock Request Status
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Total per Minute" }],
            [{ expression = "m2/PERIOD(m2)*60", label = "Succeeded per Minute" }],
            [{ expression = "m3/PERIOD(m3)*60", label = "Failed per Minute" }],
            ["${var.stack_name}", "BedrockRequestsTotal", { id = "m1", stat = "Sum", visible = false }],
            [".", "BedrockRequestsSucceeded", { id = "m2", stat = "Sum", visible = false }],
            [".", "BedrockRequestsFailed", { id = "m3", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Bedrock Request Status (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 8: Bedrock Retries
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            [{ expression = "m1/PERIOD(m1)*60", label = "Throttles per Minute" }],
            [{ expression = "m2/PERIOD(m2)*60", label = "Retry Success per Minute" }],
            [{ expression = "m3/PERIOD(m3)*60", label = "Max Retries Exceeded per Minute" }],
            ["${var.stack_name}", "BedrockThrottles", { id = "m1", stat = "Sum", visible = false }],
            [".", "BedrockRetrySuccess", { id = "m2", stat = "Sum", visible = false }],
            [".", "BedrockMaxRetriesExceeded", { id = "m3", stat = "Sum", visible = false }]
          ]
          region = var.aws_region
          title  = "Bedrock Retries (per Minute)"
          view   = "timeSeries"
          period = 60
          yAxis = {
            left = {
              label = "Count per Minute"
            }
          }
        }
      },

      # Widget 9: Bedrock Latency with threshold
      {
        type   = "metric"
        x      = 16
        y      = 12
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["${var.stack_name}", "BedrockRequestLatency", { stat = "Average" }],
            [".", "BedrockRequestLatency", { stat = "p90" }],
            [".", "BedrockRequestLatency", { stat = "Maximum" }],
            [".", "BedrockTotalLatency", { stat = "Average" }],
            [".", "BedrockTotalLatency", { stat = "p90" }],
            [".", "BedrockTotalLatency", { stat = "Maximum" }]
          ]
          region  = var.aws_region
          title   = "Bedrock Latency - per request, and total (including backoff/retries)"
          period  = 300
          view    = "timeSeries"
          stacked = false
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
        }
      },

      # Widget 10: OCR Function Duration
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", module.ocr_function.function_name]
          ]
          region = var.aws_region
          title  = "OCR Function Duration"
          period = 300
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
          stat = "Average"
          view = "timeSeries"
        }
      },

      # Widget 11: Classification Function Duration
      {
        type   = "metric"
        x      = 8
        y      = 18
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", module.classification_function.function_name]
          ]
          region = var.aws_region
          title  = "Classification Function Duration"
          period = 300
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
          stat = "Average"
          view = "timeSeries"
        }
      },

      # Widget 12: Extraction Function Duration
      {
        type   = "metric"
        x      = 16
        y      = 18
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", module.extraction_function.function_name]
          ]
          region = var.aws_region
          title  = "Extraction Function Duration"
          period = 300
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
          stat = "Average"
          view = "timeSeries"
        }
      },

      # Widget 13: Assessment Function Duration
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", module.assessment_function.function_name]
          ]
          region = var.aws_region
          title  = "Assessment Function Duration"
          period = 300
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
          stat = "Average"
          view = "timeSeries"
        }
      },

      # Widget 14: ProcessResults Function Duration
      {
        type   = "metric"
        x      = 8
        y      = 24
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", module.pattern2_process_results_function.function_name]
          ]
          region = var.aws_region
          title  = "ProcessResults Function Duration"
          period = 300
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
          stat = "Average"
          view = "timeSeries"
        }
      },

      # Widget 15: Summarization Function Duration
      {
        type   = "metric"
        x      = 16
        y      = 24
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", module.summarization_function.function_name]
          ]
          region = var.aws_region
          title  = "Summarization Function Duration"
          period = 300
          annotations = {
            horizontal = [{
              value = var.execution_time_threshold_ms
              label = "Threshold (${var.execution_time_threshold_ms}ms)"
              color = "#ff0000"
            }]
          }
          stat = "Average"
          view = "timeSeries"
        }
      }
    ]
  })
}

# ==============================================================================
# Pattern 2: Configuration Custom Resources
# ==============================================================================

# DISABLED: Custom Resource 1: Update Pattern 2 Schema in DynamoDB
# These automatic configuration resources are disabled because:
# 1. They depend on S3 config files that don't exist (pattern-2/default/)
# 2. Manual configuration loading via load_config.py is more flexible
# 3. Allows users to choose appropriate configuration for their use case
# See terraform/README.md "Configuration Management" section for manual loading instructions
#
# resource "null_resource" "pattern2_update_schema_config" {
#   triggers = {
#     # Re-run if function, table, or config files change
#     function_version = module.update_configuration_function.function_version
#     config_table     = module.configuration_table.table_name
#     # Depend on config files being copied first
#     # config_files = data.aws_lambda_invocation.copy_configuration_files.id
#   }
#
#   provisioner "local-exec" {
#     command = <<-EOT
#       # Check if AWS CLI is available
#       if ! /usr/local/bin/aws --version > /dev/null 2>&1; then
#         echo "ERROR: AWS CLI is not available at /usr/local/bin/aws"
#         exit 1
#       fi
#
#       # Prepare the payload for the Lambda function
#       # Schema is referenced from S3 (config.json uploaded by ConfigurationCopyFunction)
#       PAYLOAD=$(cat <<'EOF'
# {
#   "RequestType": "Create",
#   "ResourceProperties": {
#     "Schema": "s3://${module.config_bucket.bucket_id}/config_library/pattern-2/default/config.json"
#   },
#   "StackId": "terraform-pattern2-stack",
#   "LogicalResourceId": "Pattern2UpdateSchemaConfig"
# }
# EOF
#       )
#
#       # Invoke the Lambda function
#       echo "Invoking UpdateConfigurationFunction to update Pattern 2 schema..."
#       /usr/local/bin/aws lambda invoke \
#         --function-name ${module.update_configuration_function.function_name} \
#         --payload "$PAYLOAD" \
#         --region ${var.aws_region} \
#         --cli-binary-format raw-in-base64-out \
#         /tmp/pattern2_schema_response.json
#
#       # Check if invocation was successful
#       if [ $? -eq 0 ]; then
#         echo "Pattern 2 schema configuration updated successfully"
#         cat /tmp/pattern2_schema_response.json
#         rm /tmp/pattern2_schema_response.json
#       else
#         echo "ERROR: Failed to invoke UpdateConfigurationFunction for Pattern 2 schema"
#         exit 1
#       fi
#     EOT
#   }
#
#   depends_on = [
#     module.update_configuration_function,
#     module.configuration_table,
#     # data.aws_lambda_invocation.copy_configuration_files
#   ]
# }

# DISABLED: Custom Resource 2: Update Pattern 2 Default Configuration in DynamoDB
# See comment above for reasons why this is disabled
#
# resource "null_resource" "pattern2_update_default_config" {
#   triggers = {
#     # Re-run if function, table, or config files change
#     function_version = module.update_configuration_function.function_version
#     config_table     = module.configuration_table.table_name
#     # config_files     = data.aws_lambda_invocation.copy_configuration_files.id
#     # Ensure Schema is updated before Default
#     # schema_resource_id = null_resource.pattern2_update_schema_config.id
#   }
#
#   provisioner "local-exec" {
#     command = <<-EOT
#       # Check if AWS CLI is available
#       if ! /usr/local/bin/aws --version > /dev/null 2>&1; then
#         echo "ERROR: AWS CLI is not available at /usr/local/bin/aws"
#         exit 1
#       fi
#
#       # Prepare the payload for the Lambda function
#       # Default config is referenced from S3 (config.yaml uploaded by ConfigurationCopyFunction)
#       PAYLOAD=$(cat <<'EOF'
# {
#   "RequestType": "Create",
#   "ResourceProperties": {
#     "Default": "s3://${module.config_bucket.bucket_id}/config_library/pattern-2/default/config.yaml",
#     "ConfigLibraryHash": "${var.artifact_prefix}",
#     "CustomClassificationModelARN": "",
#     "CustomExtractionModelARN": ""
#   },
#   "StackId": "terraform-pattern2-stack",
#   "LogicalResourceId": "Pattern2UpdateDefaultConfig"
# }
# EOF
#       )
#
#       # Invoke the Lambda function
#       echo "Invoking UpdateConfigurationFunction to update Pattern 2 default configuration..."
#       /usr/local/bin/aws lambda invoke \
#         --function-name ${module.update_configuration_function.function_name} \
#         --payload "$PAYLOAD" \
#         --region ${var.aws_region} \
#         --cli-binary-format raw-in-base64-out \
#         /tmp/pattern2_default_response.json
#
#       # Check if invocation was successful
#       if [ $? -eq 0 ]; then
#         echo "Pattern 2 default configuration updated successfully"
#         cat /tmp/pattern2_default_response.json
#         rm /tmp/pattern2_default_response.json
#       else
#         echo "ERROR: Failed to invoke UpdateConfigurationFunction for Pattern 2 defaults"
#         exit 1
#       fi
#     EOT
#   }
#
#   depends_on = [
#     module.update_configuration_function,
#     module.configuration_table,
#     # null_resource.pattern2_update_schema_config,
#     # data.aws_lambda_invocation.copy_configuration_files
#   ]
# }

