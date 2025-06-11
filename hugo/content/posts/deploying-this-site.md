+++
title = 'Automating the build and deploy of this site to AWS using GitHub Actions, Terraform, and Hugo'
date = 2025-06-10T23:22:53-04:00
featured_image = 'images/IMG_2010.jpeg'
tags = ["aws", "ci/cd", "terraform", "hugo"]
draft = false
+++
In this blog post, I will explain how this site is built and deployed to AWS.

There will be code snippets, but if you want to see the whole codebase for the site, you can see it at this repository: [SethFranklin/sethfranklin.com](https://github.com/SethFranklin/sethfranklin.com)

While I had my choice of cloud platform, domain registrar, and tools, other choices would work fine as well.

### AWS infrastructure

This site is a static site hosted on an S3 bucket with static website hosting enabled, behind a CloudFront distribution for CDN.

The SSL certificate for `sethfranklin.com` is also from AWS Certificate Manager.

### Domain registrar

I bought the domain `sethfranklin.com` on Cloudflare and use it to manage my DNS records.

### Tools used

Here are the tools I used to automate the build and deploy of the site:

- Terraform: I use Terraform to manage all of the AWS resources, as well as the DNS records on Cloudflare.
- Hugo: I chose Hugo as the static site generator. I like Hugo because I can write my blogs in Markdown in a text editor. Hugo also handles deploying the static files to the S3 bucket.
- GitHub Actions: I chose GitHub Actions as the CI/CD tool, mainly because it's free and each GitHub repository comes with a secret store that my pipeline can pull secrets from.

### Terraform

The Terraform code is in the [terraform](https://github.com/SethFranklin/sethfranklin.com/tree/main/terraform) directory of the repository.

Because I'm managing both the AWS resources and Cloudflare DNS records in Terraform, I can have my DNS records use values directly from my AWS resources. Below are a couple of examples.

```
resource "cloudflare_dns_record" "cloudfront" {
  zone_id = data.cloudflare_zone.website.zone_id
  comment = "AWS Cloudfront record"
  name    = var.domain_name
  type    = "CNAME"
  proxied = false
  ttl     = 60
  content = aws_cloudfront_distribution.website.domain_name
}
```

Above is the first example, where I set the CNAME record for `sethfranklin.com` to point to the CloudFront distribution's domain name.

```
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
```

Above is the second example, where I generate the SSL certificate for `sethfranklin.com` in AWS certificate manager.

I chose DNS as my validation method, which means that in order to validate that I own the domain, I have to set a specific CNAME record that AWS gives me.

So, I set the CNAME record in Cloudflare based on the information from AWS in the variable `aws_acm_certificate.website.domain_validation_options`

This variable is actually a set of objects, because you can request a certificate with multiple names (e.g. `api.sethfranklin.com` in addition to `sethfranklin.com`), which requires you to set multiple CNAME records ([AWS docs on this](https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html)).

Because I only have one name (`sethfranklin.com`), I used the `one()` function to select the single CNAME record to set. You could use a `for_each` loop to select multiple CNAME records to set if you had more names on the certificate.

### Hugo

The Hugo site content is in the [hugo](https://github.com/SethFranklin/sethfranklin.com/tree/main/hugo) directory of the repository.

This site uses the `ananke` theme.

I use the `extended/deploy` edition of Hugo so I can run `hugo deploy` to deploy the static files to S3.

```
[deployment]
  [[deployment.targets]]
    name = 'production'
    url = 'S3_BUCKET_URL'
```

In order to use `hugo deploy`, you have to set the above block in `hugo.toml`. In my CI/CD pipeline, one of the steps is to substitute `S3_BUCKET_URL` with the actual S3 bucket URL.

### GitHub Actions

The GitHub Actions pipeline is in the [.github/workflows](https://github.com/SethFranklin/sethfranklin.com/tree/main/.github/workflows) directory of the repository.

I will show some parts of the pipeline below.

```
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
  TF_VAR_aws_region: ${{ secrets.TF_VAR_AWS_REGION }}
  TF_VAR_cloudflare_api_token: ${{ secrets.TF_VAR_CLOUDFLARE_API_TOKEN }}
  TF_VAR_domain_name: ${{ secrets.TF_VAR_DOMAIN_NAME }}
  STATE_BUCKET: ${{ secrets.STATE_BUCKET }}
  STATE_KEY: ${{ secrets.STATE_KEY }}
```

Above are the secrets from my repository that I set as environment variables. GitHub Actions automatically scrubs these variables from any pipeline outputs, which is helpful since the GitHub repository is public.

```
- name: Terraform Apply
  working-directory: ./terraform
  run: terraform apply -auto-approve -input=false

- name: Output S3 bucket URL
  working-directory: ./terraform
  run: echo "S3_BUCKET_URL=$(terraform output s3_bucket_url | tr -d '"')" >> $GITHUB_ENV
```

Above is my `terraform apply` command, as well as a command that takes sets the environment variable `S3_BUCKET_URL` to the Terraform output `s3_bucket_url`.

I need to set this environment variable because Hugo needs to know the S3 bucket's URL to deploy the static files to.

```
- name: Set S3 bucket target
  working-directory: ./hugo
  run: sed -i -e 's@S3_BUCKET_URL@'"$S3_BUCKET_URL"'@g' hugo.toml
```

Above is the step that inserts the `S3_BUCKET_URL` into the `hugo.toml` file using `sed`.

```
- name: Build Hugo site
  working-directory: ./hugo
  run: hugo

- name: Hugo deploy
  working-directory: ./hugo
  run: hugo deploy
```

Above are the final steps that build the static files, and deploys them to S3.

### Conclusion

The outcome of this automation is that I can work on writing blog posts in Markdown locally, then publish them by pushing to GitHub.

This leaves me free to focus on writing blog posts instead of managing my site.

This is goal of platform engineering: Automate the build, test, and deploy of software, so your developers can focus on writing application code instead of manually managing complex deployments.
