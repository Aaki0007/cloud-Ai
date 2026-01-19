##########################
# Lambda Module - Variables
##########################

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "filename" {
  description = "Path to the Lambda deployment package"
  type        = string
}

variable "source_code_hash" {
  description = "Base64-encoded SHA256 hash of the package"
  type        = string
}

variable "handler" {
  description = "Lambda function handler"
  type        = string
  default     = "handler.lambda_handler"
}

variable "runtime" {
  description = "Lambda runtime"
  type        = string
  default     = "python3.9"
}

variable "timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256
}

variable "role_arn" {
  description = "ARN of the IAM role for the Lambda function"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables for the Lambda function"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "purpose" {
  description = "Purpose tag for the Lambda function"
  type        = string
  default     = "Lambda function"
}
