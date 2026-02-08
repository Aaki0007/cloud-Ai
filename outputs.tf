##########################
# Outputs
##########################

# S3 Outputs
output "s3_bucket_name" {
  value       = module.s3.bucket_name
  description = "S3 bucket used for archived chatbot conversations"
}

output "s3_bucket_arn" {
  value       = module.s3.bucket_arn
  description = "ARN of the S3 bucket"
}

# DynamoDB Outputs
output "dynamodb_table_name" {
  value       = module.dynamodb.table_name
  description = "DynamoDB table storing chatbot session metadata"
}

output "dynamodb_table_arn" {
  value       = module.dynamodb.table_arn
  description = "ARN of the DynamoDB table"
}

output "dynamodb_model_gsi" {
  value       = "model_index"
  description = "Global secondary index on DynamoDB table for querying by model_name"
}

# Lambda Outputs
output "lambda_function_name" {
  value       = module.lambda.function_name
  description = "Name of the Lambda function"
}

output "lambda_function_arn" {
  value       = module.lambda.function_arn
  description = "ARN of the Lambda function"
}

output "lambda_log_group" {
  value       = module.lambda.log_group_name
  description = "CloudWatch log group for the Lambda function"
}

# API Gateway Outputs
output "api_gateway_url" {
  value       = module.api_gateway.webhook_url
  description = "API Gateway URL for Telegram webhook"
}

output "api_gateway_id" {
  value       = module.api_gateway.api_id
  description = "ID of the API Gateway"
}

output "webhook_setup_command" {
  value       = "curl 'https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook?url=${module.api_gateway.webhook_url}'"
  description = "Command to set up Telegram webhook (replace <YOUR_TOKEN>)"
  sensitive   = false
}

# Monitoring Outputs
output "error_alarm_name" {
  value       = module.monitoring.alarm_name
  description = "CloudWatch alarm for Lambda errors"
}

output "error_metric_filter" {
  value       = module.monitoring.metric_filter_name
  description = "Metric filter capturing ERROR level logs"
}
