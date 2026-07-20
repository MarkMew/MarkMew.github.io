---
layout: post
title: "AWS SQL Server 構築チュートリアル応用：監査設定とパスワードローテーション"
image: https://fastly.picsum.photos/id/844/1200/630.jpg?hmac=xWnHR7ImvXCXUaOdMpl3LvSW6QGm3mx6DlbjtClUiIo
description: "RDS for SQL Server の基本構築に加えて、SQL Server Audit、S3 への監査ログ保存、IAM ロールの権限設計、AWS Secrets Manager によるマスターユーザーパスワード管理とローテーションを整理します。"
author: Mark_Mew
categories: [AWS, RDS]
tags: [Database, RDS, SQL Server]
keywords: [Database, AWS, RDS, SQL Server, SQL Server Audit, Secrets Manager, Password Rotation]
lang: ja
date: 2026-07-20
---

前回の記事 [AWS SQL Server 構築チュートリアル：作成から接続までの実践手順](/posts/how-to-set-up-rds-sql-server/) では、RDS for SQL Server の基本構築を一通り整理しました。DB サブネットグループ、DB パラメータグループ、オプショングループ、S3、IAM、バックアップと復元、接続テストまでを扱いました。

ただし、データベースを本番環境に近い位置へ持っていくなら、「接続できる、バックアップできる、監視できる」だけでは通常まだ足りません。

本番環境では、さらに次の 2 つが重要になります。

- 誰が、いつ、どのようなデータベース操作を行ったのかを、追跡可能な監査レコードとして残せるか。
- データベースパスワードが手動保存、手動更新のままなのか、それとも管理可能なローテーションプロセスに入っているか。

この記事では、前回の RDS for SQL Server 構成を前提に、よく使う応用設定として SQL Server Audit とマスターユーザーパスワードのローテーションを追加します。

## 監査設定

RDS for SQL Server は SQL Server Audit と連携し、監査ファイルを指定した S3 バケットへ出力できます。概念としては、次の 2 つのレイヤーに分かれます。

| レイヤー | 設定すること |
| --- | --- |
| AWS RDS レイヤー | オプショングループに `SQLSERVER_AUDIT` を追加し、IAM ロール、S3 バケット、圧縮、保持時間を設定する |
| SQL Server レイヤー | SQL Server 内でサーバー監査、サーバー監査仕様、またはデータベース監査仕様を作成する |

つまり、オプショングループは RDS for SQL Server が監査ファイルを S3 に渡せるようにするための設定です。実際にどのイベントを監査するかは、SQL Server 側で監査仕様を作成して決めます。

### S3 バケットを作成する

前回作成した S3 バケット `markmew-rds-sql-server-backup-restore` は、バックアップと復元で使う `.bak` ファイルを保存するためのものです。技術的には同じバケットを使うこともできますが、本番環境ではバックアップファイルと監査レコードを分けることをおすすめします。

理由は単純です。バックアップと監査では、ライフサイクル、権限境界、保持期間、参照する人が異なることが多いからです。バックアップファイルは DBA や復元フローで使われます。一方、監査レコードはセキュリティ、監査、コンプライアンスの証跡に近いため、より厳格な読み取り権限と保持ポリシーが必要です。

![Create S3 audit bucket](/assets/img/rds/rds_s3_audit_bucket.png)

ここでは別のバケットを使います。

```plaintext
markmew-rds-sql-server-audit
```

同じバケット内に複数の RDS 監査データを保存する場合でも、少なくともプレフィックスで分けることをおすすめします。

```plaintext
sqlserver-audit/
```

### IAM ポリシーを作成する

IAM ロールを作成する前に、先に IAM ポリシーを作成します。こうしておくと、ロール作成時に直接検索してアタッチでき、後から権限を追加しに戻る必要がありません。

![IAM Policy](/assets/img/rds/rds_iam_policy2.png)

SQL Server Audit の S3 権限では、少なくとも RDS がバケットを確認し、バケット情報を取得し、指定した場所へ監査ファイルを書き込める必要があります。次はデモ用のポリシーです。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketACL",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-audit"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-audit/*"
    }
  ]
}
```

![IAM Policy review and create](/assets/img/rds/rds_iam_policy_review_and_create2.png)

> 本番環境でプレフィックスが決まっている場合は、オブジェクト権限をそのプレフィックスに絞ることをおすすめします。たとえば `arn:aws:s3:::markmew-rds-sql-server-audit/sqlserver-audit/*` のようにします。監査ログでは、通常 RDS がバケット全体へ書き込める必要はありません。
{: .prompt-info}

### IAM ロールを作成する

次に、RDS が引き受けられる IAM ロールを作成します。このロールは SQL Server Audit が S3 へ書き込むための権限を提供するため、信頼関係では少なくとも `rds.amazonaws.com` の利用を許可します。

![IAM Role](/assets/img/rds/rds_iam_role.png)

先ほど IAM ポリシーを作成していれば、ここで検索してアタッチできます。

![IAM Role attached policy](/assets/img/rds/rds_iam_role_attached_policy2.png)

信頼関係では、まず `rds.amazonaws.com` を信頼されたエンティティとして指定できます。

![IAM Role review and create](/assets/img/rds/rds_iam_role_review_and_create2.png)

デモ環境では、次のようなシンプルな信頼ポリシーから始められます。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

本番環境でより厳密にする場合は、`aws:SourceAccount` と `aws:SourceArn` を追加し、指定したアカウント、DB インスタンス、オプショングループだけがこのロールを使用できるようにします。前回の記事では、ネイティブバックアップおよび復元用 IAM ロールでこの書き方を示しました。監査用途でも同じ考え方を使えます。

### オプショングループに SQLSERVER_AUDIT を追加する

次に、SQL Server が使っているオプショングループへ戻ります。この手順は前回 `SQLSERVER_BACKUP_RESTORE` を追加したときと似ていますが、今回は `SQLSERVER_AUDIT` を追加します。

オプションを追加するときは、主に次の項目を設定します。

| 設定 | 説明 |
| --- | --- |
| `IAM_ROLE_ARN` | RDS が S3 に書き込むための IAM ロール ARN |
| `S3_BUCKET_ARN` | 監査レコードの送信先となる S3 バケットまたはプレフィックス ARN |
| `ENABLE_COMPRESSION` | 監査ファイルを圧縮するかどうか。デフォルトで有効 |
| `RETENTION_TIME` | 監査ファイルを DB インスタンス上に保持する時間。単位は時間で、最大 840 時間 |

![RDS audit option group](/assets/img/rds/rds_option_group_audit.png)

設定後、オプショングループには `SQLSERVER_BACKUP_RESTORE` と `SQLSERVER_AUDIT` の 2 つのオプションが表示されます。

![RDS option group with two options](/assets/img/rds/rds_option_group_options.png)

> `SQLSERVER_AUDIT` の追加に DB インスタンスの再起動は不要です。オプショングループの状態が有効になれば、SQL Server 内で監査を作成し、RDS が完了した監査ログを S3 へアップロードできるようになります。
{: .prompt-info}

### SQL Server で監査を作成する

オプショングループが有効になったら、SQL Server にログインして監査と監査仕様を作成します。RDS for SQL Server は SQL Server のネイティブな Audit 機能を使いますが、ファイル出力先には RDS 固有の制約があります。

サーバー監査を作成するときは、次に注意してください。

- `FILEPATH` には `D:\rdsdbdata\SQLAudit` を使用する。
- `MAXSIZE` は 2 MB から 50 MB の間に設定する。
- 監査、サーバー監査仕様、データベース監査仕様の名前を `RDS_` で始めない。
- `MAX_ROLLOVER_FILES` または `MAX_FILES` を設定しない。
- audit record の書き込み失敗時に DB インスタンスをシャットダウンする設定にしない。

次は、ログイン失敗イベントを記録する簡単な例です。

```sql
USE master;
GO

CREATE SERVER AUDIT [audit_failed_login]
TO FILE (
  FILEPATH = N'D:\rdsdbdata\SQLAudit',
  MAXSIZE = 10 MB
)
WITH (
  QUEUE_DELAY = 1000,
  ON_FAILURE = CONTINUE
);
GO

CREATE SERVER AUDIT SPECIFICATION [audit_failed_login_spec]
FOR SERVER AUDIT [audit_failed_login]
ADD (FAILED_LOGIN_GROUP)
WITH (STATE = ON);
GO

ALTER SERVER AUDIT [audit_failed_login]
WITH (STATE = ON);
GO
```

これはあくまでデモです。本番環境でどのアクショングループを監査するかは、会社のセキュリティ要件、データの機密性、システムリスクに応じて設計してください。「監査を有効化している」と言うためだけにすべてのイベントを有効化すると、次はストレージ量、分析、アラートノイズの問題になります。

### マルチ AZ の注意点

RDS for SQL Server でマルチ AZ を使う場合、SQL Server Audit がオブジェクトごとにどのように動作するかに注意が必要です。

データベース監査仕様はすべてのノードにレプリケートされますが、サーバー監査とサーバー監査仕様はセカンダリノードに自動的にはレプリケートされません。フェイルオーバー後もサーバーレベル監査を継続して取得したい場合は、セカンダリへフェイルオーバーした後、同じ名前と GUID で対応するサーバー監査またはサーバー監査仕様を作成する必要があります。

そのため、監査設定は「オプショングループが有効かどうか」だけで終わらせないほうがよいです。本番環境では、フェイルオーバー後の監査状態も運用訓練に含めることをおすすめします。

## パスワードローテーション

データベースパスワードでよくある悪い兆候は、重要だと全員が理解しているのに、実際にはドキュメント、環境変数、CI/CD 設定、誰かのパスワードマネージャーに置かれていることです。時間が経つほど、どのサービスが止まるか分からないため、誰も変更したくなくなります。

RDS では、まずマスターユーザーパスワードを AWS Secrets Manager の管理下に置けます。DB インスタンスの作成または変更時に、RDS にマスター認証情報を管理させることができます。有効化すると、RDS がパスワードを生成し、Secrets Manager に保存し、ローテーション時にデータベース側のマスターユーザーパスワードも同期します。

データベースの編集画面で、`AWS Secrets Manager` による管理を選択すると、RDS がシークレットを自動的に管理できるようになります。

![RDS Secrets Rotate](/assets/img/rds/rds_secrets_manager_autorotate.png)

`Secrets Manager` を確認すると、認証情報が自動的に作成され、ローテーションも設定されていることが分かります。

![Secrets Manager autorotate credentials](/assets/img/rds/secrets_manager_autorotate.png)

### 自分でパスワードを管理している場合の注意点

まだ RDS 管理のマスター認証情報を使っておらず、自分でマスターパスワードを管理している場合でも、DB インスタンスを変更してパスワードを変えることはできます。ただし、この方法は手動プロセスへの依存が大きく、次の問題が起きやすいです。

- パスワード変更後、アプリケーション設定が同期されていない。
- CI/CD、スケジュールジョブ、運用ツールが古いパスワードを使い続けている。
- パスワード変更後の接続プールや長時間接続の挙動を確認していない。
- パスワードは変更したが、変更記録や承認フローが残っていない。

また、RDS for SQL Server でマスターユーザーパスワードを作成または変更する場合、RDS が SQL Server 内部のパスワードポリシーに従って弱いパスワードを必ず拒否してくれるとは限りません。操作が成功したとしても、強力なパスワードを使い、監査とイベント通知も組み合わせてリスクを確認してください。

## まとめ

RDS for SQL Server の基本構築は、データベースプラットフォームを立ち上げるところまでです。本番環境に近づけるには、さらに「追跡可能であること」と「ローテーション可能であること」を追加する必要があります。

SQL Server Audit は、事後追跡とコンプライアンス証跡を扱います。誰が何をしたのか、どのイベントを記録するのか、監査ファイルをどこに保存するのか、誰が読み取れるのかを整理します。Secrets Manager とパスワードローテーションは、認証情報のガバナンスを扱います。パスワードをドキュメントや手動作業に散らばらせるのではなく、権限制御、記録、ローテーションが可能なリソースとして扱います。

これらの設定は、データベースを作成する作業ほど分かりやすい達成感はありません。それでも、データベースを安心して本番環境へ進められるかどうかを決める重要な要素です。接続できることは第一歩です。監査でき、ローテーションでき、訓練できてこそ、運用できるデータベースになります。

## 参考資料

- [Amazon RDS for SQL Server：SQL Server Audit](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.html)
- [Amazon RDS for SQL Server：DB インスタンスオプションに SQL Server Audit を追加する](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.Adding.html)
- [Amazon RDS for SQL Server：SQL Server Audit の使用](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.CreateAuditsAndSpecifications.html)
- [Amazon RDS for SQL Server：監査ログの表示](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.Viewing.html)
- [Amazon RDS for SQL Server：SQL Server Audit の IAM ロールを手動で作成する](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.IAM.html)
- [Amazon RDS：Amazon RDS と AWS Secrets Manager によるパスワード管理](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [Amazon RDS for SQL Server：マスターログインのパスワードに関する考慮事項](https://docs.aws.amazon.com/ja_jp/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.PasswordPolicy.MasterLogin.html)
- [AWS Secrets Manager：AWS Secrets Manager シークレットのローテーション](https://docs.aws.amazon.com/ja_jp/secretsmanager/latest/userguide/rotating-secrets.html)
