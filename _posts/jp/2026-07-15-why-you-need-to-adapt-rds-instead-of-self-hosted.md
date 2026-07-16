---
layout: post
title: "EC2でデータベースを自前運用し続けるのではなく、RDSを検討すべき理由"
image: https://fastly.picsum.photos/id/388/1200/630.jpg?hmac=3X4hBgiMUuCq4LWzGXpRr8aLv-ruGrEdVjJ5GJ_NBWc
description: "EC2上にデータベースを構築すると自由度が高く見えますが、実際には容量、バックアップ、リストア、接続、監視、Patchを自分たちで扱う必要があります。この記事では、多くのチームがAmazon RDSを優先的に検討すべき理由と、導入時に注意すべき制約を整理します。"
author: Mark_Mew
categories: [AWS, RDS]
tags: [RDS, Database, AWS]
keywords: [RDS, Database, EC2, Self-hosted Database, PITR, RDS Proxy, CloudWatch, AWS Backup]
lang: ja
date: 2026-07-15
---

多くのチームがAWSを使い始めるとき、データベースをEC2上にインストールするのは自然な選択に見えます。

理由はとても直感的です。以前からIDCやVM上で同じように運用してきたからです。MySQL、PostgreSQL、SQL Serverを自分でインストールすれば、自由度が高く見え、既存の運用方法もそのまま使いやすくなります。EC2を1台起動し、EBSをアタッチし、Security Groupを設定し、データベースをインストールすれば、サービスから接続できるようになります。

しかし、データベースで本当に難しいのは、たいてい「インストール」ではありません。

本当に難しいのは、継続的な運用です。

- ディスクが埋まりそうなとき、障害になる前に拡張できるか。
- バックアップは毎日成功しているか。本当にリストアしたことがあるか。
- データを誤って削除したとき、指定した時点まで戻せるか。
- 接続数が急増したとき、先に倒れるのはアプリケーションか、データベースか。
- OS、データベースバージョン、Security Patchは誰が計画し、誰が検証し、誰がロールバックを担当するのか。
- 監視はCPUだけを見ているのか、それともIOPS、Latency、Connection、`FreeStorageSpace`の異常まで検知できるのか。

これらをすべて自分たちで対応しなければならないのであれば、EC2上のデータベースはもはや安価なVMではありません。長期的に人手をかけて運用し続ける必要がある、ひとつのデータベースプラットフォームになります。

この記事は、「すべてのデータベースをRDSに移行すべきだ」と言いたいわけではありません。むしろ、多くの一般的なWeb、社内システム、エンタープライズアプリケーションの場面で、なぜデータベースを普通のEC2インスタンスとして運用し続けるのではなく、RDSを優先的に検討すべきなのかを整理するものです。

## 自前運用データベースの最大コストはEC2料金ではない

自前運用データベースでよくある誤解は、請求書上のInstance料金だけを比較してしまうことです。

たとえば、次のように考えがちです。

- EC2 + EBSのほうが、同等スペックのRDSより安く見える。
- 自分でデータベースをインストールすれば、RDSの制約に縛られない。
- 既存のバックアップスクリプトを流用できるので、追加で学ぶ必要がない。

これらが必ず間違っているわけではありません。ただし、見ているのはリソースコストだけで、運用コストが含まれていません。

データベースをEC2上に置く場合、少なくとも次の項目は自分たちで責任を持つ必要があります。

| 運用項目 | 自前EC2 Database | Amazon RDS |
| --- | --- | --- |
| OSメンテナンス | 自分で更新、再起動、スケジュール管理を行う | RDSが基盤OSのメンテナンスを管理 |
| データベース導入 | 自分でインストールと設定を行う | 作成時にEngineとバージョンを選択 |
| ストレージ拡張 | EBS、ファイルシステム、データベース設定を自分で拡張 | Storage Autoscalingを利用可能 |
| バックアップ | 自分でスケジュール、保存、削除、アラートを管理 | Automated Backup、Manual Snapshot、AWS Backup |
| PITR | Binlog、WAL、Archive Logを自分で管理 | バックアップ保持期間内の指定時点へ復元可能 |
| 高可用性 | Standby、Replication、Failoverを自分で構築 | Multi-AZ配置を選択可能 |
| 監視 | Agentと連携ツールを自分で導入 | CloudWatch、Enhanced Monitoring、Performance Insights |
| Patch | CVEの追跡、テスト、適用を自分で実施 | RDSがMaintenance WindowとPending Maintenanceを提供 |

もちろん、RDSがすべてを無料で代わりに処理してくれるわけではありません。インスタンス仕様、バックアップ保持期間、メンテナンス時間帯、パラメータ設定、監視アラーム、権限制御は引き続き決める必要があります。ただしRDSは、多くの基盤作業を「自分で設計して実行するもの」から「方針を設定し、結果を検証するもの」に変えてくれます。

この二つの差は非常に大きいです。

## ディスク容量：storage fullになるまで待たない

データベースで特に避けたい状況の一つが、ディスクが書き込みで埋まることです。

EC2上の自前運用データベースでもEBSを拡張できますが、実際の流れはボタンを一つ押すだけでは済まないことが多いです。

1. ディスクが埋まりそうなことに気づく。
2. EBS Volumeを拡張する。
3. PartitionまたはFile Systemを拡張する。
4. データベースが使用しているディレクトリから新しい容量が見えていることを確認する。
5. IOPS、Throughput、遅延が追いついているかを観察する。

これらの作業自体は難しくありません。しかし、深夜にアラームが鳴り、ディスク残量が2%しかない状況では、どんな手作業もリスクになります。

RDSにはStorage Autoscalingがあります。有効化すると、RDSが空き容量不足を検知したとき、条件に応じてストレージ容量を自動的に増やします。これは万能薬ではありません。RDSのストレージは拡張後に直接縮小できませんし、大量のデータインポートでは短時間storage full状態に近づくこともあります。そのため、妥当な初期容量、最大容量、そして`FreeStorageSpace`に対するアラーム設定は必要です。

それでも、よくある「容量拡張を忘れていた」というリスクは下げられます。

> Storage Autoscalingは保護機構であり、容量計画の代替ではありません。データベースが継続的に急成長している場合は、成長率、保持ポリシー、インデックス肥大化、アーカイブ方式を定期的に確認する必要があります。
{: .prompt-warning}

## バックアップとPITR：バックアップがあることと復元できることは違う

多くのシステムにはバックアップがあります。しかし、実際に障害が起きてから次のようなことに気づく場合があります。

- バックアップが実は数日間失敗していた。
- バックアップファイルは存在するが、誰もリストア手順を知らない。
- リストアに時間がかかりすぎ、システムが許容できるRTOを超える。
- 昨日の早朝には戻せるが、誤削除の5分前には戻せない。
- バックアップと本番データが同じ権限境界にあり、誤削除や侵害時に一緒に消える。

自前運用データベースでも、もちろんうまく構成できます。MySQLならmysqldump、XtraBackup、Binary Logを組み合わせられます。PostgreSQLならpg_dump、pg_basebackup、WAL archiveを使えます。SQL Serverにも完全バックアップ、差分バックアップ、トランザクションログバックアップがあります。

問題は、これらをチーム自身が設計し、実装し、監視し、訓練し、引き継ぐ必要があることです。

RDSのAutomated Backupは、バックアップウィンドウ中にSnapshotを作成し、トランザクションログを保持します。これにより、バックアップ保持期間内でPoint-in-Time Recoveryを実行できます。一般的なRDS DB Instanceでは、バックアップ保持期間を0日から35日まで設定できます。0に設定すると自動バックアップは無効になります。

ここで最も重要な考え方は、PITRの復元は元のDBを上書きするものではなく、新しいDB Instanceを作成するという点です。これはむしろ良いことです。先にデータを検証し、その後でアプリケーションを新しいデータベースへ切り替えるのか、必要なデータだけを元のDBへ戻すのか、あるいは事故前の状態を確認するためだけに使うのかを選べます。

組織ですでにAWS Backupを使用している場合は、RDSを統一されたBackup Planに含めることもできます。AWS Backupでは、バックアップポリシー、保持期間、クロスアカウントまたはクロスリージョンコピー、Vault Lockなどのガバナンス要件を集中管理できます。監査、コンプライアンス、複数アカウント管理が必要な企業では、各チームが個別にバックアップを設定するよりも管理しやすくなります。

### バックアップ戦略は少なくとも三つの質問に答えるべき

RDSネイティブのバックアップを使う場合でもAWS Backupを使う場合でも、まず次を定義すべきです。

| 質問 | 意味 |
| --- | --- |
| RPOはいくつか | 最大でどれくらいのデータ損失を許容できるか |
| RTOはいくつか | 最大でどれくらいの復旧時間を許容できるか |
| リストア訓練をどの頻度で行うか | ステータスが成功しているだけでなく、本当に使えるバックアップかを確認する |

多くのチームは毎日バックアップを設定しますが、リストア訓練は行っていません。それでは「バックアップが作成された」ことは証明できますが、「事故時に復旧できる」ことは証明できません。

少なくとも非本番環境で定期的にリストア訓練を行い、次を記録することをおすすめします。

1. 指定時点のDBを復元するのにどれくらい時間がかかるか。
2. アプリケーションの接続文字列を切り替えるのにどれくらい時間がかかるか。
3. 権限、Parameter Group、Option Group、Security Groupに漏れがないか。
4. 復元後のデータが期待どおりか。

これらの結果は、「バックアップを有効にしています」と言うよりもずっと価値があります。

## RDS Proxy：接続数を最初のボトルネックにしない

データベース接続は無料のリソースではありません。

各接続は、データベース側のメモリとCPUを消費します。アプリケーションが水平スケールし、Container数が増えたり、Lambdaが短時間に大量起動したりすると、Connection Stormが起きやすくなります。その結果、クエリ自体が重すぎるのではなく、データベースが大量の接続を作成し、認証し、維持することに忙しくなります。

自前運用データベースでは、PgBouncer、ProxySQL、HAProxy、またはアプリケーション側のConnection Poolを使うことがあります。これらのツールは有用ですが、同じように自分たちでデプロイ、監視、保守する必要があります。

RDS ProxyはAWSが提供するManaged Proxyです。アプリケーションとRDSの間で接続プールを維持し、既存接続を再利用することで、頻繁に接続を作成するコストを下げられます。Multi-AZやFailoverと組み合わせると、RDS Proxyはアプリケーションが利用可能なDBへより安定して再接続する助けにもなります。

RDS Proxyは特に次のような場合に向いています。

- Lambdaや短命なワークロード。
- 接続数が急増しやすいAPIサービス。
- アプリケーション側のConnection Pool設定が統一されていない環境。
- Secrets Managerと組み合わせてデータベース認証情報を管理したいシステム。

ただし、これはクエリ性能最適化ツールではありません。SQL自体が遅い、インデックス設計が悪い、トランザクションを長く保持している、といった問題がある場合、RDS Proxyが魔法のようにクエリを速くすることはありません。主に扱うのは、接続管理とFailover時の安定性です。

## CloudWatchとEnhanced Monitoring：データベースでは見るべき指標を見る

自前運用データベースでよくある監視方法は、まずEC2のCPU、Memory、Disk Usageを見ることです。これらは重要ですが、データベースにはそれだけでは足りません。

データベースの問題は、よく次のような指標に現れます。

- Connection数が継続的に増える。
- `FreeStorageSpace`が急速に減る。
- `ReadLatency`または`WriteLatency`が上がる。
- `ReadIOPS`、`WriteIOPS`、Throughputがストレージ上限に当たる。
- CPU Creditを使い切る。
- Replica Lagが拡大する。
- LockやSlow Queryが増える。

RDSはデフォルトでさまざまな指標をCloudWatchへ送信し、CloudWatch Alarmと組み合わせてアラートを作成できます。より細かいOSレベルの情報が必要な場合はEnhanced Monitoringを有効化できます。DB Load、待機イベント、SQLレベルのボトルネックを分析したい場合は、Performance InsightsまたはCloudWatch Database Insightsを利用できます。

ここで重要なのは、「ツールが多いほど良い」ということではありません。まずBaselineを作ることです。

たとえば、CPU 70%はあるシステムでは健全かもしれません。もともとCPU-boundなシステムだからです。しかし、普段は15%程度の別のシステムで突然70%まで上がった場合、クエリプランの変化や異常なトラフィックを示している可能性があります。Baselineがなければ、アラーム閾値は推測になりがちです。

私は本番データベースでは、まず次の基本アラームを設定することが多いです。

| 指標 | 観察目的 |
| --- | --- |
| `CPUUtilization` | 通常の基準値を長時間上回っていないか |
| `FreeableMemory` | メモリ不足またはメモリ圧迫が起きていないか |
| `FreeStorageSpace` | ストレージがアラーム閾値に近づいていないか |
| `DatabaseConnections` | 接続数が異常に増えていないか |
| `ReadLatency` / `WriteLatency` | ストレージ遅延が悪化していないか |
| `ReadIOPS` / `WriteIOPS` | I/Oがボトルネックに近づいていないか |
| `ReplicaLag` | Read ReplicaがPrimaryに追いついているか |

もしアラームを一つだけ選ぶなら、私はまず`FreeStorageSpace`を選びます。データベースのディスクが満杯になったとき、復旧のプレッシャーは特に大きく、書き込み、バックアップ、その後のメンテナンスにも影響する可能性があるからです。

## PatchとMaintenance Window：メンテナンスを記憶に頼らない

データベースでは、データベースエンジンだけでなく、基盤OS、ハードウェア、証明書もメンテナンス対象です。

EC2でデータベースを自前運用している場合、これらは通常チーム自身の責任になります。

- OSのSecurity Updateを追跡する。
- データベースのMinor Versionをアップグレードすべきか判断する。
- 停止またはRolling Updateを計画する。
- ロールバック手順を準備する。
- 更新後にアプリケーション互換性を検証する。

チームに成熟したSREまたはDBAプロセスがあれば、これらはうまく実施できます。しかし、データベースがアプリケーションチームの「ついでに運用している」リソースである場合、長期間誰も触れたがらない基盤になりやすいです。

RDSにはMaintenance Windowがあり、メンテナンスイベントが開始される時間を制御できます。一部の更新はすぐに適用するか、次のメンテナンスウィンドウへ回すかを選べます。一方、必要なセキュリティまたは信頼性更新は無期限には延期できません。Multi-AZ配置では、メンテナンス内容によっては先にStandbyを処理し、その後Failoverすることで影響を下げられます。

これは、RDSのPatchにまったくリスクがないという意味ではありません。引き続き次の対応は必要です。

1. Maintenance Windowをトラフィックが最も少ない時間帯に設定する。
2. Event Notificationを有効にし、Pending Maintenanceを把握する。
3. 非本番環境で先にEngine Upgradeをテストする。
4. アプリケーションのDriverとORMが互換性を持つか確認する。
5. 本番環境ではSnapshotと復旧手順を残しておく。

RDSの価値は、メンテナンスを管理可能にすることであり、メンテナンスを完全に無視できるようにすることではありません。

## Multi-AZ：高可用性はStandbyを1台用意して終わりではない

自前運用データベースで高可用性を実現するには、通常次のような要素が関係します。

- PrimaryとStandbyの同期または非同期レプリケーション。
- Failoverの判定。
- DNSまたは接続エンドポイントの切り替え。
- Split-brain対策。
- バックアップをどのインスタンスから実行するか。
- メンテナンス中に長時間の中断を避ける方法。

これらはどれも専門性の高い作業です。最も危険なのは、「見た目上は待機系がある」が、Failoverを一度も訓練していない状態です。Primaryに障害が起きてから、Standbyの遅延が大きすぎる、権限が不足している、アプリケーションが自動再接続できない、DNS TTLのせいで切り替え時間が想定を超える、といったことに気づく場合があります。

RDS Multi-AZは、異なるAvailability Zone間でデータベースの可用性と耐久性を高める機能です。これは読み取り負荷を分散するための機能ではありません。読み書きを分離したい場合は、通常Read Replicaを別途使用します。Multi-AZの主な価値は、インフラ障害、メンテナンス、一部の更新シナリオにおいて、単一障害点の影響を下げることです。

本番環境でデータベースが重要コンポーネントであるなら、私はMulti-AZを後から予算があれば追加するものではなく、デフォルトの選択肢として扱います。

## それでも自前運用が適している場合

RDSは多くの場面に適していますが、すべての場面に適しているわけではありません。

次のような場合は、自前運用が必要になることがあります。

- RDSがサポートしていないデータベースエンジン、バージョン、Extensionが必要。
- OSレベルの権限、特殊なKernel、ファイルシステム、Agentが必要。
- 非常にカスタマイズされたバックアップ、レプリケーション、トポロジーが必要。
- ライセンス形態または商用契約がRDSに合わない。
- 遅延、性能、ハードウェア要件がRDSで提供できる範囲を超えている。
- チーム自身に成熟したDBA/SRE能力があり、自前運用に明確な利益がある。

これらはどれも現実的な理由です。しかし理由が単に「以前からこうしている」または「RDSは高く見える」だけであれば、人件費、障害リスク、メンテナンス成熟度、復旧能力を含めて再計算すべきです。

## RDS導入前に確認すべきこと

EC2上の自前運用データベースからRDSへ移行する場合、まずチェックリストを作ることをおすすめします。

### 仕様と容量

- 現在のデータベースサイズと過去3か月から6か月の成長率。
- CPU、Memory、IOPS、Throughput、ConnectionのBaseline。
- Provisioned IOPSまたはgp3の指定IOPS / Throughputが必要か。
- Storage Autoscalingの初期容量と最大容量。

### 可用性と復旧

- Multi-AZを有効化するか。
- Automated Backupの保持日数。
- クロスアカウント、クロスリージョン、長期保存のためにAWS Backupが必要か。
- RPOとRTOが文書化されているか。
- リストア訓練が完了しているか。

### アプリケーション互換性

- Driver、ORM、データベースバージョンに互換性があるか。
- RDSがサポートしていない権限、Plugin、Extension、システムテーブル操作を使っていないか。
- 接続文字列、DNS、TLS、証明書を調整する必要があるか。
- RDS Proxyが必要か。

### 運用とセキュリティ

- Parameter GroupとOption Groupをどのように管理するか。
- Maintenance WindowとBackup Windowがピーク時間を避けているか。
- CloudWatch Alarm、Event Notification、Log Exportが設定されているか。
- IAM、Security Group、KMS、Secrets Managerが会社の規定に合っているか。

移行自体は、Dump/Restore、Snapshot Restore、ネイティブレプリケーション、AWS Database Migration Serviceなど、さまざまな方法で実施できます。最初に明確にすべきなのはツールではなく、停止時間、データ整合性、ロールバック計画です。

## まとめ

データベースをEC2上に構築すること自体は間違いではありません。問題は、データベース運用の重さを過小評価することです。

データベースは一般的なアプリケーションサーバーではありません。データの正確性、バックアップと復元、容量増加、性能ボトルネック、Security Patch、障害復旧が関係します。チームがこれらを継続的に扱う十分な時間を持っていない場合、自前運用データベースはRDS費用を節約しているように見えて、実際には将来の障害と人手にコストを隠しているだけかもしれません。

RDSの価値は、「AWSがデータベースをインストールしてくれる」ことだけではありません。本当に提供しているのは、Managedなデータベース運用基盤です。

1. Storage Autoscalingにより容量不足のリスクを下げる。
2. Automated BackupとPITRにより復旧戦略を実装しやすくする。
3. AWS Backupによりバックアップと保持ポリシーを集中管理できる。
4. RDS Proxyにより接続管理とFailover時の回復性を改善する。
5. CloudWatch、Enhanced Monitoring、Performance Insightsにより可観測性を提供する。
6. Maintenance WindowによりPatchとメンテナンスを制御しやすくする。

チームに成熟したDBA能力があるなら、自前運用にもまだ価値はあります。しかし多くのプロダクトチームにとっては、基盤データベースプラットフォームを自分で保守するより、データモデル、クエリ性能、データライフサイクル、アプリケーション安定性に時間を使うほうが価値があります。

Managed Serviceに任せられる基盤作業は任せる。エンジニアリングの力は、ビジネスとシステムの文脈を本当に理解する必要がある場所に残しておくべきです。

## 参考資料

- [Amazon RDS: Managing capacity automatically with Amazon RDS storage autoscaling](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.Autoscaling.html)
- [Amazon RDS: Introduction to backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html)
- [Amazon RDS: Backup retention period](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html)
- [Amazon RDS: Restoring a DB instance to a specified time](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html)
- [AWS Backup: Amazon Relational Database Service backups](https://docs.aws.amazon.com/aws-backup/latest/devguide/rds-backup.html)
- [AWS Backup: Continuous backups and point-in-time recovery](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html)
- [Amazon RDS: Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [Amazon RDS: Monitoring Amazon RDS metrics with Amazon CloudWatch](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [Amazon RDS: Monitoring OS metrics with Enhanced Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html)
- [Amazon RDS: Maintaining a DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.Maintenance.html)
