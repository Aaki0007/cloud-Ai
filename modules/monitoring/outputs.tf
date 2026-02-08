##########################
# Monitoring Module - Outputs
##########################

output "metric_filter_name" {
  description = "Name of the CloudWatch metric filter"
  value       = aws_cloudwatch_log_metric_filter.lambda_errors.name
}

output "metric_filter_pattern" {
  description = "Pattern used by the metric filter"
  value       = aws_cloudwatch_log_metric_filter.lambda_errors.pattern
}

output "alarm_name" {
  description = "Name of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.alarm_name
}

output "alarm_arn" {
  description = "ARN of the CloudWatch alarm"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}
