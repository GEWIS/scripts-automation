import boto3
import os
import json

# Set your config
S3_ENDPOINT="https://s3.nl-ams.scw.cloud"
BUCKET_NAME = 'gewisfiles01-mp3'
PREFIX = '2024'  # Optional: only restore files under a path
RESTORE_DAYS = 30  # Number of days to make restored object available

s3 = boto3.client(
    's3',
    endpoint_url=S3_ENDPOINT,
    aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
)

def restore_object(bucket, key):
    try:
        s3.restore_object(
            Bucket=bucket,
            Key=key,
            RestoreRequest={
                'Days': RESTORE_DAYS,
                'GlacierJobParameters': {
                    'Tier': 'Standard' 
                }
            }
        )
        print(f"Restore initiated: {key}")
    except Exception as e:
        if "RestoreAlreadyInProgress" in str(e):
            print(f"Restore already in progress: {key}")
        else:
            print(f"Failed to restore {key}: {e}")

def process_bucket():
    paginator = s3.get_paginator('list_objects_v2')
    for page in paginator.paginate(Bucket=BUCKET_NAME, Prefix=PREFIX):
        for obj in page.get('Contents', []):
            key = obj['Key']
            storage_class = obj.get('StorageClass', '')
            if storage_class.lower() == 'glacier':
                restore_object(BUCKET_NAME, key)
            else:
                print(f"Skipping (not Glacier): {key}")

if __name__ == '__main__':
    process_bucket()
