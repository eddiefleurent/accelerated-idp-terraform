# Core Variables
variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]{1}$", var.aws_region))
    error_message = "Must be a valid AWS region (e.g., us-west-2, us-east-1)"
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod"
  }
}

variable "stack_name" {
  description = "Name of the stack (used for resource naming)"
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.stack_name))
    error_message = "Stack name must start with a letter and contain only alphanumeric characters and hyphens"
  }
}

# KMS Configuration
variable "kms_key_id" {
  description = "ARN of the KMS key for encryption at rest"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:kms:[a-z0-9-]+:[0-9]{12}:key/[a-f0-9-]+$", var.kms_key_id))
    error_message = "Must be a valid KMS key ARN"
  }
}

# S3 Configuration
variable "enable_s3_versioning" {
  description = "Enable versioning on S3 buckets"
  type        = bool
  default     = true
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy S3 buckets with objects (use with caution in production)"
  type        = bool
  default     = false

  validation {
    condition     = var.environment != "prod" || var.s3_force_destroy == false
    error_message = "force_destroy cannot be true in production environment"
  }
}

variable "s3_lifecycle_days" {
  description = "Days before transitioning objects to cheaper storage classes"
  type        = number
  default     = 90

  validation {
    condition     = var.s3_lifecycle_days >= 30
    error_message = "Lifecycle transition must be at least 30 days"
  }
}

# DynamoDB Configuration
variable "dynamodb_billing_mode" {
  description = "DynamoDB billing mode (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"

  validation {
    condition     = contains(["PROVISIONED", "PAY_PER_REQUEST"], var.dynamodb_billing_mode)
    error_message = "Billing mode must be PROVISIONED or PAY_PER_REQUEST"
  }
}

variable "enable_point_in_time_recovery" {
  description = "Enable point-in-time recovery for DynamoDB tables"
  type        = bool
  default     = true
}

variable "dynamodb_ttl_attribute" {
  description = "Attribute name for DynamoDB TTL"
  type        = string
  default     = "ExpiresAfter"
}

# Lambda Configuration
variable "lambda_runtime" {
  description = "Lambda function runtime"
  type        = string
  default     = "python3.12"
}

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 900

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds"
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 3008

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB (AWS limit); project default is 3008 MB"
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 7

  validation {
    condition = contains([
      1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180,
      365, 400, 545, 731, 1827, 3653
    ], var.log_retention_days)
    error_message = "Must be a valid CloudWatch Logs retention period"
  }
}

variable "log_level" {
  description = "Application log level"
  type        = string
  default     = "WARN"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"], var.log_level)
    error_message = "Log level must be DEBUG, INFO, WARN, ERROR, or CRITICAL"
  }
}

# Lambda Environment Variables
variable "max_workers" {
  description = "Maximum number of concurrent workers for Lambda"
  type        = number
  default     = 20

  validation {
    condition     = var.max_workers >= 1 && var.max_workers <= 100
    error_message = "Max workers must be between 1 and 100"
  }
}

# IAM Configuration
variable "permissions_boundary_arn" {
  description = "(Optional) ARN of IAM permissions boundary policy"
  type        = string
  default     = ""

  validation {
    condition = var.permissions_boundary_arn == "" || can(regex(
      "^arn:aws:iam::[0-9]{12}:policy/.+$",
      var.permissions_boundary_arn
    ))
    error_message = "Must be empty or a valid IAM policy ARN"
  }
}

# S3 Bucket Names (will be created)
variable "input_bucket_name" {
  description = "Name of the input S3 bucket (will be created)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.input_bucket_name)) && !can(regex("\\.\\.|-\\.", var.input_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters"
  }
}

variable "output_bucket_name" {
  description = "Name of the output S3 bucket (will be created)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.output_bucket_name)) && !can(regex("\\.\\.|-\\.", var.output_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters"
  }
}

variable "working_bucket_name" {
  description = "Name of the working S3 bucket (will be created)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.working_bucket_name)) && !can(regex("\\.\\.|-\\.", var.working_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters"
  }
}

# Step Functions Configuration
variable "enable_hitl" {
  description = "Enable Human In The Loop (HITL) functionality"
  type        = bool
  default     = true
}

variable "enable_xray_tracing" {
  description = "Enable AWS X-Ray tracing for Step Functions"
  type        = bool
  default     = true
}

variable "create_step_functions_alarms" {
  description = "Create CloudWatch alarms for Step Functions state machine"
  type        = bool
  default     = true
}

variable "execution_failed_threshold" {
  description = "Threshold for Step Functions failed executions alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.execution_failed_threshold >= 0
    error_message = "Threshold must be a non-negative number"
  }
}

variable "execution_time_threshold_ms" {
  description = "Threshold for Step Functions execution duration alarm in milliseconds"
  type        = number
  default     = 30000

  validation {
    condition     = var.execution_time_threshold_ms > 0
    error_message = "Threshold must be a positive number"
  }
}

variable "alarm_sns_topic_arns" {
  description = "List of SNS topic ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

# AppSync Configuration (optional)
variable "appsync_api_url" {
  description = "URL of the AppSync GraphQL API for document status updates"
  type        = string
  default     = ""
}

variable "appsync_api_arn" {
  description = "ARN of the AppSync GraphQL API for document status updates"
  type        = string
  default     = ""
}

# Bedrock Guardrail Configuration (optional)
variable "bedrock_guardrail_id" {
  description = "ID (not name) of an existing Bedrock Guardrail"
  type        = string
  default     = ""
}

variable "bedrock_guardrail_version" {
  description = "Version of the Bedrock Guardrail"
  type        = string
  default     = ""
}

# SageMaker A2I Configuration
variable "sagemaker_a2i_review_portal_url" {
  description = "SageMaker A2I Review Portal URL for HITL tasks"
  type        = string
  default     = ""
}

# Discovery Configuration
variable "discovery_bucket_name" {
  description = "Name of the discovery S3 bucket (will be created)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.discovery_bucket_name)) && !can(regex("\\.\\.|-\\.", var.discovery_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters"
  }
}

# Tags
variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Data Retention Configuration
variable "data_retention_days" {
  description = "Number of days to retain document data in DynamoDB (TTL)"
  type        = number
  default     = 90

  validation {
    condition     = var.data_retention_days >= 1
    error_message = "Data retention must be at least 1 day"
  }
}

# Bedrock Logging Configuration
variable "bedrock_log_level" {
  description = "Log level for Bedrock client operations"
  type        = string
  default     = "INFO"

  validation {
    condition     = contains(["DEBUG", "INFO", "WARN", "ERROR", "CRITICAL"], var.bedrock_log_level)
    error_message = "Bedrock log level must be DEBUG, INFO, WARN, ERROR, or CRITICAL"
  }
}

# Queue Processing Configuration
variable "max_concurrent_workflows" {
  description = "Maximum number of concurrent Step Functions workflows"
  type        = number
  default     = 5

  validation {
    condition     = var.max_concurrent_workflows >= 1 && var.max_concurrent_workflows <= 1000
    error_message = "Max concurrent workflows must be between 1 and 1000"
  }
}

# Reporting Configuration (optional)
variable "reporting_bucket_name" {
  description = "Name of the reporting S3 bucket (optional, for analytics data)"
  type        = string
  default     = ""

  validation {
    condition     = var.reporting_bucket_name == "" || (can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.reporting_bucket_name)) && !can(regex("\\.\\.|-\\.", var.reporting_bucket_name)))
    error_message = "Bucket name must be empty or valid S3 bucket name (3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters)"
  }
}

variable "save_reporting_function_name" {
  description = "Name of the SaveReportingData Lambda function (optional)"
  type        = string
  default     = ""
}

# Configuration Functions - Artifact Bucket Configuration
variable "artifact_bucket_name" {
  description = "Name of the S3 bucket containing deployment artifacts (must already exist)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name)) && !can(regex("\\.\\.|-\\.", var.artifact_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters"
  }
}

variable "artifact_prefix" {
  description = "S3 prefix where deployment artifacts are stored (e.g., 'idp-artifacts/v1.0.0')"
  type        = string
  default     = ""
}

# Configuration Functions - Custom Configuration (optional)
variable "custom_config_bucket_name" {
  description = "Name of the S3 bucket containing custom configuration files (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.custom_config_bucket_name == "" || (can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.custom_config_bucket_name)) && !can(regex("\\.\\.|-\\.", var.custom_config_bucket_name)))
    error_message = "Bucket name must be empty or valid S3 bucket name (3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters)"
  }
}

# Evaluation Configuration
variable "evaluation_baseline_bucket_name" {
  description = "Name of existing S3 bucket for evaluation baseline data. Leave empty to create a new bucket."
  type        = string
  default     = ""

  validation {
    condition     = var.evaluation_baseline_bucket_name == "" || (can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.evaluation_baseline_bucket_name)) && !can(regex("\\.\\.|-\\.", var.evaluation_baseline_bucket_name)))
    error_message = "Bucket name must be empty or valid S3 bucket name (3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters)"
  }
}

variable "evaluation_auto_enabled" {
  description = "Automatically evaluate documents if baseline data exists"
  type        = bool
  default     = false
}

# WebUI Bucket
variable "webui_bucket_name" {
  description = "Name of the WebUI/assets S3 bucket"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.webui_bucket_name)) && !can(regex("\\.\\.|-\\.", var.webui_bucket_name))
    error_message = "Bucket name must be 3-63 characters, start/end with alphanumeric, contain only lowercase letters, numbers, hyphens, and periods, and not have consecutive special characters"
  }
}

# Notifications
variable "alerts_email" {
  description = "Email address for SNS alert notifications (optional)"
  type        = string
  default     = ""

  validation {
    condition     = var.alerts_email == "" || can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.alerts_email))
    error_message = "Must be a valid email address or empty"
  }
}

# Post-Processing Hook
variable "post_processing_lambda_hook_arn" {
  description = "ARN of external Lambda function to trigger after document processing (optional)"
  type        = string
  default     = ""

  validation {
    condition = var.post_processing_lambda_hook_arn == "" || can(regex(
      "^arn:aws:lambda:[a-z0-9-]+:[0-9]{12}:function:.+$",
      var.post_processing_lambda_hook_arn
    ))
    error_message = "Must be empty or a valid Lambda function ARN"
  }
}

# CORS Configuration
variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS (e.g., CloudFront domain for production)"
  type        = list(string)
  default     = ["http://localhost:3000"]

  validation {
    condition     = length(var.cors_allowed_origins) > 0
    error_message = "At least one allowed origin must be specified"
  }
}

variable "cors_max_age_seconds" {
  description = "Maximum age in seconds for CORS preflight cache"
  type        = number
  default     = 3000

  validation {
    condition     = var.cors_max_age_seconds >= 0 && var.cors_max_age_seconds <= 86400
    error_message = "CORS max age must be between 0 and 86400 seconds (24 hours)"
  }
}
