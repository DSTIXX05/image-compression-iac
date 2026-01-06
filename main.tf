//S3
resource "aws_s3_bucket" "source_bucket" {
  bucket        = "delightsome-original-images-bucket"
  force_destroy = true
}

resource "aws_s3_bucket" "failed_bucket" {
  bucket        = "delightsome-failed-images-bucket"
  force_destroy = true
}

resource "aws_s3_bucket" "destination_bucket" {
  bucket        = "delightsome-compressed-images-bucket"
  force_destroy = true
}

//Lambda
resource "aws_iam_role" "lambda_role" {
  name = "image_compressor_lambda_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "lambda_policy" {
  name = "image-compressor-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.source_bucket.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.destination_bucket.arn}/*",
          "${aws_s3_bucket.failed_bucket.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = aws_sns_topic.image_compression_notifications.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
  excludes    = ["PIL", "pillow-*.dist-info", "__pycache__", "*.jpg"]
}

resource "aws_lambda_layer_version" "pillow_layer" {
  filename         = "pillow-layer.zip"
  layer_name       = "pillow-python310"
  source_code_hash = filebase64sha256("pillow-layer.zip")
  compatible_runtimes = ["python3.10"]
}

resource "aws_lambda_function" "image_compressor" {
  function_name = "image-compressor"
  role          = aws_iam_role.lambda_role.arn
  handler       = "index.handler"
  runtime       = "python3.10"

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  layers = [aws_lambda_layer_version.pillow_layer.arn]

  environment {
    variables = {
      DEST_BUCKET   = aws_s3_bucket.destination_bucket.bucket
      FAILED_BUCKET = aws_s3_bucket.failed_bucket.bucket
      SNS_TOPIC_ARN = aws_sns_topic.image_compression_notifications.arn
    }
  }
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.image_compressor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.source_bucket.arn
}

resource "aws_s3_bucket_notification" "s3_notification" {
  bucket = aws_s3_bucket.source_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.image_compressor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".jpg"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

//SNS
resource "aws_sns_topic" "image_compression_notifications" {
  name = "image-compression-notifications"
}

resource "aws_sns_topic_subscription" "admin_email" {
  topic_arn = aws_sns_topic.image_compression_notifications.arn
  protocol  = "email"
  endpoint  = var.admin_email
}

