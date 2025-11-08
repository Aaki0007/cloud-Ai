output "s3_bucket_name" {
  value = aws_s3_bucket.chatbot_conversations.bucket
  description = "S3 bucket storing chatbot conversation logs"
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.chatbot_sessions.name
  description = "DynamoDB table storing active user sessions and context"
}

