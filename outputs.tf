output "api_url" {
  value = module.order_platform.api_url
}

output "sqs_queue_url" {
  value = module.order_platform.sqs_queue_url
}

output "dynamodb_table_name" {
  value = module.order_platform.dynamodb_table_name
}

output "sns_topic_arn" {
  value = module.order_platform.sns_topic_arn
}