import requests
import zipfile
import io
import pandas as pd
from utils.scrape import scrape_href_from_url

link = scrape_href_from_url("https://data.ca.gov/dataset/c14a017a-8a8c-42f7-a078-3ab64a873e32/resource/eb61f9a1-b1c6-4840-99c7-420a2c494a43")

# Download ZIP to memory
response = requests.get(link, headers = {'User-Agent': 'Mozilla/5.0'})
zip_buffer = io.BytesIO(response.content)

# Extract and read parquet from ZIP
with zipfile.ZipFile(zip_buffer) as zip_file:
    # Get the parquet file name (assuming it's the first or only file)
    parquet_filename = [name for name in zip_file.namelist() if name.endswith('.parquet')][0]
    
    # Read parquet directly into pandas
    with zip_file.open(parquet_filename) as parquet_file:
        df = pd.read_parquet(parquet_file)
    
