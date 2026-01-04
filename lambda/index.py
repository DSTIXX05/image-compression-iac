import boto3
from PIL import Image
import io
import os

s3 = boto3.client("s3")

def compress_image(image_bytes):
    image = Image.open(io.BytesIO(image_bytes))
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=20)
    return buffer.getvalue()

def handler(event, context):
    dest_bucket = os.environ.get("DEST_BUCKET")

    if not dest_bucket:
        raise RuntimeError("DEST_BUCKET environment variable not set")

    for record in event["Records"]:
        src_bucket = record["s3"]["bucket"]["name"]
        key = record["s3"]["object"]["key"]

        obj = s3.get_object(Bucket=src_bucket, Key=key)
        compressed = compress_image(obj["Body"].read())

        s3.put_object(
            Bucket=dest_bucket,
            Key=key,
            Body=compressed,
            ContentType="image/jpeg"
        )
