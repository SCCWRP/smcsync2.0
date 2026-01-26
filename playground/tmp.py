import daft
import boto3

chemfolderglob = "s3://ceden-raw-data/chemistry/*/**"

df = daft.read_parquet(chemfolderglob)