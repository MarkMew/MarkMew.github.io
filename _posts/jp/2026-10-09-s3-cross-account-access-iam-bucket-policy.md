---
layout: post
title: "S3 のクロスアカウントアクセス：IAM ポリシーとバケットポリシーの設定方法"
image: https://fastly.picsum.photos/id/905/1200/630.jpg?hmac=ZWehW4CmzynIJ9lxyGHPkwHnki7vekeNFaXiaJWJaeo
description: "別の AWS アカウントにある S3 バケットへの読み取りアクセスを、IAM ポリシーとバケットポリシーで設定します。プレフィックスによる制限、AWS CLI での動作確認、AccessDenied の確認ポイントも紹介します。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, IAM]
keywords: [S3 クロスアカウントアクセス, S3 バケットポリシー, IAM ポリシー, S3 プレフィックス 権限, AccessDenied]
lang: ja
date: 2026-10-09
---

**アクセス元の IAM ユーザーやロールから、別の AWS アカウントにある S3 バケットへ直接アクセスするには、アクセス元の IAM ポリシーとアクセス先のバケットポリシーの両方で、対象の操作を許可する必要があります。** アクセス元に S3 の読み取り権限があっても、アクセス先のバケットがそのユーザーやロールを許可していなければ、リクエストは拒否されます。逆に、バケットポリシーだけ設定しても十分ではありません。[AWS のクロスアカウントアクセスに関するドキュメント](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html)

両方のポリシーで許可したうえで、ほかに適用される権限制限も満たす必要があります。明示的な `Deny` がある場合も、アクセスは拒否されます。

この記事では、「アカウント A のアプリケーションから、アカウント B の S3 にあるファイルを読み取る」ケースを例に、特定のプレフィックスへの読み取り専用アクセスを設定します。AWS CLI での動作確認と、`AccessDenied` が出たときの確認ポイントも見ていきます。

## なぜ IAM ポリシーとバケットポリシーの両方が必要なのか

クロスアカウントアクセスでは、それぞれのアカウントが自分の側の権限を管理します。アクセス元は「自分の IAM ユーザーやロールに何を許可するか」、アクセス先は「自分のバケットを誰に使わせるか」を決めます。

| 設定する場所 | ポリシー | 許可する内容 |
|---|---|---|
| アクセス元のアカウント A にある IAM ロール | IAM ポリシー | このロールがアカウント B の特定の S3 オブジェクトを読み取ること |
| アクセス先のアカウント B にある S3 バケット | バケットポリシー | アカウント A の指定したロールが対象のオブジェクトを読み取ること |

たとえば `reports/sample.txt` をダウンロードする場合、アクセス元のロールの IAM ポリシーで、そのオブジェクトへの `s3:GetObject` を許可します。アクセス先のバケットポリシーでも、同じロールによる同じ操作を許可する必要があります。リクエストには一貫してアカウント A の認証情報を使います。

## 今回の構成と前提条件

アカウント A の `AppReadReportsRole` を使うアプリケーションから、アカウント B の `reports/` 配下を読み取る構成にします。

| 項目 | サンプル値 |
|---|---|
| アクセス元のアカウント A | `111111111111` |
| アクセス先のアカウント B | `222222222222` |
| アカウント A のロール | `AppReadReportsRole` |
| アカウント B のバケット | `example-cross-account-reports-222222222222` |
| 読み取りを許可するプレフィックス | `reports/` |
| 動作確認用のオブジェクト | `reports/sample.txt` |
| CLI プロファイル | `account-a-app` |

上記の値は、自分の環境に合わせて置き換えてください。以下の準備ができていることを前提に進めます。

- アカウント A にロールが作成済みで、アプリケーションまたは作業者が、そのロールの一時的な認証情報を取得できること。
- アカウント B にバケットが作成済みで、動作確認用のファイル `reports/sample.txt` があること。
- CLI プロファイル `account-a-app` が、上記のロールを使うように設定されていること。
- バケットの Object Ownership が **Bucket owner enforced（バケット所有者の強制）** になっていること。
- 動作確認用のオブジェクトが、S3 マネージドキーによるサーバー側の暗号化（SSE-S3）を使用していること。

`Bucket owner enforced` では ACL が無効になり、バケット所有者がバケット内のすべてのオブジェクトを所有します。アクセス権限をポリシーでまとめて管理でき、新しく作成する S3 バケットではこの設定がデフォルトです。[S3 Object Ownership のドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

この記事では設定例と想定される結果を紹介します。実際の動作は、自分の AWS 環境で確認してください。

## 手順 1：アカウント A のロールにアクセス権限を付与する

アカウント A の IAM で `AppReadReportsRole` を開き、次の IAM ポリシーを追加します。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListReportsPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222",
      "Condition": {
        "StringLike": {
          "s3:prefix": "reports/*"
        }
      }
    },
    {
      "Sid": "ReadReportObjects",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222/reports/*"
    }
  ]
}
```

このポリシーでは、次の 2 つの操作を許可しています。

| 権限 | 用途 | Resource |
|---|---|---|
| `s3:ListBucket` | 指定したプレフィックス配下のオブジェクトを一覧表示する | バケット ARN |
| `s3:GetObject` | 指定したパス配下のオブジェクトを読み取る | オブジェクト ARN |

`ListBucket` の対象リソースはバケット自体なので、`s3:prefix` で一覧表示できる範囲を絞ります。一方、`GetObject` は `Resource` にオブジェクトのパスを直接指定します。

ここで指定している `reports/*` は `reports/` にもマッチします。そのため、後ほど実行する一覧取得のコマンドでは `--prefix reports/` を明示します。S3 のプレフィックスは、`reports/2026/report.csv` のようなオブジェクトキーの先頭部分を指すもので、ファイルシステム上のディレクトリではありません。[AWS のプレフィックスを使った権限制御の例](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html)

## 手順 2：アカウント B のバケットポリシーを設定する

アカウント B で対象のバケットを開き、**Permissions（アクセス許可）→ Bucket policy（バケットポリシー）** に次の設定を追加します。

すでにバケットポリシーがある場合は、必要な既存のルールを残し、以下の Statement を追加してください。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARoleToListReports",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppReadReportsRole"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222",
      "Condition": {
        "StringLike": {
          "s3:prefix": "reports/*"
        }
      }
    },
    {
      "Sid": "AllowAccountARoleToReadReports",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppReadReportsRole"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222/reports/*"
    }
  ]
}
```

`Principal` には、アクセスを許可するアクセス元のロールを指定します。ロールにパスが含まれる場合は、IAM から ARN 全体をコピーすると、パスの指定漏れを防げます。

それぞれのポリシーの役割を整理すると、次のようになります。

- アカウント A の IAM ポリシー：このロールが、どのリソースに対して何をできるか。
- アカウント B のバケットポリシー：このバケットに対して、誰のどの操作を許可するか。

**この `Allow` は、記載した権限を追加するものです。既存のほかの権限を取り消すわけではありません。** ロールやバケットに、より広い範囲を許可するポリシーがある場合は、そちらも確認してください。

## 手順 3：AWS CLI で動作確認する

### まず、使用中の認証情報を確認する

```shell
aws sts get-caller-identity --profile account-a-app
```

`Account` が `111111111111` で、ARN が次のようになっていることを確認します。

```text
arn:aws:sts::111111111111:assumed-role/AppReadReportsRole/example-session
```

別のロールが表示された場合は、S3 の動作確認に進む前に、プロファイルや認証情報の取得元を見直してください。

ここに表示されるのは STS のロールセッション ARN です。バケットポリシーには、先ほどの IAM ロール ARN を指定します。

### 許可したプレフィックス配下のオブジェクトを一覧表示する

```shell
aws s3api list-objects-v2 --bucket example-cross-account-reports-222222222222 --prefix reports/ --profile account-a-app
```

設定が正しければ、リクエストが成功し、`reports/` 配下のオブジェクトが表示されます。成功してもオブジェクトが表示されない場合は、該当するオブジェクトキーがバケット内にあるか確認してください。

### 動作確認用のオブジェクトをダウンロードする

```shell
aws s3api get-object --bucket example-cross-account-reports-222222222222 --key reports/sample.txt --profile account-a-app ./downloaded-sample.txt
```

ローカルに `downloaded-sample.txt` として保存されれば成功です。`get-object` の最後の引数は、ダウンロード先のファイルパスです。[AWS CLI GetObject リファレンス](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html)

### 許可していないプレフィックスへのアクセスが拒否されるか確認する

次に、許可の対象外であるプレフィックスの一覧取得を試します。

```shell
aws s3api list-objects-v2 --bucket example-cross-account-reports-222222222222 --prefix private/ --profile account-a-app
```

ほかにアクセスを許可するポリシーがなければ、`AccessDenied` になるはずです。

許可した操作だけでなく、許可していない操作が拒否されることも確認しておくと、権限の範囲を検証できます。成功してしまう場合は、ロールやバケットに、より広い権限を付与する別のポリシーがないか確認してください。

## AccessDenied が出たら、どこを確認する？

まず、「オブジェクトの一覧取得」と「ダウンロード」のどちらで失敗しているかを切り分けます。そのうえで、次の項目を確認します。

| 確認項目 | 確認する内容 |
|---|---|
| 実際に使っている認証情報 | `get-caller-identity` に想定したアカウントとロールが表示されているか |
| アクセス元の IAM ポリシー | 対象の Action と Resource が許可されているか |
| アクセス先のバケットポリシー | `Principal` に正しいロール ARN が指定されているか |
| バケット ARN とオブジェクト ARN | `ListBucket` にはバケット ARN、`GetObject` にはオブジェクト ARN を指定しているか |
| プレフィックスの条件 | リクエストに `reports/` を指定しているか。大文字・小文字やスラッシュは一致しているか |
| 明示的な拒否と権限の制限 | SCP、RCP、アクセス許可の境界、セッションポリシーなどがリクエストを制限していないか |
| ネットワーク関連の条件 | 特定の VPC エンドポイントや送信元 IP が必須になっていないか。エンドポイントポリシーによる制限はないか |
| オブジェクトの所有者 | ACL が有効な古いバケットで、別のアカウントがオブジェクトを所有していないか |

`Allow` を追加しても、適用される明示的な `Deny` は上書きできません。組織レベルの制御やネットワーク条件がある環境では、それらも含めて確認します。[AWS の S3 403 エラーのトラブルシューティング](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-403-errors.html)

よくある次の 2 パターンも、切り分けの手がかりになります。

**一覧は表示できるが、ダウンロードできない**

`ListBucket` のリクエストは通っています。次に、両方のポリシーで `GetObject` を許可しているか、対象オブジェクトが許可範囲に含まれるか、オブジェクト自体が存在するかを確認します。

**キーが分かっているファイルはダウンロードできるが、一覧を取得できない**

`GetObject` だけが許可されているか、一覧取得時のプレフィックスが条件に一致していない可能性があります。一覧取得とダウンロードは別の操作なので、それぞれの権限を確認してください。

## よくある質問

### クロスアカウントアクセスでは S3 Block Public Access を無効にする必要がある？

必要ありません。この記事では特定の IAM ロールを明示して許可しているので、Block Public Access は有効のままで構いません。

ただし、バケットポリシー内のほかの記述によって、S3 がそのポリシーをパブリックと判定する場合、`RestrictPublicBuckets` がクロスアカウントアクセスに影響することがあります。ポリシー全体を確認してください。[S3 Block Public Access のドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)

### s3:ListBucket は必ず必要？

必須ではありません。アプリケーションが完全なオブジェクトキーを把握していて、そのオブジェクトをダウンロードするだけなら、`s3:GetObject` のみで対応できます。この記事では `reports/` 配下の一覧も取得するため、`ListBucket` を追加しています。[GetObject に必要な権限](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html)

**IAM ユーザーの認証情報（アクセスキー ID とシークレットアクセスキー）を使い、WinSCP や FileZilla Pro などの S3 クライアントでフォルダーをたどる場合は、`s3:ListBucket` が必要です。** クライアントは、バケットや指定したプレフィックスの内容を取得して、フォルダーやファイルを表示します。この権限がないと、接続できたりバケットが見えたりしても、フォルダーを開こうとすると `AccessDenied` になることがあります。一覧取得に必要な権限なので、IAM ロールを使う場合も同じです。[WinSCP 公式サポートでの説明](https://winscp.net/forum/viewtopic.php?t=34760)

クロスアカウントの場合は、アクセス元の IAM ユーザーの IAM ポリシーと、アクセス先のバケットポリシーの両方で、該当する `s3:ListBucket` 操作を許可します。バケットポリシーの `Principal` も、実際に使う IAM ユーザーの ARN に変更してください。

また、この記事の設定では、一覧取得を許可しているのは `reports/` とその配下のプレフィックスだけで、バケットのルートは対象外です。`s3:ListBucket` を追加していても、クライアントが最初にルートの一覧を取得しようとすると拒否されることがあります。デフォルトのリモートディレクトリを `/バケット名/reports/` に設定し、許可した範囲にアクセスするようにしてください。「バケットの一覧取得」と「バケット内のオブジェクトの一覧取得」は別の操作です。別アカウントのバケットでは、接続先のパスを直接指定する必要がある場合もあります。[WinSCP の S3 接続設定](https://winscp.net/eng/docs/guide_amazon_s3)、[FileZilla Pro の S3 接続設定](https://filezillapro.com/docs/v3/cloud/configure-filezilla-pro-to-connect-to-s3/)

### ACL の設定は必要？

この記事では `Bucket owner enforced` を使用しているため、ACL は無効です。IAM ポリシーとバケットポリシーでアクセスを管理します。ACL が有効な既存環境では、オブジェクトの所有者も確認してください。[S3 Object Ownership のドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

### アップロードも許可したい場合は？

アクセス元の IAM ポリシーとアクセス先のバケットポリシーの両方で、対象のオブジェクト ARN に対する `s3:PutObject` を追加します。

### CLI では成功するのに、コンソールでうまく表示できないのはなぜ？

この記事で付与しているのは、特定のバケットとプレフィックスに対する API のアクセス権限です。コンソールでは画面の表示や移動時に別の API を呼び出すことがあるため、この権限だけですべての画面を操作できるとは限りません。今回の設定は、紹介した CLI コマンドで動作確認してください。[S3 の IAM ポリシー例とコンソールの権限](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-policies-s3.html)
