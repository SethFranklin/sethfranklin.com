
variable "aws_region" {
  description = "The AWS region to deploy the resources to"
  type        = string
}

variable "domain_name" {
  description = "The domain name to use for the website"
  type        = string
}

variable "cloudflare_api_token" {
  description = "The Cloudflare API token to use"
  type        = string
  sensitive   = true
}

