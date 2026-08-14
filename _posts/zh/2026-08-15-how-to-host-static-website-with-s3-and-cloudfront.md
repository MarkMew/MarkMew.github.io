---
layout: post
title: "如何使用 Amazon S3 搭配 CloudFront 架設靜態網站"
image: https://fastly.picsum.photos/id/744/1200/630.jpg?hmac=kS4Oj4MhjZO_5wgBsLvMbWCz1I98gS21Ftba3BcV2c8
description: "使用 Amazon S3 與 Amazon CloudFront 架設安全的靜態網站，介紹 Origin Access Control、私有 Bucket、HTTPS、自訂網域、快取失效與 Terraform 設定。"
author: Mark_Mew
categories: [AWS, S3, CloudFront]
tags: [AWS, S3, CloudFront, Terraform, Static Website]
keywords: [AWS, Amazon S3, CloudFront, Origin Access Control, OAC, Static Website, Terraform, HTTPS]
lang: zh-TW
date: 2026-08-15
---

上一篇文章介紹了[如何單獨使用 Amazon S3 架設靜態網站](/posts/how-to-host-static-website-on-s3/)。這種方式設定簡單，但 S3 Website endpoint 只支援 HTTP，而且必須讓 Bucket 內容可以被公開讀取。

如果網站希望使用 HTTPS、自訂網域、快取，以及更清楚的來源存取控制，可以讓 CloudFront 放在 S3 前面：

```text
使用者 -- HTTPS --> CloudFront -- OAC / SigV4 --> 私有 S3 Bucket
```

這篇文章會使用一般的 S3 Bucket endpoint 作為 CloudFront origin，不啟用 S3 靜態網站託管，也不公開 S3 Bucket。CloudFront 會透過 Origin Access Control（OAC）存取 Bucket，讓網站使用者只能從 CloudFront 取得內容。

## S3 Website endpoint 與 CloudFront origin 的差異

使用 CloudFront 搭配 OAC 時，S3 Bucket 必須使用一般的 S3 REST endpoint，而不是 S3 Website endpoint。兩者的差異如下：

| 架構 | S3 靜態網站託管 | Bucket 是否公開 | CloudFront OAC | HTTPS |
| --- | --- | --- | --- | --- |
| 直接使用 S3 Website endpoint | 需要 | 需要 | 不支援 | 不支援 |
| S3 + CloudFront | 不需要 | 不需要 | 支援 | 支援 |

也就是說，這一篇不需要建立 `aws_s3_bucket_website_configuration`，也不需要設定 `public-read` ACL。S3 只負責保存檔案，網站入口與 HTTPS 則交給 CloudFront 處理。

## 建立私有 S3 Bucket

首先建立一個 S3 Bucket。Bucket 名稱必須符合 DNS 命名規則，且在所有 AWS 帳號與 Region 中都必須唯一。

![S3 Create Bucket](/assets/img/s3/s3-create-bucket.png)

這次建議使用以下設定：

- Object Ownership：`Bucket owner enforced`
- ACL：停用
- Block Public Access：四個選項全部保持啟用
- Static website hosting：不啟用

![S3 Disable ACL](/assets/img/s3/s3-disable-acl.png)

![S3 Enable block public access](/assets/img/s3/s3-enable-block-public-access.png)


使用 OAC 時，AWS 建議使用 `Bucket owner enforced`，讓 Bucket 擁有所有物件，並完全以 Bucket policy 管理存取權限。CloudFront 會透過 OAC 存取 S3，因此不需要透過 ACL 公開物件。

> 這個架構的重點是 S3 Bucket 保持私有。不要為了測試方便而加入 `Principal: "*"` 的公開讀取 policy，否則使用者仍然可以繞過 CloudFront，直接讀取 S3 物件。
{: .prompt-warning}

接著將網站檔案上傳到 Bucket，例如：

- `index.html`
- `error.html`
- CSS
- JavaScript
- 圖片與其他靜態資源

## 建立 CloudFront Distribution

進入 CloudFront Console，建立新的 distribution，主要設定如下。

### Origin

在 Origin domain 中選擇剛剛建立的 S3 Bucket。這裡要選擇一般的 S3 Bucket origin，不要手動輸入 S3 Website endpoint。

如果使用的是 CloudFront 的 S3 origin，Console 會顯示 Origin access 設定。請選擇「Origin access control settings」，建立或選擇一個 OAC。

![Cloudfront Origin](/assets/img/cloudfront/cloudfront-origin.png)

![Cloudfront Settings](/assets/img/cloudfront/cloudfront-settings.png)

### Default root object

將 Default root object 設定為：

```text
index.html
```

這裡只要填入檔名，不要加上開頭的 `/`。使用者開啟 CloudFront 根網址時，CloudFront 就會回傳 `index.html`。由於這次使用的是一般 S3 origin，不會套用 S3 Website hosting 的 Index document，因此必須在 CloudFront distribution 中設定 Default root object。

### Viewer protocol policy

在 Default cache behavior 中，將 Viewer protocol policy 設定為：

```text
Redirect HTTP to HTTPS
```

如此一來，使用者使用 HTTP 存取時，CloudFront 會將請求重新導向到 HTTPS。

一般靜態網站可以只允許以下方法：

- Allowed HTTP methods：`GET, HEAD`
- Cached HTTP methods：`GET, HEAD`

如果網站需要透過瀏覽器送出 OPTIONS，才需要額外加入 `OPTIONS`。靜態網站通常不需要 `POST`、`PUT` 或 `DELETE`。

### Origin Access Control

這部分在建立 CloudFront distribution 時就可以一併設定。請選擇「Origin access control settings」，如果 Console 已經自動建立 OAC，直接選用即可，不需要重複建立。

![Cloudfront Origin Access Control](/assets/img/cloudfront/cloudfront-origin-access-control.png)

### Origin access policy

建立或修改 CloudFront distribution 後，CloudFront Console 通常會提供一份 Bucket policy 範例。將它加到 S3 Bucket 的 Permissions → Bucket policy 中，並確認 `AWS:SourceArn` 是這個 distribution 的 ARN。

概念上，policy 會像以下這樣：

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

這個 policy 只允許 CloudFront service principal 讀取物件，而且透過 `AWS:SourceArn` 將權限限制在指定的 distribution。不要把 `Principal` 改成 `*`，也不要加入 `s3:ListBucket`、`s3:PutObject` 或 `s3:DeleteObject`。

使用 Console 建立完成後，請確認 Bucket policy 已經套用；如果 Console 只提供複製 policy 的按鈕，就要手動貼到 S3 Bucket 的 Bucket policy 中。

## 設定錯誤頁面

如果 CloudFront 找不到 S3 物件，私有 S3 origin 常見會回傳 `403 Forbidden`，而不一定是 `404 Not Found`。

![Cloudfront Default Error Page](/assets/img/cloudfront/cloudfront-default-error-page.png)

可以在 CloudFront 的 Error responses 中加入自訂錯誤回應：

| HTTP error code | Response page path | Response code |
| --- | --- | --- |
| `403` | `/error.html` | `404` |
| `404` | `/error.html` | `404` |

![Cloudfront Customized Error Page](/assets/img/cloudfront/cloudfront-customized-error-page.png)

如果網站是一般多頁式網站，這樣可以讓訪客看到自訂錯誤頁面。如果網站是 SPA，想讓前端 Router 處理所有路徑，才考慮將 `403` 與 `404` 導向 `/index.html` 並回傳 `200`；否則不建議把所有不存在的網址都偽裝成成功頁面。

## 使用 CloudFront 預設網域測試

Distribution 建立完成後，CloudFront 會提供一個類似以下的網域：

```text
https://dxxxxxxxxxxxx.cloudfront.net
```

開啟這個網址時，應該可以看到 S3 Bucket 中的 `index.html`。如果出現 `403 Forbidden`，建議依序檢查：

1. Distribution 是否已經部署完成。
2. Default root object 是否設定為 `index.html`，且沒有多加 `/`。
3. `index.html` 是否真的存在於 Bucket 根目錄。
4. Origin 是否使用 S3 REST endpoint，而不是 Website endpoint。
5. Bucket policy 的 `AWS:SourceArn` 是否指向正確的 distribution。
6. Bucket 的 Block Public Access 是否維持啟用，且沒有其他 policy 阻擋 CloudFront。

## 使用自訂網域與 HTTPS 憑證

CloudFront 預設網域已經可以使用 HTTPS。如果想使用自己的網域，例如 `www.example.com`，需要準備以下設定：

1. 在 AWS Certificate Manager（ACM）申請憑證。
2. 憑證必須建立在 `us-east-1` Region，才能綁定到 CloudFront。
3. 在 CloudFront distribution 的 Alternate domain names 中加入自訂網域。
4. 在 Viewer certificate 中選擇 ACM 憑證。
5. 在 DNS 服務中建立 Alias 或 CNAME，將網域指向 CloudFront domain name。

如果使用 Route 53，可以建立 Alias A record；如果使用其他 DNS 服務，通常使用 CNAME 指向 `dxxxxxxxxxxxx.cloudfront.net`。DNS 設定生效並等待 CloudFront 部署完成後，就能使用自訂網域存取網站。

> CloudFront 使用的 Viewer certificate 必須來自 `us-east-1` 的 ACM。即使 S3 Bucket 建立在其他 Region，憑證仍然要在 `us-east-1` 申請，否則在 CloudFront 選擇憑證時不會出現。
{: .prompt-warning}

## 更新檔案與清除 CloudFront 快取

CloudFront 會快取 S3 的物件。上傳新版本的 `index.html` 後，訪客不一定會立即看到最新內容，因為 Edge location 可能仍保存舊快取。

可以在 CloudFront Console 建立 invalidation，或使用 AWS CLI：

```shell
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

`/*` 會清除整個 distribution 的快取，適合測試或小型網站。正式環境可以只清除有更新的檔案，例如 `/index.html`，或在檔名中加入版本號，減少 invalidation 次數與等待時間。

## 使用 Terraform 建立

以下範例建立私有 S3 Bucket、OAC、CloudFront distribution，以及只允許指定 CloudFront distribution 讀取 S3 物件的 Bucket policy。這個範例使用 CloudFront 預設網域與憑證，之後可以再加入 ACM 與自訂網域設定。

請先將 Bucket 名稱替換成符合 DNS 命名規則，且在所有 AWS 帳號與 Region 中唯一的名稱。

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

這個範例沒有使用 `aws_s3_bucket_website_configuration`，也沒有建立公開 ACL。Terraform apply 後，仍然需要將 `index.html`、`error.html` 與其他網站檔案上傳到 S3。你可以使用 AWS CLI、CI/CD，或額外建立 `aws_s3_object` resource 管理檔案。

如果要加入自訂網域，還需要使用 `us-east-1` provider 建立 ACM certificate，並在 CloudFront distribution 中設定 `aliases` 與 `viewer_certificate.acm_certificate_arn`。憑證完成 DNS validation 後，才能讓 CloudFront 使用該憑證。

## 監控與成本

CloudFront 會產生請求、資料傳輸與快取相關費用；S3 也可能產生儲存、請求與資料傳出費用。除了檢查 S3 的使用量，也建議觀察 CloudFront 的 Requests、Bytes downloaded、4xxErrorRate 與 5xxErrorRate。

如果需要更細緻地觀察 S3 請求數、錯誤與延遲，可以參考[如何啟用 Amazon S3 Request Metrics：用 CloudWatch 監控請求、錯誤與延遲](/posts/enable-s3-metrics/)。

## 結語

S3 + CloudFront 比直接使用 S3 Website endpoint 多了一些設定，但能得到更完整的網站架構：

- S3 Bucket 可以保持私有。
- CloudFront 透過 OAC 存取 S3，不需要公開 Bucket。
- CloudFront 提供 HTTPS 與自訂網域支援。
- 靜態資源可以透過 Edge location 快取。
- 可以透過 CloudFront invalidation 更新快取內容。

如果只是快速測試或展示公開內容，上一篇的 S3 Website endpoint 已經足夠；如果是正式網站，則建議使用 S3 REST origin 搭配 CloudFront OAC，讓網站入口、加密傳輸與來源存取控制各自由適合的服務負責。

## 參考資料

- [Restrict access to an Amazon S3 origin with Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Specify a default root object](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DefaultRootObject.html)
- [Origin settings for CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistValuesOrigin.html)
- [Require HTTPS for communication between CloudFront and your Amazon S3 origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-https-cloudfront-to-s3-origin.html)
- [AWS Provider: aws_cloudfront_origin_access_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control)
- [AWS Provider: aws_cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)
