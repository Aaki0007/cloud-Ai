##########################
# Monitoring Module - Variables
##########################

variable "function_name" {
  description = "Name of the Lambda function to monitor"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name to apply metric filter on"
  type        = string
}

variable "metric_namespace" {
  description = "CloudWatch metric namespace"
  type        = string
  default     = "TelegramBot"
}

variable "error_threshold" {
  description = "Number of errors to trigger the alarm"
  type        = number
  default     = 1
}

variable "evaluation_period_minutes" {
  description = "Period in minutes over which to evaluate errors"
  type        = number
  default     = 5
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}
