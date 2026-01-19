##########################
# S3 Module - Variables
##########################

variable "bucket_name" {
  description = "Name of the S3 bucket"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to the bucket"
  type        = map(string)
  default     = {}
}

variable "purpose" {
  description = "Purpose tag for the bucket"
  type        = string
  default     = "General storage"
}

variable "versioning_enabled" {
  description = "Enable versioning on the bucket"
  type        = bool
  default     = true
}

variable "enable_lifecycle_rules" {
  description = "Enable lifecycle rules for archiving"
  type        = bool
  default     = true
}

variable "archive_prefix" {
  description = "Prefix for objects to apply lifecycle rules"
  type        = string
  default     = "archives/"
}

variable "transition_to_ia_days" {
  description = "Days before transitioning to STANDARD_IA"
  type        = number
  default     = 90
}

variable "transition_to_glacier_days" {
  description = "Days before transitioning to GLACIER"
  type        = number
  default     = 180
}

variable "noncurrent_version_expiration_days" {
  description = "Days before expiring noncurrent versions"
  type        = number
  default     = 30
}
