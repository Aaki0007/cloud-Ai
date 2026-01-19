##########################
# DynamoDB Module - Variables
##########################

variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "billing_mode" {
  description = "Billing mode for the table (PROVISIONED or PAY_PER_REQUEST)"
  type        = string
  default     = "PAY_PER_REQUEST"
}

variable "hash_key" {
  description = "Hash key (partition key) name"
  type        = string
}

variable "hash_key_type" {
  description = "Hash key type (S, N, or B)"
  type        = string
  default     = "S"
}

variable "range_key" {
  description = "Range key (sort key) name"
  type        = string
}

variable "range_key_type" {
  description = "Range key type (S, N, or B)"
  type        = string
  default     = "S"
}

variable "additional_attributes" {
  description = "Additional attributes for indexes"
  type = list(object({
    name = string
    type = string
  }))
  default = []
}

variable "global_secondary_indexes" {
  description = "List of Global Secondary Indexes"
  type = list(object({
    name            = string
    hash_key        = string
    range_key       = optional(string)
    projection_type = optional(string, "ALL")
  }))
  default = []
}

variable "ttl_enabled" {
  description = "Enable TTL on the table"
  type        = bool
  default     = false
}

variable "ttl_attribute_name" {
  description = "Attribute name for TTL"
  type        = string
  default     = "ttl"
}

variable "common_tags" {
  description = "Common tags to apply to the table"
  type        = map(string)
  default     = {}
}

variable "purpose" {
  description = "Purpose tag for the table"
  type        = string
  default     = "Data storage"
}
