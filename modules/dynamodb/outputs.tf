##########################
# DynamoDB Module - Outputs
##########################

output "table_name" {
  description = "Name of the DynamoDB table"
  value       = aws_dynamodb_table.this.name
}

output "table_arn" {
  description = "ARN of the DynamoDB table"
  value       = aws_dynamodb_table.this.arn
}

output "table_id" {
  description = "ID of the DynamoDB table"
  value       = aws_dynamodb_table.this.id
}

output "hash_key" {
  description = "Hash key of the table"
  value       = aws_dynamodb_table.this.hash_key
}

output "range_key" {
  description = "Range key of the table"
  value       = aws_dynamodb_table.this.range_key
}
