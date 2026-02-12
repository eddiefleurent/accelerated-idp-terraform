# Glue Module - Data Catalog for document evaluation metrics and sections
# Enables Athena queries on processed document data stored in S3 (Parquet format)

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
data "aws_url_suffix" "current" {}

# ============================================================================
# Glue Database
# ============================================================================

resource "aws_glue_catalog_database" "this" {
  name        = var.database_name
  description = "Database for document evaluation results and processing metrics"

  tags = var.tags
}

# ============================================================================
# Glue Catalog Tables - Evaluation Metrics
# ============================================================================

# 1. Document-level evaluation metrics table
resource "aws_glue_catalog_table" "document_evaluations" {
  name          = "document_evaluations"
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  description = "Document-level accuracy metrics and evaluation scores"

  parameters = {
    classification                  = "parquet"
    typeOfData                      = "file"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.range"         = "2024-01-01,2030-12-31"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.reporting_bucket}/evaluation_metrics/document_metrics/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.reporting_bucket}/evaluation_metrics/document_metrics/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "document_id"
      type = "string"
    }
    columns {
      name = "input_key"
      type = "string"
    }
    columns {
      name = "evaluation_date"
      type = "timestamp"
    }
    columns {
      name = "accuracy"
      type = "double"
    }
    columns {
      name = "precision"
      type = "double"
    }
    columns {
      name = "recall"
      type = "double"
    }
    columns {
      name = "f1_score"
      type = "double"
    }
    columns {
      name = "false_alarm_rate"
      type = "double"
    }
    columns {
      name = "false_discovery_rate"
      type = "double"
    }
    columns {
      name = "execution_time"
      type = "double"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}

# 2. Section-level evaluation metrics table
resource "aws_glue_catalog_table" "section_evaluations" {
  name          = "section_evaluations"
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  description = "Section-level accuracy metrics for document sections"

  parameters = {
    classification                  = "parquet"
    typeOfData                      = "file"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.range"         = "2024-01-01,2030-12-31"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.reporting_bucket}/evaluation_metrics/section_metrics/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.reporting_bucket}/evaluation_metrics/section_metrics/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "document_id"
      type = "string"
    }
    columns {
      name = "section_id"
      type = "string"
    }
    columns {
      name = "section_type"
      type = "string"
    }
    columns {
      name = "accuracy"
      type = "double"
    }
    columns {
      name = "precision"
      type = "double"
    }
    columns {
      name = "recall"
      type = "double"
    }
    columns {
      name = "f1_score"
      type = "double"
    }
    columns {
      name = "false_alarm_rate"
      type = "double"
    }
    columns {
      name = "false_discovery_rate"
      type = "double"
    }
    columns {
      name = "evaluation_date"
      type = "timestamp"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}

# 3. Attribute-level evaluation metrics table
resource "aws_glue_catalog_table" "attribute_evaluations" {
  name          = "attribute_evaluations"
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  description = "Attribute-level evaluation metrics for individual fields"

  parameters = {
    classification                  = "parquet"
    typeOfData                      = "file"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.range"         = "2024-01-01,2030-12-31"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.reporting_bucket}/evaluation_metrics/attribute_metrics/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.reporting_bucket}/evaluation_metrics/attribute_metrics/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "document_id"
      type = "string"
    }
    columns {
      name = "section_id"
      type = "string"
    }
    columns {
      name = "section_type"
      type = "string"
    }
    columns {
      name = "attribute_name"
      type = "string"
    }
    columns {
      name = "expected"
      type = "string"
    }
    columns {
      name = "actual"
      type = "string"
    }
    columns {
      name = "matched"
      type = "boolean"
    }
    columns {
      name = "score"
      type = "double"
    }
    columns {
      name = "reason"
      type = "string"
    }
    columns {
      name = "evaluation_method"
      type = "string"
    }
    columns {
      name = "confidence"
      type = "string"
    }
    columns {
      name = "confidence_threshold"
      type = "string"
    }
    columns {
      name = "evaluation_date"
      type = "timestamp"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}

# 4. Document metering table
resource "aws_glue_catalog_table" "metering" {
  name          = "metering"
  database_name = aws_glue_catalog_database.this.name
  table_type    = "EXTERNAL_TABLE"

  description = "Document processing metering data for cost tracking"

  parameters = {
    classification                  = "parquet"
    typeOfData                      = "file"
    "projection.enabled"            = "true"
    "projection.date.type"          = "date"
    "projection.date.format"        = "yyyy-MM-dd"
    "projection.date.range"         = "2024-01-01,2030-12-31"
    "projection.date.interval"      = "1"
    "projection.date.interval.unit" = "DAYS"
    "storage.location.template"     = "s3://${var.reporting_bucket}/metering/date=$${date}/"
  }

  storage_descriptor {
    location      = "s3://${var.reporting_bucket}/metering/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
    }

    columns {
      name = "document_id"
      type = "string"
    }
    columns {
      name = "context"
      type = "string"
    }
    columns {
      name = "service_api"
      type = "string"
    }
    columns {
      name = "unit"
      type = "string"
    }
    columns {
      name = "value"
      type = "double"
    }
    columns {
      name = "number_of_pages"
      type = "int"
    }
    columns {
      name = "unit_cost"
      type = "double"
    }
    columns {
      name = "estimated_cost"
      type = "double"
    }
    columns {
      name = "timestamp"
      type = "timestamp"
    }
  }

  partition_keys {
    name = "date"
    type = "string"
  }
}

# ============================================================================
# Glue Security Configuration
# ============================================================================

# Security configuration for Glue crawler to enable KMS encryption for S3 data
resource "aws_glue_security_configuration" "crawler" {
  name = "${var.stack_name}-document-sections-crawler-security-config-v2"

  encryption_configuration {
    s3_encryption {
      s3_encryption_mode = "SSE-KMS"
      kms_key_arn        = var.kms_key_arn
    }
  }
}

# ============================================================================
# IAM Role for Glue Crawler
# ============================================================================

# IAM role for Glue crawler with minimal necessary permissions
resource "aws_iam_role" "crawler" {
  name                 = "${var.stack_name}-DocumentSectionsCrawlerRole"
  description          = "IAM role for Glue crawler to discover document section tables"
  permissions_boundary = var.permissions_boundary_arn

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "glue.${data.aws_url_suffix.current.suffix}"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-DocumentSectionsCrawlerRole"
    }
  )
}

# Attach AWS managed Glue service role policy
resource "aws_iam_role_policy_attachment" "crawler_service_role" {
  role       = aws_iam_role.crawler.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Custom inline policy for S3 and KMS access
resource "aws_iam_role_policy" "crawler_s3_access" {
  name = "DocumentSectionsCrawlerS3Access"
  role = aws_iam_role.crawler.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # S3 read permissions
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.reporting_bucket}",
          "arn:${data.aws_partition.current.partition}:s3:::${var.reporting_bucket}/*"
        ]
      },
      # KMS decrypt permissions for S3 objects
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = var.kms_key_arn
      }
    ]
  })
}

# ============================================================================
# Glue Crawler
# ============================================================================

# Crawler to automatically discover and catalog document section tables
resource "aws_glue_crawler" "document_sections" {
  name          = "${var.stack_name}-document-sections-crawler"
  description   = "Crawler to discover document section tables in the reporting bucket"
  role          = aws_iam_role.crawler.arn
  database_name = aws_glue_catalog_database.this.name

  # Security configuration for KMS encryption
  security_configuration = aws_glue_security_configuration.crawler.name

  # Crawler configuration for partition management and table discovery
  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = { AddOrUpdateBehavior = "InheritFromTable" }
      Tables     = { AddOrUpdateBehavior = "MergeNewColumns" }
    }
    Grouping             = { TableLevelConfiguration = 3 }
    CreatePartitionIndex = true
  })

  # S3 target path for document sections
  s3_target {
    path = "s3://${var.reporting_bucket}/document_sections/"
  }

  # Schema change handling
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  # Table prefix for discovered tables
  table_prefix = "document_sections_"

  # Optional: Schedule for crawler (only if enabled)
  dynamic "schedule" {
    for_each = var.crawler_enabled ? [1] : []
    content {
      schedule_expression = var.crawler_schedule
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.stack_name}-document-sections-crawler"
    }
  )

  depends_on = [
    aws_iam_role_policy.crawler_s3_access,
    aws_iam_role_policy_attachment.crawler_service_role
  ]
}
