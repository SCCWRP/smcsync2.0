from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta


def scrape_href_from_url(target_url):
    """Scrapes the href attribute of the <a> tag with class 'resource-url-analytics'"""
    try:
        import requests
        from bs4 import BeautifulSoup
        response = requests.get(target_url)
        response.raise_for_status()
        
        soup = BeautifulSoup(response.text, 'html.parser')
        link = soup.find('a', class_='resource-url-analytics')
        
        if link and 'href' in link.attrs:
            return link['href']
        else:
            print("No link with the specified class found.")
            return None
    except requests.RequestException as e:
        print(f"Error during request: {e}")
        return None


def data_ca_gov_to_sccwrp_s3():
    """Pull CEDEN data from data.ca.gov and upload to S3"""
    import boto3
    import requests
    import zipfile
    import io
    import os
    urls = {
        'benthic': 'https://data.ca.gov/dataset/c14a017a-8a8c-42f7-a078-3ab64a873e32/resource/eb61f9a1-b1c6-4840-99c7-420a2c494a43'
    }

    for dtype, url in urls.items():
        print("Fetching download link...")
        link = scrape_href_from_url(url)
        print("Got the download link:", link)

        # Download ZIP to memory
        response = requests.get(link, headers={'User-Agent': 'Mozilla/5.0'})
        zip_buffer = io.BytesIO(response.content)

        s3_client = boto3.client('s3')

        with zipfile.ZipFile(zip_buffer) as zip_file:
            parquet_filenames = [name for name in zip_file.namelist() if name.endswith('.parquet')]
            for parquet_filename in parquet_filenames:
                print("Found parquet file:", parquet_filename)
            
                # Read parquet content and upload directly to S3
                with zip_file.open(parquet_filename) as parquet_file:
                    bucket_name = os.getenv('CEDEN_RAW_DATA_BUCKET')
                    if not bucket_name:
                        raise ValueError("CEDEN_RAW_DATA_BUCKET environment variable not set")
                    
                    s3_client.upload_fileobj(
                        parquet_file,
                        bucket_name,
                        f'{dtype}/{parquet_filename}'
                    )
                print(f"Uploaded {parquet_filename} to S3")

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'ceden_data_sync',
    default_args=default_args,
    description='Sync CEDEN data from data.ca.gov to S3',
    schedule_interval='@daily',  # or use a cron expression
    start_date=datetime(2025, 12, 26),
    catchup=False,
    tags=['ceden', 's3'],
) as dag:
    
    ceden_to_s3_task = PythonOperator(
        task_id='pull_ceden_data_to_s3',
        python_callable=data_ca_gov_to_sccwrp_s3,
    )
    
    ceden_to_s3_task