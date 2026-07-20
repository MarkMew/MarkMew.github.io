---
layout: post
title: "AWS SQL Server 構築チュートリアル：作成から接続までの実践手順"
image: https://fastly.picsum.photos/id/210/1200/630.jpg?hmac=U8wtlsOPi38zUOhUIWdeBtlklDDrIKanqey3u6CXoco
description: "AWSでRDS for SQL Serverを作成する手順を、DBサブネットグループ、DBパラメータグループ、オプショングループ、ストレージ、接続、バックアップ、Terraformまで整理します。"
author: Mark_Mew
categories: [AWS, RDS]
tags: [Database, RDS, SQL Server]
keywords: [Database, AWS, RDS, SQL Server]
lang: ja
date: 2026-07-18
---

SQL Server は、エンタープライズシステムでよく使われるリレーショナルデータベースです。オンプレミス環境や VM で運用する場合、DBA やシステム管理者が SQL Server をインストールし、OS を調整し、バックアップを計画し、監視を設定してから、アプリケーションに利用させる流れが一般的です。

AWS 上では、これらの作業をすべて自分たちで抱える必要はありません。特別な OS 権限、RDS がサポートしていない SQL Server 機能、または独自のライセンス要件がなければ、Amazon RDS for SQL Server のほうが運用しやすい選択肢になることが多いです。RDS は基盤ホスト、ストレージ、バックアップ、メンテナンスウィンドウ、監視連携、高可用性機能を管理しやすくしてくれるため、チームはデータモデル、クエリ性能、アクセス制御、復元訓練により多くの時間を使えます。

この記事では、RDS for SQL Server DB インスタンスを作成する手順を、次の 2 つの方法で整理します。

- AWS マネジメントコンソールで作成する。
- Terraform で基本リソースを作成する。

例は開発環境またはテスト環境を想定しています。本番環境では、データ量、RPO、RTO、セキュリティ要件、可用性要件に応じて設計を調整してください。

> RDS for SQL Server でサポートされるバージョンは、AWS と Microsoft のサポートポリシーに応じて変わります。実装時は、対象リージョンの AWS マネジメントコンソール、または `aws rds describe-db-engine-versions` の結果を正としてください。
{: .prompt-info}

## 事前に確認すること

RDS を作成する前に、まず次の項目を確認しておくことをおすすめします。

| 項目 | 確認内容 |
| --- | --- |
| VPC とサブネット | DB をどの VPC に配置するか、プライベートサブネットのみに配置するか |
| セキュリティグループ | どの送信元から SQL Server の `1433` port に接続できるか |
| SQL Server バージョン | アプリケーションが対応している SQL Server major/minor version |
| エディション | Express、Web、Standard、Enterprise の機能とライセンス差異 |
| ストレージ容量 | 初期容量、最大容量、IOPS、Throughput、成長速度 |
| バックアップ | Automated Backup のバックアップ保持期間、PITR や AWS Backup が必要か |
| メンテナンスウィンドウ | メンテナンスやバージョン更新をいつ適用できるか |
| パラメータとオプション | カスタム DB パラメータグループやオプショングループが必要か |

これらは事前準備の細かい確認に見えますが、データベースで怖いのは、作成後にネットワーク配置が間違っている、バージョンが合わない、バックアップ戦略が要件を満たしていない、またはセキュリティグループを広く開けすぎていることに気づくケースです。

## 方法 1：AWS マネジメントコンソールで作成する

AWS マネジメントコンソールで RDS のページを開きます。

![Amazon and RDS dashboard page](/assets/img/rds/rds_home_page.png)

RDS の作成フロー自体は難しくありません。ただし、最初は次の「グループ」の違いが混ざりやすいです。

- DB サブネットグループ：RDS が利用できるサブネットを決める。
- DB パラメータグループ：データベースエンジンのパラメータを管理する。
- オプショングループ：SQL Server のネイティブバックアップおよび復元など、エンジン固有の追加機能を有効化する。
- セキュリティグループ：DB に接続できる送信元を制御する。

以下では、構築順にそれぞれ作成します。

### DB サブネットグループを作成する

RDS を初めて構築する場合は、通常 DB サブネットグループから設計します。

VPC 内に複数のサブネットがあっても、すべてのサブネットがデータベース配置に適しているわけではありません。一般的に、データベースをパブリックサブネットに直接配置したり、インターネットから直接到達できるようにしたりするべきではありません。よくある構成は、複数のアベイラビリティーゾーンにまたがるプライベートサブネットに RDS を配置し、アプリケーションのセキュリティグループまたは内部ネットワーク範囲からのみ接続を許可する方法です。

新しい環境では、DB サブネットグループの一覧が空の場合があります。そのまま作成ボタンを押して開始します。

![RDS Subnet Group list page](/assets/img/rds/rds_subnet_group_list_page.png)

作成ページでは、まず VPC を選択します。VPC を選択すると、その VPC 配下のアベイラビリティーゾーンとサブネットを選べるようになります。

![RDS Subnet Group create page](/assets/img/rds/rds_subnet_group_create_page.png)

少なくとも 2 つの異なるアベイラビリティーゾーンのプライベートサブネットを選ぶことをおすすめします。将来マルチ AZ を有効化する場合や、メンテナンスおよびフェイルオーバーの場面で、RDS の高可用性設計に合わせやすくなります。

![Subnet Group create sample](/assets/img/rds/rds_subnet_group_create_sample_page.png)

作成が完了すると、DB サブネットグループが一覧に表示されます。

![Subnet Group create result](/assets/img/rds/rds_subnet_group_create_result.png)

### DB パラメータグループを作成する

各データベースエンジンには調整可能なパラメータがあります。自前運用の SQL Server であれば、SQL Server Management Studio、T-SQL、またはホストレベルの設定で調整することがあります。しかし RDS では基盤 OS に直接ログインできず、完全な `sysadmin` 権限も得られません。そのため、RDS が許可しているパラメータは DB パラメータグループで管理します。

まだカスタム DB パラメータグループがない場合、一覧は空です。

![RDS Parameter Group list page](/assets/img/rds/rds_parameter_group_list_page.png)

作成を選択すると、DB パラメータグループの作成ページに進みます。

![RDS Parameter Group create page](/assets/img/rds/rds_parameter_group_create_page.png)

DB パラメータグループは、データベースエンジンと major version に紐づきます。つまり SQL Server 2019 と SQL Server 2022 では、それぞれ互換性のある parameter group family を使う必要があります。作成時は、これから作成する RDS のバージョンに合う family を選択してください。

![RDS Parameter Group create sample](/assets/img/rds/rds_parameter_group_create_sample_page.png)

作成後、DB パラメータグループの一覧に表示されます。

![RDS Parameter Group create result](/assets/img/rds/rds_parameter_group_create_result.png)

> 一部のパラメータ変更はすぐに適用できますが、DB の再起動が必要なものもあります。本番環境で変更する前に、非本番環境で検証し、メンテナンスウィンドウを確認してください。
{: .prompt-warning}

### データベースを作成する

DB サブネットグループと DB パラメータグループを用意したら、RDS DB インスタンスを作成できます。このデータベースでネイティブバックアップおよび復元も使う場合は、後述するオプショングループ、S3、IAM の設定を追加で準備します。

![RDS Database list page](/assets/img/rds/rds_database_list_page.png)

データベースの作成を選ぶと、コンソールには多くの設定項目が表示されます。データベースのネットワーク、セキュリティ、バックアップ、メンテナンスウィンドウは明示的に設定したほうがよいため、簡略化されたデフォルトフローではなく、完全な設定フローを使うことをおすすめします。

![RDS Database create page](/assets/img/rds/rds_database_create_page.png)

設定例は次のとおりです。

```plaintext
エンジンオプション
> SQL Server

テンプレート
> 開発/テスト

設定
> データベース管理タイプ
>> Amazon RDS

> エディション
>> SQL Server Express Edition

> エンジンバージョン
>> コンソールで現在サポートされているバージョンを選択。例：SQL Server 2022

> DB インスタンス識別子
>> sql-server-express-demo

認証情報の設定
> マスターユーザー名
>> admin

> 認証情報管理
>> セルフマネージド、または会社標準に応じて Secrets Manager

> マスターパスワード
>> 強力なパスワードを設定
```

ここではデモとテストのために Express Edition を使っています。本番環境では、機能要件、ライセンス、データベースサイズ、性能要件に応じて適切なエディションを選んでください。

DB インスタンスクラスについては、開発環境やテスト環境であれば小さめの t クラスから始められます。

```plaintext
DB インスタンスクラス
> バースト可能クラス
>> db.t3.small
```

ただし本番環境では CPU と Memory だけで判断しないでください。SQL Server の workload は、IOPS、Throughput、接続数、TempDB 使用量、クエリパターン、ロック動作の影響を受けやすいです。既存環境の監視データを使って、必要なスペックを見積もることをおすすめします。

#### ストレージを設定する

ストレージ設定は特に注意が必要です。初期容量だけでなく、ストレージの自動スケーリングを有効化するか、IOPS や Throughput を指定する必要があるかも考えます。

![RDS Database create page storage spec](/assets/img/rds/rds_database_create_page_storage_spec.png)

少なくとも次を確認してください。

- 初期容量が現在のデータ量と短期的な成長に足りているか。
- 最大ストレージ容量が予算とリスク管理に合っているか。
- gp3 で IOPS / Throughput を指定する必要があるか。
- `FreeStorageSpace` に対する CloudWatch Alarm を作成するか。

ストレージの自動スケーリングは、データベース容量不足のリスクを下げられます。ただし容量計画の代替ではありません。RDS ストレージは拡張後に直接縮小できないため、成長が制御できない場合は、最終的にコストとガバナンスの問題になります。

#### 接続とセキュリティグループを設定する

接続設定では、先ほど作成した `DB サブネットグループ` を選択します。

![RDS Database create page connection](/assets/img/rds/rds_database_create_page_connection.png)

セキュリティグループのルールを `0.0.0.0/0` に開かないでください。SQL Server のデフォルト接続 port は `1433` です。許可する送信元は、必要なものだけにします。

- アプリケーションサーバーのセキュリティグループ。
- Bastion Host または VPN のセキュリティグループ。
- 会社の内部ネットワーク範囲。ただし、より厳格なネットワーク制御と組み合わせること。

開発やテストであれば、一時的に VPC CIDR から `1433` への接続を許可する場合もあります。本番環境では、ネットワーク範囲全体を開けるより、セキュリティグループ参照を使ってアプリケーションリソースに追従するルールにするほうがよいです。

#### 監視、バックアップ、メンテナンスを設定する

監視は、まず CloudWatch のデフォルトメトリクスから始められます。より細かい OS レベルのメトリクスが必要な場合は Enhanced Monitoring を有効化します。DB load、待機イベント、SQL レベルのボトルネックを確認したい場合は、Performance Insights または CloudWatch Database Insights を有効化します。

![RDS Database create page addition config](/assets/img/rds/rds_database_create_page_addition_config.png)

その他の設定では、次も確認します。

- 先ほど作成した DB パラメータグループを選択しているか。
- ネイティブバックアップおよび復元を使う場合、対応するオプショングループを選択しているか。
- バックアップ保持期間が要件を満たしているか。
- バックアップウィンドウがピーク時間を避けているか。
- メンテナンスウィンドウが運用時間帯に合っているか。
- 削除保護を有効化する必要があるか。
- タイムゾーンと照合順序がアプリケーション要件に合っているか。

> タイムゾーンと照合順序は、作成後に簡単に変更できるとは限りません。特に照合順序は、並べ替え、比較、大文字小文字の扱いに影響します。本番環境では、アプリケーション、レポート、既存データベースの設定と先に合わせてください。
{: .prompt-warning}

設定を確認したら作成し、RDS のステータスが Available になるまで待ちます。作成時間は DB インスタンスクラス、ストレージ設定、その時点のサービス状況によって変わります。テスト環境では、数分から十数分程度かかることがよくあります。

作成後、エンドポイントを取得し、SQL Server Management Studio、Azure Data Studio、DBeaver、またはアプリケーションから接続をテストします。Automated Backup を有効化している場合、RDS は設定に従って自動バックアップを処理するため、最初のバックアップを手動で実行する必要はありません。

接続情報はおおよそ次の形です。

```plaintext
Server / Host: <rds-endpoint>
Port: 1433
User: admin
Password: 作成時に設定したパスワード
Database: 必要に応じて指定、またはまず既定のデータベースに接続
```

接続できない場合は、まず次を確認します。

1. RDS が Available になっているか。
2. Client が許可されたネットワーク位置にあるか。
3. セキュリティグループの inbound が送信元から `1433` への接続を許可しているか。
4. Route table、NACL、VPN、Bastion が正しいか。
5. SQL Server のユーザー名とパスワードが正しいか。
6. DNS が RDS エンドポイントを解決できるか。

### バックアップと復元を設定する（Optional）

この RDS for SQL Server DB インスタンスでネイティブバックアップおよび復元を使う場合、つまり SQL Server の `.bak` ファイルを S3 に置いて RDS に復元したり、RDS から `.bak` を S3 にバックアップしたりする場合は、S3、IAM ロール、オプショングループを追加で設定する必要があります。

この機能では、次の 3 つのコンポーネントを接続します。

| コンポーネント | 用途 |
| --- | --- |
| S3 バケット | SQL Server の `.bak` バックアップファイルを保存する |
| IAM ロールとポリシー | RDS が指定した S3 バケットを読み書きできるようにする |
| オプショングループ | `SQLSERVER_BACKUP_RESTORE` を追加し、IAM role ARN を指定する |

設定順序は次のようになります。

1. SQL Server バックアップファイル専用の S3 バケットを作成する。
2. IAM ロールを作成し、信頼関係で `rds.amazonaws.com` がロールを引き受けられるようにする。
3. IAM ロールに S3 アクセス権限ポリシーをアタッチする。
4. SQL Server のオプショングループに `SQLSERVER_BACKUP_RESTORE` を追加する。
5. オプション設定 `IAM_ROLE_ARN` に IAM role ARN を指定する。
6. RDS DB インスタンスを作成または変更し、このオプショングループを SQL Server に適用する。

S3 バケットは RDS DB インスタンスと同じリージョンに置くことをおすすめします。RDS for SQL Server のネイティブバックアップおよび復元では、別リージョンの S3 バケットへのバックアップまたは別リージョンの S3 バケットからの復元はサポートされていません。バックアップファイルが別リージョンにある場合は、S3 Replication などで RDS と同じリージョンへ先にコピーします。

> `SQLSERVER_BACKUP_RESTORE` と `S3_INTEGRATION` は混同しやすいです。前者は `.bak` のネイティブバックアップおよび復元で使うオプショングループの option です。後者は RDS host の `D:\S3\` と S3 の間でファイルを転送する機能です。この記事では主にネイティブバックアップおよび復元を扱うため、中心になる設定はオプショングループの `SQLSERVER_BACKUP_RESTORE` です。
{: .prompt-info}

#### オプショングループを作成する

オプショングループは、RDS の設定の中でも見落とされやすいものです。一般的なデータベースパラメータではなく、特定のデータベースエンジン向けの追加機能を有効化するために使います。

SQL Server の場合、ネイティブバックアップおよび復元を使って `.bak` ファイルを S3 にバックアップしたり、S3 から復元したりするには、オプショングループに `SQLSERVER_BACKUP_RESTORE` オプションを追加し、S3 権限を持つ IAM ロールを RDS に使わせる必要があります。

![RDS Option Group list page](/assets/img/rds/rds_option_group_list_page.png)

オプショングループを作成するときも、SQL Server エンジンと対応するバージョンを選択します。

![RDS Option Group create page](/assets/img/rds/rds_option_group_create_page.png)

まだ IAM ロールがない場合は、まず空のオプショングループを作成しても構いません。S3 バケット、IAM policy、IAM ロールの準備ができたら、戻って `SQLSERVER_BACKUP_RESTORE` を追加し、option setting に `IAM_ROLE_ARN` を設定します。

![RDS Option Group create sample](/assets/img/rds/rds_option_group_create_sample_page.png)

作成が完了すると、オプショングループが一覧に表示されます。

![RDS Option Group create result](/assets/img/rds/rds_option_group_create_result.png)

> RDS の Automated Backup と PITR だけを使う場合、SQL Server のネイティブバックアップおよび復元は必須ではありません。`.bak` ファイルのインポート/エクスポートや、既存の SQL Server バックアップ運用と接続したい場合に、このオプションを検討します。
{: .prompt-info}

#### S3 バケットを作成する

SQL Server の `.bak` ファイル専用の S3 バケットを作成します。この bucket は RDS DB インスタンスと同じリージョンに置くことをおすすめします。RDS for SQL Server のネイティブバックアップおよび復元では、別リージョンの S3 バケットはサポートされていません。

バックアップファイルがすでに別リージョンにある場合は、S3 Replication などで RDS と同じリージョンへ先にコピーしてから、RDS にインポートまたは復元させます。

![S3 バックアップ復元 Bucket を作成](/assets/img/rds/rds_s3_backup_restore_bucket.png)

#### S3 バケットへアクセスする IAM Policy を作成する

IAM ロールを作成する前に、IAM policy を先に作成しておくことをおすすめします。そうすると、ロール作成時にその policy を検索してそのままアタッチでき、あとから権限を戻って追加する必要がありません。

![IAM Policy](/assets/img/rds/rds_iam_policy.png)

S3 アクセス権限ポリシーでは、少なくとも RDS がバケットを一覧表示し、バケットの場所を取得し、バックアップオブジェクトを読み書きできる必要があります。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-backup-restore"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectAttributes",
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-backup-restore/*"
    }
  ]
}
```

![IAM Policy review and create](/assets/img/rds/rds_iam_policy_review_and_create.png)

> 専用 bucket、または少なくとも `sqlserver-native-backup/` のような専用 prefix を使うことをおすすめします。prefix を空にすると、複数ファイル復元時に RDS が bucket 内の無関係なファイルまで対象にする可能性があり、トラブルシューティングが面倒になります。
{: .prompt-info}

バックアップファイルを KMS で暗号化する場合は、IAM ロールに対象 KMS key への `kms:DescribeKey`、`kms:GenerateDataKey`、`kms:Encrypt`、`kms:Decrypt` を追加し、KMS key policy でもこの IAM ロールの利用を許可する必要があります。

#### IAM Role を作成する

次に、RDS が assume できる IAM ロールを作成します。この role はネイティブバックアップおよび復元で S3 にアクセスするための権限を提供するため、信頼関係では少なくとも `rds.amazonaws.com` が利用できるようにします。

![IAM Role](/assets/img/rds/rds_iam_role.png)

先ほど policy を作成している場合は、ここで検索してアタッチできます。

![IAM Role attached policy](/assets/img/rds/rds_iam_role_attached_policy.png)

信頼関係では、まず `rds.amazonaws.com` を trusted entity として設定できます。

![IAM Role review and create](/assets/img/rds/rds_iam_role_review_and_create.png)

本番環境でより厳格にする場合は、`aws:SourceAccount` と `aws:SourceArn` を追加し、指定したアカウント、DB instance、オプショングループだけがこの role を使えるように制限できます。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "<account-id>"
        },
        "ArnLike": {
          "aws:SourceArn": [
            "arn:aws:rds:<region>:<account-id>:db:<db-instance-id>",
            "arn:aws:rds:<region>:<account-id>:og:<option-group-name>"
          ]
        }
      }
    }
  ]
}
```

#### IAM Role をオプショングループへ接続する

S3 バケット、IAM policy、IAM ロールの準備ができたら、SQL Server のオプショングループに戻り、`SQLSERVER_BACKUP_RESTORE` option を追加して、`IAM_ROLE_ARN` に先ほど作成した IAM role ARN を設定します。

DB instance がすでに存在する場合は、オプショングループ変更後に、その DB instance がこのオプショングループを使用していることを確認してください。一部のオプショングループ変更では DB instance の再起動が必要になるため、本番環境ではメンテナンスウィンドウ内で操作してください。

#### 補足：S3 Integration を有効化する

ネイティブバックアップおよび復元とは別に、RDS for SQL Server の S3 integration も使いたい場合があります。たとえば S3 のファイルを DB instance host の `D:\S3\` へダウンロードし、その後 SQL Server の機能で処理する場合です。この場合は、DB instance の `Connectivity & security` タブで IAM role を設定します。

下にスクロールすると、`Manage IAM roles` の設定が表示されます。

![RDS IAM ロール管理](/assets/img/rds/rds_manage_iam_role.png)

IAM role の信頼関係が正しければ、ドロップダウンリストに表示されます。Feature には `S3_INTEGRATION` を選択します。

![RDS IAM ロール設定](/assets/img/rds/rds_manage_iam_role_settings.png)

数分待つと、ステータスが active になります。これで S3 integration が有効化されます。

> `rds_backup_database` または `rds_restore_database` だけを実行したい場合、重要なのはオプショングループの `SQLSERVER_BACKUP_RESTORE` です。`S3_INTEGRATION` は別のファイル転送機能なので、同じ設定として扱わないでください。
{: .prompt-warning}

#### `.bak` バックアップファイルを作成して S3 へ出力する

SQL Server に接続できるマシンから、SQL Server Management Studio、Azure Data Studio、または他の SQL client を使って RDS に接続します。

次の例では、`my_app` データベースを完全バックアップとして `.bak` ファイルにし、S3 へ出力します。

```sql
exec msdb.dbo.rds_backup_database
  @source_db_name='my_app',
  @s3_arn_to_backup_to='arn:aws:s3:::markmew-rds-sql-server-backup-restore/my_app_full.bak',
  @overwrite_s3_backup_file=1,
  @type='FULL';
```

バックアップ状態は `rds_task_status` で確認できます。

```sql
exec msdb.dbo.rds_task_status @db_name='my_app';
```

現在の DB instance 上にあるすべてのネイティブバックアップおよび復元 task を確認したい場合は、引数なしで実行できます。

```sql
exec msdb.dbo.rds_task_status;
```

オンプレミスのようにバックアップファイルを直接操作するのとは違い、RDS for SQL Server のネイティブバックアップおよび復元では task が作成されます。task は `CREATED` から `IN_PROGRESS` に進み、完了すると `SUCCESS` になります。失敗した場合は `ERROR` になり、`task_info` にエラー内容が表示されます。

S3 から `.bak` ファイルを復元する場合は、`rds_restore_database` を使います。復元では既存の同名データベースを上書きできないため、通常は新しいデータベース名へ復元します。

```sql
exec msdb.dbo.rds_restore_database
  @restore_db_name='my_app_restore',
  @s3_arn_to_restore_from='arn:aws:s3:::markmew-rds-sql-server-backup-restore/my_app_full.bak';
```

##### RDS for SQL Server の `rds_*` ストアドプロシージャと Task

RDS for SQL Server を使っていると、自前運用 SQL Server では GUI、OS 権限、`sysadmin` 権限、またはファイルシステムアクセスで処理していた作業の多くが、Amazon RDS が提供する `msdb.dbo.rds_*` stored procedures / functions 経由で実行されることに気づきます。

これは SQL Server のネイティブ構文が置き換えられているという意味ではありません。RDS がマネージドサービスだからです。AWS は DB instance への shell access を提供せず、高権限を必要とする一部のシステムプロシージャやシステムテーブルへのアクセスも制限します。その代わり、よくある DBA 作業を RDS-specific procedures / functions として提供し、基盤ホストに触れずに管理操作を実行できるようにしています。

AWS 公式ドキュメントには、これらの関数とストアドプロシージャをまとめたページがあります。代表的な分類は次のとおりです。

| 分類 | 主な procedures / functions | 用途 |
| --- | --- | --- |
| 管理タスク | `rds_drop_database`、`rds_modify_db_name`、`rds_read_error_log`、`rds_set_configuration` | データベースの削除や名前変更、エラーログの読み取り、RDS-specific 設定の調整 |
| CDC | `rds_cdc_enable_db`、`rds_cdc_disable_db` | RDS for SQL Server で change data capture を有効化または無効化 |
| ネイティブバックアップおよび復元 | `rds_backup_database`、`rds_restore_database`、`rds_restore_log`、`rds_finish_restore`、`rds_cancel_task` | `.bak` バックアップ、復元、キャンセルを task として処理 |
| Task 状態 | `rds_task_status` | ネイティブバックアップおよび復元 task の状態確認 |
| S3 ファイル転送 | `rds_download_from_s3`、`rds_upload_to_s3`、`rds_gather_file_details`、`rds_delete_from_filesystem` | S3 integration と組み合わせて、S3 と DB instance host の `D:\S3\` 間でファイルを転送または管理 |
| TDE | `rds_backup_tde_certificate`、`rds_restore_tde_certificate`、`rds_drop_tde_certificate`、`rds_fn_list_user_tde_certificates` | Transparent Data Encryption 証明書の管理 |
| SQL Server Agent / system database sync | `rds_set_system_database_sync_objects`、`rds_fn_get_system_database_sync_objects`、`rds_fn_server_object_last_sync_time` | 特定のシナリオで SQL Server Agent job などのシステムデータベースオブジェクトを同期 |
| MSBI | `rds_msbi_task`、`rds_fn_task_status` | SSAS、SSIS、SSRS 関連 task の管理または確認 |
| Resource Governor | `rds_create_resource_pool`、`rds_alter_resource_pool`、`rds_drop_resource_pool`、`rds_create_workload_group` | Resource Governor 関連オブジェクトの管理 |

特に次の 2 つの状態確認は混同しやすいです。

- `rds_task_status`：`rds_backup_database` や `rds_restore_database` など、ネイティブバックアップおよび復元 task を確認する。
- `rds_fn_task_status`：SSAS、SSIS、SSRS のデプロイや管理など、MSBI 関連 task を確認する。

そのため、RDS for SQL Server で慣れたホストレベル操作が見つからない場合でも、すぐに「RDS ではサポートされていない」と判断しないほうがよいです。まず公式の関数とストアドプロシージャ一覧を確認し、AWS が対応する `rds_*` procedure または function を提供していないかを確認します。

## 方法 2：Terraform で作成する

本番環境のインフラを Terraform で管理している場合は、RDS も Terraform に含めることをおすすめします。AWS マネジメントコンソールでの変更による設定ドリフトを避けやすくなります。

以下は、DB サブネットグループ、DB パラメータグループ、セキュリティグループ、S3 バケット、IAM ロール、オプショングループ、RDS DB インスタンスの関係を示す簡略化した例です。実環境では、VPC、Subnet、KMS、パスワード、Tag、命名規則を既存モジュールに接続してください。

```terraform
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "backup_bucket_name" {
  type = string
}

variable "backup_prefix" {
  type    = string
  default = "sqlserver-native-backup"
}

resource "aws_db_subnet_group" "database" {
  name       = "rds-database-subenet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "rds-database-subenet-group"
  }
}

resource "aws_security_group" "sqlserver" {
  name        = "sqlserver"
  description = "Allow application access to RDS SQL Server"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SQL Server from application"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "sqlserver_backup" {
  bucket = var.backup_bucket_name

  tags = {
    Name = var.backup_bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "sqlserver_backup" {
  bucket = aws_s3_bucket.sqlserver_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "sqlserver_backup_restore" {
  name = "rds-sqlserver-backup-restore"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = [
              "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:*",
              "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:og:*"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "sqlserver_backup_restore" {
  name = "rds-sqlserver-backup-restore-s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.sqlserver_backup.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectAttributes",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.sqlserver_backup.arn}/${var.backup_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqlserver_backup_restore" {
  role       = aws_iam_role.sqlserver_backup_restore.name
  policy_arn = aws_iam_policy.sqlserver_backup_restore.arn
}

resource "aws_db_parameter_group" "mssql_ex_17_parameter_group" {
  name        = "sqlserver-ex-17-parameter-group"
  family      = "sqlserver-ex-17.0"
  description = "sqlserver express 2025 parametergroup"
}

resource "aws_db_option_group" "mssql_ex_17" {
  name                     = "sqlserver-demo-option-group"
  option_group_description = "Option group for SQL Server demo"
  engine_name              = "sqlserver-ex"
  major_engine_version     = "17.00"

  option {
    option_name = "SQLSERVER_BACKUP_RESTORE"

    option_settings {
      name  = "IAM_ROLE_ARN"
      value = aws_iam_role.sqlserver_backup_restore.arn
    }
  }

  tags = {
    Name = "sqlserver-demo-option-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.sqlserver_backup_restore
  ]
}

resource "aws_db_instance" "sqlserver" {
  identifier = "sqlserver-express-demo"

  engine         = "sqlserver-ex"
  engine_version = "17.00.4045.5.v1"
  license_model  = "license-included"

  instance_class        = "db.t3.small"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  username = "admin"
  password = var.db_password
  port     = 1433

  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.sqlserver.id]
  parameter_group_name   = aws_db_parameter_group.mssql_ex_17_parameter_group.name
  option_group_name      = aws_db_option_group.mssql_ex_17.name

  timezone                = "Taipei Standard Time"
  backup_retention_period = 7
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:00-sun:20:00"

  multi_az            = false
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "sqlserver-express-demo"
  }
}
```

この Terraform はデモ用です。本番環境では、少なくとも次を調整してください。

- `.tf` ファイルにパスワードを直接書かない。Secrets Manager、SSM Parameter Store、または CI/CD secret を使う。
- 本番環境では `deletion_protection` を有効化する。
- 本番環境では通常 `skip_final_snapshot = true` を使わない。
- データベースが重要なサービスであれば、`multi_az` を評価する。
- `family`、`engine_version`、`major_engine_version` は実際にサポートされるバージョンに合わせる。
- CloudWatch log exports の対応項目はエンジンとバージョンにより異なるため、対象バージョンで確認する。
- S3 バケットは RDS DB インスタンスと同じリージョンに置く。
- S3 バケット名はグローバルで一意なので、例の `backup_bucket_name` は自分の名前に置き換える。
- KMS で `.bak` ファイルを暗号化する場合、IAM policy と KMS key policy の両方で、この role が key を使用できるようにする。
- Trust policy の例では、同一アカウント・同一リージョンの RDS DB とオプショングループ ARN pattern に権限を絞っている。本番環境では、明示的な DB インスタンス ARN とオプショングループ ARN にさらに絞ることもできる。
- `backup_prefix` は、実際のバックアップおよび復元で使う S3 object path と合わせる。

## バックアップと復元戦略

RDS for SQL Server では、主に次の 3 つのバックアップ方式を使います。

| 方式 | 用途 |
| --- | --- |
| Automated Backup | RDS の自動バックアップ。バックアップ保持期間内の PITR をサポート |
| Manual Snapshot | 特定時点の DB snapshot を手動作成 |
| ネイティブバックアップおよび復元 | `.bak` ファイルと S3 を使って SQL Server データベースをインポート/エクスポート |

Automated Backup は最も基本的で、通常は有効化すべきバックアップ機能です。設定したバックアップ保持期間内で Point-in-Time Recovery を利用できます。誤削除、誤ったデプロイ、バッチ処理によるデータ破損が起きた場合、指定した時点へ復元できます。

RDS の PITR は元の DB を直接上書きするものではなく、新しい DB インスタンスを作成します。これは通常、より安全です。先にデータを検証し、その後でアプリケーション接続を切り替えるか、必要なデータを元のデータベースへ戻すか、事故分析用として保持するかを選べます。

Manual Snapshot は、アップグレード、パラメータ調整、大規模なバッチ更新など、重要な変更前に役立ちます。Automated Backup の代替ではありませんが、変更前の明確な復旧ポイントになります。

ネイティブバックアップおよび復元は、既存の SQL Server 運用と接続したい場合に向いています。たとえば、オンプレミス SQL Server を `.bak` ファイルとして S3 にバックアップし、それを RDS に復元できます。または RDS のデータベースを S3 にバックアップし、別環境で使うこともできます。この場合、オプショングループに `SQLSERVER_BACKUP_RESTORE` を追加し、S3 権限を持つ IAM ロールを用意します。

本番環境のバックアップ戦略では、少なくとも次の 3 つに答えられる必要があります。

| 質問 | 意味 |
| --- | --- |
| RPO はどれくらいか | 許容できる最大データ損失 |
| RTO はどれくらいか | サービス復旧までに許容できる最大時間 |
| 復元訓練をどれくらいの頻度で行うか | バックアップのステータスが成功しているだけでなく、本当に使えることを確認する |

バックアップがあることと、復元できることは別です。非本番環境で定期的に復元訓練を行い、復元時間、切り替え手順、権限差異、DB パラメータグループ、オプショングループ、セキュリティグループ、アプリケーション接続設定を記録することをおすすめします。

## RDS for SQL Server を使う利点

### 監視を導入しやすい

EC2 やオンプレミスで SQL Server を自前運用する場合、通常は Agent を導入し、log を収集し、監視基盤と連携して、ようやくデータベースを観測できる状態になります。

RDS では、CPU、接続数、ストレージ、IOPS、Latency など、多くの CloudWatch メトリクスがデフォルトで提供されます。より詳細が必要な場合は、Enhanced Monitoring、Performance Insights、CloudWatch Database Insights を有効化できます。

少なくとも、次の基本アラームを設定することをおすすめします。

| メトリクス | 観察目的 |
| --- | --- |
| `CPUUtilization` | 通常の基準値を長時間上回っていないか |
| `FreeableMemory` | メモリ不足が起きていないか |
| `FreeStorageSpace` | ストレージが不足しそうか |
| `DatabaseConnections` | 接続数が異常に増えていないか |
| `ReadLatency` / `WriteLatency` | ストレージ遅延が悪化していないか |
| `ReadIOPS` / `WriteIOPS` | I/O がボトルネックに近づいていないか |

### ストレージ拡張が比較的シンプル

オンプレミスや EC2 の自前運用データベースでは、ディスク容量不足に遭遇することがあります。特にアプリケーションやバッチ処理が大量の log、一時データ、履歴データを誤ってデータベースに書き込むと、容量が急に埋まることがあります。

RDS では、ストレージの自動スケーリングを使って、空き容量がしきい値に近づいたときにストレージを自動的に増やせます。容量計画とコスト管理は引き続き必要ですが、深夜に手動でディスク、ファイルシステム、mount point を拡張する負担は下げられます。

### バックアップとメンテナンスを管理しやすい

RDS は Automated Backup、Manual Snapshot、PITR、メンテナンスウィンドウを提供します。これらの機能は、DBA やエンジニアがデータベースを完全に気にしなくてよいという意味ではありません。多くの低レイヤー運用を、設定可能で追跡可能、かつ訓練可能なプロセスに変えるものです。

組織ですでに AWS Backup を使っている場合は、RDS を集中管理されたバックアップ計画に含め、保持期間、クロスアカウントまたはクロスリージョンコピー、監査要件を管理できます。

### 高可用性を標準化しやすい

本番環境でデータベースが重要なコンポーネントであれば、マルチ AZ を評価すべきです。RDS マルチ AZ は、複数のアベイラビリティーゾーンにまたがって可用性と耐久性を高め、一部のメンテナンスや障害シナリオで影響を下げます。

マルチ AZ は読み取り負荷分散のための機能ではありません。読み取りトラフィックを分散したい場合は、リードレプリカまたはアプリケーションレベルの読み書きルーティングを別途検討します。

> 高可用性では、SQL Server のエディションと engine version の両方を確認してください。
> RDS for SQL Server のマルチ AZ は主に Standard / Enterprise をサポートします。SQL Server 2022 Web Edition では、ブロックレベルレプリケーションに 16.00.4215.2 以降が必要です。Express Edition はマルチ AZ をサポートしていません。
{: .prompt-info}

## RDS for SQL Server の制限

### 完全な `sa` 権限や OS 権限はない

RDS for SQL Server で作成時に指定する master user は、自前運用 SQL Server でよく使う `sa` と同じではありません。また、完全な `sysadmin` 権限も持ちません。これは AWS が利用を許可している範囲で最も強い権限を持つユーザーです。

つまり、OS アクセス、インスタンスレベルのアクセス、または `sysadmin` 権限が必要な操作は実行できない場合があります。導入前に、既存システム、運用スクリプト、バックアップ運用、DBA の操作習慣がこれらの権限に依存していないか確認してください。

### 一部の SQL Server 機能はサポートされない

RDS for SQL Server はマネージドサービスであるため、自前運用 SQL Server のすべての機能を公開することはできません。よくある制限には、サーバーレベルのトリガーを使えないこと、一部の OS アクセスが必要な機能を使えないこと、基盤ファイルシステムを任意に変更できないことなどがあります。

既存システムが SQL Server Agent Job、Linked Server、CLR、SSIS、SSRS、特殊なバックアップフロー、その他の高度な機能に強く依存している場合は、導入前に各要件を RDS のサポート状況と照合してください。

### バージョン、エディション、リソースクラスが機能に影響する

SQL Server の機能は、エディション、バージョン、RDS のサポート範囲に影響されます。Express Edition はデモや小規模テストに適していますが、本番環境では容量、リソース、機能の制限を受けやすいです。Web、Standard、Enterprise Edition も、コストと利用可能な機能が異なります。

テスト環境で動いたからといって、その設定をそのまま本番環境へ持ち込まないでください。本番環境では、先に次を確認します。

- データベースサイズがエディションの制限を超えないか。
- アプリケーションが必要とする機能がサポートされているか。
- RDS インスタンスクラスが対象エンジンとエディションをサポートしているか。
- ライセンスコストが予算に合っているか。

## 作成後のチェックリスト

RDS を作成した後、接続テストが 1 回成功しただけで終わらせないでください。少なくとも次を確認します。

- RDS がパブリックアクセス可能ではなく、正しいプライベートサブネットに配置されている。
- セキュリティグループが必要な送信元から `1433` への接続だけを許可している。
- アプリケーションまたは管理ツールから正常に接続できる。
- Automated Backup が有効で、バックアップ保持期間が要件を満たしている。
- メンテナンスウィンドウとバックアップウィンドウがピーク時間を避けている。
- DB パラメータグループとオプショングループが正しいバージョンを使っている。
- CloudWatch Alarm が設定されている。少なくともストレージ容量と接続数は含める。
- Enhanced Monitoring または Performance Insights を有効化する必要があるか確認している。
- 削除保護が環境要件に合っている。
- 復元テストを実施し、バックアップが単なるチェック項目ではないことを確認している。

## まとめ

RDS for SQL Server を作成することは、EC2 上のデータベースをマネージドサービスに置き換えるだけではありません。重要なのは、データベース運用をネットワーク、セキュリティ、バージョン、パラメータ、ストレージ、バックアップ、監視、メンテナンス、復元といった管理可能な領域に分けることです。

開発やテストであれば、小さな SQL Server Express の RDS はすぐに作成できます。しかし本番環境では、作成できたかどうかだけでなく、長期的に運用、監視、バックアップ、復元できるかを確認する必要があります。

RDS はすべてのデータベース責任を消すものではありません。それでも、多くの低レイヤーなプラットフォーム作業を減らしてくれます。データベースプラットフォーム運用が会社の差別化ポイントでないなら、その作業をマネージドサービスに任せるほうが、自分たちで基盤を作って運用し続けるより現実的です。

## 参考資料

- [Amazon RDS for Microsoft SQL Server](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/CHAP_SQLServer.html)
- [Amazon RDS での Microsoft SQL Server バージョン](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.VersionSupport.html)
- [Amazon RDS for Microsoft SQL Server のバージョンポリシー](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.VersionPolicy.html)
- [SQL Server のネイティブバックアップおよび復元のサポート](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.BackupRestore.html)
- [ネイティブバックアップおよび復元のセットアップ](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.Native.Enabling.html)
- [ネイティブバックアップと復元を使用した SQL Server データベースのインポートとエクスポート](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.html)
- [ネイティブバックアップおよび復元の使用](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.Native.Using.html)
- [ネイティブバックアップおよび復元のトラブルシューティング](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.Native.Troubleshooting.html)
- [Amazon RDS for SQL Server DB インスタンスと Amazon S3 の統合](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/User.SQLServer.Options.S3-integration.html)
- [RDS for SQL Server と S3 の統合を有効化する](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.S3-integration.enabling.html)
- [Amazon RDS for Microsoft SQL Server の関数とストアドプロシージャ](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.StoredProcedures.html)
- [Amazon RDS for Microsoft SQL Server の一般的な DBA タスク](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.CommonDBATasks.html)
- [サポートされない機能およびサポートが限定的な機能](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.FeatureNonSupport.html)
- [Terraform Registry: aws_db_option_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_option_group)
