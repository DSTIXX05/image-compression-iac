import boto3
from PIL import Image
import io
import os
import json

s3 = boto3.client("s3")
sns = boto3.client("sns")

def compress_image(image_bytes):
    image = Image.open(io.BytesIO(image_bytes))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=20)
    return buffer.getvalue()

def publish_notification(status, key, error_message=None):
    dest_bucket = os.environ.get("DEST_BUCKET")
    sns_topic_arn = os.environ.get("SNS_TOPIC_ARN")
    
    if status == "success":
        message = f"Image compression successful!\n\nFile: {key}\nDestination bucket: {dest_bucket}"
    else:
        message = f"Image compression failed!\n\nFile: {key}\nError: {error_message}"
    
    sns.publish(
        TopicArn=sns_topic_arn,
        Subject=f"Image Compression {status.upper()}: {key}",
        Message=message
    )

def handler(event, context):
    dest_bucket = os.environ.get("DEST_BUCKET")
    failed_bucket = os.environ.get("FAILED_BUCKET")

    if not dest_bucket or not failed_bucket:
        raise RuntimeError("DEST_BUCKET or FAILED_BUCKET environment variables not set")

    for record in event["Records"]:
        src_bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        try:
            obj = s3.get_object(Bucket=src_bucket, Key=key)
            compressed = compress_image(obj["Body"].read())

            s3.put_object(
                Bucket=dest_bucket,
                Key=key,
                Body=compressed,
                ContentType="image/jpeg"
            )
            
            publish_notification("success", key)
            print(f"Successfully compressed: {key}")

        except Exception as e:
            error_message = str(e)
            print(f"Failed to compress {key}: {error_message}")
            
            # Move failed image to failed bucket
            try:
                obj = s3.get_object(Bucket=src_bucket, Key=key)
                s3.put_object(
                    Bucket=failed_bucket,
                    Key=key,
                    Body=obj["Body"].read(),
                    ContentType="image/jpeg"
                )
            except Exception as copy_error:
                print(f"Failed to copy {key} to failed bucket: {str(copy_error)}")
            
            # Notify admin of failure
            publish_notification("failed", key, error_message)

