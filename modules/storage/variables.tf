variable "resource_group_name" {} 
variable "location" {} 
variable "db_name" {
  type        = string
  description = "Database name"
}

variable "db_user" {
  type        = string
  description = "Database user"
}

variable "db_password" {
  type        = string
  description = "Database password"
}

variable "azure_storage_container" {
  type        = string
}

variable "azure_storage_account_name" {
  type        = string
}


