---
layout: post
title: "Amazon S3 を使用して静的ウェブサイトを構築する方法"
image: https://fastly.picsum.photos/id/954/1200/630.jpg?hmac=c_eAwJdG1uf9VexIXGqgw1DL9Rrtj96kbFIedSnoV7U
description: "Amazon S3 を使って静的ウェブサイトを構築する方法を紹介します。Console と Terraform によるバケットの作成、静的ウェブサイトホスティング、パブリックアクセス用のポリシー、リダイレクト、ウェブサイトファイルのアップロードと確認まで説明します。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, Static Website, Terraform]
keywords: [AWS, Amazon S3, S3 Static Website, S3 Website Hosting, S3 Bucket Policy, Terraform]
lang: ja
date: 2026-08-13
---

Amazon S3 はファイルを保存するだけでなく、静的ウェブサイトを簡単にホストするためにも利用できます。

ウェブサイトが HTML、CSS、JavaScript、画像などの静的ファイルだけで構成されている場合、EC2 インスタンスを作成したり、Web Server をインストールしたりする必要はありません。後から OS やサーバーを自分で運用する必要もありません。

そのため、S3 は PoC（概念実証）だけでなく、設定が簡単で運用負担の少ない静的ウェブサイトホスティングサービスとしても利用できます。

ただし、S3 の静的ウェブサイトホスティングには重要な制限があります。S3 の Website endpoint は HTTP のみに対応しており、HTTPS には対応していません。この記事では、S3 で簡単に動作する静的ウェブサイトを構築し、基本的な設定とアクセス方法を説明します。

## S3 バケットを作成する

まず、Amazon S3 Console を開き、新しいバケットを作成します。

バケット名は DNS 命名規則に従う必要があり、すべての AWS アカウントと Region の中で一意でなければなりません。バケット名は識別子になるだけでなく、後でウェブサイトの URL の一部にもなるため、変更しにくい名前を最初から付けることをおすすめします。

![S3 Create Bucket](/assets/img/s3/s3-create-bucket.png)

### オブジェクト所有権

「オブジェクト所有権」の設定では、通常、デフォルトの「ACL 無効」のままで問題ありません。

ACL を無効にすると、オブジェクトのアクセス権限はバケットポリシーまたは IAM ポリシーで一元管理できます。権限の仕組みが分かりやすくなり、異なるユーザーがファイルをアップロードした場合でも、オブジェクト所有権の不整合を避けられます。

旧式の ACL を使用する必要がある場合や、個別のオブジェクトに ACL を設定する必要がある場合だけ、ACL の有効化を検討してください。

![S3 Object Owner](/assets/img/s3/s3-object-owner.png)

### パブリックアクセスをブロックする設定

S3 Website endpoint を通じて誰でもウェブサイトのコンテンツを読み取れるようにするには、「パブリックアクセスをすべてブロック」を無効にする必要があります。

![S3 Block Public Access](/assets/img/s3/s3-block-public-access.png)

無効にすると、AWS からバケットがパブリックアクセス可能になることへの確認を求められます。このバケットには公開しても問題ないウェブサイトのファイルだけを保存してください。パスワード、秘密鍵、バックアップ、その他の機密情報は保存しないでください。

アカウントレベルで Block Public Access が有効なままだと、バケットレベルの設定だけではパブリックポリシーが有効にならない場合があります。その場合は、組織のセキュリティ要件に従って、アカウントまたは Organization レベルのパブリックアクセス設定を確認してください。

その他の設定はデフォルトのままにして、「バケットを作成」をクリックします。

## 静的ウェブサイトホスティングを有効にする

バケットを作成したら、バケットの「プロパティ」タブを開き、ページの一番下にある「静的ウェブサイトホスティング」を探します。

![S3 Host static website](/assets/img/s3/s3-host-static-website.png)

「編集」をクリックして静的ウェブサイトホスティングを有効にし、次の内容を設定します。

- インデックスドキュメント：`index.html`
- エラードキュメント：`error.html`

インデックスドキュメントは、ユーザーがウェブサイトのルートにアクセスしたときに S3 がデフォルトで返すページです。エラードキュメントは、要求されたファイルが存在しない場合に表示されます。必要に応じて別のファイル名も使用できますが、そのファイルが実際にバケット内に存在していなければなりません。

![S3 Edit host static website settings](/assets/img/s3/s3-edit-host-static-website.png)

設定を保存すると、同じページに Website endpoint が表示されます。Region によって endpoint の形式が異なる場合があるため、Console に表示された URL をそのままコピーするのがおすすめです。

## ウェブサイトのリダイレクトを設定する

ウェブサイトのパスを変更した場合は、リダイレクトルールを使用して、古い URL がすぐに 404 にならないようにできます。

たとえば、ウェブサイト内の `docs` フォルダを `documents` に変更した場合、`docs/` で始まるリクエストを新しいパスへリダイレクトできます。

```json
[
  {
    "Condition": {
      "KeyPrefixEquals": "docs/"
    },
    "Redirect": {
      "ReplaceKeyPrefixWith": "documents/"
    }
  }
]
```

このようなルールは、ウェブサイトのパスを変更した場合や、古い URL との互換性を維持したい場合に便利です。1 ページだけを変更する場合は、ウェブサイト側でリダイレクトを処理するか、リダイレクト用の古いファイルを残す方法もあります。

## バケットポリシーを設定する

デフォルトでは、S3 はインターネット上の匿名ユーザーによるオブジェクトの読み取りを許可していません。静的ウェブサイトを公開するには、読み取りだけを許可するバケットポリシーを作成します。

バケットの「アクセス許可」タブを開き、「バケットポリシー」に次の内容を貼り付けます。`YOUR_BUCKET_NAME` は実際のバケット名に置き換えてください。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicReadForWebsite",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*"
    }
  ]
}
```

このポリシーは、バケット内のオブジェクトを誰でも読み取れるようにしますが、アップロード、変更、削除の権限は付与しません。特定のフォルダだけを公開したい場合は、Resource を特定の prefix に限定できます。

```json
"Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/public/*"
```

オブジェクトごとにアクセス権限を設定するのが面倒な場合は、バケットポリシーを使用すると便利です。ポリシーの範囲内に新しいファイルをアップロードすれば、同じ読み取りルールが自動的に適用されるため、オブジェクトごとに権限を設定する必要はありません。

> バケットを公開すると、ポリシーの範囲内にあるオブジェクトを誰でも読み取れる可能性があります。バケットには公開してよいウェブサイトのリソースだけを保存し、バケットポリシーとアクセスログを定期的に確認してください。
{: .prompt-warning}

## ウェブサイトのファイルをアップロードして確認する

次に、`index.html`、`error.html`、CSS、JavaScript、画像などのウェブサイトファイルをバケットにアップロードします。

アップロードが完了したら、S3 Console に表示された Website endpoint を使ってウェブサイトを開きます。通常は次のいずれかの形式です。

```text
http://YOUR_BUCKET_NAME.s3-website-YOUR_REGION.amazonaws.com
```

または：

```text
http://YOUR_BUCKET_NAME.s3-website.YOUR_REGION.amazonaws.com
```

ウェブサイトのルートにアクセスすると、設定した `index.html` が自動的に読み込まれます。存在しないパスにアクセスすると、`error.html` が表示されます。

### Website endpoint と REST endpoint の違い

この 2 種類の URL は混同しやすいため注意してください。

| Endpoint | 用途 | HTTPS | ウェブサイト設定の適用 |
| --- | --- | --- | --- |
| S3 Website endpoint | 静的ウェブサイトへのアクセス | 非対応 | index、error、redirect に対応 |
| S3 REST endpoint | 特定のオブジェクトへのアクセス、または S3 API の利用 | 対応 | Website endpoint の動作は適用されない |

たとえば、`https://YOUR_BUCKET_NAME.s3.YOUR_REGION.amazonaws.com/index.html` は REST endpoint を使ったオブジェクト URL です。指定した `index.html` は HTTPS で読み取れますが、S3 静的ウェブサイトの Website endpoint ではありません。そのため、ウェブサイトのルート、エラーページ、リダイレクトの設定は完全には適用されません。

## Terraform でウェブサイトを構築する

AWS Console の代わりに、Terraform で S3 静的ウェブサイトを管理することもできます。次の例では、バケット、オブジェクト所有権、パブリックアクセス設定、Website configuration、およびオブジェクトのパブリック読み取りを許可するバケットポリシーを作成します。

サンプル内のバケット名は、DNS 命名規則に従い、すべての AWS アカウントと Region で一意になる名前に置き換えてください。

```terraform
resource "aws_s3_bucket" "markmew_s3_static_html" {
    bucket = "markmew-s3-static-html"
}

resource "aws_s3_bucket_ownership_controls" "markmew_s3_static_html" {
    bucket = aws_s3_bucket.markmew_s3_static_html.id
    
    rule {
        object_ownership = "BucketOwnerPreferred"
    }
}

resource "aws_s3_bucket_public_access_block" "markmew_s3_static_html" {
    bucket = aws_s3_bucket.markmew_s3_static_html.id
    
    block_public_acls       = false
    block_public_policy     = false
    ignore_public_acls      = false
    restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "markmew_s3_static_html" {
    depends_on = [
        aws_s3_bucket_ownership_controls.markmew_s3_static_html,
        aws_s3_bucket_public_access_block.markmew_s3_static_html,
    ]
    bucket = aws_s3_bucket.markmew_s3_static_html.id
    acl    = "public-read"
}

resource "aws_s3_bucket_website_configuration" "markmew_s3_static_html" {
    bucket = aws_s3_bucket.markmew_s3_static_html.id

    index_document {
        suffix = "index.html"
    }

    error_document {
        key = "error.html"
    }
}

data "aws_iam_policy_document" "markmew_s3_static_html_public_read" {
    statement {
        sid    = "AllowPublicReadForWebsite"
        effect = "Allow"

        principals {
            type        = "*"
            identifiers = ["*"]
        }

        actions = [
            "s3:GetObject",
        ]

        resources = [
            "${aws_s3_bucket.markmew_s3_static_html.arn}/*",
        ]
    }
}

resource "aws_s3_bucket_policy" "markmew_s3_static_html_public_read" {
    depends_on = [
        aws_s3_bucket_public_access_block.markmew_s3_static_html,
    ]
    bucket = aws_s3_bucket.markmew_s3_static_html.id
    policy = data.aws_iam_policy_document.markmew_s3_static_html_public_read.json
}
```

## リクエストとコストを監視する

S3 の料金には、ストレージだけでなく、リクエスト数、データ転送、その他の関連サービスの料金が含まれる場合があります。ウェブサイトのトラフィックが増えたら、S3 のストレージ量、リクエスト数、データ転送量を定期的に確認してください。

リクエスト数、エラー、レイテンシーをより詳しく確認したい場合は、以前の記事「[Amazon S3 Request Metrics を有効にする方法：CloudWatch でリクエスト、エラー、レイテンシーを監視する](/ja/posts/enable-s3-metrics)」を参照してください。

監視に加えて、AWS Budgets や CloudWatch Alarm も設定しておくと、トラフィックやコストの異常に早く対応できます。公開ウェブサイトの場合は、大量のファイルダウンロードや悪意のあるリクエストにも注意してください。

## まとめ

S3 で静的ウェブサイトをホストする手順は難しくありません。バケットを作成し、静的ウェブサイトホスティングを有効にして、パブリック読み取りポリシーを設定し、ウェブサイトのファイルをアップロードするだけです。

この方法は、個人ウェブサイト、ドキュメントページ、製品紹介ページ、PoC に適しています。ただし、公開した S3 Website endpoint は HTTP のみに対応しているため、暗号化通信が必要な機密情報をウェブサイトに含めないようにしてください。

パブリックアクセスを有効にする前に、バケットに機密情報がないことを確認してください。ウェブサイト公開後は、コストとリクエストを監視することで、シンプルな構成を維持しながら、権限設定の誤りや予期しないトラフィックのリスクを減らせます。

## 参考資料

- [Tutorial: Configuring a static website on Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/HostingWebsiteOnS3Setup.html)
- [Website endpoints for Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteEndpoints.html)
- [Setting permissions for website access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteAccessPermissionsReqd.html)
