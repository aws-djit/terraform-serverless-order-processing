import json
import os
import boto3

# Connect to AWS DynamoDB
dynamodb = boto3.resource("dynamodb")

# Connect to AWS SNS
sns = boto3.client("sns")

# Read environment variables
table = dynamodb.Table(os.environ["TABLE_NAME"])
SNS_ARN = os.environ["SNS_ARN"]


def lambda_handler(event, context):

    # Read messages from SQS
    for record in event["Records"]:

        # Convert SQS message body into Python dictionary
        order = json.loads(record["body"])

        # Save order details into DynamoDB
        table.put_item(
            Item=order
        )

        # Prepare customer email message
        message = (
            f"Hello {order['customer_name']},\n\n"
            f"Your order has been received successfully.\n"
            f"Order ID: {order['order_id']}\n"
            f"Product: {order['product']}\n"
            f"Quantity: {order['quantity']}\n"
            f"Status: {order['status']}"
        )

        # Send email through SNS
        sns.publish(
            TopicArn=SNS_ARN,
            Subject="Order Confirmation",
            Message=message
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "message": "Orders processed successfully"
        })
    }