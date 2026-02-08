##########################
# EC2 Module - Outputs
##########################

output "instance_id" {
  description = "ID of the EC2 instance"
  value       = aws_instance.ollama.id
}

output "public_ip" {
  description = "Elastic IP address of the Ollama instance"
  value       = aws_eip.ollama.public_ip
}

output "private_ip" {
  description = "Private IP address of the Ollama instance"
  value       = aws_instance.ollama.private_ip
}

output "ollama_url" {
  description = "Full Ollama API URL"
  value       = "http://${aws_eip.ollama.public_ip}:11434"
}

output "security_group_id" {
  description = "ID of the Ollama security group"
  value       = aws_security_group.ollama.id
}

output "api_key" {
  description = "API key for authenticating Ollama requests"
  value       = var.api_key
  sensitive   = true
}
