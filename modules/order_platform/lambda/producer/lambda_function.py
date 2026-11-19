import json
import os
import uuid
import boto3

# Connect to AWS SQS
sqs = boto3.client("sqs")

# Get SQS URL from Lambda environment variable
QUEUE_URL = os.environ["SQS_URL"]


def lambda_handler(event, context):

    try:
        # Read request body from API Gateway
        body = event.get("body")

        if isinstance(body, str):
            order = json.loads(body)
        elif isinstance(body, dict):
            order = body
        else:
            order = {}

        # Validate required fields
        if not order.get("customer_name") or not order.get("product"):
            return {
                "statusCode": 400,
                "body": json.dumps({
                    "message": "customer_name and product are required"
                })
            }

        # Generate unique order ID
        order_id = str(uuid.uuid4())

        # Prepare order message
        message = {
            "order_id": order_id,
            "customer_name": order["customer_name"],
            "product": order["product"],
            "quantity": int(order.get("quantity", 1)),
            "status": "ORDER_RECEIVED"
        }

        # Send order message to SQS
        sqs.send_message(
            QueueUrl=QUEUE_URL,
            MessageBody=json.dumps(message)
        )

        # Return successful response
        return {
            "statusCode": 202,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "message": "Order submitted successfully",
                "order_id": order_id
            })
        }

    except (ValueError, TypeError, KeyError) as error:

        return {
            "statusCode": 400,
            "body": json.dumps({
                "message": str(error)
            })
        }