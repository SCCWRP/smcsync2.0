# SMC Sync 2.0 - Airflow Development Guide

## Overview

This project includes both local Airflow development environment and AWS MWAA (Managed Workflows for Apache Airflow) CloudFormation deployment.

## Local Development with Docker

### Prerequisites
- Docker Desktop installed and running
- At least 4GB of RAM allocated to Docker

### Quick Start

1. **Create environment file**:
   ```bash
   cp .env.example .env
   ```

2. **Start Airflow**:
   ```bash
   docker-compose up -d
   ```
   
   This will:
   - Start PostgreSQL database
   - Initialize Airflow database
   - Start Airflow webserver on http://localhost:8080
   - Start Airflow scheduler

3. **Access Airflow UI**:
   - URL: http://localhost:8080
   - Username: `airflow`
   - Password: `airflow`

4. **Install Python dependencies** (if needed):
   
   The requirements from `requirements.txt` are automatically available since the `tasks/` folder is mounted.
   
   To install additional packages, edit `.env` file:
   ```bash
   _PIP_ADDITIONAL_REQUIREMENTS=beautifulsoup4 boto3 pandas requests
   ```
   
   Then restart:
   ```bash
   docker-compose down
   docker-compose up -d
   ```

5. **View logs**:
   ```bash
   docker-compose logs -f airflow-scheduler
   docker-compose logs -f airflow-webserver
   ```

6. **Stop Airflow**:
   ```bash
   docker-compose down
   ```

7. **Clean up everything** (removes database):
   ```bash
   docker-compose down -v
   ```

### Project Structure

```
.
├── dags/                    # DAG definitions (auto-synced to Airflow)
├── tasks/                   # Custom Python modules for tasks
├── logs/                    # Airflow logs (created by Docker)
├── plugins/                 # Airflow plugins (created by Docker)
├── requirements.txt         # Python dependencies for MWAA
├── docker-compose.yml       # Local Airflow setup
└── cloudformation-mwaa.yaml # AWS MWAA deployment
```

### Debugging DAGs

#### Common Issues

**DAGs not showing up?**

1. Check for Python syntax errors:
   ```bash
   docker-compose exec airflow-scheduler python /opt/airflow/dags/main.py
   ```

2. Check scheduler logs:
   ```bash
   docker-compose logs airflow-scheduler | grep ERROR
   ```

3. Verify DAG file location:
   - DAGs must be in the `dags/` folder
   - Must contain a DAG object
   - File must be importable Python

**Import errors?**

- Make sure dependencies are installed (see step 4 in Quick Start)
- The `tasks/` folder is mounted, so imports like `from tasks.utils.scrape import...` should work

**DAG paused by default?**

- Unpause in UI, or set in DAG:
  ```python
  dag = DAG(
      'my_dag',
      is_paused_upon_creation=False,
      ...
  )
  ```

## AWS MWAA Deployment

### Prerequisites
- AWS CLI configured with appropriate credentials
- CloudFormation permissions
- S3 permissions

### Deploy MWAA Environment

1. **Deploy CloudFormation stack**:
   ```bash
   aws cloudformation create-stack \
     --stack-name smc-airflow-stack \
     --template-body file://cloudformation-mwaa.yaml \
     --capabilities CAPABILITY_IAM \
     --parameters \
       ParameterKey=EnvironmentName,ParameterValue=smc-airflow-env \
       ParameterKey=AirflowVersion,ParameterValue=2.7.2 \
       ParameterKey=MaxWorkers,ParameterValue=2 \
       ParameterKey=MinWorkers,ParameterValue=1
   ```

2. **Wait for stack creation** (takes 20-30 minutes):
   ```bash
   aws cloudformation wait stack-create-complete \
     --stack-name smc-airflow-stack
   ```

3. **Get the S3 bucket name**:
   ```bash
   aws cloudformation describe-stacks \
     --stack-name smc-airflow-stack \
     --query 'Stacks[0].Outputs[?OutputKey==`MWAABucketName`].OutputValue' \
     --output text
   ```

4. **Update deploy.sh with new bucket name** and deploy:
   ```bash
   # Update the bucket name in deploy.sh first!
   ./deploy.sh
   ```

5. **Get the Airflow Web UI URL**:
   ```bash
   aws cloudformation describe-stacks \
     --stack-name smc-airflow-stack \
     --query 'Stacks[0].Outputs[?OutputKey==`MWAAWebServerUrl`].OutputValue' \
     --output text
   ```

### What the CloudFormation Template Creates

The template creates a complete MWAA environment:

1. **Networking**:
   - VPC with public and private subnets in 2 availability zones
   - Internet Gateway for public subnets
   - NAT Gateways for private subnets
   - Route tables and security groups

2. **Storage**:
   - S3 bucket for DAGs, requirements, and plugins
   - Versioning enabled for better tracking

3. **MWAA Environment**:
   - Apache Airflow 2.7.2
   - Public web server access
   - CloudWatch logging enabled
   - IAM role with necessary permissions

### Common MWAA Issues

**DAGs not showing up in MWAA?**

1. **Check S3 structure**:
   ```
   s3://your-bucket-name/
   ├── dags/
   │   ├── main.py
   │   ├── hello_dag.py
   │   └── test_dag.py
   └── requirements.txt
   ```

2. **Check requirements.txt is at bucket root**:
   ```bash
   aws s3 ls s3://your-bucket-name/requirements.txt
   ```

3. **Verify DAG file has no syntax errors** locally first:
   ```bash
   docker-compose up -d
   # Check if DAG appears at http://localhost:8080
   ```

4. **Check CloudWatch logs**:
   - Go to CloudWatch > Log groups
   - Look for `/aws/mwaa/smc-airflow-env/`
   - Check `dag-processing`, `scheduler`, and `task` logs

5. **Common mistakes**:
   - DAG files in wrong S3 path (must be in `dags/` folder)
   - Missing dependencies in `requirements.txt`
   - Import errors from local modules
   - DAG definition syntax errors

**Module import errors in MWAA?**

If you have custom modules (like `tasks/` folder):

1. **Option 1: Include as part of DAG folder**:
   ```bash
   aws s3 sync ./dags s3://bucket/dags/
   aws s3 sync ./tasks s3://bucket/dags/tasks/
   ```
   
   Then import as: `from tasks.utils.scrape import ...`

2. **Option 2: Create plugins.zip**:
   ```bash
   cd tasks
   zip -r ../plugins.zip .
   cd ..
   aws s3 cp plugins.zip s3://bucket/plugins.zip
   ```
   
   Update MWAA environment to use `PluginsS3Path: plugins.zip`

**Requirements update not taking effect?**

MWAA caches requirements. To force update:
1. Change the requirements.txt content
2. Wait 10-15 minutes
3. Or trigger environment update via AWS Console

### Docker Images with MWAA

**Can you use Docker images with MWAA?**

MWAA doesn't support custom Docker images directly. Instead:

1. **Use requirements.txt** for Python packages (what you're currently doing)
2. **Use plugins.zip** for custom Python modules
3. **Use startup script** (advanced) for system-level dependencies

For most use cases (like yours), `requirements.txt` is sufficient. Custom Docker images are only needed for:
- System-level dependencies (C libraries, etc.)
- Complex dependency conflicts
- Custom Airflow providers

**Your current approach is correct**: Just use `requirements.txt` with `beautifulsoup4`, `boto3`, `pandas`, and `requests`.

## Development Workflow

### Recommended Workflow

1. **Develop locally**:
   ```bash
   docker-compose up -d
   # Edit DAGs in dags/ folder
   # Test in local Airflow at http://localhost:8080
   ```

2. **Test DAG runs locally** before deploying to AWS

3. **Deploy to MWAA**:
   ```bash
   ./deploy.sh
   ```

4. **Monitor in AWS**:
   - Check MWAA UI for DAG appearance (can take 2-5 minutes)
   - Check CloudWatch logs for errors

### Updating Dependencies

1. Update `requirements.txt`
2. Test locally:
   ```bash
   docker-compose down
   # Edit .env to add _PIP_ADDITIONAL_REQUIREMENTS
   docker-compose up -d
   ```
3. Deploy to MWAA:
   ```bash
   aws s3 cp requirements.txt s3://your-bucket/requirements.txt
   ```

## Troubleshooting

### Local Airflow Issues

**Port 8080 already in use?**

Change port in docker-compose.yml:
```yaml
ports:
  - "8081:8080"  # Change 8081 to any free port
```

**Permission denied errors?**

On Linux, set correct UID in `.env`:
```bash
echo "AIRFLOW_UID=$(id -u)" >> .env
```

### MWAA Issues

**Stack creation failed?**

Most common causes:
- Insufficient IAM permissions
- Region doesn't support MWAA
- Not enough Elastic IPs available

Check CloudFormation Events in AWS Console for specific error.

**Environment stuck in "Creating"?**

This is normal - MWAA takes 20-30 minutes to create.

**Can't access Web UI?**

- WebserverAccessMode is set to PUBLIC_ONLY
- Check that IAM user has permission to access MWAA
- May need to add IAM policy for `airflow:CreateWebLoginToken`

## Cost Considerations

**Local Development**: Free (just uses your computer resources)

**MWAA on AWS**:
- Base environment (mw1.small): ~$0.49/hour
- Additional workers: ~$0.30/hour each
- Total estimated cost: ~$360-500/month for a small environment

To minimize costs:
- Use local development for testing
- Keep MinWorkers at 1
- Delete stack when not in use:
  ```bash
  aws cloudformation delete-stack --stack-name smc-airflow-stack
  ```

## Additional Resources

- [Apache Airflow Documentation](https://airflow.apache.org/docs/)
- [MWAA User Guide](https://docs.aws.amazon.com/mwaa/latest/userguide/)
- [MWAA Best Practices](https://docs.aws.amazon.com/mwaa/latest/userguide/best-practices.html)
