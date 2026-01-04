import os
os.environ["DEST_BUCKET"] = "local-test-bucket"

from index import compress_image

with open("sample.jpg", "rb") as f:
    original = f.read()

compressed = compress_image(original)

with open("compressed.jpg", "wb") as f:
    f.write(compressed)

print("Compression successful")
