##########################
# API Gateway Module - Variables
##########################

variable "api_name" {
  description = "Name of the API Gateway"
  type        = string
}

variable "api_description" {
  description = "Description of the API Gateway"
  type        = string
  default     = "API Gateway"
}

variable "endpoint_type" {
  description = "Endpoint type (REGIONAL, EDGE, PRIVATE)"
  type        = string
  default     = "REGIONAL"
}

variable "resource_path" {
  description = "API resource path (e.g., webhook)"
  type        = string
  default     = "webhook"
}

variable "http_method" {
  description = "HTTP method for the endpoint"
  type        = string
  default     = "POST"
}

variable "authorization" {
  description = "Authorization type for the method"
  type        = string
  default     = "NONE"
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the Lambda function to integrate"
  type        = string
}

variable "lambda_function_name" {
  description = "Name of the Lambda function for permission"
  type        = string
}

variable "stage_name" {
  description = "Name of the deployment stage"
  type        = string
  default     = "dev"
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}
