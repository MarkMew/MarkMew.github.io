---
layout: post
title: "Amazon S3へファイルをアップロードする5つの方法：Console、CLI、API、SFTP、署名付きURL"
image: https://fastly.picsum.photos/id/1051/1200/630.jpg?hmac=0-hLWE8LP6zTWPjN1tDobiunaNnZTQlPKIimN3WbBVM
description: "AWS Management Console、AWS CLI、API Gateway、AWS Transfer Family、署名付きURLを使ってAmazon S3へファイルをアップロードする方法を、用途、制約、セキュリティ、実装例とともに比較します。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3]
keywords: [AWS, S3, AWS Management Console, AWS CLI, API Gateway, Transfer Family, 署名付きURL]
lang: ja
date: 2026-07-08
---

S3へのファイルアップロードは、AWSでもっとも一般的な基本操作の一つです。

しかし、「ファイルをアップロードする」といっても、エンジニアがローカル環境から送る場合、CIから静的ファイルを公開する場合、バックエンドでユーザーの添付ファイルを受け取る場合、ブラウザから大容量ファイルを直接送る場合、取引先がSFTPしか利用できない場合など、状況は大きく異なります。最終的にはいずれもS3にオブジェクトを書き込みますが、適切な入口は同じではありません。

この記事では、実務でよく使われる5つの方法を比較します。

1. AWS Management Consoleから直接アップロードする
2. AWS CLIを使用する
3. API GatewayとS3を直接統合する、またはバックエンド経由でアップロードする
4. AWS Transfer Familyを使い、SFTP/FTPSで外部とファイルを交換する
5. 署名付きURLを使い、フロントエンドや外部クライアントから直接アップロードする

## 早見表

| 方法 | 適した用途 | メリット | 主な制約 |
| --- | --- | --- | --- |
| AWS Management Console | 一時的な作業、少数のファイル、S3の初回利用 | ツールのインストールが不要で、操作がわかりやすい | 手作業に依存し、自動化や大量の反復処理には向かない |
| AWS CLI | エンジニア、ローカル運用、CI/CD | シンプルで、ディレクトリや大容量ファイルにも対応できる | 実行環境にAWSの認証情報とIAM権限が必要 |
| API Gateway／バックエンド | 小さな添付ファイル、業務ロジックや検証が必要なAPI | 認証、認可、監査、命名規則を一元管理できる | APIのペイロード制限を受け、バックエンド経由では計算リソースも消費する |
| AWS Transfer Family | 取引先、レガシーシステム、SFTP/FTPSフロー | 相手にAWS APIへの移行を求めずに済む | エンドポイント、ユーザー、ネットワーク、サービス費用の管理が必要 |
| 署名付きURL | Web、アプリ、外部システムからの直接アップロード | ファイルがバックエンドを通らず、拡張しやすい | URLの有効期限、CORS、ファイル名、アップロード条件の管理が必要 |

## 方法1：AWS Management Console

CLIやIaCツールを使い始める前であれば、AWS Management Consoleにログインし、Amazon S3から対象バケットを開いて「アップロード」を選ぶ方法がもっとも直感的です。

ツールのインストールやコマンド入力が不要なため、一時的なアップロード、テスト、S3の操作を覚える場面に向いています。画面上でメタデータ、ストレージクラス、その他のオブジェクト設定も指定できます。

ただし、コンソールでの操作は手作業のため、再現や自動化が難しく、CI/CDや定期実行には向きません。Amazon S3コンソールでアップロードできる単一ファイルの上限は現在160 GBです。それより大きなファイルには、AWS CLI、AWS SDK、またはS3 REST APIを使用します。

## 方法2：AWS CLI

エンジニアがローカル環境、踏み台サーバー、CIから直接アップロードする場合に適しています。手軽に始められますが、IAM権限と認証情報の管理には注意が必要です。

### 単一ファイルをアップロードする

```bash
aws s3 cp ./report.csv s3://example-bucket/uploads/report.csv
```

アップロード後、オブジェクトが存在することを確認します。

```bash
aws s3 ls s3://example-bucket/uploads/report.csv
```

### ディレクトリ全体をアップロードする

ディレクトリを再帰的にアップロードするには、`--recursive`を使用します。

```bash
aws s3 cp ./dist s3://example-bucket/site/ --recursive
```

送信元と送信先を継続的に同期する場合は、`sync`を使用します。

```bash
aws s3 sync ./dist s3://example-bucket/site/
```

AWS CLIの高レベルS3コマンドは、ファイルがmultipart thresholdに達すると自動的にマルチパートアップロードへ切り替わるため、各パートを手動で分割する必要はありません。本番環境では、ローカルからのアクセスにAWS IAM Identity Centerを使用し、EC2、ECS、EKS、CI RunnerではIAMロールまたは一時的な認証情報を使用します。長期のアクセスキーをソースコードやPipeline変数に保存しないでください。

> 踏み台サーバーやほかのEC2インスタンスにバックアップ対象のファイルがある場合は、`cron`から`aws s3 sync`を定期実行できます。EC2のIAMロールを使用し、権限を専用のS3プレフィックスに限定したうえで、インスタンスに長期のアクセスキーを保存しないようにします。
{: .prompt-info }

### 権限設定

#### WinSCPまたはS3 Browserからアップロードする

WinSCPやS3 BrowserなどのGUIクライアントはS3 APIを通してオブジェクトへアクセスするもので、内部でAWS CLIを実行しているわけではありません。アップロードに必要な`s3:PutObject`に加え、指定したバケット内のオブジェクトを画面に表示するには`s3:ListBucket`も必要です。

クライアントによっては、最初にアカウント内の全バケットを一覧表示するため、`s3:ListAllMyBuckets`が必要です。この権限を付与すると、アカウント内のバケット名がユーザーに見えるようになります。対象バケットを直接指定できるクライアントであれば省略できます。次の例では、`uploads/`の参照とアップロードを許可します。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListUploadPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uploads", "uploads/*"]
        }
      }
    },
    {
      "Sid": "UploadObjects",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    },
    {
      "Sid": "ListBucketsInClient",
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

ダウンロードや削除も必要な場合に限り、`s3:GetObject`または`s3:DeleteObject`を追加します。最初からすべてを許可する必要はありません。

#### CLIからアップロードする

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListUploadPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uploads", "uploads/*"]
        }
      }
    },
    {
      "Sid": "UploadObjects",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    }
  ]
}
```

この権限で`uploads/`へのアップロードと一覧表示ができます。前述の`site/`を対象とするディレクトリアップロードを実行する場合は、そのプレフィックスもポリシーに追加してください。オブジェクトを一覧表示しないのであれば、`s3:ListBucket`は削除できます。

## 方法3：API GatewayとS3の直接統合、またはバックエンド経由

### API GatewayからS3へ直接アップロードする

API Gatewayが呼び出せるのはLambdaだけではありません。REST APIのAWSサービス統合を利用すれば、Lambdaを経由せずにリクエストをS3へ直接渡せます。

```text
Client → API Gateway REST API → Amazon S3
```

API Gateway用の実行ロールを作成し、対象の場所に対する`s3:PutObject`を許可します。次のポリシーは`uploads/`への書き込みだけを許可します。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    }
  ]
}
```

次に、REST APIへ`PUT`メソッドを作成し、AWSサービス統合としてS3を選択します。URL内のファイル名をS3のオブジェクトキーへマッピングし、アップロードに必要な`Content-Type`を渡します。バイナリファイルを受け取る場合は、APIのバイナリメディアタイプも設定します。

実行ロールが表すのは、API GatewayにS3への書き込み権限があるということだけで、呼び出し元の認証が済んでいるという意味ではありません。外部公開するAPIには、IAM、Cognitoオーソライザーなどの認可も別途設定します。この構成ではLambdaを省略できますが、ファイルはAPI Gatewayを通るため、10 MBのペイロード上限は変わりません。

### Lambdaまたはバックエンド経由でアップロードする

認証、認可、監査をバックエンドで一元管理する必要がある場合に適しています。柔軟性は高いものの、システムは複雑になります。

```text
Client → API Gateway → Lambda/Backend → Amazon S3
```

バックエンドは、ログインユーザー、ファイル形式、業務上の識別番号、オブジェクト名を検証してから、AWS SDKで`PutObject`を呼び出せます。中心となる処理は次のとおりです。HTTPリクエストの解析やエラー処理は、使用するフレームワークによって異なります。

```python
import boto3

s3 = boto3.client("s3")

s3.put_object(
    Bucket="example-bucket",
    Key="uploads/report.pdf",
    Body=file_bytes,
    ContentType="application/pdf",
)
```

この方法では、すべてのルールをバックエンドに集約できます。たとえば、注文の所有者だけが添付ファイルを追加できる、データベースへの書き込みが成功した後にだけオブジェクトを作成する、アップロード後にマルウェアスキャンや審査を実行する、といった制御が可能です。

一方、ファイルはAPI Gatewayとバックエンドの両方を通り、ネットワーク帯域と計算リソースを消費します。API Gateway HTTP APIのペイロード上限は10 MBで、引き上げることはできません。Base64エンコードも必要な場合、送信できる元ファイルはさらに小さくなります。そのため、小さな添付ファイルには向きますが、大容量の動画、バックアップ、データセットには不向きです。

大容量ファイルには署名付きURLを使い、API Gatewayにはユーザー認証とアップロード権限の発行だけを担当させます。

## 方法4：AWS Transfer Family

SFTP/FTPSで外部システムとファイルを交換する必要がある場合に適しており、既存のフローを大きく変えずにS3へ接続できます。

AWS Transfer Familyは、SFTP、FTPS、FTP、AS2、ブラウザベースの転送をサポートするマネージドファイル転送サービスで、バックエンドにはS3またはEFSを使用できます。相手側はWinSCP、Cyberduck、FileZilla、OpenSSHなどの使い慣れたツールをそのまま利用でき、AWS CLIを覚えたりAWSの認証情報を取得したりする必要はありません。

基本的な流れは次のとおりです。

1. S3バケットとTransfer Familyが使用するIAMロールを作成する。
2. SFTPまたはFTPSに対応するTransfer Familyサーバーを作成する。
3. サービスマネージド、Microsoft AD、またはカスタムIDプロバイダーを選択する。
4. ユーザーのホームディレクトリとアクセス可能なS3プレフィックスを設定する。
5. Transfer Familyのエンドポイントを取引先へ通知する。

SFTPクライアントからの操作は一般的なSFTPサーバーと同じです。

```bash
sftp -i ~/.ssh/partner-key partner@s-0123456789abcdef0.server.transfer.ap-northeast-1.amazonaws.com
sftp> put report.csv /uploads/report.csv
```

S3には実際のディレクトリ階層がないため、SFTPクライアントに表示されるディレクトリはオブジェクトキーのプレフィックスです。`chmod`やシンボリックリンクなどのファイルシステム操作も、必ずしもS3へ対応付けられるわけではありません。

Transfer Familyは、既存のB2Bファイル交換、固定された送信元IP、企業の認証基盤、変更が難しいレガシーシステムに向いています。一人のユーザーがときどき一つのファイルを送るだけなら、署名付きURLより構成が複雑になり、エンドポイントやデータ転送の費用も考慮する必要があります。

## 方法5：署名付きURL

フロントエンドや外部クライアントからS3へ直接アップロードし、バックエンドの通信負荷を軽減できます。適切な有効期限とアップロード条件の設定が必要です。

```text
1. ClientがBackendへアップロード権限を要求する
2. Backendが認証を行い、署名付きURLを生成する
3. ClientがURLを使ってS3へ直接PUTする
4. S3 Eventが後続処理を開始する
```

署名付きURLを生成するIAMプリンシパルには、対象オブジェクトキーへのアップロード権限が必要です。次のPython例では、指定したオブジェクトキーにだけ使用でき、15分間有効な`PUT` URLを生成します。

```python
import boto3

s3 = boto3.client("s3")

upload_url = s3.generate_presigned_url(
    ClientMethod="put_object",
    Params={
        "Bucket": "example-bucket",
        "Key": "uploads/8f6c2f4a/report.pdf",
        "ContentType": "application/pdf",
    },
    ExpiresIn=900,
)
```

URLを受け取ったクライアントは直接アップロードできます。

```bash
curl --request PUT \
  --header "Content-Type: application/pdf" \
  --upload-file ./report.pdf \
  "<presigned-url>"
```

`Content-Type`が署名に含まれている場合、クライアントは同じヘッダーを送信しなければならず、異なるとS3は署名不一致を返します。ブラウザから直接アップロードする場合は、対象オリジンとHTTPメソッドを許可するCORS設定もバケットに必要です。

署名付きURLは短期間有効なBearer Tokenとして扱います。URLを入手した人は、有効期限まで使用できます。少なくとも次の点に注意してください。

- バケットとオブジェクトキーはバックエンドで決定し、ユーザーが送信した完全なパスをそのまま信頼しない。
- UUIDまたはテナント別プレフィックスを使い、別のユーザーが同じキーを上書きしないようにする。
- 有効期限を短く設定し、URLを公開ログや分析ツールへ記録しない。
- アップロード前に許可する拡張子、MIMEタイプ、業務状態を検証し、アップロード後に実際の内容も確認する。
- ファイルサイズやフォーム項目を制限する場合は、ポリシー条件を設定した署名付きPOSTを検討する。
- 大容量ファイルには署名付きマルチパートアップロードを使い、クライアント側で分割、並列化、再試行を行う。

同じ署名付きURLは、有効期限内であれば再利用できます。対象キーがすでに存在する場合、バージョニングが無効なら既存のオブジェクトを上書きする可能性があり、有効なら新しいバージョンが作成されます。一度限りのURLではないため、「一度使用した」ことだけでは安全性を保証できません。

## 共通するセキュリティと運用上の考慮事項

どの方法を選ぶ場合でも、次の項目を確認します。

### IAMの最小権限

アクセスできるバケット、プレフィックス、操作を制限します。アップロード専用のアプリケーションに通常必要なのは`s3:PutObject`だけです。一覧表示、ダウンロード、削除が本当に必要な場合に限り、`s3:ListBucket`、`s3:GetObject`、`s3:DeleteObject`を追加します。バケットポリシーやライフサイクルルールを変更する管理権限は、通常のアップロード処理へ付与しないでください。

### 意図しない上書きを防ぐ

S3ではオブジェクトキーがオブジェクトの識別名です。同じキーへ再度アップロードすると、既存のオブジェクトを上書きする可能性があります。履歴を残す必要がある場合は、S3 Versioningを有効にするか、重複しないキーを使用します。

### 暗号化と機密データ

S3へ新しくアップロードされたオブジェクトは、SSE-S3で自動的に暗号化されます。法令、監査、職務分離の要件からカスタマーマネージドキーが必要な場合は、バケットのデフォルト暗号化をSSE-KMSに設定し、必要なKMS権限を追加します。

### 拡張子だけでファイルの内容を信用しない

`.jpg`、`.pdf`、`Content-Type`はいずれもクライアントが指定するため、内容の安全性を証明できません。外部からのアップロードは、最初に隔離用プレフィックスへ保存します。その後、イベント駆動処理で形式の確認、マルウェアスキャン、目視確認などを行い、安全性を確認してから正式な領域へ移動します。

### 大容量ファイルと未完了のアップロード

S3では一度の`PUT`で最大5 GBをアップロードできます。より大きなオブジェクトにはマルチパートアップロードが必要で、現在の単一S3オブジェクトの上限は50 TBです。未完了のマルチパートアップロードでも、送信済みのパートにはストレージ料金が発生します。期限切れの未完了アップロードを自動削除するライフサイクルルールを設定してください。

## まとめ

すべての用途に最適な方法はありません。誰がアップロードするのか、ファイルの大きさ、既存プロトコルとの互換性が必要か、ファイル本体をバックエンドへ通す必要があるかによって選択します。

- 少数のファイルを一時的にアップロードするなら、AWS Management Consoleを使用する。
- 信頼できるエンジニアやCI/CDからであれば、AWS CLIから始める。
- 小さなファイルをS3へ転送するだけなら、API GatewayのAWSサービス統合を検討する。
- 小さなファイルにバックエンドの業務ロジックが必要なら、API Gatewayとバックエンドを使用する。
- 取引先がSFTP/FTPSしか利用できないなら、AWS Transfer Familyを使用する。
- Web、アプリ、外部システムから直接アップロードするなら、署名付きURLを優先する。

エンドユーザー向けアップロード機能の多くでは、バックエンドが認可とオブジェクトキーの決定を担当し、クライアントが署名付きURLでS3へ直接ファイルを送る構成を採用できます。これはセキュリティ、パフォーマンス、システムの複雑さのバランスを取りやすい方法です。

---

## 参考資料

- [AWS CLI `s3 cp` Command Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html)
- [Uploading objects - Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/upload-objects.html)
- [Listing Amazon S3 general purpose buckets](https://docs.aws.amazon.com/AmazonS3/latest/userguide/list-buckets.html)
- [Tutorial: Create a REST API as an Amazon S3 proxy](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-s3.html)
- [Quotas for configuring and running a REST API in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html)
- [Quotas for configuring and running an HTTP API in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html)
- [What is AWS Transfer Family?](https://docs.aws.amazon.com/transfer/latest/userguide/what-is-aws-transfer-family.html)
- [Download and upload objects with presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)
- [Configuring cross-origin resource sharing (CORS)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ManageCorsUsing.html)
- [Configuring default encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html)
- [Deleting incomplete multipart uploads with a Lifecycle rule](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-abort-incomplete-mpu-lifecycle-config.html)
