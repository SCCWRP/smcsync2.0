#!/bin/zsh

STACK_NAME=smc-pipelines-airflow-stack
CHANGE_SET_NAME="${STACK_NAME}-changeset-$(date +%s)"

echo "Checking if stack exists..."

# Check if stack exists and get its status
STACK_STATUS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --query 'Stacks[0].StackStatus' --output text 2>/dev/null)

if [ -n "$STACK_STATUS" ] && [ "$STACK_STATUS" != "None" ]; then
    echo "Stack exists with status: $STACK_STATUS"
    
    # Handle failed states - must delete first
    if [[ "$STACK_STATUS" == "ROLLBACK_FAILED" ]] || [[ "$STACK_STATUS" == "ROLLBACK_COMPLETE" ]] || [[ "$STACK_STATUS" == "CREATE_FAILED" ]] || [[ "$STACK_STATUS" == "DELETE_FAILED" ]]; then
        echo "Stack is in a failed state ($STACK_STATUS). Deleting stack first..."
        aws cloudformation delete-stack --stack-name $STACK_NAME
        
        echo "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME
        
        echo "Stack deleted. Proceeding with creation..."
        STACK_STATUS=""  # Reset so we create below
    fi
fi

if [ -n "$STACK_STATUS" ]; then
    echo "Updating existing stack via change set..."
    
    # Create change set
    aws cloudformation create-change-set \
        --stack-name $STACK_NAME \
        --change-set-name $CHANGE_SET_NAME \
        --template-body file://cloudformation-mwaa.yaml \
        --capabilities CAPABILITY_IAM
    
    echo "Waiting for change set to be created..."
    aws cloudformation wait change-set-create-complete \
        --stack-name $STACK_NAME \
        --change-set-name $CHANGE_SET_NAME
    
    # Check if change set has changes
    CHANGE_COUNT=$(aws cloudformation describe-change-set \
        --stack-name $STACK_NAME \
        --change-set-name $CHANGE_SET_NAME \
        --query 'length(Changes)' \
        --output text)
    
    if [ "$CHANGE_COUNT" = "0" ] || [ "$CHANGE_COUNT" = "None" ]; then
        echo "No changes detected. Deleting change set..."
        aws cloudformation delete-change-set \
            --stack-name $STACK_NAME \
            --change-set-name $CHANGE_SET_NAME
    else
        echo "Changes detected: $CHANGE_COUNT change(s)"
        echo "Executing change set..."
        aws cloudformation execute-change-set \
            --stack-name $STACK_NAME \
            --change-set-name $CHANGE_SET_NAME
        
        echo "Waiting for stack update to complete..."
        aws cloudformation wait stack-update-complete --stack-name $STACK_NAME
        echo "Stack updated successfully!"
    fi
else
    echo "Stack does not exist. Creating new stack..."
    
    # Create stack
    aws cloudformation create-stack \
        --stack-name $STACK_NAME \
        --template-body file://cloudformation-mwaa.yaml \
        --capabilities CAPABILITY_IAM
    
    echo "Waiting for stack creation to complete (this takes 20-30 minutes)..."
    aws cloudformation wait stack-create-complete --stack-name $STACK_NAME
    
    if [ $? -ne 0 ]; then
        echo "ERROR: Stack creation failed!"
        echo "Checking failure reason..."
        aws cloudformation describe-stack-events \
            --stack-name $STACK_NAME \
            --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
            --output table
        exit 1
    fi
    
    echo "Stack created successfully!"
fi

# Get bucket name
echo "Getting S3 bucket name..."
BUCKET_NAME=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`MWAABucketName`].OutputValue' \
    --output text)

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" = "None" ]; then
    echo "ERROR: Could not get bucket name. Stack may have failed."
    exit 1
fi

echo "Bucket name: $BUCKET_NAME"

# Upload DAGs
echo "Uploading DAGs to S3..."
aws s3 sync ./dags s3://$BUCKET_NAME/dags/ --delete \
    --exclude "__pycache__/*" \
    --exclude "*.pyc"

# Upload tasks folder (so imports work)
# will apply this later - first i just want to see any DAG show up in the airflow ui
# echo "Uploading tasks module to S3..."
# aws s3 sync ./tasks s3://$BUCKET_NAME/dags/tasks/ --delete \
#     --exclude "__pycache__/*" \
#     --exclude "*.pyc"

# Upload requirements.txt to bucket root
echo "Uploading requirements.txt..."
aws s3 cp requirements.txt s3://$BUCKET_NAME/requirements.txt

echo "Deployment complete!"
echo "MWAA Web UI: https://$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].Outputs[?OutputKey==`MWAAWebServerUrl`].OutputValue' \
    --output text)"
