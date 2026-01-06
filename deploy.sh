#!/bin/zsh

# Upload DAGs
aws s3 sync ./dags s3://airflow-smc-pipelines/dags/ --delete \
	--exclude "__pycache__/*" \
	--exclude "*.pyc"

# Upload requirements.txt to bucket root
aws s3 cp requirements.txt s3://airflow-smc-pipelines/requirements.txt
# Upload versioned requirements to force MWAA refresh
aws s3 cp requirements-2026-01-05.txt s3://airflow-smc-pipelines/requirements-2026-01-05.txt