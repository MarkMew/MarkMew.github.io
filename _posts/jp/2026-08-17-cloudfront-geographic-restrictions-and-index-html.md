---
layout: post
title: "CloudFront で地域アクセスを制限し、パスに自動で index.html を適用する"
image: https://fastly.picsum.photos/id/483/1200/630.jpg?hmac=JZXUWHFxPtwnPWfMU_Zvehy5wGP3ozlrotebH9l5H9A
description: "Amazon S3 と CloudFront で構築した静的ウェブサイトを拡張し、Geographic restrictions と、拡張子のないパスを対応する index.html に書き換える CloudFront Function を紹介します。"
author: Mark_Mew
categories: [AWS, CloudFront]
tags: [AWS, CloudFront, CloudFront Functions, S3, Terraform, Static Website]
keywords: [AWS, Amazon CloudFront, Geographic Restrictions, Geo Blocking, CloudFront Functions, URI Rewrite]
lang: ja
date: 2026-08-17
---

前回の記事では、[Amazon S3 と CloudFront で静的ウェブサイトを構築する方法](/ja/posts/how-to-host-static-website-with-s3-and-cloudfront/)を紹介しました。基本構成ができた後、次のような要件が出てくることがあります。

- 特定の国や地域からだけアクセスを許可したい。
- ユーザーが `/docs` や `/docs/` を開いたときに、`/docs/index.html` を自動で読み込みたい。

1 つ目の要件には CloudFront の Geographic restrictions を使用できます。2 つ目の要件では、CloudFront Function を作成し、origin にリクエストを送る前に URI を書き換えます。

この 2 つの機能は別の問題を解決します。Geographic restrictions はリクエスト元の国や地域を判定し、Function はリクエストのパスを変更します。

## Geographic restrictions で地域アクセスを制限する

CloudFront の Geographic restrictions を使うと、distribution 全体のコンテンツへのアクセスを国単位で制限できます。設定方法には次の 2 種類があります。

| モード | 説明 |
| --- | --- |
| Allowlist | リストに登録した国だけがアクセスできます。 |
| Blocklist | リストに登録した国を拒否し、それ以外の国からはアクセスできます。 |

この設定は distribution が配信するすべてのファイルに適用されます。特定のパスだけを制限したい場合や、国単位より細かい判定が必要な場合は、Geographic restrictions だけでは対応できません。

### Console で Geographic restrictions を設定する

CloudFront Console を開き、変更する distribution を選択します。`Security` タブにある `Geographic restrictions` を開き、`Edit` を選択してください。

![CloudFront Geographic Restrictions](/assets/img/cloudfront/cloudfront-geographic-restrictions.png)

`Allow list` または `Block list` を選択し、許可または拒否する国を追加します。国は ISO 3166-1 alpha-2 コードで指定します。例えば次のようになります。

- `TW`: Taiwan
- `JP`: Japan
- `US`: United States
- `SG`: Singapore

保存後、distribution のデプロイが完了するまで待ちます。デプロイが完了すると、CloudFront はユーザーの地理的位置に応じてリクエストを処理します。制限されたリクエストには通常 `403 Forbidden` が返されます。

> Geographic restrictions は国単位のコンテンツ配信制御であり、認証機能や完全なセキュリティ境界ではありません。CloudFront は IP の地理情報を使ってユーザーの国を判定します。位置を判定できない場合、CloudFront がコンテンツを配信する可能性もあります。機密データを保護する場合は、認証、署名付き URL、AWS WAF などのアクセス制御も組み合わせてください。
{: .prompt-warning}

### Terraform で Geographic restrictions を設定する

前回の記事の Terraform で CloudFront distribution を作成している場合は、distribution の `restrictions` ブロックを変更します。

```terraform
restrictions {
  geo_restriction {
    restriction_type = "whitelist"
    locations        = ["TW", "JP"]
  }
}
```

この設定では、台湾と日本からのリクエストだけがアクセスできます。拒否する国を指定する場合は、`restriction_type` を `blacklist` に変更します。

```terraform
restrictions {
  geo_restriction {
    restriction_type = "blacklist"
    locations        = ["CN", "RU"]
  }
}
```

地域制限を使用しない場合は、次のように設定します。

```terraform
restrictions {
  geo_restriction {
    restriction_type = "none"
  }
}
```

## index.html に書き換える理由

前回の記事では、CloudFront distribution の `Default root object` に `index.html` を設定しました。そのため、ユーザーがウェブサイトのルート `/` を開くと、CloudFront はルートの `index.html` を返します。

ただし、この設定で処理できるのは distribution のルートだけです。ほかのディレクトリは自動で処理されません。例えば次のようになります。

| ユーザーのリクエスト | 読み込むファイル |
| --- | --- |
| `/` | `/index.html` |
| `/docs/` | `/docs/index.html` |
| `/docs` | `/docs/index.html` |
| `/about.html` | `/about.html` |
| `/assets/app.js` | `/assets/app.js` |

S3 バケットに `docs/index.html` が存在していても、ユーザーが `/docs/` をリクエストした場合、CloudFront は S3 Website endpoint のようにサブディレクトリ内の index ファイルを自動では探しません。この場合は通常の `Function` を作成し、distribution の `Viewer request` に関連付けて URI を書き換えます。

## Function を作成する

CloudFront Console の左側にある `Functions` を開き、`Create function` を選択します。

> **Warning**
> 
> 古い記事では「CloudFront Function を作成して、`Viewer request` を選択する」と説明されていることがあります。新しい手順では、Function の作成時に表示されるのは `Function` と `Connection Function` です。この記事で使用するのは `Function` だけです。`Connection Function` は TLS handshake と Viewer mTLS 用なので、ここでは使用しません。
{: .prompt-warning}

![CloudFront Create Function](/assets/img/cloudfront/cloudfront-create-function.png)

Function 名を入力し、Runtime に `cloudfront-js-2.0` を指定して、次のコードをエディターに貼り付けます。

```javascript
function handler(event) {
    var request = event.request;
    if (request.uri !== "/" && (request.uri.endsWith("/") || request.uri.lastIndexOf(".") < request.uri.lastIndexOf("/"))) {
        if (request.uri.endsWith("/")) {
            request.uri = request.uri.concat("index.html");
        } else {
            request.uri = request.uri.concat("/index.html");
        }
    }
    return request;
}
```

この Function は、リクエストされたパスを次のように処理します。

- `/`：URI は変更せず、Default root object に `/index.html` の読み込みを任せます。
- `/docs/`：`/docs/index.html` に書き換えます。
- `/docs`：`/docs/index.html` に書き換えます。
- `/about.html`：最後の部分に拡張子があるため、元のパスを維持します。
- `/assets/app.js`：ディレクトリとして扱わず、元のパスを維持します。

Function を `Viewer request` に関連付けると、CloudFront はユーザーからリクエストを受け取り、キャッシュを確認する前に Function を実行します。Function が変更するのは CloudFront から origin に送る URI なので、ブラウザのアドレスバーは `/docs` または `/docs/` のままです。HTTP リダイレクトは発生しません。

> この方法は、ディレクトリパスをそのディレクトリ内の `index.html` に対応させる静的ウェブサイトに適しています。`/download` のような拡張子のない実ファイルがある場合、そのパスはディレクトリとして扱われ、`/download/index.html` に書き換えられます。サイトのファイル命名規則に合わせて条件を調整してください。
{: .prompt-info}

## CloudFront Function をテストする

Function のテスト画面で HTTP request のテストイベントを作成し、異なる URI を入力して書き換え結果を確認します。

| テスト URI | 期待する結果 |
| --- | --- |
| `/` | `/`。Default root object が処理します。 |
| `/docs/` | `/docs/index.html` |
| `/docs` | `/docs/index.html` |
| `/about.html` | `/about.html` |
| `/assets/app.js` | `/assets/app.js` |

テスト結果に問題がなければ `Publish` を選択し、その後 Function を CloudFront distribution に関連付けます。Function を Development の状態で保存するだけでは、本番トラフィックには影響しません。

## Function を CloudFront distribution に関連付ける

CloudFront distribution の `Behaviors` を開き、ウェブサイトのコンテンツを処理する Default behavior を編集します。

Function associations に次の設定を追加します。

- Event type：`Viewer request`
- Function type：`Function`
- Function：先ほど Publish した Function を選択します。

ここで選択する `Function` は通常の CloudFront Function です。URI rewrite に `Connection Function` は使用しません。

保存後、distribution のデプロイが完了するまで待ちます。デプロイが完了すると、CloudFront は Edge location で URI rewrite を実行します。

複数の cache behavior がある場合は、正しい behavior に Function が関連付けられていることを確認してください。Default behavior だけを変更しても、より具体的な path pattern に自動で適用されるわけではありません。

## Terraform で CloudFront Function を管理する

通常の Function は `aws_cloudfront_function` で作成し、`function_association` で CloudFront distribution に関連付けます。

```terraform
resource "aws_cloudfront_function" "directory_index" {
  name    = "directory-index"
  runtime = "cloudfront-js-2.0"
  comment = "Rewrite directory paths to index.html"
  publish = true

  code = file("${path.module}/functions/directory-index.js")
}
```

既存の `aws_cloudfront_distribution` resource の `default_cache_behavior` に、次のブロックを追加します。

```terraform
# aws_cloudfront_distribution の default_cache_behavior 内に追加
function_association {
  event_type   = "viewer-request"
  function_arn = aws_cloudfront_function.directory_index.arn
}
```

`functions/directory-index.js` の内容は、CloudFront Console で使用した JavaScript と同じです。Terraform の `publish = true` によって、distribution が使用できるバージョンが公開されます。Function が distribution に関連付けられている場合は、先に association を削除してから Function を削除してください。

Terraform には Connection Function 用の `aws_cloudfront_connection_function` resource もあります。ただし、これは Viewer mTLS 用であり、ここで使用する `aws_cloudfront_function` の代わりにはなりません。

## テストとキャッシュの無効化

Geographic restrictions と Function の設定が完了したら、次の順番で確認します。

1. 許可した国から CloudFront domain を開き、`/` でホームページが表示されることを確認する。
2. `/docs/` を開き、`/docs/index.html` の内容が返ることを確認する。
3. `/docs` を開き、末尾にスラッシュがなくても同じページが表示されることを確認する。
4. `/about.html` と `/assets/app.js` を開き、パスが誤って書き換えられていないことを確認する。
5. 拒否した国またはテスト環境からアクセスし、`403` が返ることを確認する。

Function の新しいバージョンや association のデプロイ後も古い結果が表示される場合は、invalidation を作成します。

![Cloudfront Create Validation](/assets/img/cloudfront/cloudfront-create-validation.png)

CLI を使う場合は、次のコマンドを実行します。

```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR_DISTRIBUTION_ID \
  --paths "/*"
```

## 通常の CloudFront Function の制限

通常の `Function` は軽量で低レイテンシーの URI やヘッダー処理に適していますが、完全なバックエンド実行環境ではありません。主な制限は次のとおりです。

- `Viewer request` または `Viewer response` イベントにだけ関連付けられます。
- request body にアクセスできません。
- ネットワーク、ファイルシステム、環境変数に直接アクセスできません。
- 複雑な処理や長時間実行する処理には適していません。
- 1 つの cache behavior の同じイベントには、1 つの CloudFront Function だけを関連付けられます。

`Connection Function` が使用するのは `Connection request` イベントです。通常の `Function` が使用する `Viewer request`／`Viewer response` とは異なります。

request body へのアクセス、外部サービスの呼び出し、origin request／origin response の段階での処理が必要な場合は、CloudFront Functions に無理に詰め込まず、Lambda@Edge や別のバックエンドサービスを検討してください。

## まとめ

CloudFront Geographic restrictions と通常の CloudFront Function は、それぞれ別の要件に対応します。

- Geographic restrictions：distribution にアクセスできる国や地域を制限する。
- Function：S3 にリクエストを送る前に、`/docs` や `/docs/` を `/docs/index.html` に書き換える。

前者は国単位のコンテンツ配信制御で、後者は Edge で実行する軽量な URI rewrite です。両方を組み合わせることで、S3 バケットをプライベートに保ったまま、S3 + CloudFront の静的ウェブサイトでより自然なディレクトリ URL を使用できます。

Connection Function は TLS handshake と Viewer mTLS の証明書検証に使う別の Function type です。この記事では使用しません。

## 参考資料

- [Restrict the geographic distribution of your content](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/georestrictions.html)
- [Create a CloudFront function](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/create-function.html)
- [CloudFront connection functions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/connection-functions.html)
- [Add index.html to request URLs without a file name in a CloudFront Functions viewer request event](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/example_cloudfront_functions_url_rewrite_single_page_apps_section.html)
- [Restrictions on CloudFront Functions](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/cloudfront-function-restrictions.html)
- [AWS Provider: aws_cloudfront_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function)
- [AWS Provider: aws_cloudfront_connection_function](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_connection_function)
- [AWS Provider: aws_cloudfront_distribution](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_distribution)
