# Quick Reference: DAG Troubleshooting

If your DAGs aren't showing up in Airflow (local or MWAA), follow these steps:

## Local Development (Docker)

1. **Start Airflow**:
   ```bash
   cp .env.example .env
   docker-compose up -d
   ```

2. **Access**: http://localhost:8080 (airflow/airflow)

3. **Check for errors**:
   ```bash
   docker-compose logs airflow-scheduler | grep ERROR
   docker-compose exec airflow-scheduler python /opt/airflow/dags/main.py
   ```

## MWAA Deployment

1. **Deploy stack** (first time, takes 20-30 min):
   ```bash
   aws cloudformation create-stack \
     --stack-name smc-airflow-stack \
     --template-body file://cloudformation-mwaa.yaml \
     --capabilities CAPABILITY_IAM
   ```

2. **Get bucket name**:
   ```bash
   aws cloudformation describe-stacks \
     --stack-name smc-airflow-stack \
     --query 'Stacks[0].Outputs[?OutputKey==`MWAABucketName`].OutputValue' \
     --output text
   ```

3. **Update deploy.sh with bucket name**, then deploy:
   ```bash
   ./deploy.sh
   ```

4. **Check CloudWatch Logs**:
   - Log group: `/aws/mwaa/smc-airflow-env/`
   - Check: `dag-processing`, `scheduler`, `task` logs

## Common Issues

### DAGs not appearing?
- ✅ Check syntax: Test locally first
- ✅ Verify S3 structure: `dags/` folder contains DAG files
- ✅ Check requirements.txt: At bucket root, not in dags/
- ✅ Wait: MWAA can take 2-5 minutes to detect new DAGs
- ✅ Check imports: Custom modules must be in S3

### Import errors?
- **Local**: Edit `.env`, add to `_PIP_ADDITIONAL_REQUIREMENTS`
- **MWAA**: Add to `requirements.txt`, re-upload to S3 root

### Tasks folder not found?
Upload tasks with DAGs:
```bash
aws s3 sync ./tasks s3://your-bucket/dags/tasks/
```

## Full Documentation

See [DEVELOPMENT.md](DEVELOPMENT.md) for complete guide.
