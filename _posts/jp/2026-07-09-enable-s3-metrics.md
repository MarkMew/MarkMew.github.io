---
layout: post
title: "Amazon S3 Request Metricsを有効にする方法：CloudWatchでリクエスト、エラー、レイテンシーを監視する"
image: https://fastly.picsum.photos/id/403/1200/630.jpg?hmac=s8l5rkJ33EaYe1pNzAO8voSUhrQoQlScUq0cxuPM2bk
description: "Amazon S3のStorage MetricsとRequest Metricsの違い、およびAWS Console、AWS CLI、Terraform、CloudFormationでリクエストメトリクスを有効にする方法を解説します。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, CloudWatch, Terraform]
keywords: [AWS, Amazon S3, CloudWatch, S3 Metrics, S3 Request Metrics, Terraform]
lang: ja
date: 2026-07-09
---

Amazon S3は、AWSでもっとも歴史が長く、広く利用されているサービスの一つです。ファイルの保存だけでなく、バックアップ、静的Webサイトのコンテンツ、データレイク、アプリケーションからのアップロード先など、さまざまな用途で使われています。

バケットを作成すると、**Metrics**ページで`BucketSizeBytes`や`NumberOfObjects`などの容量メトリクスを確認できます。しかし、容量データだけでは次のような疑問には答えられません。

- 1分あたりに何回の`GET`や`PUT`が発生しているか。
- ユーザーが遭遇する`4xx`や`5xx`エラーが増えていないか。
- S3の応答時間が遅くなっていないか。
- どのプレフィックスへのトラフィックが多いか。

これらを確認するには、Amazon S3 Request Metricsを有効にする必要があります。この記事では、S3が提供するメトリクスの違いを説明したうえで、AWS Management Console、AWS CLI、Terraform、CloudFormationからRequest Metricsを有効にする方法を紹介します。

## S3が提供するCloudWatchメトリクス

S3からCloudWatchへ送信されるメトリクスは、主に次の種類に分けられます。

| 種類 | 更新頻度 | デフォルトで有効 | 主な用途 |
| --- | --- | --- | --- |
| Storage Metrics | 1日1回 | 有効、追加料金なし | バケット容量とオブジェクト数の確認 |
| Request Metrics | 1分ごと | 無効。metrics configurationの作成が必要 | リクエスト数、エラー、通信量、レイテンシーの監視 |
| Replication Metrics | 1分ごと | replication ruleでの有効化が必要 | レプリケーションの遅延、保留中データ、失敗した操作の監視 |
| S3 Storage Lens | 日次集計。高度なメトリクスはオプション | 無料版と有料版あり | アカウント、リージョン、組織を横断したストレージとアクティビティの分析 |

つまり、S3で利用できるメトリクスが二つしかないわけではありません。デフォルトで有効なのが、日次更新のStorage Metricsだけということです。ほぼリアルタイムのリクエスト情報を取得するには、Request Metrics configurationを別途作成します。

> Request MetricsにはCloudWatchの標準料金が適用され、データはベストエフォートで配信されます。傾向の把握、Dashboard、Alarmには適していますが、リクエスト単位の完全な監査記録や正確な課金データとしては使用できません。完全な記録が必要な場合は、S3 Server Access LoggingまたはCloudTrail Data Eventsを併用してください。
{: .prompt-warning }

## 有効化すると確認できるデータ

Request Metricsは、CloudWatchの`AWS/S3` namespaceへデータを送信します。代表的なメトリクスは次のとおりです。

- `AllRequests`：すべてのHTTPリクエスト数。
- `GetRequests`、`PutRequests`、`DeleteRequests`：操作別のリクエスト数。
- `ListRequests`：バケットの内容を一覧表示するリクエスト数。
- `BytesDownloaded`、`BytesUploaded`：ダウンロードおよびアップロードされたバイト数。
- `4xxErrors`、`5xxErrors`：クライアント側およびサーバー側のエラー。
- `FirstByteLatency`：リクエストを受信してから最初の1バイトを返し始めるまでの時間。
- `TotalRequestLatency`：リクエストを受信してからレスポンスが完了するまでの時間。

一つのmetrics configurationで、利用可能なRequest Metrics一式が有効になります。特定のメトリクスだけを選んで有効にすることはできません。また、まだ発生していない操作のメトリクスはCloudWatchに表示されない場合があります。

## バケット全体または特定のオブジェクトを監視する

configurationを作成するときは、バケット全体を対象にするか、次の条件で範囲を絞り込めます。

- `uploads/`や`logs/production/`などのオブジェクトキープレフィックス。
- `environment=production`などのオブジェクトタグ。
- S3 Access Point ARN。
- 複数条件の組み合わせ。この場合、オブジェクトはすべての条件を満たす必要があります。

複数のシステムで一つのバケットを共有している場合は、`production-uploads`や`audit-logs`のように、アプリケーションまたはプレフィックスごとにconfigurationを分けると管理しやすくなります。CloudWatchの`FilterId`ディメンションでワークロードを区別でき、不要なデータ収集も避けられます。

ただし、filterを設定した場合、条件に一致する単一オブジェクトへの操作だけが集計されます。`ListObjects`や`DeleteObjects`のように単一オブジェクトへ関連付けられないリクエストは、filter付きconfigurationには表示されません。バケット全体のリクエスト数を把握したい場合は、filterなしのconfigurationも作成してください。

## 方法1：AWS Management Console

Consoleから有効にする方法がもっとも直感的です。

1. Amazon S3 Consoleを開き、対象のgeneral purpose bucketを選択する。
2. **Metrics**タブを選択する。
3. **Bucket metrics**で**View additional charts**を選択する。
4. **Request metrics**を開き、**Create filter**を選択する。
5. `EntireBucket`などのFilter nameを入力する。
6. バケット全体を監視する場合はfilterを設定しない。一部のオブジェクトだけを監視する場合は、プレフィックス、オブジェクトタグ、またはS3 Access Pointを追加する。
![S3メトリクスフィルターを作成する](/assets/img/amazon_s3_create_filter.png)
7. 設定を保存する。

作成直後にグラフが表示されるわけではありません。AWSのドキュメントによると、CloudWatchが追跡を開始してからデータを確認できるまで、およそ15分かかります。また、その間にバケットへのリクエストがなければ、該当するメトリクスは生成されません。

## 方法2：AWS CLI

AWS CLIを使用すれば、ScriptやCI/CDへ設定操作を組み込めます。次のコマンドは、バケット全体のRequest Metricsを有効にします。

```bash
aws s3api put-bucket-metrics-configuration \
  --bucket example-bucket \
  --id EntireBucket \
  --metrics-configuration '{"Id":"EntireBucket"}'
```

`uploads/`プレフィックスだけを監視する場合は、`Filter`を追加します。

```bash
aws s3api put-bucket-metrics-configuration \
  --bucket example-bucket \
  --id Uploads \
  --metrics-configuration '{"Id":"Uploads","Filter":{"Prefix":"uploads/"}}'
```

実行後、現在のconfigurationを一覧表示できます。

```bash
aws s3api list-bucket-metrics-configurations \
  --bucket example-bucket
```

configurationを削除するには、次のコマンドを実行します。

```bash
aws s3api delete-bucket-metrics-configuration \
  --bucket example-bucket \
  --id Uploads
```

configurationの作成、更新、削除を行うIAMプリンシパルには`s3:PutMetricsConfiguration`が必要です。設定の取得と一覧表示には`s3:GetMetricsConfiguration`が必要です。

## 方法3：Terraform

すでにTerraformでバケットを管理している場合は、Request MetricsもTerraformで作成し、設定をバージョン管理できるようにします。

### バケット全体を監視する

```hcl
resource "aws_s3_bucket" "example" {
  bucket = "example-bucket"
}

resource "aws_s3_bucket_metric" "entire_bucket" {
  bucket = aws_s3_bucket.example.id
  name   = "EntireBucket"
}
```

`aws_s3_bucket_metric`の`name`がmetrics configuration IDとなり、CloudWatchでは`FilterId`として表示されます。

### プレフィックスとオブジェクトタグで絞り込む

```hcl
resource "aws_s3_bucket_metric" "production_uploads" {
  bucket = aws_s3_bucket.example.id
  name   = "ProductionUploads"

  filter {
    prefix = "uploads/"

    tags = {
      environment = "production"
    }
  }
}
```

リソースを作成する前に、予定されている変更を確認します。

```bash
terraform plan
terraform apply
```

バケットがすでに存在し、同じTerraform configurationでは管理されていない場合でも、`bucket`へバケット名を直接指定できます。メトリクスを有効にするためにバケットを作り直す必要はありません。

```hcl
resource "aws_s3_bucket_metric" "entire_bucket" {
  bucket = "existing-example-bucket"
  name   = "EntireBucket"
}
```

## 方法4：AWS CloudFormation

CloudFormationでは、`AWS::S3::Bucket`リソースの`MetricsConfigurations`に設定を記述します。

```yaml
Resources:
  ExampleBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: example-bucket
      MetricsConfigurations:
        - Id: EntireBucket
        - Id: Uploads
          Prefix: uploads/
```

オブジェクトタグのfilterを追加する場合は、`TagFilters`を使用します。

```yaml
MetricsConfigurations:
  - Id: ProductionUploads
    Prefix: uploads/
    TagFilters:
      - Key: environment
        Value: production
```

CloudFormationでmetrics configurationを更新すると、既存の設定は完全に置き換えられます。引き続き必要なconfigurationはすべてtemplateに残してください。記述されていない項目は削除されます。

## CloudWatchでメトリクスを確認する

Request Metricsのデータが生成され始めたら、次の手順で確認できます。

1. Amazon CloudWatch Consoleを開く。
2. **Metrics** → **All metrics**へ移動する。
3. **S3**を選択する。
4. **Request metrics**を選択するか、`BucketName`と`FilterId`で検索する。

CloudWatchは、バケットが存在するリージョンへ切り替えてください。メトリクスが表示されない場合は、次の項目を確認します。

1. metrics configurationが正常に作成されているか。
2. AWSアカウントとリージョンが正しいか。
3. 有効化後にバケットが実際にリクエストを受け取ったか。
4. プレフィックスまたはタグのfilterが対象オブジェクトと一致しているか。
5. およそ15分待ったか。

簡単にテストするには、テスト用オブジェクトへ何度か`PUT`と`GET`を実行し、`AllRequests`、`PutRequests`、`GetRequests`を確認します。Alarmでは、`5xxErrors`や`FirstByteLatency`を監視したり、Metric Mathで`4xxErrors / AllRequests`の割合を計算したりする方法がよく使われます。

## 料金と利用時のポイント

Request MetricsはCloudWatch metricsとして課金されます。configurationを追加するたびに一式のメトリクスが生成される可能性があるため、小さなプレフィックスごとにfilterを作成したり、費用を確認せず大量のバケットで一括有効化したりしないでください。

まずは重要なproduction bucketから始め、Alarmやトラブルシューティングが本当に必要なワークロードだけにconfigurationを作成することをおすすめします。

- バケット全体の状態を把握する：filterなしの`EntireBucket`を作成する。
- 複数のアプリケーションでバケットを共有する：プレフィックスまたはAccess Pointでグループ分けする。
- 特定のデータだけを監視する：プレフィックスとオブジェクトタグを組み合わせる。
- リクエスト単位の監査が必要：CloudTrail Data EventsまたはS3 Server Access Loggingを使用する。
- バケット、アカウント、組織を横断して長期分析する：S3 Storage Lensを検討する。

一つのバケットには最大1,000個のmetrics configurationsを作成できますが、上限まで作ることが適切とは限りません。configurationが増えるほど、Dashboard、Alarm、費用の管理も複雑になります。

## まとめ

S3でデフォルト有効のStorage Metricsは容量の監視には役立ちますが、アプリケーションのリクエスト数、エラー、レイテンシーをほぼリアルタイムで確認することはできません。Request Metricsを有効にすると、CloudWatchで`GET`、`PUT`、`4xx`、`5xx`、転送量、レイテンシーを1分単位で確認し、DashboardやAlarmを作成できます。

テストや一度だけの設定にはAWS Console、自動化にはAWS CLI、本番環境の設定をバージョン管理する場合はTerraformまたはCloudFormationを使用するとよいでしょう。最後に、Request Metricsは無料ではなく、データはベストエフォートで配信されます。これは運用監視のための機能であり、完全なアクセス監査ログではありません。

---

## 参考資料

- [Monitoring metrics with Amazon CloudWatch](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-dimensions.html)
- [CloudWatch metrics configurations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-configurations.html)
- [Creating a metrics configuration that filters by prefix, object tag, or access point](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-configurations-filter.html)
- [PutBucketMetricsConfiguration API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutBucketMetricsConfiguration.html)
- [AWS::S3::Bucket MetricsConfiguration](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-properties-s3-bucket-metricsconfiguration.html)
- [Terraform `aws_s3_bucket_metric`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_metric)
