import os
import json
from datetime import datetime
from kafka import KafkaProducer
import socket

from aws_msk_iam_sasl_signer import MSKAuthTokenProvider


class MSKTokenProvider():
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token('us-east-1')
        return token

def lambda_handler(event, context):
    # Get the bootstrap server and topic from environment variables
    bootstrap_server = os.environ.get('BS')
    topic = os.environ.get('TOPIC')

    print(event)
    print(context)

    if not bootstrap_server or not topic:
        raise ValueError("Bootstrap server and topic must be provided as environment variables")

    tp = MSKTokenProvider()

    # Create the Kafka producer with IAM SASL
    producer = KafkaProducer(
        bootstrap_servers=os.getenv('BS'),
        security_protocol='SASL_SSL',
        sasl_mechanism='OAUTHBEARER',
        sasl_oauth_token_provider=tp,
   )

    # Emit the current time
    current_time = datetime.utcnow().isoformat()
    message = json.dumps({'timestamp': current_time, "aws.request_id": context.aws_request_id}).encode('utf-8')

    # Send the message to the Kafka topic
    producer.send(topic, message)
    producer.flush()

    return {
        'statusCode': 200,
        'body': json.dumps('Message sent successfully!')
    }


if __name__ == "__main__":
    # For local testing purposes
    print(lambda_handler({}, {}))
