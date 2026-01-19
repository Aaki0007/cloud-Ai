##########################
# Lambda Module - Main
##########################

# CloudWatch Log Group for Lambda
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days

  tags = merge(var.common_tags, {
    Purpose = "Lambda function logs"
  })
}

# Lambda Function
resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  filename         = var.filename
  source_code_hash = var.source_code_hash
  handler          = var.handler
  runtime          = var.runtime
  timeout          = var.timeout
  memory_size      = var.memory_size
  role             = var.role_arn

  environment {
    variables = var.environment_variables
  }

  depends_on = [aws_cloudwatch_log_group.this]

  tags = merge(var.common_tags, {
    Purpose = var.purpose
  })
}
