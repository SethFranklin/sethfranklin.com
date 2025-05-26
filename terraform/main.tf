
terraform {
  required_version = ">= 1.12.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.98.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.7.2"
    }
  }
  backend "s3" {
  }
}

provider "aws" {
  region = var.aws_region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "random" {
}

data "cloudflare_zone" "website" {
  filter = {
    name = var.domain_name
  }
}

resource "random_string" "bucket_name_affix" {
  length  = 62 - length(var.domain_name)
  special = false
  upper   = false
}

resource "aws_s3_bucket" "website" {
  bucket = "${var.domain_name}.${random_string.bucket_name_affix.result}"

  tags = {
    Name = var.domain_name
  }
}

resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "website" {
  bucket = aws_s3_bucket.website.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.website]
}

resource "aws_acm_certificate" "website" {
  domain_name       = var.domain_name
  validation_method = "DNS"

  tags = {
    Name = var.domain_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_dns_record" "validation" {
  zone_id = data.cloudflare_zone.website.zone_id
  comment = "AWS ACM Certificate validation record"
  name    = trim(one(aws_acm_certificate.website.domain_validation_options).resource_record_name, ".")
  type    = "CNAME"
  proxied = false
  ttl     = 60
  content = trim(one(aws_acm_certificate.website.domain_validation_options).resource_record_value, ".")
}

resource "aws_cloudfront_origin_access_control" "website" {
  name                              = var.domain_name
  description                       = var.domain_name
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name              = aws_s3_bucket.website.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.website.id
    origin_id                = var.domain_name
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.domain_name
  default_root_object = "index.html"

  aliases = [var.domain_name]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.domain_name

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  price_class = "PriceClass_100"

  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.website.arn
    ssl_support_method  = "sni-only"
  }

  tags = {
    Name = "New Tag"
  }
}

data "aws_iam_policy_document" "cloudfront_access_s3" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.website.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.website.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id
  policy = data.aws_iam_policy_document.cloudfront_access_s3.json
}

resource "cloudflare_dns_record" "cloudfront" {
  zone_id = data.cloudflare_zone.website.zone_id
  comment = "AWS Cloudfront record"
  name    = var.domain_name
  type    = "CNAME"
  proxied = false
  ttl     = 60
  content = aws_cloudfront_distribution.website.domain_name
}

