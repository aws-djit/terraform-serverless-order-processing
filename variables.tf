variable "project_name" {
  description = "Project name"
  type        = string
  default     = "serverless-order"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "email_address" {
  description = "Email address for SNS notifications"
  type        = string
}