##########################
# Monitoring Module - Main
##########################

# Metric filter to capture ERROR level log entries
resource "aws_cloudwatch_log_metric_filter" "lambda_errors" {
  name           = "${var.function_name}-error-filter"
  pattern        = "{ $.level = \"ERROR\" }"
  log_group_name = var.log_group_name

  metric_transformation {
    name          = "${var.function_name}-error-count"
    namespace     = var.metric_namespace
    value         = "1"
    default_value = "0"
  }
}

# CloudWatch alarm that triggers when errors >= threshold within period
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.function_name}-error-alarm"
  alarm_description   = "Alarm when ${var.function_name} logs ${var.error_threshold} or more errors within ${var.evaluation_period_minutes} minutes"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "${var.function_name}-error-count"
  namespace           = var.metric_namespace
  period              = var.evaluation_period_minutes * 60
  statistic           = "Sum"
  threshold           = var.error_threshold
  treat_missing_data  = "notBreaching"

  tags = merge(var.common_tags, {
    Purpose = "Lambda error alerting"
  })
}
