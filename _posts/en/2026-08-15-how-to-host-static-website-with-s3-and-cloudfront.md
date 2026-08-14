---
layout: post
title: "How to Host a Static Website with Amazon S3 and CloudFront"
image: https://fastly.picsum.photos/id/744/1200/630.jpg?hmac=kS4Oj4MhjZO_5wgBsLvMbWCz1I98gS21Ftba3BcV2c8
description: "Learn how to host a secure static website with Amazon S3 and Amazon CloudFront, including Origin Access Control, a private bucket, HTTPS, custom domains, cache invalidation, and Terraform."
author: Mark_Mew
categories: [AWS, S3, CloudFront]
tags: [AWS, S3, CloudFront, Terraform, Static Website]
keywords: [AWS, Amazon S3, CloudFront, Origin Access Control, OAC, Static Website, Terraform, HTTPS]
lang: en
date: 2026-08-15
---

The [previous article covered how to host a static website using Amazon S3 alone](/en/posts/how-to-host-static-website-on-s3/). This approach is simple, but the S3 Website endpoint supports HTTP only, and the bucket content must be publicly readable.

If you want HTTPS, a custom domain, caching, and clearer origin access control, place CloudFront in front of S3:

```text
User -- HTTPS --> CloudFront -- OAC / SigV4 --> Private S3 bucket
```

This article uses a regular S3 bucket endpoint as the CloudFront origin. It does not enable S3 static website hosting or make the bucket public. CloudFront signs requests with Origin Access Control (OAC), so only the specified CloudFront distribution can read objects in the bucket.

## S3 Website Endpoint vs. CloudFront Origin

When using CloudFront with OAC, the S3 bucket must use the regular S3 REST endpoint instead of the S3 Website endpoint.

| Architecture | S3 static website hosting | Public bucket | CloudFront OAC | HTTPS |
| --- | --- | --- | --- | --- |
| Direct S3 Website endpoint | Required | Required | Not supported | Not supported |
| S3 + CloudFront | Not required | Not required | Supported | Supported |

In other words, this article does not need `aws_s3_bucket_website_configuration` or a `public-read` ACL. S3 stores the files, while CloudFront handles the website entry point and HTTPS.

## Create a Private S3 Bucket

First, create an S3 bucket. The bucket name must follow DNS naming rules and be globally unique across all AWS accounts and Regions.

Use the following settings:

- Object Ownership: `Bucket owner enforced`
- ACLs: Disabled
- Block Public Access: Keep all four settings enabled
- Static website hosting: Disabled

When using OAC, AWS recommends `Bucket owner enforced` so that the bucket owns every object and access is managed entirely through the bucket policy. Because CloudFront signs requests with OAC, you do not need to make objects public through ACLs.

> The key point of this architecture is that the S3 bucket remains private. Do not add a public read policy with `Principal: "*"` just to make testing easier, or users could bypass CloudFront and access S3 objects directly.
{: .prompt-warning}

Upload the website files to the bucket, for example:

- `index.html`
- `error.html`
- CSS
- JavaScript
- Images and other static assets

## Create a CloudFront Distribution

Open the CloudFront Console and create a distribution with the following settings.

### Origin

Select the S3 bucket in Origin domain. Choose a regular S3 bucket origin; do not manually enter the S3 Website endpoint.

If you use an S3 origin, the Console will usually show an Origin access option. Select Origin access control settings and create or select an OAC.

![CloudFront Origin](/assets/img/cloudfront/cloudfront-origin.png)

![CloudFront Settings](/assets/img/cloudfront/cloudfront-settings.png)

### Origin Access Control

You can configure this while creating the CloudFront distribution. Select Origin access control settings. If the Console has already created an OAC, select it instead of creating another one.

![CloudFront Origin Access Control](/assets/img/cloudfront/cloudfront-origin-access-control.png)

### Default root object

Set the Default root object to:

```text
index.html
```

Enter only the file name and do not add a leading `/`. When a user opens the root URL of the CloudFront distribution, CloudFront returns `index.html`.

This is different from the Index document in S3 Website hosting. When CloudFront connects to a regular S3 origin, it does not automatically use the S3 Website configuration, so you must set the Default root object in the CloudFront distribution.

### Viewer protocol policy

In the default cache behavior, set the Viewer protocol policy to:

```text
Redirect HTTP to HTTPS
```

CloudFront will redirect HTTP requests from viewers to HTTPS.

For a typical static website, the allowed methods can be limited to:

- Allowed HTTP methods: `GET, HEAD`
- Cached HTTP methods: `GET, HEAD`

Add `OPTIONS` only if the website needs browsers to send OPTIONS requests. Static websites usually do not need `POST`, `PUT`, or `DELETE`.

### Origin access policy

After creating or editing the distribution, the CloudFront Console usually provides a bucket policy template. Add it under S3 Bucket → Permissions → Bucket policy, and make sure `AWS:SourceArn` contains the ARN of this distribution.

Conceptually, the policy looks like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipalReadOnly",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::YOUR_ACCOUNT_ID:distribution/YOUR_DISTRIBUTION_ID"
        }
      }
    }
  ]
}
```

This policy allows only the CloudFront service principal to read objects and limits the permission to the specified distribution through `AWS:SourceArn`. Do not change `Principal` to `*`, and do not add `s3:ListBucket`, `s3:PutObject`, or `s3:DeleteObject`.

After configuring the distribution in the Console, confirm that the bucket policy has been applied. If the Console only provides a Copy policy button, paste the policy into the S3 bucket policy manually.

## Configure Error Pages

When CloudFront cannot find an object in a private S3 origin, it commonly receives `403 Forbidden` rather than `404 Not Found`. You can add custom error responses in CloudFront:

![CloudFront Default Error Page](/assets/img/cloudfront/cloudfront-default-error-page.png)

| HTTP error code | Response page path | Response code |
| --- | --- | --- |
| `403` | `/error.html` | `404` |
| `404` | `/error.html` | `404` |

For a regular multi-page website, this lets visitors see a custom error page. For an SPA, you may route `403` and `404` to `/index.html` with a `200` response so that the frontend router handles the path. Otherwise, do not turn every missing URL into a successful page.

![CloudFront Customized Error Page](/assets/img/cloudfront/cloudfront-customized-error-page.png)

## Test with the CloudFront Default Domain

After the distribution is deployed, CloudFront provides a domain similar to:

```text
https://dxxxxxxxxxxxx.cloudfront.net
```

Open this URL and you should see the `index.html` stored in the S3 bucket. If you receive `403 Forbidden`, check the following in order:

1. The distribution has finished deploying.
2. The Default root object is `index.html` without a leading `/`.
3. `index.html` exists at the root of the bucket.
4. The origin uses the S3 REST endpoint, not the Website endpoint.
5. OAC is configured to `Sign requests`.
6. The bucket policy's `AWS:SourceArn` points to the correct distribution.
7. Block Public Access remains enabled and no other policy blocks CloudFront.

## Use a Custom Domain and HTTPS Certificate

The CloudFront default domain already supports HTTPS. To use your own domain, such as `www.example.com`, prepare the following:

1. Request a certificate in AWS Certificate Manager (ACM).
2. The certificate must be created in `us-east-1` to be used with CloudFront.
3. Add the custom domain under Alternate domain names in the CloudFront distribution.
4. Select the ACM certificate under Viewer certificate.
5. In your DNS service, create an Alias or CNAME record pointing to the CloudFront domain name.

With Route 53, you can create an Alias A record. With another DNS provider, use a CNAME pointing to `dxxxxxxxxxxxx.cloudfront.net`. After DNS propagation and CloudFront deployment are complete, the website will be available through the custom domain.

## Update Files and Invalidate the CloudFront Cache

CloudFront caches S3 objects. After uploading a new version of `index.html`, visitors may not see it immediately because an edge location may still have the old object cached.

You can create an invalidation in the CloudFront Console or use the AWS CLI:

```shell
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

`/*` clears the entire distribution cache and is convenient for testing or small websites. In production, invalidate only changed files such as `/index.html`, or add version numbers to filenames to reduce invalidation frequency and waiting time.

## Create It with Terraform

The following example creates a private S3 bucket, an OAC, a CloudFront distribution, and a bucket policy that allows only the specified CloudFront distribution to read S3 objects. It uses the CloudFront default domain and certificate; ACM and a custom domain can be added later.

Replace the bucket name with a name that follows DNS naming rules and is globally unique across all AWS accounts and Regions.

```terraform
resource "aws_s3_bucket" "static_website" {
  bucket = "YOUR_UNIQUE_BUCKET_NAME"
}

resource "aws_s3_bucket_ownership_controls" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "static_website" {
  name                              = "static-website-oac"
  description                       = "Access control for the private S3 static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_distribution" "static_website" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  origin {
    domain_name              = aws_s3_bucket.static_website.bucket_regional_domain_name
    origin_id                = "s3-static-website"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_website.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-static-website"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.caching_optimized.id
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "allow_cloudfront_read" {
  statement {
    sid    = "AllowCloudFrontServicePrincipalReadOnly"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static_website.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.static_website.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "allow_cloudfront_read" {
  bucket = aws_s3_bucket.static_website.id
  policy = data.aws_iam_policy_document.allow_cloudfront_read.json
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.static_website.domain_name
}
```

This example does not use `aws_s3_bucket_website_configuration` or create a public ACL. After `terraform apply`, you still need to upload `index.html`, `error.html`, and other website files to S3. You can use the AWS CLI, a CI/CD pipeline, or additional `aws_s3_object` resources to manage the files.

To add a custom domain, create the ACM certificate with a `us-east-1` provider and configure `aliases` and `viewer_certificate.acm_certificate_arn` on the CloudFront distribution. The certificate must pass DNS validation before CloudFront can use it.

## Monitor Usage and Costs

CloudFront can incur charges for requests, data transfer, and caching-related usage. S3 can also incur charges for storage, requests, and data transfer. In addition to S3 usage, monitor CloudFront Requests, Bytes downloaded, 4xxErrorRate, and 5xxErrorRate.

For more detailed visibility into S3 request counts, errors, and latency, see [How to Enable Amazon S3 Request Metrics: Monitor Requests, Errors, and Latency with CloudWatch](/en/posts/enable-s3-metrics).

## Conclusion

S3 + CloudFront requires more configuration than a direct S3 Website endpoint, but it provides a more complete architecture:

- The S3 bucket can remain private.
- CloudFront accesses S3 through OAC without making the bucket public.
- CloudFront provides HTTPS and custom domain support.
- Static assets can be cached at edge locations.
- CloudFront invalidations can be used when cached content must be refreshed.

For quick testing or low-risk public content, the S3 Website endpoint from the previous article may be enough. For a production website, use an S3 REST origin with CloudFront OAC so that the appropriate service handles the website entry point, encrypted transport, and origin access control.

## References

- [Restrict access to an Amazon S3 origin with Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Specify a default root object](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DefaultRootObject.html)
- [Origin settings for CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistValuesOrigin.html)
- [Require HTTPS for communication between CloudFront and your Amazon S3 origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-https-cloudfront-to-s3-origin.html)
- [AWS Provider: aws_cloudfront_origin_access_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control)
- [AWS Provider: aws_cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)
