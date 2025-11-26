#!/bin/bash

# Script to purge (flush) all messages from SQS queues in LocalStack

set -e

ENDPOINT="http://localhost:4566"
REGION="us-east-2"
ACCOUNT_ID="000000000000"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Purging all messages from SQS queues...${NC}"

# List of all queues to purge
QUEUES=(
    "offer-performance-updater.fifo"
    "participation-verification-complete.fifo"
    "participation-verification.fifo"
    "offer-performance-updater-dlq.fifo"
    "participation-verification-complete-dlq.fifo"
    "participation-verification-dlq.fifo"
)

for queue_name in "${QUEUES[@]}"; do
    echo -e "\n${YELLOW}Purging queue: ${queue_name}${NC}"
    
    # Get queue URL
    QUEUE_URL=$(aws --endpoint-url=$ENDPOINT sqs get-queue-url \
        --queue-name "$queue_name" \
        --region $REGION \
        --query 'QueueUrl' \
        --output text 2>/dev/null || echo "")
    
    if [ -z "$QUEUE_URL" ]; then
        echo -e "${RED}Queue not found: ${queue_name}${NC}"
        continue
    fi
    
    # Purge the queue
    if aws --endpoint-url=$ENDPOINT sqs purge-queue \
        --queue-url "$QUEUE_URL" \
        --region $REGION 2>/dev/null; then
        echo -e "${GREEN}✓ Purged: ${queue_name}${NC}"
    else
        echo -e "${RED}✗ Failed to purge: ${queue_name}${NC}"
    fi
done

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Queue purge completed!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Note: Purge operations may take up to 60 seconds to complete.${NC}"

