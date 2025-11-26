#!/bin/bash

# LocalStack SNS and SQS Setup Script
# This script creates all SNS topics, SQS queues, and subscriptions

set -e

echo "Starting LocalStack SNS/SQS setup..."

# AWS endpoint
ENDPOINT="http://localhost:4566"
REGION="us-east-2"
ACCOUNT_ID="167524899392"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Wait for LocalStack to be ready
echo "Waiting for LocalStack to be ready..."
until curl -s http://localhost:4566/_localstack/health | grep -q "\"sqs\": \"available\""; do
  sleep 2
done
echo -e "${GREEN}LocalStack is ready!${NC}"

# Create SNS Topics (FIFO)
echo -e "\n${YELLOW}Creating SNS Topics...${NC}"

# Capture topic ARNs from create-topic responses
NEW_PARTICIPATION_TOPIC_ARN=$(aws --endpoint-url=$ENDPOINT sns create-topic \
  --name new-participation-item.fifo \
  --attributes FifoTopic=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'TopicArn' \
  --output text)

VERIFICATION_COMPLETE_TOPIC_ARN=$(aws --endpoint-url=$ENDPOINT sns create-topic \
  --name participation-verification-complete.fifo \
  --attributes FifoTopic=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'TopicArn' \
  --output text)

VERIFICATION_TOPIC_ARN=$(aws --endpoint-url=$ENDPOINT sns create-topic \
  --name participation-verification.fifo \
  --attributes FifoTopic=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'TopicArn' \
  --output text)

echo -e "${GREEN}SNS Topics created successfully!${NC}"

# Create SQS Queues (FIFO)
echo -e "\n${YELLOW}Creating SQS Queues...${NC}"

# Main queues - capture queue URLs from create-queue response
OFFER_PERF_UPDATER_QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs create-queue \
  --queue-name offer-performance-updater.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'QueueUrl' \
  --output text)

PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs create-queue \
  --queue-name participation-verification-complete.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'QueueUrl' \
  --output text)

PARTICIPATION_VERIFICATION_QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs create-queue \
  --queue-name participation-verification.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'QueueUrl' \
  --output text)

# Dead Letter Queues
OFFER_PERF_UPDATER_DLQ_QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs create-queue \
  --queue-name offer-performance-updater-dlq.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'QueueUrl' \
  --output text)

PARTICIPATION_VERIFICATION_COMPLETE_DLQ_QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs create-queue \
  --queue-name participation-verification-complete-dlq.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'QueueUrl' \
  --output text)

PARTICIPATION_VERIFICATION_DLQ_QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs create-queue \
  --queue-name participation-verification-dlq.fifo \
  --attributes FifoQueue=true,ContentBasedDeduplication=true \
  --region $REGION \
  --query 'QueueUrl' \
  --output text)

echo -e "${GREEN}SQS Queues created successfully!${NC}"

# Get Queue ARNs for subscriptions
echo -e "\n${YELLOW}Getting Queue ARNs...${NC}"

OFFER_PERF_UPDATER_QUEUE_ARN=$(aws --endpoint-url=$ENDPOINT sqs get-queue-attributes \
  --queue-url "$OFFER_PERF_UPDATER_QUEUE_URL" \
  --attribute-names QueueArn \
  --region $REGION \
  --query 'Attributes.QueueArn' \
  --output text)

PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_ARN=$(aws --endpoint-url=$ENDPOINT sqs get-queue-attributes \
  --queue-url "$PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_URL" \
  --attribute-names QueueArn \
  --region $REGION \
  --query 'Attributes.QueueArn' \
  --output text)

PARTICIPATION_VERIFICATION_QUEUE_ARN=$(aws --endpoint-url=$ENDPOINT sqs get-queue-attributes \
  --queue-url "$PARTICIPATION_VERIFICATION_QUEUE_URL" \
  --attribute-names QueueArn \
  --region $REGION \
  --query 'Attributes.QueueArn' \
  --output text)

# Create SNS-SQS Subscriptions
echo -e "\n${YELLOW}Creating SNS-SQS Subscriptions...${NC}"

# Topic ARNs are already captured from create-topic responses above

# Set up queue policies to allow SNS to send messages
# Queue policy for offer-performance-updater.fifo
OFFER_PERF_UPDATER_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "$OFFER_PERF_UPDATER_QUEUE_ARN",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "$NEW_PARTICIPATION_TOPIC_ARN"
        }
      }
    }
  ]
}
EOF
)

# Queue policy for participation-verification-complete.fifo
PARTICIPATION_VERIFICATION_COMPLETE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "$PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_ARN",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "$VERIFICATION_COMPLETE_TOPIC_ARN"
        }
      }
    }
  ]
}
EOF
)

# Queue policy for participation-verification.fifo
PARTICIPATION_VERIFICATION_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "sns.amazonaws.com"
      },
      "Action": "sqs:SendMessage",
      "Resource": "$PARTICIPATION_VERIFICATION_QUEUE_ARN",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "$VERIFICATION_TOPIC_ARN"
        }
      }
    }
  ]
}
EOF
)

# Apply queue policies
# Export queue URLs for Python script
export OFFER_PERF_UPDATER_QUEUE_URL
export PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_URL
export PARTICIPATION_VERIFICATION_QUEUE_URL
export ENDPOINT
export REGION

# Use Python to properly escape and set policies
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

# Write policies to temp files
echo "$OFFER_PERF_UPDATER_POLICY" > "$TMP_DIR/policy1.json"
echo "$PARTICIPATION_VERIFICATION_COMPLETE_POLICY" > "$TMP_DIR/policy2.json"
echo "$PARTICIPATION_VERIFICATION_POLICY" > "$TMP_DIR/policy3.json"

# Use Python to create properly formatted attributes JSON
TMP_DIR=$TMP_DIR python3 <<PYEOF
import json
import subprocess
import sys
import os

endpoint = os.environ.get('ENDPOINT', 'http://localhost:4566')
region = os.environ.get('REGION', 'us-east-2')
tmp_dir = os.environ.get('TMP_DIR', '/tmp')

# Queue URLs from environment
queue_urls = [
    os.environ.get('OFFER_PERF_UPDATER_QUEUE_URL'),
    os.environ.get('PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_URL'),
    os.environ.get('PARTICIPATION_VERIFICATION_QUEUE_URL')
]

policy_files = [
    f"{tmp_dir}/policy1.json",
    f"{tmp_dir}/policy2.json",
    f"{tmp_dir}/policy3.json"
]

queue_names = [
    "offer-performance-updater.fifo",
    "participation-verification-complete.fifo",
    "participation-verification.fifo"
]

for queue_url, policy_file, queue_name in zip(queue_urls, policy_files, queue_names):
    if not queue_url:
        print(f"Error: Queue URL not set for {queue_name}", file=sys.stderr)
        continue
    
    with open(policy_file, 'r') as f:
        policy_json = f.read()
    
    # Policy attribute value must be a JSON string (the policy itself as a string)
    attributes = {"Policy": policy_json}
    attributes_json = json.dumps(attributes)
    
    cmd = [
        "aws", "--endpoint-url", endpoint,
        "sqs", "set-queue-attributes",
        "--queue-url", queue_url,
        "--attributes", attributes_json,
        "--region", region
    ]
    
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error setting policy for {queue_name}: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"✓ Policy set for {queue_name}")

PYEOF

# Function to create or update subscription with RawMessageDelivery
create_or_update_subscription() {
  local topic_arn=$1
  local queue_arn=$2
  local subscription_name=$3
  
  # Try to find existing subscription
  local subscription_arn=$(aws --endpoint-url=$ENDPOINT sns list-subscriptions-by-topic \
    --topic-arn "$topic_arn" \
    --region $REGION \
    --query "Subscriptions[?Endpoint=='$queue_arn'].SubscriptionArn" \
    --output text 2>/dev/null | head -n1)
  
  if [ -n "$subscription_arn" ] && [ "$subscription_arn" != "None" ] && [ "$subscription_arn" != "PendingConfirmation" ]; then
    # Subscription exists, update it
    echo "Updating existing subscription: $subscription_name"
    aws --endpoint-url=$ENDPOINT sns set-subscription-attributes \
      --subscription-arn "$subscription_arn" \
      --attribute-name RawMessageDelivery \
      --attribute-value true \
      --region $REGION
    echo -e "${GREEN}✓ Updated subscription: $subscription_name${NC}"
  else
    # Subscription doesn't exist, create it
    echo "Creating new subscription: $subscription_name"
    aws --endpoint-url=$ENDPOINT sns subscribe \
      --topic-arn "$topic_arn" \
      --protocol sqs \
      --notification-endpoint "$queue_arn" \
      --attributes RawMessageDelivery=true \
      --region $REGION > /dev/null
    echo -e "${GREEN}✓ Created subscription: $subscription_name${NC}"
  fi
}

# Subscription 1: new-participation-item.fifo -> offer-performance-updater.fifo
create_or_update_subscription "$NEW_PARTICIPATION_TOPIC_ARN" "$OFFER_PERF_UPDATER_QUEUE_ARN" "new-participation-item -> offer-performance-updater"

# Subscription 2: participation-verification-complete.fifo -> participation-verification-complete.fifo
create_or_update_subscription "$VERIFICATION_COMPLETE_TOPIC_ARN" "$PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_ARN" "participation-verification-complete -> participation-verification-complete"

# Subscription 3: participation-verification.fifo -> participation-verification.fifo
create_or_update_subscription "$VERIFICATION_TOPIC_ARN" "$PARTICIPATION_VERIFICATION_QUEUE_ARN" "participation-verification -> participation-verification"

echo -e "${GREEN}Subscriptions configured successfully!${NC}"

# Set up Dead Letter Queue policies (optional - configure redrive policy on main queues)
echo -e "\n${YELLOW}Configuring Dead Letter Queues...${NC}"

# Get DLQ ARNs
OFFER_PERF_UPDATER_DLQ_ARN=$(aws --endpoint-url=$ENDPOINT sqs get-queue-attributes \
  --queue-url "$OFFER_PERF_UPDATER_DLQ_QUEUE_URL" \
  --attribute-names QueueArn \
  --region $REGION \
  --query 'Attributes.QueueArn' \
  --output text)

PARTICIPATION_VERIFICATION_COMPLETE_DLQ_ARN=$(aws --endpoint-url=$ENDPOINT sqs get-queue-attributes \
  --queue-url "$PARTICIPATION_VERIFICATION_COMPLETE_DLQ_QUEUE_URL" \
  --attribute-names QueueArn \
  --region $REGION \
  --query 'Attributes.QueueArn' \
  --output text)

PARTICIPATION_VERIFICATION_DLQ_ARN=$(aws --endpoint-url=$ENDPOINT sqs get-queue-attributes \
  --queue-url "$PARTICIPATION_VERIFICATION_DLQ_QUEUE_URL" \
  --attribute-names QueueArn \
  --region $REGION \
  --query 'Attributes.QueueArn' \
  --output text)

# Set redrive policy on main queues (maxReceiveCount=3 means after 3 failed attempts, message goes to DLQ)
aws --endpoint-url=$ENDPOINT sqs set-queue-attributes \
  --queue-url "$OFFER_PERF_UPDATER_QUEUE_URL" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$OFFER_PERF_UPDATER_DLQ_ARN\\\",\\\"maxReceiveCount\\\":3}\"}" \
  --region $REGION

aws --endpoint-url=$ENDPOINT sqs set-queue-attributes \
  --queue-url "$PARTICIPATION_VERIFICATION_COMPLETE_QUEUE_URL" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$PARTICIPATION_VERIFICATION_COMPLETE_DLQ_ARN\\\",\\\"maxReceiveCount\\\":3}\"}" \
  --region $REGION

aws --endpoint-url=$ENDPOINT sqs set-queue-attributes \
  --queue-url "$PARTICIPATION_VERIFICATION_QUEUE_URL" \
  --attributes "{\"RedrivePolicy\":\"{\\\"deadLetterTargetArn\\\":\\\"$PARTICIPATION_VERIFICATION_DLQ_ARN\\\",\\\"maxReceiveCount\\\":3}\"}" \
  --region $REGION

echo -e "${GREEN}Dead Letter Queues configured successfully!${NC}"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}LocalStack SNS/SQS setup completed!${NC}"
echo -e "${GREEN}========================================${NC}"

