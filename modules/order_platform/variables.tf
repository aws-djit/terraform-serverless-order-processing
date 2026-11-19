variable "project_name" {
  description = "Project name"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "email_address" {
  description = "SNS notification email"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}