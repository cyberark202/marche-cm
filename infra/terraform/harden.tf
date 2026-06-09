# Hardening AWS Resources for Marché CM

# ── CloudFront Origin Access Control (OAC) ──────────────────────────────────
resource "aws_cloudfront_origin_access_control" "media" {
  name                              = "market-cm-oac"
  description                       = "OAC for Marché CM media bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── S3 Bucket Policy (CloudFront OAC only) ──────────────────────────────────
resource "aws_s3_bucket_policy" "media_policy" {
  bucket = aws_s3_bucket.media.id

  # Depends on the public access block configuration to avoid conflicts during apply
  depends_on = [aws_s3_bucket_public_access_block.media]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.media.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.media.arn
          }
        }
      }
    ]
  })
}

# ── S3 Public Access Block (Strict configuration) ──────────────────────────
resource "aws_s3_bucket_public_access_block" "media" {
  bucket = aws_s3_bucket.media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3 CORS Configuration (Restricted) ─────────────────────────────────────
resource "aws_s3_bucket_cors_configuration" "media_cors" {
  bucket = aws_s3_bucket.media.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = [
      "https://cm.digital-get.com",
      "https://df7t18zqeme69.cloudfront.net",
      "http://localhost:3000",
      "http://localhost:5001",
      "http://localhost:5003",
      "http://localhost:8000",
      "http://127.0.0.1:3000",
      "http://127.0.0.1:5001",
      "http://127.0.0.1:5003",
      "http://127.0.0.1:8000"
    ]
    expose_headers  = ["ETag", "Content-Type", "Content-Length"]
    max_age_seconds = 3000
  }
}

# ── S3 Server-Side Encryption (SSE-S3) ────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "media_encryption" {
  bucket = aws_s3_bucket.media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"  # SSE-S3 (AWS-managed keys)
    }
  }
}

# ── S3 Versioning (Recovery + Audit Trail) ─────────────────────────────────
resource "aws_s3_bucket_versioning" "media_versioning" {
  bucket = aws_s3_bucket.media.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── RDS Encryption (KMS Customer-Managed) ──────────────────────────────────
# NOTE: This requires RDS to be recreated with storage_encrypted = true
# Uncomment after backup is taken:
# resource "aws_kms_key" "rds" {
#   description             = "KMS key for RDS encryption"
#   deletion_window_in_days = 10
#   enable_key_rotation     = true
# }
#
# resource "aws_kms_alias" "rds" {
#   name          = "alias/marche-cm-rds"
#   target_key_id = aws_kms_key.rds.key_id
# }

# ── AWS Budget (Monthly Alerts) ────────────────────────────────────────────
resource "aws_budgets_budget" "monthly_budget" {
  name              = "marche-cm-monthly-budget"
  budget_type       = "COST"
  limit_amount      = "300"  # Increased from $50 for production
  limit_unit        = "USD"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }
}
