#!/bin/zsh
set -e

STACK_NAME="smc-pipelines-airflow-stack"
CHANGE_SET_NAME="${STACK_NAME}-changeset-$(date +%s)"
NO_CHANGESET=false

usage() {
    echo "Usage: $0 [--no-changeset]"
    echo "  --no-changeset  Skip CloudFormation, only upload DAGs and requirements.txt"
}

# -----------------------------
# Argument parsing
# -----------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-changeset)
            NO_CHANGESET=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# -----------------------------
# Helpers
# -----------------------------
get_bucket_name() {
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --query 'Stacks[0].Outputs[?OutputKey==`MWAABucketName`].OutputValue' \
        --output text
}

upload_dags_and_requirements() {
    local bucket="$1"

    if [[ -z "$bucket" || "$bucket" == "None" ]]; then
        echo "ERROR: Invalid S3 bucket name"
        exit 1
    fi

    echo "Uploading DAGs to s3://$bucket/dags/"
    aws s3 sync ./dags "s3://$bucket/dags/" --delete \
        --exclude "__pycache__/*" \
        --exclude "*.pyc"

    echo "Uploading requirements.txt"
    aws s3 cp requirements.txt "s3://$bucket/requirements.txt"
}

# -----------------------------
# --no-changeset path (EXIT EARLY)
# -----------------------------
if [[ "$NO_CHANGESET" == true ]]; then
    echo "Skipping CloudFormation — uploading DAGs only"

    BUCKET_NAME=$(get_bucket_name)

    if [[ -z "$BUCKET_NAME" || "$BUCKET_NAME" == "None" ]]; then
        echo "ERROR: Stack does not exist or has no MWAA bucket output"
        echo "Run without --no-changeset at least once to create the stack."
        exit 1
    fi

    upload_dags_and_requirements "$BUCKET_NAME"

    echo "DAG-only deployment complete"
    exit 0
fi

# -----------------------------
# CloudFormation deployment
# -----------------------------
echo "Checking CloudFormation stack status..."

STACK_STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || true)

if [[ -n "$STACK_STATUS" && "$STACK_STATUS" != "None" ]]; then
    echo "Stack exists with status: $STACK_STATUS"

    if [[ "$STACK_STATUS" =~ ^(ROLLBACK_FAILED|ROLLBACK_COMPLETE|CREATE_FAILED|DELETE_FAILED)$ ]]; then
        echo "Stack is in failed state — deleting"
        aws cloudformation delete-stack --stack-name "$STACK_NAME"
        aws cloudformation wait stack-delete-complete --stack-name "$STACK_NAME"
        STACK_STATUS=""
    fi
fi

if [[ -n "$STACK_STATUS" ]]; then
    echo "Updating stack via change set"

    aws cloudformation create-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --template-body file://cloudformation-mwaa.yaml \
        --capabilities CAPABILITY_IAM

    aws cloudformation wait change-set-create-complete \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME"

    CHANGE_COUNT=$(aws cloudformation describe-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --query 'length(Changes)' \
        --output text)

    if [[ "$CHANGE_COUNT" == "0" || "$CHANGE_COUNT" == "None" ]]; then
        echo "No infrastructure changes"
        aws cloudformation delete-change-set \
            --stack-name "$STACK_NAME" \
            --change-set-name "$CHANGE_SET_NAME"
    else
        aws cloudformation execute-change-set \
            --stack-name "$STACK_NAME" \
            --change-set-name "$CHANGE_SET_NAME"

        aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME"
    fi
else
    echo "Creating new stack"
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body file://cloudformation-mwaa.yaml \
        --capabilities CAPABILITY_IAM

    aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"
fi

# -----------------------------
# Upload DAGs after deploy
# -----------------------------
BUCKET_NAME=$(get_bucket_name)
upload_dags_and_requirements "$BUCKET_NAME"

echo "Deployment complete"
echo "MWAA Web UI: https://$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`MWAAWebServerUrl`].OutputValue' \
    --output text)"
