---
layout: post
title: "Amazon S3 と CloudFront で静的ウェブサイトを構築する方法"
image: https://fastly.picsum.photos/id/744/1200/630.jpg?hmac=kS4Oj4MhjZO_5wgBsLvMbWCz1I98gS21Ftba3BcV2c8
description: "Amazon S3 と Amazon CloudFront を使って安全な静的ウェブサイトを構築する方法を紹介します。Origin Access Control、プライベートバケット、HTTPS、カスタムドメイン、キャッシュ無効化、Terraform の設定を説明します。"
author: Mark_Mew
categories: [AWS, S3, CloudFront]
tags: [AWS, S3, CloudFront, Terraform, Static Website]
keywords: [AWS, Amazon S3, CloudFront, Origin Access Control, OAC, Static Website, Terraform, HTTPS]
lang: ja
date: 2026-08-15
---

前回の記事では、[Amazon S3 だけで静的ウェブサイトをホストする方法](/ja/posts/how-to-host-static-website-on-s3/)を紹介しました。この方法は簡単ですが、S3 Website endpoint は HTTP のみに対応しており、バケットのコンテンツをパブリックに読み取れる状態にする必要があります。

HTTPS、カスタムドメイン、キャッシュ、そしてより明確なオリジンアクセス制御が必要な場合は、S3 の前段に CloudFront を配置します。

```text
ユーザー -- HTTPS --> CloudFront -- OAC / SigV4 --> プライベート S3 バケット
```

この記事では、通常の S3 バケット endpoint を CloudFront のオリジンとして使用します。S3 の静的ウェブサイトホスティングは有効にせず、バケットも公開しません。CloudFront は Origin Access Control（OAC）でリクエストに署名するため、指定した CloudFront distribution だけがバケット内のオブジェクトを読み取れます。

## S3 Website endpoint と CloudFront オリジンの違い

CloudFront で OAC を使用する場合、S3 バケットは S3 Website endpoint ではなく、通常の S3 REST endpoint を使用する必要があります。

| 構成 | S3 静的ウェブサイトホスティング | バケットの公開 | CloudFront OAC | HTTPS |
| --- | --- | --- | --- | --- |
| S3 Website endpoint を直接使用 | 必要 | 必要 | 非対応 | 非対応 |
| S3 + CloudFront | 不要 | 不要 | 対応 | 対応 |

つまり、この記事では `aws_s3_bucket_website_configuration` も `public-read` ACL も使用しません。S3 はファイルを保存し、ウェブサイトの入口と HTTPS は CloudFront が担当します。

## プライベート S3 バケットを作成する

まず、S3 バケットを作成します。バケット名は DNS 命名規則に従い、すべての AWS アカウントと Region の中で一意でなければなりません。

次の設定を使用します。

- Object Ownership：`Bucket owner enforced`
- ACL：無効
- Block Public Access：4 つの設定をすべて有効
- 静的ウェブサイトホスティング：無効

OAC を使用する場合、AWS は `Bucket owner enforced` を推奨しています。これによりバケットがすべてのオブジェクトを所有し、アクセスはバケットポリシーだけで管理できます。CloudFront は OAC でリクエストに署名するため、ACL でオブジェクトを公開する必要はありません。

> この構成の重要な点は、S3 バケットをプライベートに保つことです。テストを簡単にするために `Principal: "*"` のパブリック読み取りポリシーを追加しないでください。追加すると、ユーザーが CloudFront を経由せずに S3 オブジェクトへ直接アクセスできる可能性があります。
{: .prompt-warning}

バケットに次のようなウェブサイトファイルをアップロードします。

- `index.html`
- `error.html`
- CSS
- JavaScript
- 画像やその他の静的リソース

## CloudFront distribution を作成する

CloudFront Console を開き、新しい distribution を作成します。

### Origin

Origin domain では、作成した S3 バケットを選択します。通常の S3 バケット origin を選択し、S3 Website endpoint を手動で入力しないでください。

S3 origin を使用すると、Console に Origin access の設定が表示されます。「Origin access control settings」を選択し、OAC を作成または選択します。

![CloudFront Origin](/assets/img/cloudfront/cloudfront-origin.png)

![CloudFront Settings](/assets/img/cloudfront/cloudfront-settings.png)

### Origin Access Control

この設定は CloudFront distribution の作成時に一緒に行えます。「Origin access control settings」を選択し、Console がすでに OAC を作成している場合は、それを選択してください。重複して作成する必要はありません。

![CloudFront Origin Access Control](/assets/img/cloudfront/cloudfront-origin-access-control.png)

### Default root object

Default root object に次を設定します。

```text
index.html
```

ファイル名だけを入力し、先頭に `/` を付けないでください。ユーザーが CloudFront distribution のルート URL を開くと、CloudFront は `index.html` を返します。

これは S3 Website hosting の Index document とは異なります。CloudFront が通常の S3 origin に接続する場合、S3 の Website configuration は自動的には使われないため、CloudFront distribution で Default root object を設定する必要があります。

### Viewer protocol policy

Default cache behavior の Viewer protocol policy を次のように設定します。

```text
Redirect HTTP to HTTPS
```

これにより、ユーザーが HTTP でアクセスした場合、CloudFront は HTTPS へリダイレクトします。

一般的な静的ウェブサイトでは、許可するメソッドを次のように制限できます。

- Allowed HTTP methods：`GET, HEAD`
- Cached HTTP methods：`GET, HEAD`

ブラウザから OPTIONS リクエストを送信する必要がある場合だけ、`OPTIONS` を追加してください。静的ウェブサイトでは通常、`POST`、`PUT`、`DELETE` は必要ありません。

### オリジンアクセス用のバケットポリシー

distribution を作成または編集すると、CloudFront Console にバケットポリシーのテンプレートが表示されることがあります。S3 Bucket の Permissions → Bucket policy に追加し、`AWS:SourceArn` がこの distribution の ARN になっていることを確認してください。

ポリシーは概念的には次のようになります。

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

このポリシーは CloudFront service principal だけにオブジェクトの読み取りを許可し、`AWS:SourceArn` によって指定した distribution に権限を限定します。`Principal` を `*` に変更したり、`s3:ListBucket`、`s3:PutObject`、`s3:DeleteObject` を追加したりしないでください。

Console で distribution の設定が完了したら、バケットポリシーが適用されていることを確認してください。Console に Copy policy ボタンだけが表示される場合は、ポリシーを S3 バケットポリシーへ手動で貼り付けます。

## エラーページを設定する

CloudFront がプライベート S3 origin でオブジェクトを見つけられない場合、`404 Not Found` ではなく `403 Forbidden` を受け取ることがよくあります。CloudFront の Error responses にカスタムエラー応答を追加できます。

![CloudFront Default Error Page](/assets/img/cloudfront/cloudfront-default-error-page.png)

| HTTP error code | Response page path | Response code |
| --- | --- | --- |
| `403` | `/error.html` | `404` |
| `404` | `/error.html` | `404` |

通常の複数ページ構成では、訪問者にカスタムエラーページを表示できます。SPA の場合は、`403` と `404` を `/index.html` に転送し、レスポンスコードを `200` にしてフロントエンドルーターで処理する方法もあります。それ以外の場合、存在しない URL をすべて成功ページに変換することはおすすめしません。

![CloudFront Customized Error Page](/assets/img/cloudfront/cloudfront-customized-error-page.png)

## CloudFront のデフォルトドメインで確認する

distribution のデプロイが完了すると、CloudFront から次のようなドメインが提供されます。

```text
https://dxxxxxxxxxxxx.cloudfront.net
```

この URL を開くと、S3 バケットに保存した `index.html` が表示されるはずです。`403 Forbidden` が表示された場合は、次の順番で確認してください。

1. distribution のデプロイが完了しているか。
2. Default root object が先頭の `/` なしで `index.html` になっているか。
3. バケットのルートに `index.html` が存在するか。
4. origin が Website endpoint ではなく S3 REST endpoint になっているか。
5. OAC が `Sign requests` に設定されているか。
6. バケットポリシーの `AWS:SourceArn` が正しい distribution を指しているか。
7. Block Public Access が有効で、他のポリシーが CloudFront を拒否していないか。

## カスタムドメインと HTTPS 証明書を使用する

CloudFront のデフォルトドメインはすでに HTTPS に対応しています。`www.example.com` のような独自ドメインを使う場合は、次の設定を準備します。

1. AWS Certificate Manager（ACM）で証明書をリクエストする。
2. CloudFront で使用する証明書は `us-east-1` Region に作成する。
3. CloudFront distribution の Alternate domain names にカスタムドメインを追加する。
4. Viewer certificate で ACM 証明書を選択する。
5. DNS サービスで、ドメインを CloudFront domain name に向ける Alias または CNAME レコードを作成する。

Route 53 を使用する場合は Alias A record を作成できます。その他の DNS サービスでは、通常 `dxxxxxxxxxxxx.cloudfront.net` を指す CNAME を作成します。DNS の反映と CloudFront のデプロイが完了すると、カスタムドメインでアクセスできます。

## ファイルを更新して CloudFront キャッシュを無効化する

CloudFront は S3 オブジェクトをキャッシュします。`index.html` を更新しても、Edge location に古いオブジェクトが残っていると、訪問者がすぐに新しい内容を見られない場合があります。

CloudFront Console で invalidation を作成するか、AWS CLI を使用します。

```shell
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

`/*` は distribution 全体のキャッシュを削除するため、テストや小規模サイトには便利です。本番環境では `/index.html` など変更したファイルだけを無効化するか、ファイル名にバージョンを含めて invalidation の回数と待ち時間を減らす方法があります。

## Terraform で構築する

次の例では、プライベート S3 バケット、OAC、CloudFront distribution、および指定した CloudFront distribution だけに S3 オブジェクトの読み取りを許可するバケットポリシーを作成します。CloudFront のデフォルトドメインと証明書を使用し、ACM とカスタムドメインは後から追加する構成です。

バケット名は DNS 命名規則に従い、すべての AWS アカウントと Region で一意になる名前に置き換えてください。

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

この例では `aws_s3_bucket_website_configuration` もパブリック ACL も使用していません。`terraform apply` の後、`index.html`、`error.html`、その他のウェブサイトファイルを S3 にアップロードする必要があります。AWS CLI、CI/CD パイプライン、または追加の `aws_s3_object` リソースを使用できます。

カスタムドメインを追加する場合は、`us-east-1` provider で ACM 証明書を作成し、CloudFront distribution に `aliases` と `viewer_certificate.acm_certificate_arn` を設定します。CloudFront が証明書を使用する前に、DNS validation を完了させる必要があります。

## 使用量とコストを監視する

CloudFront では、リクエスト、データ転送、キャッシュ関連の利用に料金が発生する場合があります。S3 でもストレージ、リクエスト、データ転送の料金が発生する場合があります。S3 の使用量に加えて、CloudFront の Requests、Bytes downloaded、4xxErrorRate、5xxErrorRate も監視してください。

S3 のリクエスト数、エラー、レイテンシーをより詳しく確認したい場合は、[Amazon S3 Request Metrics を有効にする方法：CloudWatch でリクエスト、エラー、レイテンシーを監視する](/ja/posts/enable-s3-metrics)を参照してください。

## まとめ

S3 + CloudFront は S3 Website endpoint を直接使用する方法より設定が増えますが、より完全な構成を作れます。

- S3 バケットをプライベートに保てる。
- CloudFront が OAC 経由で S3 にアクセスし、バケットを公開しなくてよい。
- CloudFront が HTTPS とカスタムドメインを提供する。
- 静的リソースを Edge location にキャッシュできる。
- CloudFront の invalidation でキャッシュを更新できる。

簡単なテストやリスクの低い公開コンテンツだけなら、前回の記事の S3 Website endpoint で十分な場合もあります。正式なウェブサイトでは、S3 REST origin と CloudFront OAC を使用し、ウェブサイトの入口、暗号化通信、オリジンアクセス制御をそれぞれ適切なサービスに任せる構成がおすすめです。

## 参考資料

- [Restrict access to an Amazon S3 origin with Origin Access Control](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [Specify a default root object](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DefaultRootObject.html)
- [Origin settings for CloudFront](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/DownloadDistValuesOrigin.html)
- [Require HTTPS for communication between CloudFront and your Amazon S3 origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-https-cloudfront-to-s3-origin.html)
- [AWS Provider: aws_cloudfront_origin_access_control](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_origin_access_control)
- [AWS Provider: aws_cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)
