# --------------------------------------------------
# 1. SQS DEAD LETTER QUEUE
# --------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.project_name}-${var.environment}-dlq"
  message_retention_seconds = 1209600
}

# --------------------------------------------------
# 2. MAIN SQS QUEUE
# --------------------------------------------------

resource "aws_sqs_queue" "orders" {
  name                       = "${var.project_name}-${var.environment}-orders"
  visibility_timeout_seconds = 180
  message_retention_seconds  = 345600

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 3
  })
}

# --------------------------------------------------
# 3. SNS TOPIC
# --------------------------------------------------

resource "aws_sns_topic" "orders" {
  name = "${var.project_name}-${var.environment}-notifications"
}

# --------------------------------------------------
# 4. SNS EMAIL SUBSCRIPTION
# --------------------------------------------------

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.orders.arn
  protocol  = "email"
  endpoint  = var.email_address
}

# --------------------------------------------------
# 5. DYNAMODB TABLE
# --------------------------------------------------

resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-${var.environment}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

# --------------------------------------------------
# 6. PACKAGE PRODUCER LAMBDA
# --------------------------------------------------

data "archive_file" "producer" {
  type        = "zip"
  source_file = "${path.module}/lambda/producer/lambda_function.py"
  output_path = "${path.module}/producer.zip"
}

# --------------------------------------------------
# 7. PACKAGE PROCESSOR LAMBDA
# --------------------------------------------------

data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/lambda/processor/lambda_function.py"
  output_path = "${path.module}/processor.zip"
}

# --------------------------------------------------
# 8. PRODUCER LAMBDA IAM ROLE
# --------------------------------------------------

resource "aws_iam_role" "producer" {
  name = "${var.project_name}-${var.environment}-producer-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# --------------------------------------------------
# 9. PROCESSOR LAMBDA IAM ROLE
# --------------------------------------------------

resource "aws_iam_role" "processor" {
  name = "${var.project_name}-${var.environment}-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# --------------------------------------------------
# 10. PRODUCER CLOUDWATCH LOG PERMISSION
# --------------------------------------------------

resource "aws_iam_role_policy_attachment" "producer_logs" {
  role       = aws_iam_role.producer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------
# 11. PROCESSOR CLOUDWATCH LOG PERMISSION
# --------------------------------------------------

resource "aws_iam_role_policy_attachment" "processor_logs" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# --------------------------------------------------
# 12. PRODUCER SQS PERMISSION
# --------------------------------------------------

resource "aws_iam_role_policy" "producer_sqs" {
  name = "${var.project_name}-producer-sqs-policy"
  role = aws_iam_role.producer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:SendMessage"
      ]
      Resource = aws_sqs_queue.orders.arn
    }]
  })
}

# --------------------------------------------------
# 13. PROCESSOR SQS PERMISSION
# --------------------------------------------------

resource "aws_iam_role_policy" "processor_sqs" {
  name = "${var.project_name}-processor-sqs-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"
      ]
      Resource = aws_sqs_queue.orders.arn
    }]
  })
}

# --------------------------------------------------
# 14. PROCESSOR DYNAMODB PERMISSION
# --------------------------------------------------

resource "aws_iam_role_policy" "processor_dynamodb" {
  name = "${var.project_name}-processor-dynamodb-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:PutItem"
      ]
      Resource = aws_dynamodb_table.orders.arn
    }]
  })
}

# --------------------------------------------------
# 15. PROCESSOR SNS PERMISSION
# --------------------------------------------------

resource "aws_iam_role_policy" "processor_sns" {
  name = "${var.project_name}-processor-sns-policy"
  role = aws_iam_role.processor.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "sns:Publish"
      ]
      Resource = aws_sns_topic.orders.arn
    }]
  })
}

# --------------------------------------------------
# 16. PRODUCER LAMBDA FUNCTION
# --------------------------------------------------

resource "aws_lambda_function" "producer" {
  function_name = "${var.project_name}-${var.environment}-producer"
  role          = aws_iam_role.producer.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.producer.output_path
  source_code_hash = data.archive_file.producer.output_base64sha256

  timeout = 30

  environment {
    variables = {
      SQS_URL = aws_sqs_queue.orders.url
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.producer_logs,
    aws_iam_role_policy.producer_sqs
  ]
}

# --------------------------------------------------
# 17. PROCESSOR LAMBDA FUNCTION
# --------------------------------------------------

resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-${var.environment}-processor"
  role          = aws_iam_role.processor.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"

  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256

  timeout = 60

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders.name
      SNS_ARN    = aws_sns_topic.orders.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.processor_logs,
    aws_iam_role_policy.processor_sqs,
    aws_iam_role_policy.processor_dynamodb,
    aws_iam_role_policy.processor_sns
  ]
}

# --------------------------------------------------
# 18. SQS TO PROCESSOR LAMBDA TRIGGER
# --------------------------------------------------

resource "aws_lambda_event_source_mapping" "orders" {
  event_source_arn = aws_sqs_queue.orders.arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 5
  enabled          = true

  depends_on = [
    aws_iam_role_policy.processor_sqs
  ]
}

# --------------------------------------------------
# 19. API GATEWAY REST API
# --------------------------------------------------

resource "aws_api_gateway_rest_api" "orders" {
  name        = "${var.project_name}-${var.environment}-api"
  description = "Order processing API"
}

# --------------------------------------------------
# 20. API RESOURCE /orders
# --------------------------------------------------

resource "aws_api_gateway_resource" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id
  parent_id   = aws_api_gateway_rest_api.orders.root_resource_id
  path_part   = "orders"
}

# --------------------------------------------------
# 21. API POST METHOD
# --------------------------------------------------

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  resource_id   = aws_api_gateway_resource.orders.id
  http_method   = "POST"
  authorization = "NONE"
}

# --------------------------------------------------
# 22. API GATEWAY TO PRODUCER LAMBDA INTEGRATION
# --------------------------------------------------

resource "aws_api_gateway_integration" "producer" {
  rest_api_id             = aws_api_gateway_rest_api.orders.id
  resource_id             = aws_api_gateway_resource.orders.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.producer.invoke_arn
}

# --------------------------------------------------
# 23. ALLOW API GATEWAY TO INVOKE PRODUCER LAMBDA
# --------------------------------------------------

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.producer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_api_gateway_rest_api.orders.execution_arn}/*/POST/orders"
}

# --------------------------------------------------
# 24. API GATEWAY DEPLOYMENT
# --------------------------------------------------

resource "aws_api_gateway_deployment" "orders" {
  rest_api_id = aws_api_gateway_rest_api.orders.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.orders.id,
      aws_api_gateway_method.post.id,
      aws_api_gateway_integration.producer.id
    ]))
  }

  depends_on = [
    aws_api_gateway_integration.producer,
    aws_lambda_permission.api_gateway
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# --------------------------------------------------
# 25. API GATEWAY STAGE
# --------------------------------------------------

resource "aws_api_gateway_stage" "dev" {
  rest_api_id   = aws_api_gateway_rest_api.orders.id
  deployment_id = aws_api_gateway_deployment.orders.id
  stage_name    = var.environment
}