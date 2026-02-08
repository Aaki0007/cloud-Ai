##########################
# Data Sources
##########################
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

##########################
# Lambda Packaging
##########################
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/package"
  output_path = "${path.module}/lambda_function.zip"
  excludes    = []
}

##########################
# S3 Module
##########################
module "s3" {
  source = "./modules/s3"

  bucket_name        = "${local.s3_bucket_prefix}-${data.aws_caller_identity.current.account_id}"
  common_tags        = local.common_tags
  purpose            = "Store archived user conversation transcripts"
  versioning_enabled = true

  # Lifecycle configuration
  enable_lifecycle_rules             = true
  archive_prefix                     = "archives/"
  transition_to_ia_days              = 90
  transition_to_glacier_days         = 180
  noncurrent_version_expiration_days = 30
}

##########################
# DynamoDB Module
##########################
module "dynamodb" {
  source = "./modules/dynamodb"

  table_name     = local.dynamodb_table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "pk"
  hash_key_type  = "N"
  range_key      = "sk"
  range_key_type = "S"

  additional_attributes = [
    { name = "model_name", type = "S" },
    { name = "session_id", type = "S" },
    { name = "is_active", type = "N" },
    { name = "last_message_ts", type = "N" }
  ]

  global_secondary_indexes = [
    {
      name            = "model_index"
      hash_key        = "model_name"
      range_key       = "session_id"
      projection_type = "ALL"
    },
    {
      name            = "active_sessions_index"
      hash_key        = "is_active"
      range_key       = "last_message_ts"
      projection_type = "ALL"
    }
  ]

  ttl_enabled        = true
  ttl_attribute_name = "ttl"

  common_tags = local.common_tags
  purpose     = "Store user sessions and conversation data"
}

##########################
# Lambda Module
##########################
module "lambda" {
  source = "./modules/lambda"

  function_name    = local.lambda_function_name
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = local.lambda_handler
  runtime          = local.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size
  role_arn         = var.lab_role_arn

  environment_variables = {
    TELEGRAM_TOKEN = var.telegram_token
    S3_BUCKET_NAME = module.s3.bucket_name
    ENVIRONMENT    = var.environment
  }

  log_retention_days = var.log_retention_days
  common_tags        = local.common_tags
  purpose            = "Telegram bot message handler"

  depends_on = [module.s3, module.dynamodb]
}

##########################
# API Gateway Module
##########################
module "api_gateway" {
  source = "./modules/api_gateway"

  api_name             = local.api_gateway_name
  api_description      = "API Gateway for Telegram Bot webhook"
  endpoint_type        = "REGIONAL"
  resource_path        = "webhook"
  http_method          = "POST"
  authorization        = "NONE"
  lambda_invoke_arn    = module.lambda.invoke_arn
  lambda_function_name = module.lambda.function_name
  stage_name           = var.environment == "prod" ? "prod" : "dev"

  common_tags = local.common_tags

  depends_on = [module.lambda]
}

##########################
# Monitoring Module
##########################
module "monitoring" {
  source = "./modules/monitoring"

  function_name             = module.lambda.function_name
  log_group_name            = module.lambda.log_group_name
  metric_namespace          = "TelegramBot"
  error_threshold           = 1
  evaluation_period_minutes = 5
  common_tags               = local.common_tags

  depends_on = [module.lambda]
}
