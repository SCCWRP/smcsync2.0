import boto3
import requests
import requests
import zipfile
import io
from bs4 import BeautifulSoup

def scrape_href_from_url(target_url):
    """
    Scrapes the href attribute of the <a> tag with class 'resource-url-analytics' from the given URL.
    :param target_url: The URL to scrape.
    :return: The href attribute if found, otherwise None.
    """
    try:
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
    

# Pulls data from CEDEN (technically, data.ca.gov) and uploads to S3
def ceden2s3():
    
    urls = {
        'benthic': 'https://data.ca.gov/dataset/c14a017a-8a8c-42f7-a078-3ab64a873e32/resource/eb61f9a1-b1c6-4840-99c7-420a2c494a43',
        'habitat': 'https://data.ca.gov/dataset/surface-water-habitat-results/resource/0f83793d-1f12-4fee-87b2-45dcc1389f0c',
        'chemistry': 'https://data.ca.gov/dataset/28d7a81d-6458-47bd-9b79-4fcbfbb88671/resource/f4aa224d-4a59-403d-aad8-187955aa2e38'
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
                        'ceden-raw-data',
                        f'{dtype}/{parquet_filename}'
                    )
                print(f"Uploaded {parquet_filename} to S3")
