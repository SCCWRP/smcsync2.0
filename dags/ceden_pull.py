from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

# Technically, it pulls data from data.ca.gov. But we typically refer to it as CEDEN data, since CEDEN uploads their data there.
from utils.scrape import ceden2s3



# Define the DAG
with DAG(
    dag_id="ceden_data_pull",
    start_date=datetime(2025, 1, 1),
    schedule_interval="@daily",  # Run daily, adjust as needed
    catchup=False,
    tags=["smc", "data-ingestion", "ceden"],
    description="Pull CEDEN data from data.ca.gov and upload to S3"
) as dag:
    
    # Create the data pull task
    pull_ceden_data = PythonOperator(
        task_id="pull_ceden_data",
        python_callable=ceden2s3,
        doc_md="""
        ### Pull CEDEN Data Task
        
        This task downloads benthic data from the California Open Data Portal
        and uploads it to the S3 bucket for further processing.
        
        - Source: data.ca.gov CEDEN dataset
        - Destination: S3 bucket 'ceden-raw-data'
        - Format: Parquet files
        """
    )