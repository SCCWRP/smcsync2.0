import boto3
import requests
import zipfile
import io, os, sys
import pandas as pd
from utils.scrape import scrape_href_from_url
from dotenv import load_dotenv
load_dotenv()

def data_ca_gov_to_sccwrp_s3():
    
    urls = {
        'benthic': 'https://data.ca.gov/dataset/c14a017a-8a8c-42f7-a078-3ab64a873e32/resource/eb61f9a1-b1c6-4840-99c7-420a2c494a43'
    }

    for dtype, url in urls.items():
        print("Fetching download link...")
        link = scrape_href_from_url(url)
        print("Got the download link:", link)

        # Download ZIP to memory
        response = requests.get(link, headers = {'User-Agent': 'Mozilla/5.0'})
        zip_buffer = io.BytesIO(response.content)


        s3_client = boto3.client('s3')

        with zipfile.ZipFile(zip_buffer) as zip_file:
            parquet_filenames = [name for name in zip_file.namelist() if name.endswith('.parquet')]
            for parquet_filename in parquet_filenames:
                print("Found parquet file:", parquet_filename)
            
                # Read parquet content and upload directly to S3
                with zip_file.open(parquet_filename) as parquet_file:
                    s3_client.upload_fileobj(
                        parquet_file,
                        os.getenv('CEDEN_RAW_DATA_BUCKET'),
                        f'{dtype}/{parquet_filename}'
                    )
                print(f"Uploaded {parquet_filename} to S3")

if __name__ == "__main__":
    data_ca_gov_to_sccwrp_s3()