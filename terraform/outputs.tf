# Terraform Outputs

# ============================================================================
# Locals for Deployment Status
# ============================================================================

locals {
  # Configuration functions deployment status
  configuration_copy_deployed   = module.configuration_copy_function.function_arn != ""
  update_configuration_deployed = module.update_configuration_function.function_arn != ""
  concurrency_counter_deployed  = aws_dynamodb_table_item.concurrency_counter.id != ""
  lookup_function_deployed      = module.lookup_function.function_arn != ""
}

# ============================================================================
# S3 Buckets
# ============================================================================

output "input_bucket_name" {
  description = "Name of the input S3 bucket"
  value       = module.input_bucket.bucket_id
}

output "input_bucket_arn" {
  description = "ARN of the input S3 bucket"
  value       = module.input_bucket.bucket_arn
}

output "discovery_bucket_name" {
  description = "Name of the discovery S3 bucket"
  value       = module.discovery_bucket.bucket_id
}

output "discovery_bucket_arn" {
  description = "ARN of the discovery S3 bucket"
  value       = module.discovery_bucket.bucket_arn
}

output "working_bucket_name" {
  description = "Name of the working S3 bucket"
  value       = module.working_bucket.bucket_id
}

output "working_bucket_arn" {
  description = "ARN of the working S3 bucket"
  value       = module.working_bucket.bucket_arn
}

output "output_bucket_name" {
  description = "Name of the output S3 bucket"
  value       = module.output_bucket.bucket_id
}

output "output_bucket_arn" {
  description = "ARN of the output S3 bucket"
  value       = module.output_bucket.bucket_arn
}

# Evaluation Baseline Bucket
output "evaluation_baseline_bucket_name" {
  description = "Name of the evaluation baseline S3 bucket"
  value       = var.evaluation_baseline_bucket_name != "" ? var.evaluation_baseline_bucket_name : try(module.evaluation_baseline_bucket[0].bucket_id, null)
}

output "evaluation_baseline_bucket_arn" {
  description = "ARN of the evaluation baseline S3 bucket"
  value       = var.evaluation_baseline_bucket_name != "" ? "arn:${data.aws_partition.current.partition}:s3:::${var.evaluation_baseline_bucket_name}" : try(module.evaluation_baseline_bucket[0].bucket_arn, null)
}

# WebUI Bucket
output "webui_bucket_name" {
  description = "Name of the WebUI assets S3 bucket"
  value       = module.webui_bucket.bucket_id
}

output "webui_bucket_arn" {
  description = "ARN of the WebUI assets S3 bucket"
  value       = module.webui_bucket.bucket_arn
}

# ============================================================================
# DynamoDB Tables
# ============================================================================

output "configuration_table_name" {
  description = "Name of the Configuration DynamoDB table"
  value       = module.configuration_table.table_name
}

output "configuration_table_arn" {
  description = "ARN of the Configuration DynamoDB table"
  value       = module.configuration_table.table_arn
}

output "discovery_tracking_table_name" {
  description = "Name of the Discovery Tracking DynamoDB table"
  value       = module.discovery_tracking_table.table_name
}

output "discovery_tracking_table_arn" {
  description = "ARN of the Discovery Tracking DynamoDB table"
  value       = module.discovery_tracking_table.table_arn
}

output "tracking_table_name" {
  description = "Name of the Tracking DynamoDB table"
  value       = module.tracking_table.table_name
}

output "tracking_table_arn" {
  description = "ARN of the Tracking DynamoDB table"
  value       = module.tracking_table.table_arn
}

output "concurrency_table_name" {
  description = "Name of the Concurrency DynamoDB table"
  value       = module.concurrency_table.table_name
}

output "concurrency_table_arn" {
  description = "ARN of the Concurrency DynamoDB table"
  value       = module.concurrency_table.table_arn
}

# ============================================================================
# Shared Lambda Functions
# ============================================================================

# QueueSender Function
output "queue_sender_function_name" {
  description = "Name of the QueueSender Lambda function"
  value       = module.queue_sender_function.function_name
}

output "queue_sender_function_arn" {
  description = "ARN of the QueueSender Lambda function"
  value       = module.queue_sender_function.function_arn
}

output "queue_sender_function_role_arn" {
  description = "ARN of the QueueSender Lambda function's IAM role"
  value       = module.queue_sender_function.role_arn
}

# QueueProcessor Function
output "queue_processor_function_name" {
  description = "Name of the QueueProcessor Lambda function"
  value       = module.queue_processor_function.function_name
}

output "queue_processor_function_arn" {
  description = "ARN of the QueueProcessor Lambda function"
  value       = module.queue_processor_function.function_arn
}

output "queue_processor_function_role_arn" {
  description = "ARN of the QueueProcessor Lambda function's IAM role"
  value       = module.queue_processor_function.role_arn
}

# WorkflowTracker Function
output "workflow_tracker_function_name" {
  description = "Name of the WorkflowTracker Lambda function"
  value       = module.workflow_tracker_function.function_name
}

output "workflow_tracker_function_arn" {
  description = "ARN of the WorkflowTracker Lambda function"
  value       = module.workflow_tracker_function.function_arn
}

output "workflow_tracker_function_role_arn" {
  description = "ARN of the WorkflowTracker Lambda function's IAM role"
  value       = module.workflow_tracker_function.role_arn
}

output "workflow_tracker_dlq_arn" {
  description = "ARN of the WorkflowTracker function's dead letter queue"
  value       = aws_sqs_queue.workflow_tracker_dlq.arn
}

# Evaluation Function
output "evaluation_function_name" {
  description = "Name of the Evaluation Lambda function"
  value       = module.evaluation_function.function_name
}

output "evaluation_function_arn" {
  description = "ARN of the Evaluation Lambda function"
  value       = module.evaluation_function.function_arn
}

output "evaluation_function_role_arn" {
  description = "ARN of the Evaluation Lambda function's IAM role"
  value       = module.evaluation_function.role_arn
}

output "evaluation_function_dlq_arn" {
  description = "ARN of the Evaluation function's dead letter queue"
  value       = aws_sqs_queue.evaluation_function_dlq.arn
}

# SaveReportingData Function
output "save_reporting_data_function_name" {
  description = "Name of the SaveReportingData Lambda function"
  value       = module.save_reporting_data_function.function_name
}

output "save_reporting_data_function_arn" {
  description = "ARN of the SaveReportingData Lambda function"
  value       = module.save_reporting_data_function.function_arn
}

output "save_reporting_data_function_role_arn" {
  description = "ARN of the SaveReportingData Lambda function's IAM role"
  value       = module.save_reporting_data_function.role_arn
}

# ============================================================================
# SQS Queues
# ============================================================================

output "document_processing_queue_arn" {
  description = "ARN of the document processing SQS queue"
  value       = aws_sqs_queue.document_processing_queue.arn
}

output "document_processing_queue_url" {
  description = "URL of the document processing SQS queue"
  value       = aws_sqs_queue.document_processing_queue.url
}

output "document_processing_queue_dlq_arn" {
  description = "ARN of the document processing queue DLQ"
  value       = aws_sqs_queue.document_processing_dlq.arn
}

# ============================================================================
# SNS Topics
# ============================================================================

output "alerts_topic_arn" {
  description = "ARN of the SNS alerts topic"
  value       = aws_sns_topic.alerts_topic.arn
}

output "alerts_topic_name" {
  description = "Name of the SNS alerts topic"
  value       = aws_sns_topic.alerts_topic.name
}

# ============================================================================
# General Information
# ============================================================================

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "stack_name" {
  description = "Name of the stack"
  value       = var.stack_name
}

output "environment" {
  description = "Environment name"
  value       = var.environment
}

# ============================================================================
# Configuration/Setup Lambda Functions
# ============================================================================

# UpdateConfigurationFunction ARN - Used by pattern nested stacks
output "update_configuration_function_arn" {
  description = "ARN of UpdateConfigurationFunction (for pattern stack integration)"
  value       = module.update_configuration_function.function_arn
}

# LookupFunction - User-facing function for querying document status
output "lookup_function_name" {
  description = "Name of LookupFunction (for CLI/API invocations)"
  value       = module.lookup_function.function_name
}

output "lookup_function_arn" {
  description = "ARN of LookupFunction"
  value       = module.lookup_function.function_arn
}

output "lookup_function_console_url" {
  description = "AWS Console URL for LookupFunction"
  value       = "https://console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${module.lookup_function.function_name}"
}

# Configuration Bucket
output "configuration_bucket_name" {
  description = "Name of the configuration S3 bucket"
  value       = module.config_bucket.bucket_id
}

output "configuration_bucket_arn" {
  description = "ARN of the configuration S3 bucket"
  value       = module.config_bucket.bucket_arn
}

# Configuration/Setup Functions Summary
output "configuration_functions_summary" {
  description = "Summary of configuration/setup functions deployed"
  value       = <<-EOT

  ╔════════════════════════════════════════════════════════════════════════════╗
  ║                  Configuration/Setup Functions Deployed                    ║
  ╠════════════════════════════════════════════════════════════════════════════╣
  ║                                                                            ║
  ║  4 Lambda functions have been deployed for system configuration:          ║
  ║                                                                            ║
  ║  1. ConfigurationCopyFunction                                             ║
  ║     Purpose: Copies configuration files from artifact bucket              ║
  ║     Status: ✓ Deployed
  ║                                                                            ║
  ║  2. UpdateConfigurationFunction                                           ║
  ║     Purpose: Manages configuration in DynamoDB                            ║
  ║     Status: ✓ Deployed
  ║     ARN: ${module.update_configuration_function.function_arn}
  ║                                                                            ║
  ║  3. ConcurrencyTable Initialization (Terraform Native)                    ║
  ║     Purpose: Initializes workflow counter in DynamoDB                     ║
  ║     Status: ✓ Deployed
  ║                                                                            ║
  ║  4. LookupFunction                                                        ║
  ║     Purpose: Queries document processing status                           ║
  ║     Status: ✓ Deployed
  ║     Function: ${module.lookup_function.function_name}
  ║     Console: https://console.aws.amazon.com/lambda/home?region=${var.aws_region}#/functions/${module.lookup_function.function_name}
  ║                                                                            ║
  ╠════════════════════════════════════════════════════════════════════════════╣
  ║  Configuration Bucket: ${module.config_bucket.bucket_id}
  ╚════════════════════════════════════════════════════════════════════════════╝

  Usage Examples:

  1. Query document status (LookupFunction):
     aws lambda invoke \
       --function-name ${module.lookup_function.function_name} \
       --payload '{"object_key": "your-document.pdf"}' \
       --region ${var.aws_region} \
       response.json && cat response.json

  2. Update configuration manually:
     aws lambda invoke \
       --function-name ${module.update_configuration_function.function_name} \
       --payload '{"RequestType": "Create", "ResourceProperties": {...}}' \
       --region ${var.aws_region} \
       response.json

  3. View configuration in DynamoDB:
     aws dynamodb scan \
       --table-name ${module.configuration_table.table_name} \
       --region ${var.aws_region}

  4. List configuration files:
     aws s3 ls s3://${module.config_bucket.bucket_id}/config_library/ --recursive

  NOTE: Custom resource invocations (config copy, counter init, config update)
        are executed automatically during terraform apply via null_resource
        provisioners.

  EOT
}

# ============================================================================
# Pattern 2: Textract + Bedrock Pipeline Outputs
# ============================================================================

# OCR Function
output "ocr_function_arn" {
  description = "ARN of the OCR Lambda function"
  value       = module.ocr_function.function_arn
}

output "ocr_function_name" {
  description = "Name of the OCR Lambda function"
  value       = module.ocr_function.function_name
}

output "ocr_function_role_arn" {
  description = "ARN of the OCR Lambda function's IAM role"
  value       = module.ocr_function.role_arn
}

output "ocr_function_log_group_name" {
  description = "Name of the OCR Lambda function's CloudWatch Log Group"
  value       = module.ocr_function.log_group_name
}

# Classification Function
output "classification_function_arn" {
  description = "ARN of the Classification Lambda function"
  value       = module.classification_function.function_arn
}

output "classification_function_name" {
  description = "Name of the Classification Lambda function"
  value       = module.classification_function.function_name
}

output "classification_function_role_arn" {
  description = "ARN of the Classification Lambda function's IAM role"
  value       = module.classification_function.role_arn
}

output "classification_function_log_group_name" {
  description = "Name of the Classification Lambda function's CloudWatch Log Group"
  value       = module.classification_function.log_group_name
}

# Extraction Function
output "extraction_function_arn" {
  description = "ARN of the Extraction Lambda function"
  value       = module.extraction_function.function_arn
}

output "extraction_function_name" {
  description = "Name of the Extraction Lambda function"
  value       = module.extraction_function.function_name
}

output "extraction_function_role_arn" {
  description = "ARN of the Extraction Lambda function's IAM role"
  value       = module.extraction_function.role_arn
}

output "extraction_function_log_group_name" {
  description = "Name of the Extraction Lambda function's CloudWatch Log Group"
  value       = module.extraction_function.log_group_name
}

# Assessment Function
output "assessment_function_arn" {
  description = "ARN of the Assessment Lambda function"
  value       = module.assessment_function.function_arn
}

output "assessment_function_name" {
  description = "Name of the Assessment Lambda function"
  value       = module.assessment_function.function_name
}

output "assessment_function_role_arn" {
  description = "ARN of the Assessment Lambda function's IAM role"
  value       = module.assessment_function.role_arn
}

output "assessment_function_log_group_name" {
  description = "Name of the Assessment Lambda function's CloudWatch Log Group"
  value       = module.assessment_function.log_group_name
}

# ProcessResults Function (Pattern 2)
output "pattern2_process_results_function_arn" {
  description = "ARN of the ProcessResults Lambda function (Pattern 2)"
  value       = module.pattern2_process_results_function.function_arn
}

output "pattern2_process_results_function_name" {
  description = "Name of the ProcessResults Lambda function (Pattern 2)"
  value       = module.pattern2_process_results_function.function_name
}

output "pattern2_process_results_function_role_arn" {
  description = "ARN of the ProcessResults Lambda function's IAM role (Pattern 2)"
  value       = module.pattern2_process_results_function.role_arn
}

output "pattern2_process_results_function_log_group_name" {
  description = "Name of the ProcessResults Lambda function's CloudWatch Log Group (Pattern 2)"
  value       = module.pattern2_process_results_function.log_group_name
}

# ==============================================================================
# Pattern 2: EventBridge Integration
# ==============================================================================

output "pattern2_hitl_event_rule_arn" {
  description = "ARN of the Pattern 2 HITL EventBridge rule"
  value       = aws_cloudwatch_event_rule.pattern2_hitl_event_rule.arn
}

output "pattern2_hitl_event_rule_name" {
  description = "Name of the Pattern 2 HITL EventBridge rule"
  value       = aws_cloudwatch_event_rule.pattern2_hitl_event_rule.name
}

# ==============================================================================
# Pattern 2: Step Functions State Machine
# ==============================================================================

output "pattern2_state_machine_arn" {
  description = "ARN of the Pattern 2 Step Functions state machine"
  value       = aws_sfn_state_machine.pattern2_document_processing.arn
}

output "pattern2_state_machine_name" {
  description = "Name of the Pattern 2 Step Functions state machine"
  value       = aws_sfn_state_machine.pattern2_document_processing.name
}

output "pattern2_state_machine_role_arn" {
  description = "ARN of the Pattern 2 state machine IAM role"
  value       = aws_iam_role.pattern2_state_machine.arn
}

output "pattern2_state_machine_log_group_name" {
  description = "Name of the Pattern 2 state machine CloudWatch Log Group"
  value       = aws_cloudwatch_log_group.pattern2_state_machine.name
}

output "pattern2_state_machine_console_url" {
  description = "AWS Console URL for the Pattern 2 Step Functions state machine"
  value       = "https://console.aws.amazon.com/states/home?region=${var.aws_region}#/statemachines/view/${aws_sfn_state_machine.pattern2_document_processing.arn}"
}

# ==============================================================================
# Pattern 2: CloudWatch Dashboard
# ==============================================================================

output "pattern2_dashboard_name" {
  description = "Name of the Pattern 2 CloudWatch Dashboard"
  value       = aws_cloudwatch_dashboard.pattern2_dashboard.dashboard_name
}

output "pattern2_dashboard_arn" {
  description = "ARN of the Pattern 2 CloudWatch Dashboard"
  value       = "arn:${data.aws_partition.current.partition}:cloudwatch::${data.aws_caller_identity.current.account_id}:dashboard/${aws_cloudwatch_dashboard.pattern2_dashboard.dashboard_name}"
}

output "pattern2_dashboard_url" {
  description = "AWS Console URL for the Pattern 2 CloudWatch Dashboard"
  value       = "https://console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.pattern2_dashboard.dashboard_name}"
}

# ==============================================================================
# Lambda Layer Outputs
# ==============================================================================

output "idp_common_layer_arn" {
  description = "ARN of the IDP common Lambda layer"
  value       = aws_lambda_layer_version.idp_common.arn
}

output "idp_common_layer_version" {
  description = "Version of the IDP common Lambda layer"
  value       = aws_lambda_layer_version.idp_common.version
}

output "idp_common_layer_source_code_hash" {
  description = "Source code hash of the IDP common Lambda layer"
  value       = aws_lambda_layer_version.idp_common.source_code_hash
}
