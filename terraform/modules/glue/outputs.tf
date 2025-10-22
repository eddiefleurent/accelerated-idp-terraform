# Glue Module Outputs

output "database_name" {
  description = "Name of the Glue database"
  value       = aws_glue_catalog_database.this.name
}

output "database_arn" {
  description = "ARN of the Glue database"
  value       = "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.this.name}"
}

output "table_names" {
  description = "List of Glue table names"
  value = [
    aws_glue_catalog_table.document_evaluations.name,
    aws_glue_catalog_table.section_evaluations.name,
    aws_glue_catalog_table.attribute_evaluations.name,
    aws_glue_catalog_table.metering.name
  ]
}

output "table_arns" {
  description = "Map of table names to ARNs"
  value = {
    document_evaluations  = "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.this.name}/${aws_glue_catalog_table.document_evaluations.name}"
    section_evaluations   = "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.this.name}/${aws_glue_catalog_table.section_evaluations.name}"
    attribute_evaluations = "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.this.name}/${aws_glue_catalog_table.attribute_evaluations.name}"
    metering              = "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.this.name}/${aws_glue_catalog_table.metering.name}"
  }
}

output "crawler_name" {
  description = "Name of the Glue crawler"
  value       = aws_glue_crawler.document_sections.name
}

output "crawler_arn" {
  description = "ARN of the Glue crawler"
  value       = aws_glue_crawler.document_sections.arn
}

output "crawler_role_arn" {
  description = "ARN of the IAM role for the Glue crawler"
  value       = aws_iam_role.crawler.arn
}

output "crawler_role_name" {
  description = "Name of the IAM role for the Glue crawler"
  value       = aws_iam_role.crawler.name
}

output "security_configuration_name" {
  description = "Name of the Glue security configuration"
  value       = aws_glue_security_configuration.crawler.name
}
