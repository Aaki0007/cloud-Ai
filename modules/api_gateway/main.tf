##########################
# API Gateway Module - Main
##########################

# REST API
resource "aws_api_gateway_rest_api" "this" {
  name        = var.api_name
  description = var.api_description

  endpoint_configuration {
    types = [var.endpoint_type]
  }

  tags = var.common_tags
}

# Resource (path)
resource "aws_api_gateway_resource" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = var.resource_path
}

# Method
resource "aws_api_gateway_method" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.this.id
  http_method   = var.http_method
  authorization = var.authorization
}

# Lambda Integration
resource "aws_api_gateway_integration" "this" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.this.id
  http_method             = aws_api_gateway_method.this.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# Deployment
resource "aws_api_gateway_deployment" "this" {
  depends_on = [aws_api_gateway_integration.this]

  rest_api_id = aws_api_gateway_rest_api.this.id

  lifecycle {
    create_before_destroy = true
  }
}

# Stage
resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.stage_name

  tags = var.common_tags
}

# Lambda Permission
resource "aws_lambda_permission" "this" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}
