---
layout: post
title: "IAM ポリシーで S3 の特定フォルダだけにアクセスを制限する：s3:prefix と s3:delimiter の設定方法"
description: "IAM ポリシーで S3 バケット内の特定フォルダだけにアクセスを制限する方法を紹介します。s3:prefix、s3:delimiter、Null 条件の書き方と、よくある間違った例を比較し、WinSCP や S3 Browser などのクライアントでも正しく閲覧できるようにします。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, IAM]
keywords: [S3 IAM ポリシー, S3 フォルダ 権限, S3 プレフィックス 権限, s3:prefix, s3:delimiter, s3:ListBucket, AccessDenied]
lang: ja
date: 2026-11-19
---

以前の記事で [Amazon S3 のクロスアカウントアクセス](/ja/posts/s3-cross-account-access-iam-bucket-policy/) について書きましたが、実務ではそれ以上によくある要件があります。**複数のユーザーやシステムで同じバケットを共有し、それぞれ許可されたフォルダだけにアクセスさせる**というものです。

IAM ユーザーの認証情報（アクセスキー ID とシークレットアクセスキー）でアクセスする場合も、IAM ロールでアクセスする場合も、権限はその IAM ユーザーやロールにアタッチされた IAM ポリシーで決まります。そのため、本記事のポリシーはどちらの方法にも使えます。

**フォルダ単位でアクセスを制限する場合、`GetObject` や `PutObject` などのオブジェクト操作は Resource にパスを書くだけで済みます。間違えやすいのは `s3:ListBucket` です。** このアクションの Resource はバケット自体なので、一覧表示できる範囲は `s3:prefix` と `s3:delimiter` の条件キーでしか制限できません。本記事では、実際に私が間違えたポリシーを例に、それぞれの条件の書き方を説明します。

## 今回の構成

| 項目 | 例 |
|---|---|
| バケット | `markmew-test-bucket` |
| アクセスを許可するフォルダ | `foo/bar/` |
| 許可する操作 | `foo/bar/` 配下のファイルの一覧表示、ダウンロード、アップロード、削除 |
| アクセス方法 | AWS CLI、または WinSCP や S3 Browser などのクライアントツール |

S3 には実際のフォルダは存在しません。`foo/bar/report.csv` は単なるオブジェクトキーで、コンソールやクライアントツールが `/` で区切ってフォルダのように表示しているだけです。つまり、ポリシーで「フォルダを制限する」とは、実際には「キーのプレフィックスを制限する」ことです。

## クライアントツールが呼び出す API を確認する

ユーザーがクライアントツールで `foo/bar/` まで開くと、おおむね次のリクエストが送信されます。

| ユーザーの操作 | API | 必要な権限 | リクエストの内容 |
|---|---|---|---|
| アカウント内のバケットを一覧表示 | `ListBuckets` | `s3:ListAllMyBuckets` | なし |
| バケットのリージョンを取得 | `GetBucketLocation` | `s3:GetBucketLocation` | なし |
| バケットのルートを開く | `ListObjectsV2` | `s3:ListBucket` | prefix が空または指定なし、delimiter が `/` |
| `foo/` を開く | `ListObjectsV2` | `s3:ListBucket` | prefix が `foo/`、delimiter が `/` |
| `foo/bar/` を開く | `ListObjectsV2` | `s3:ListBucket` | prefix が `foo/bar/` |
| ファイルのダウンロード、アップロード、削除 | `GetObject` など | `s3:GetObject` など | Resource が `foo/bar/*` |

API で特定のパスに直接アクセスするのではなく、クライアントツールからアクセスする場合は、通常 `s3:ListAllMyBuckets` の権限が必要です。ほかの S3 バケット名が見えてしまう可能性はありますが、AWS アカウントから見るとバケットの一覧がパスの第 1 階層にあたります。この権限がないと、クライアントは接続できても、何も表示されません。

```json
{
    "Action": [
        "s3:ListAllMyBuckets"
    ],
    "Effect": "Allow",
    "Resource": "*"
}
```

> `s3:ListAllMyBuckets` で見えるのはバケット名だけで、バケットの中身は見えません。ツールで対象のバケットとリモートパスを直接指定できる場合（たとえば WinSCP のデフォルトのリモートディレクトリを `/markmew-test-bucket/foo/bar/` に設定する場合）は、この権限を省略できます。
{: .prompt-tip }

## 間違った例：すべて Allow してから Deny で除外する

最初は、インターネットで見つけた書き方を参考にしました。バケット全体に `s3:ListBucket` を許可し、`Deny` と `StringNotLike` でほかのフォルダを除外する方法です。

```terraform
resource "aws_iam_policy" "s3_foo_bar_access_policy" {
    name   = "S3FooBarAccessPolicy"

    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "HomeDirObjectAccess",
                "Action": [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:GetObjectACL"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket/*"
                ]
            },
            {
                "Action": [
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:DeleteObject",
                    "s3:DeleteObjectVersion",
                    "s3:GetObjectVersion",
                    "s3:GetObjectACL",
                    "s3:PutObjectACL",
                    "s3:AbortMultipartUpload"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket/foo/bar/*"
                ]
            },
            {
                "Action": [
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ]
            },
            {
                "Sid": "DisallowListingOfOtherFolder",
                "Action": [
                    "s3:ListBucket"
                ],
                "Condition": {
                    "StringNotLike": {
                        "s3:prefix": [
                            "",
                            "foo/",
                            "foo/*",
                            "foo/bar/",
                            "foo/bar/*"
                        ]
                    }
                },
                "Effect": "Deny",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ]
            },
            {
                "Action": [
                    "s3:ListAllMyBuckets"
                ],
                "Effect": "Allow",
                "Resource": "*"
            }
        ]
    })
}
```

このポリシーは制限できているように見えますが、実際にはいくつかの問題があります。

1. **`HomeDirObjectAccess` がバケット全体の読み取りを許可している。** Resource が `markmew-test-bucket/*` なので、オブジェクトキーさえわかれば、どのフォルダのファイルでもダウンロードできます。一覧表示を制限しても「見えない」だけで、「取得できない」わけではありません。
2. **`foo/*` によって、ほかのサブフォルダも一覧表示できてしまう。** Deny の除外リストに `foo/*` が含まれているため、`foo/other/` や `foo/secret/` へのリクエストは拒否されず、それらのフォルダ内のファイル名が見えてしまいます。
3. **空文字列 `""` で delimiter を制限していない。** prefix が空で delimiter を指定しないリクエスト（たとえば `aws s3 ls s3://markmew-test-bucket --recursive`）で、バケット内のすべてのオブジェクトキーが一覧表示されます。
4. **prefix パラメータを送らないクライアントが Deny される。** クライアントによっては、バケットのルートを開くときに prefix パラメータをまったく送りません。`StringNotLike` のような否定の演算子では、**キーが存在しない場合は条件が true と評価される**ため、リクエストは明示的に拒否され、クライアントはバケットを開けません。[IAM 条件演算子のドキュメント](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition_operators.html)
5. **明示的な Deny はすべての Allow より優先される。** 後からほかのポリシーで別のフォルダへのアクセスを追加しようとしても、この Deny にブロックされます。トラブルシューティングの際にも原因に気づきにくくなります。

## 正しい例：必要なプレフィックスだけを Allow する

より良い方法は、最初にすべてを許可するのではなく、**クライアントが実際に送信する prefix と delimiter の組み合わせを、ひとつずつ Allow する**ことです。

```terraform
resource "aws_iam_policy" "s3_foo_bar_access_policy" {
    name   = "S3FooBarAccessPolicy"

    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "ListAllBucketsForClient",
                "Action": [
                    "s3:ListAllMyBuckets"
                ],
                "Effect": "Allow",
                "Resource": "*"
            },
            {
                "Sid": "GetBucketLocation",
                "Action": [
                    "s3:GetBucketLocation"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ]
            },
            {
                "Sid": "ListBucketRootWithoutPrefix",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ],
                "Condition": {
                    "Null": {
                        "s3:prefix": "true"
                    },
                    "StringEquals": {
                        "s3:delimiter": "/"
                    }
                }
            },
            {
                "Sid": "ListParentFoldersTopLevelOnly",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ],
                "Condition": {
                    "StringEquals": {
                        "s3:prefix": [
                            "",
                            "foo",
                            "foo/",
                            "foo/bar"
                        ],
                        "s3:delimiter": "/"
                    }
                }
            },
            {
                "Sid": "ListTargetFolder",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ],
                "Condition": {
                    "StringLike": {
                        "s3:prefix": [
                            "foo/bar/*"
                        ]
                    }
                }
            },
            {
                "Sid": "TargetFolderObjectAccess",
                "Action": [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:DeleteObjectVersion",
                    "s3:AbortMultipartUpload"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket/foo/bar/*"
                ]
            }
        ]
    })
}
```

### 各ステートメントの役割

| Sid | 許可するリクエスト | 必要な理由 |
|---|---|---|
| `ListAllBucketsForClient` | バケットの一覧表示 | クライアントツールの最初の画面 |
| `GetBucketLocation` | バケットのリージョンの取得 | クライアントやコンソールが接続先のリージョンを知るため |
| `ListBucketRootWithoutPrefix` | prefix なし、delimiter が `/` の一覧表示 | ルートを開くときに prefix パラメータをまったく送らないクライアントに対応するため |
| `ListParentFoldersTopLevelOnly` | ルートと `foo/` の「1 階層だけ」の一覧表示 | `foo/bar/` までたどれるようにしつつ、見えるのはフォルダ名だけにするため |
| `ListTargetFolder` | `foo/bar/` 配下の任意の一覧表示 | 対象フォルダ内は自由に閲覧でき、再帰的な一覧表示もできるようにするため |
| `TargetFolderObjectAccess` | `foo/bar/` 内のファイルのダウンロード、アップロード、削除 | オブジェクト操作は Resource のパスで制限する |

### 上位フォルダで `s3:delimiter` を制限する理由

`ListObjectsV2` を `delimiter=/` 付きで呼び出すと、S3 はその階層のファイルとサブフォルダ名（CommonPrefixes）だけを返し、それより下は展開しません。そのため、ユーザーにはルートでは `foo/` だけが、`foo/` では `bar/` と同じ階層のほかのフォルダ名だけが見え、ほかのフォルダ内のファイルは見えません。

delimiter を制限しないと、prefix が `foo/` のリクエストで `foo/` 配下のすべてのオブジェクトキーを再帰的に一覧表示でき、`foo/other/` の中身まで見えてしまいます。つまり、フォルダの制限を回避できてしまいます。

同じ理由で、末尾に `/` がない `foo/bar` も delimiter を必須とするステートメントに入れています。prefix の `foo/bar` は `foo/barbaz/` のような似た名前のフォルダにも一致するため、delimiter を制限しないと、見せるべきでないファイルが一覧表示される可能性があります。

> 上位フォルダの 1 階層だけの一覧表示でも、同じ階層のフォルダ名や、`foo/` 直下に置かれたファイル名は見えます（ダウンロードはできません）。名前すら見せたくない場合は、ユーザーに `/markmew-test-bucket/foo/bar/` へ直接接続してもらい、`ListBucketRootWithoutPrefix` と `ListParentFoldersTopLevelOnly` の 2 つのステートメントを削除してください。
{: .prompt-warning }

### 対象フォルダで `StringLike` を使う理由

`foo/bar/*` の `*` は 0 文字以上の任意の文字列に一致するため、`foo/bar/` 自体とその配下の任意の深さのプレフィックスをまとめてカバーできます。また delimiter を制限していないので、`aws s3 ls --recursive` や `aws s3 sync` のような再帰的な一覧表示が必要な操作も使えます。

### ACL 関連の権限を削除した理由

新しく作成したバケットはデフォルトで「バケット所有者の強制」（Bucket owner enforced）になっており、ACL は無効です。そのため `s3:GetObjectAcl` や `s3:PutObjectAcl` は効果がありません。ACL が有効なままの古いバケットで、クライアントが ACL を読み書きする場合は、必要に応じて追加してください。[S3 オブジェクト所有権のドキュメント](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

## AWS CLI で動作確認する

設定が終わったら、AWS CLI で許可される範囲と拒否される範囲が想定どおりか確認します。

```bash
# 許可：ルートを一覧表示（foo/ だけが見える）
aws s3 ls s3://markmew-test-bucket/

# 許可：foo/ の階層を一覧表示
aws s3 ls s3://markmew-test-bucket/foo/

# 許可：対象フォルダを一覧表示、再帰的に一覧表示
aws s3 ls s3://markmew-test-bucket/foo/bar/
aws s3 ls s3://markmew-test-bucket/foo/bar/ --recursive

# 許可：対象フォルダ内のファイルのアップロード、ダウンロード、削除
aws s3 cp ./test.txt s3://markmew-test-bucket/foo/bar/test.txt
aws s3 cp s3://markmew-test-bucket/foo/bar/test.txt ./download.txt
aws s3 rm s3://markmew-test-bucket/foo/bar/test.txt
```

次の操作は、すべて `AccessDenied` が返るはずです。

```bash
# 拒否：バケット全体を再帰的に一覧表示
aws s3 ls s3://markmew-test-bucket --recursive

# 拒否：ほかのフォルダを一覧表示
aws s3 ls s3://markmew-test-bucket/foo/other/

# 拒否：対象フォルダ以外の場所にアップロード
aws s3 cp ./test.txt s3://markmew-test-bucket/foo/test.txt

# 拒否：ほかのフォルダのファイルをダウンロード
aws s3 cp s3://markmew-test-bucket/foo/other/secret.txt ./secret.txt
```

## よくある質問

### ユーザーごとに自分のフォルダだけにアクセスさせることはできますか？

できます。固定のパスの代わりにポリシー変数 `${aws:username}` を使い、Resource をたとえば `arn:aws:s3:::markmew-test-bucket/home/${aws:username}/*` と書けば、すべての IAM ユーザーで同じポリシーを共有できます。この変数は IAM ユーザーでのみ使えます。IAM ロールの場合は、セッションタグと `${aws:PrincipalTag/...}` を組み合わせて使います。[IAM ポリシー変数のドキュメント](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html)

Terraform の文字列では `${...}` が補間構文として扱われるため、`$${aws:username}` とエスケープする必要があります。

### バケットが SSE-KMS で暗号化されている場合、ほかに必要な権限はありますか？

カスタマーマネージドの KMS キーで暗号化されている場合は、S3 の権限に加えて、ダウンロードには `kms:Decrypt`、アップロードには `kms:GenerateDataKey` が必要です。また、KMS キーポリシーでもその IAM ユーザーやロールにキーの使用を許可する必要があります。SSE-S3 や AWS マネージドキーの `aws/s3` を使っている場合は、追加の設定は不要です。

### コンソールの一部のタブで権限エラーが表示されますが、問題ありませんか？

問題ありません。本記事のポリシーで、コンソールから `foo/bar/` までたどってファイルを操作することはできます。ただし、バケットの「プロパティ」や「アクセス許可」タブはほかの API（`GetBucketPolicyStatus` や `GetBucketVersioning` など）を呼び出すため、権限がないとエラーメッセージが表示されます。ファイル操作には影響しません。

### プログラムからアクセスするだけでも、これだけの ListBucket 条件が必要ですか？

必要ありません。アプリケーションが完全なオブジェクトキーを知っているなら、`TargetFolderObjectAccess` だけで十分です。ファイルの一覧表示が必要な場合は、`ListTargetFolder` を追加します。上位フォルダの一覧表示権限は、クライアントツールやコンソールで 1 階層ずつたどれるようにするためのものです。

## 関連記事

- [S3 のクロスアカウントアクセス：IAM ポリシーとバケットポリシーの設定方法](/ja/posts/s3-cross-account-access-iam-bucket-policy/)
- [Amazon S3へファイルをアップロードする5つの方法：Console、CLI、API、SFTP、署名付きURL](/ja/posts/upload-files-to-amazon-s3/)
- [AWS IAM Role の権限設計に深く潜る](/ja/posts/iam-role-policy-and-trust-relationship/)
- [AWS 公式のバケットポリシーの例](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
