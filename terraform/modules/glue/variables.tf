# Glue Module Variables - Data Catalog for evaluation metrics and document sections

variable "database_name" {
  description = "Name of the Glue database for evaluation metrics"
  type        = string
}

variable "reporting_bucket" {
  description = "S3 bucket containing evaluation metrics and document sections"
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encrypting Glue crawler data"
  type        = string
}

variable "stack_name" {
  description = "Stack name for resource naming"
  type        = string
}

variable "crawler_enabled" {
  description = "Enable scheduled Glue crawler runs"
  type        = bool
  default     = false
}

variable "crawler_schedule" {
  description = "Cron expression for crawler schedule (e.g., 'cron(0 1 * * ? *)')"
  type        = string
  default     = "cron(0 1 * * ? *)" # Daily at 1 AM UTC
}

variable "permissions_boundary_arn" {
  description = "Optional IAM permissions boundary for crawler role"
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
