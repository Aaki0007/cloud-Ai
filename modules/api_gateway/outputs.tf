##########################
# API Gateway Module - Outputs
##########################

output "api_id" {
  description = "ID of the REST API"
  value       = aws_api_gateway_rest_api.this.id
}

output "api_arn" {
  description = "ARN of the REST API"
  value       = aws_api_gateway_rest_api.this.arn
}

output "execution_arn" {
  description = "Execution ARN of the REST API"
  value       = aws_api_gateway_rest_api.this.execution_arn
}

output "invoke_url" {
  description = "Invoke URL for the stage"
  value       = aws_api_gateway_stage.this.invoke_url
}

output "stage_name" {
  description = "Name of the deployment stage"
  value       = aws_api_gateway_stage.this.stage_name
}

output "webhook_url" {
  description = "Full webhook URL (invoke_url + resource path)"
  value       = "${aws_api_gateway_stage.this.invoke_url}/${var.resource_path}"
}
