resource "aws_cloudfront_distribution" "media" {
  origin {
    domain_name              = aws_s3_bucket.media.bucket_regional_domain_name
    origin_id                = "S3-market-cm"
    origin_access_control_id = aws_cloudfront_origin_access_control.media.id
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront for Marché CM public media"
  default_root_object = ""

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-market-cm"
    compress         = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_All"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Environment = var.environment
    Project     = "marche-cm"
  }
}

output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.media.domain_name
}

