##########################
# EC2 Module - Variables
##########################

variable "instance_name" {
  description = "Name tag for the EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.large"
}

variable "ami_id" {
  description = "AMI ID (leave empty to auto-select Amazon Linux 2)"
  type        = string
  default     = ""
}

variable "key_pair_name" {
  description = "EC2 key pair name for SSH access (empty = no SSH key)"
  type        = string
  default     = ""
}

variable "instance_profile_name" {
  description = "IAM instance profile name (e.g. LabInstanceProfile)"
  type        = string
  default     = ""
}

variable "security_group_name" {
  description = "Name for the security group"
  type        = string
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed for SSH access"
  type        = string
  default     = "0.0.0.0/0"
}

variable "ollama_model" {
  description = "Ollama model to pull on first boot"
  type        = string
  default     = "tinyllama"
}

variable "models_s3_bucket" {
  description = "S3 bucket for model persistence"
  type        = string
}

variable "models_s3_prefix" {
  description = "S3 prefix for model storage"
  type        = string
  default     = "ollama-models"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 30
}

variable "api_key" {
  description = "API key for authenticating requests to Ollama via nginx proxy"
  type        = string
  sensitive   = true
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "purpose" {
  description = "Purpose tag for the EC2 instance"
  type        = string
  default     = "Ollama AI inference server"
}
