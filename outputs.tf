output "s3_bucket_name" {
  value       = aws_s3_bucket.chatbot_conversations.bucket
  description = "S3 bucket used for archived chatbot conversations"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.chatbot_sessions.name
  description = "DynamoDB table storing chatbot session metadata"
}

output "dynamodb_model_gsi" {
  value       = "model_index"
  description = "Global secondary index on DynamoDB table for querying by model_name"
}

output "lambda_function_name" {
  value       = aws_lambda_function.telegram_bot.function_name
  description = "Name of the Lambda function"
}

output "lambda_function_arn" {
  value       = aws_lambda_function.telegram_bot.arn
  description = "ARN of the Lambda function"
}

output "api_gateway_url" {
  value       = "${aws_api_gateway_stage.prod.invoke_url}/webhook"
  description = "API Gateway URL for Telegram webhook"
}

output "webhook_setup_command" {
  value       = "curl 'https://api.telegram.org/bot<YOUR_TOKEN>/setWebhook?url=${aws_api_gateway_stage.prod.invoke_url}/webhook'"
  description = "Command to set up Telegram webhook (replace <YOUR_TOKEN>)"
  sensitive   = false
}
