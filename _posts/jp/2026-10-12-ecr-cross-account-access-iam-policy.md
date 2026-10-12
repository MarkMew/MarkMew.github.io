---
layout: post
title: "Amazon ECR クロスアカウントアクセス：Repository Policy と IAM Policy の設定"
image: https://fastly.picsum.photos/id/776/1200/630.jpg?hmac=Lb8y0-sLk2uqC_rjc_vHCUEnR1NLKPZjFgwq2FtfAoQ
description: "ECR Repository Policy と IAM Policy を使って、別の AWS アカウントの IAM ロールにプライベートイメージの Pull 権限を付与する方法を、AWS CLI と Docker での確認手順とともに解説します。"
author: Mark_Mew
categories: [AWS, ECR]
tags: [AWS, ECR, IAM]
keywords: [ECR クロスアカウントアクセス, ECR Repository Policy, IAM Policy, Docker pull]
lang: ja
date: 2026-10-12
---

**アクセス元の AWS アカウントにある IAM ロールから、別アカウントの Amazon ECR プライベートリポジトリのイメージを Pull するには、アクセス先の Repository Policy でロールを許可し、アクセス元の IAM Policy でも必要な ECR アクションを許可します。** また、ECR Registry にログインするには、アクセス元のロールに `ecr:GetAuthorizationToken` が必要です。ログインできても、Repository Policy で許可されていなければイメージの Pull は失敗します。[ECR Repository Policy のドキュメント](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html)

この記事では、「アカウント A のアプリケーションがアカウント B のプライベートリポジトリからイメージを Pull する」ケースを例に、最小権限の設定、ECR へのログイン、イメージの Pull、よくあるエラーの確認方法を説明します。[S3 のクロスアカウントアクセスの記事](/posts/s3-cross-account-access-iam-bucket-policy/)も参考にしてください。

## Repository Policy と IAM Policy の役割

ECR の Repository Policy（リソースベースポリシー）は、個々のリポジトリに対して、どのプリンシパルにどの操作を許可するかを設定します。IAM Policy（アイデンティティベースポリシー）は、アクセス元アカウントのロールに許可する操作を設定します。クロスアカウントアクセスでは、アクセス先アカウントが Repository Policy でアクセス元を許可し、アクセス元のロールにも必要な IAM 権限を付与します。適用される明示的な `Deny` があれば、`Allow` があってもアクセスは拒否されます。[ECR と IAM の連携](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_service-with-iam.html)

| 設定場所 | ポリシー | 許可する操作 |
|---|---|---|
| アカウント A の IAM ロール | IAM Policy | ECR にログインし、アカウント B の指定リポジトリからイメージを Pull する |
| アカウント B の ECR Repository | Repository Policy | アカウント A の指定ロールによるリポジトリへのアクセスを許可する |

## 構成例と前提条件

| 項目 | サンプル値 |
|---|---|
| アクセス元アカウント A | `111111111111` |
| アクセス先アカウント B | `222222222222` |
| AWS リージョン | `ap-northeast-1` |
| アカウント A のロール | `AppPullImageRole` |
| アカウント B のリポジトリ | `backend-api` |
| イメージタグ | `2026.10.12` |
| CLI プロファイル | `account-a-app` |

サンプル値は実際の環境に置き換えてください。アクセス先の Repository とアクセス元の IAM ロールは作成済みで、AWS CLI と Docker が利用できることを前提とします。ECR Registry URI は `<account-id>.dkr.ecr.<region>.amazonaws.com` の形式です。Repository URI には、その末尾にリポジトリ名を追加します。

この記事では既存イメージの Pull のみを許可し、Push、Repository の作成・削除は許可しません。ECR のクロスアカウント／クロスリージョンレプリケーションは、イメージを別の Registry に複製する別の方法です。アクセス先から元の Repository を直接 Pull する場合は、この記事の Repository Policy を使用します。[ECR プライベートイメージのレプリケーション](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html)

## 手順 1：アカウント A のロールに権限を付与する

アカウント A の IAM で `AppPullImageRole` に次の IAM Policy をアタッチします。`ecr:GetAuthorizationToken` は `Resource: "*"` が必要です。それ以外の Pull アクションは、アカウント B の対象 Repository ARN に限定します。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetECRAuthorizationToken",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PullFromAccountBRepository",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:ap-northeast-1:222222222222:repository/backend-api"
    }
  ]
}
```

`GetAuthorizationToken` は Registry へのログインに必要で、Repository Policy では代替できません。ほかの 3 つのアクションは、レイヤーの確認、イメージ Manifest の取得、レイヤーのダウンロードに使われます。イメージ一覧や Repository 情報を取得するツールを使う場合は、要件に応じて `ecr:ListImages`、`ecr:DescribeImages`、`ecr:DescribeRepositories` も追加してください。この `docker pull` の例では権限を広げる必要はありません。[ECR の IAM Policy 例](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html)

### Terraform：アクセス元ロールの IAM Policy

次の Terraform は、GitLab Runner が `dockerdind` と `devtool` の 2 つの Repository から Pull するための IAM Policy を作成します。作成した Policy は、アカウント A の Runner ロールにアタッチしてください。

```terraform
resource "aws_iam_policy" "pull_ecr_from_other_account_policy" {
  name = "PullECRFromOtherAccountPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PullCrossAccountRunnerImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:ap-northeast-1:222222222222:repository/dockerdind",
          "arn:aws:ecr:ap-northeast-1:222222222222:repository/devtool"
        ]
      }
    ]
  })
}
```

## 手順 2：アカウント B の Repository Policy を設定する

アカウント B の `ap-northeast-1` リージョンで ECR Repository `backend-api` を開き、**Permissions** から次の Repository Policy を追加します。既存の Policy がある場合は、必要な Statement を残したまま追加してください。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARoleToPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppPullImageRole"
      },
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "*"
    }
  ]
}
```

`Principal` にはアクセス元の IAM ロール ARN を指定します。ロールに Path がある場合は、`arn:aws:iam::111111111111:role/team/AppPullImageRole` のように完全な ARN を指定してください。この記事では特定のロールを指定しています。アカウント全体を Principal にする場合は `arn:aws:iam::111111111111:root` を指定できますが、アクセス元アカウントの IAM Policy で、利用できるロールを制限してください。必要がない限り、アカウント全体やワイルドカード Principal は使用しないでください。[ECR Repository Policy の例](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)

### Terraform：アクセス先の Repository Policy

次の設定は、アカウント B の `devtool` と `dockerdind` の Repository にクロスアカウント Pull 権限を付与します。実際の Repository 名とアクセス元ロール ARN に合わせて変更してください。

```terraform
resource "aws_ecr_repository_policy" "devtool" {
  repository = aws_ecr_repository.devtool.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountGitLabRunnerPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::111111111111:role/DummyRole"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "dockerdind" {
  repository = aws_ecr_repository.dockerdind.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountGitLabRunnerPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::111111111111:role/DummyRole"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}
```

## 手順 3：アクセス元の認証情報を確認して ECR にログインする

まず、AWS CLI がアカウント A の想定したロールを使用していることを確認します。

```shell
aws sts get-caller-identity --profile account-a-app
```

`Account` が `111111111111` で、ARN が次のような形式であることを確認します。

```text
arn:aws:sts::111111111111:assumed-role/AppPullImageRole/example-session
```

別のロールが表示された場合は、プロファイルまたは認証情報の取得元を修正してから ECR にアクセスしてください。

ここに表示されるのは STS のロールセッション ARN です。Repository Policy の Principal には、IAM ロール ARN を指定します。

ログインパスワードを取得し、アカウント B の `ap-northeast-1` Registry にログインします。

```shell
aws ecr get-login-password --region ap-northeast-1 --profile account-a-app | docker login --username AWS --password-stdin 222222222222.dkr.ecr.ap-northeast-1.amazonaws.com
```

成功すると Docker に `Login Succeeded` と表示されます。ECR の認証トークンには有効期限があります。期限が切れた場合は、ログインコマンドを再実行してください。[AWS CLI get-login-password リファレンス](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html)

## 手順 4：イメージを Pull する

ログイン後、Repository URI とタグを指定してイメージを Pull します。

```shell
docker pull 222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/backend-api:2026.10.12
```

アカウント ID とリージョンが、対象 Repository の Registry と一致していることを確認してください。Repository 名とタグも実在する必要があります。リージョンをまたぐ場合は、イメージが保存されているリージョンの Registry にログインして Pull します。

## AccessDenied が発生したときの確認項目

| エラー／状況 | 確認する内容 |
|---|---|
| `get-login-password` が `AccessDeniedException` を返す | アクセス元ロールに `ecr:GetAuthorizationToken` が許可されているか。SCP、Permissions Boundary、Session Policy などで制限されていないか |
| Docker ログイン失敗、または `no basic auth credentials` | Registry URI、リージョン、アカウント ID が一致しているか。ユーザー名に `AWS` を指定しているか |
| ログインできるが `docker pull` が `denied` になる | アクセス元 IAM Policy と Repository Policy の Pull アクション、Repository ARN、Principal のロール ARN が正しいか |
| イメージまたはタグが見つからない | Repository 名、タグ、Registry URI、リージョンが正しいか |
| Policy が正しそうなのに拒否される | 明示的な `Deny`、SCP、Resource Control Policy、VPC Endpoint Policy などがないか |

アクセス元の IAM Policy では Repository ARN を正確に指定します。Repository Policy では `Resource` に `"*"` を指定し、`Principal` にアクセス元の IAM ロール ARN を指定します。`get-caller-identity` に表示される STS assumed-role session ARN は Principal に使用しません。`Allow` を追加しても、適用される明示的な `Deny` は上書きできません。[ECR Repository Policy の設定方法](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html)

## よくある質問

### Repository Policy だけで設定できますか？

クロスアカウントアクセスでは、アクセス先の Repository Policy とアクセス元ロールの IAM Policy の両方を確認してください。また、`ecr:GetAuthorizationToken` はアクセス元の IAM Policy で許可する必要があり、Repository Policy では代替できません。

### この設定でイメージの Push もできますか？

できません。この記事の設定は Pull に必要なアクションのみです。Push には `ecr:CompleteLayerUpload`、`ecr:InitiateLayerUpload`、`ecr:PutImage`、`ecr:UploadLayerPart` などの権限が別途必要です。Repository の範囲を限定して追加してください。[ECR Repository Policy の例](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)

### IAM ロールを使う必要がありますか？

この記事では、一時認証情報を利用できる IAM ロールを使用しています。ほかの IAM プリンシパルも要件に応じて利用できますが、長期アクセスキーをイメージ、ソースコード、デプロイ設定に保存するのは避けてください。AWS の実行環境では、実行ロールやワークロード ID を優先してください。

---

設定が完了すると、アカウント A の `AppPullImageRole` でアカウント B の ECR Registry にログインし、`backend-api` の指定イメージを Pull できます。別のロールにも許可する場合は、両アカウントの Policy に対象の Principal と Repository 権限を追加し、実際の AWS 環境で確認してください。

## 参考ドキュメント

- [Private repository policies in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html)：Repository Policy と IAM Policy の役割。
- [Private repository policy examples in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)：クロスアカウントアクセスを含む Policy の例。
- [Amazon ECR identity-based policy examples](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html)：ECR の IAM Policy 例。
- [Setting a private repository policy statement in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html)：Repository Policy の設定方法。
- [get-login-password — AWS CLI Command Reference](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html)：ECR Registry のログインパスワード取得。
- [aws_iam_policy — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy)：Terraform の IAM Policy リソース。
- [aws_ecr_repository_policy — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy)：Terraform の ECR Repository Policy リソース。
