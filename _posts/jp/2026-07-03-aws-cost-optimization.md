---
layout: post
title: "AWS コスト最適化の実践：リソース棚卸しから Savings Plans まで"
description: "AWS のコスト最適化は RI の購入だけではありません。コストの可視化、遊休リソースの削除、Rightsizing、S3 Lifecycle、Spot、ALB の統合、停止スケジュールまで、継続可能な FinOps の進め方を解説します。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, Cost Management]
keywords: [AWS, Cost Management, FinOps, Savings Plans, Reserved Instances, Spot Instance]
lang: ja
date: 2026-07-03
---

クラウドサービスによって、インフラ構築のハードルは大きく下がりました。EC2 インスタンスの起動や RDS の作成は、今では数分で完了します。しかし、リソースを簡単に作れるからこそ、期限切れのテスト環境、使われていないディスク、不要になったバックアップが、何か月も請求に残り続けることがあります。

システムを段階的に AWS へ移行するなかで、コストの増加が必ずしも無駄を意味するわけではありません。ユーザー数の増加、可用性の向上、冗長化の強化には、当然コストがかかります。本当に確認すべきなのは、各コストの目的を説明できるか、そして必要な性能と信頼性を適正な価格で得られているかという点です。

本記事では、私が実際にコスト最適化へ取り組んだ際に用いた方法を整理します。基本となる順序は次のとおりです。

1. コストを可視化し、帰属先を明確にする。
2. 価値を生んでいないリソースを削除する。
3. 実際の使用量に合わせて Rightsizing を行う。
4. 最後に Reserved Instances や Savings Plans で割引を得る。

この順序は重要です。最初に長期契約を購入すると、現在の過剰な構成をそのまま固定してしまう可能性があります。その後インスタンスを停止しても、契約したコミットメントの支払いは残ります。

## 背景：請求額が増えても、何に使ったかは分からない

デジタルトランスフォーメーションを進める多くの企業と同様に、私たちもシステムのレジリエンスを高めるために SLA と SLO を定め、サービスを段階的にクラウドへ移行しました。システムが増えるにつれて、AWS の請求額も年々増加しました。

最初に直面した問題は「どう節約するか」ではありません。次の問いに、誰もすぐ答えられなかったことです。

- この費用を発生させた製品、部門、環境はどれか。
- コストの増加はトラフィックの成長によるものか、それともリソースの停止忘れか。
- この EC2 インスタンスは必要なキャパシティなのか、念のため過剰に確保したものか。
- サービスの停止後も、EBS、Snapshot、Elastic IP、Log の料金が発生していないか。

したがって、コスト最適化の第一歩はアーキテクチャの変更ではなく、可観測性の確立です。

## ステップ 1：コストのベースラインを作る

### リソースタグを標準化する

EC2、RDS、S3、ECR などのリソースには、最低限、用途と責任者を示すタグを付けます。実際の Tag Key は組織に合わせて調整できます。例えば次のように定義します。

| Tag Key | 例 | 用途 |
| --- | --- | --- |
| `Application` | `order-service` | 製品またはシステムを識別する |
| `Environment` | `prod`、`staging` | 本番環境と非本番環境を区別する |
| `Owner` | `platform-team` | 管理を担当するチームを識別する |
| `CostCenter` | `CC-1001` | 社内のコストセンターに対応付ける |
| `ManagedBy` | `terraform` | リソースの作成・管理方法を示す |

タグを付けた後は、Billing and Cost Management で Cost Allocation Tag として有効化しなければ、Cost Explorer や Cost and Usage Report で分析できません。新しい Tag Key が有効化画面に表示されるまで最大 24 時間、さらに有効化にも最大 24 時間かかる場合があります。そのため、タグは当日の費用をリアルタイムに調査する用途には向いていません。

さらに重要なのは、Cost Allocation Tag が、過去のタグなし利用分までさかのぼって補完するわけではない点です。すでに大量のリソースが存在する場合は、請求額に占める割合が大きいサービスから手作業で棚卸しします。その後、Terraform、CloudFormation、またはリソース作成パイプラインにタグ付けルールを組み込み、同じ問題が再発しないようにします。

### 本当のコストドライバーを特定する

まず Cost Explorer で直近 3〜6 か月の推移を確認し、Service、Linked Account、Region、Usage Type、Tag ごとにグループ化します。「EC2 にいくらかかったか」だけで終わらせず、次の項目まで掘り下げます。

- EC2 の稼働時間とインスタンスタイプ
- EBS の容量、IOPS、Snapshot
- NAT Gateway が処理したデータ量
- Availability Zone 間、Region 間、インターネット向けの Data Transfer
- RDS インスタンス、ストレージ、バックアップ
- Load Balancer の稼働時間と LCU
- CloudWatch Logs の取り込み量と保持期間

分析時点の月額コスト、リソース数、主要指標を記録しておくことを勧めます。ベースラインがなければ、最適化後に「安くなった気がする」としか言えず、変更の効果を証明できません。

AWS Budgets と Cost Anomaly Detection も設定できます。Budgets は支出が予想を超えていないか追跡するのに適し、Anomaly Detection は過去のパターンと異なる異常な支出を検出します。どちらもアラートであり、資産管理の代わりにはなりませんが、問題が請求に残り続ける時間を短縮できます。

## ステップ 2：ビジネス価値のないリソースを先に削除する

完全に不要なリソースを削除する方が、そのリソースに 20% の割引を適用するより効果的です。私はまず削除候補の一覧を作り、Owner に確認してもらったうえで、観察期間と削除日を設定します。コスト削減のために、まだ利用中のサービスを誤って壊すことを防ぐためです。

### 小さいインスタンスではなく、遊休 EC2 を削除する

社内には `t3.small` や `t3.medium` のようなテスト用インスタンスが残りがちです。1 台あたりの料金は安く見えるため、誰も積極的に対処しません。しかし、同様のリソースが数十台に増え、数か月稼働すれば、継続的な支出になります。

ただし、小さいインスタンスだから削除してよいとは限りません。少なくとも次の点を確認します。

- 過去 30 日間、CPU、Network、Disk I/O が継続的にほぼゼロだったか
- 最近の接続、スケジュール、デプロイ履歴が残っていないか
- DNS、Target Group、Auto Scaling Group が引き続き参照していないか
- Owner が用途と保持期限を説明できるか

不要であることを確認してから、必要に応じて Snapshot や AMI を作成し、一定期間停止して観察した後、最後に Terminate します。EC2 を Stop しても停止するのはインスタンスのコンピューティング料金だけであり、アタッチされた EBS や一部の IP リソースには引き続き料金が発生する可能性があります。

同じ確認を、未接続の EBS、古い Snapshot、遊休 Elastic IP、旧 AMI、トラフィックのない Load Balancer、テスト終了後に残された RDS にも行います。

### S3 の旧バージョンを削除し、Lifecycle を設定する

CI/CD では JavaScript、CSS、インストールパッケージ、レポートなどを S3 にアップロードすることがよくあります。Build ごとにファイルを保存していると、プロジェクト数とデプロイ頻度が増えるにつれて、二度と読み込まれないオブジェクトが Bucket に蓄積します。Versioning を有効にした Bucket では、Noncurrent Version も確認する必要があります。通常の画面に表示されないからといって、容量を使用していないわけではありません。

定期的に手作業で削除するより、データの性質に合わせて S3 Lifecycle を設定する方が効果的です。

- CI Artifact：最新の数バージョンだけを残し、それ以外は 30 日または 90 日後に削除する。
- アクセスパターンが不明：S3 Intelligent-Tiering への移行を検討する。
- 法令により長期保存が必要で、ほぼアクセスしない：Glacier ストレージクラスを検討する。
- 未完了の Multipart Upload が残したパーツ：数日後に自動削除する。

早く Glacier に移行すれば必ず安くなるわけではありません。一部のストレージクラスには最低保存期間、取り出し料金、オブジェクト単位の追加コストがあります。非常に小さいファイルが大量にある場合も、アーカイブに向かないことがあります。オブジェクトサイズ、アクセス頻度、保存期間、目標復旧時間を基に試算してからルールを定義します。

## ステップ 3：一律にスペックを下げず、Rightsizing する

クリーンアップ後は、必要ではあるものの過剰に構成されているリソースを見直します。AWS Compute Optimizer は、現在の構成と使用状況のメトリクスを基に、EC2、Auto Scaling Group、EBS、ECS on Fargate、一部の RDS と Aurora に対する推奨を提供します。

平均 CPU 使用率だけを見てはいけません。次のいずれもボトルネックになる可能性があります。

- CPU 使用率の平均値とピーク値
- メモリ使用量と Swap
- Network PPS と Throughput
- EBS IOPS、Throughput、Queue Length
- RDS Connection、Freeable Memory、Read/Write Latency
- T ファミリーの CPU Credit Balance

メモリ使用率は、EC2 が標準で CloudWatch に送信するメトリクスではありません。CloudWatch Agent または既存の監視システムで収集する必要があります。CPU だけで判断すると、メモリ負荷の高いサービスを小さくしすぎる可能性があります。

スペックを変更する際は十分な Headroom を残し、まず非本番環境で検証してから、リスクの低い時間帯に適用します。本番環境では、起動時間、Auto Scaling、耐障害性、ロールバック手順も確認します。コスト最適化の目的は無駄をなくすことであり、余裕をまったく持たない状態でシステムを運用することではありません。

### 構成は標準化するが、制約を増やしすぎない

チームが多数の EC2 Family、OS、データベースバージョンを同時に管理すると、監視、Patch、イメージ、キャパシティ計画が複雑になります。類似したワークロードを検証済みの少数の構成へ集約すると、運用と長期割引の計画が容易になります。

ただし、すべてのサービスで使用可能な Instance Type を 3 種類だけに制限する必要はありません。コンピューティング集約型、メモリ集約型、汎用のワークロードでは、必要な構成が異なります。制約が厳しすぎると、新世代の Instance や Graviton による Price Performance の向上を逃す可能性もあります。標準化の目的は、意味のない差異を減らすことであり、すべてのワークロードに同じ靴を履かせることではありません。

## ステップ 4：適切な料金モデルを選ぶ

クリーンアップと Rightsizing が完了すると、初めて安定したベースライン使用量が見えてきます。その段階で、On-Demand、Reserved Instances、Savings Plans、Spot のどれを使うか判断します。

### Reserved Instances と Savings Plans

Savings Plans では、1 年または 3 年にわたり、1 時間あたり一定金額のコンピューティング利用をコミットすることで、On-Demand より低い料金が適用されます。これは「利用可能な時間」をまとめて前払いする仕組みではありません。ある時間帯の対象利用量が不足していても、その時間のコミットメント金額は支払う必要があります。

実務では次のように検討できます。

- 長期にわたり安定して稼働する RDS、ElastiCache、OpenSearch：各サービスに対応する Reserved Instance または Reserved Node を検討する。
- EC2 Family と Region が安定しており、より大きな割引を求める：EC2 Instance Savings Plans を検討する。
- Family や Region をまたいで移行する可能性がある、または Fargate や Lambda を利用する：柔軟性の高い Compute Savings Plans を検討する。
- 短期プロジェクト、需要が不明なサービス、終了予定のサービス：契約を急がず On-Demand を維持する。

購入前には Cost Explorer の推奨を参考にできますが、選択した Lookback Period が将来の利用状況を表しているか確認する必要があります。AWS の推奨は過去の利用量から算出されます。製品の終了、アーキテクチャの移行、翌月のトラフィック変化を予測するものではありません。

より安全な方法は、分割して購入することです。継続が確実なベースライン使用量のみを先にカバーし、Coverage と Utilization を観察してから、コミットメントを段階的に増やします。100% の Coverage を追求するあまり、Utilization を低下させないようにします。

### Spot Instance

Spot は、Batch、CI Runner、画像変換、Stateless Worker など、中断可能で再試行でき、水平スケール可能なワークロードに適しています。復旧できない単一の本番サーバーを Spot に置き換え、回収されないことを期待するような使い方には向きません。

Spot を使う場合は、中断を前提にシステムを設計します。

- ジョブの状態を外部ストレージに保存し、単一インスタンスのローカルディスクに依存しない。
- タスクを Idempotent にし、失敗後も安全に再試行できるようにする。
- 中断通知を受けたら、新しいジョブの受け付けを停止して Drain を完了する。
- Auto Scaling Group に複数の利用可能な Instance Type と Availability Zone を設定する。
- 容量が不足した最安の Pool だけを選ばず、Capacity Optimized などの配分戦略を使う。
- 重要なサービスには、ベースラインとなる On-Demand キャパシティを一部残す。

[EC2 Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/) では、各 Instance Pool の過去の中断頻度を確認できます。ただし、特定の Family を永続的に安全または危険と見なすことはできません。Spot の利用可能な容量は、Region、Availability Zone、インスタンスタイプ、時間によって変化します。単一の Instance Type に賭けるより、複数のタイプに分散する方が一般に信頼性は高くなります。

## ステップ 5：アーキテクチャから固定費を減らす

インスタンスを小さくするだけでは改善できないコストもあります。アーキテクチャ内で重複している基盤コンポーネントに起因する費用です。

### 低トラフィックシステムの ALB を統合する

ALB は Host Header や Path Pattern を使用して、リクエストを異なる Target Group にルーティングできます。そのため、同じ低トラフィックシステムのフロントエンド、バックエンド、注文、会員モジュールごとに、必ずしも個別の ALB を用意する必要はありません。

6 つの低トラフィックモジュールがそれぞれ ALB を持っている場合、統合によって Load Balancer の固定時間料金を減らせます。ただし、請求額が正確に 6 分の 1 になるとは限りません。ALB には LCU による料金もあり、Listener Rule、証明書、WAF、AZ 間トラフィックもコストへ影響するためです。

さらに重要なのは、統合によって Blast Radius が広がることです。次の場合は分離した方が適切です。

- システムが異なるセキュリティ境界またはアカウントに属する
- 異なる WAF、TLS、アクセス方針が必要である
- リリースやメンテナンスのサイクルが異なる
- 1 つのシステムのトラフィックが多く、他のサービスへ影響する可能性がある
- 独立した可観測性、クォータ、障害分離が必要である

したがって、ALB の統合は、トラフィックが少なく、ライフサイクルが近く、セキュリティ要件が共通するサービスに適しています。すべてのシステムで 1 つの ALB を共有すべきという意味ではありません。

### 非本番環境に起動・停止スケジュールを設定する

開発、テスト、研修環境は、通常 1 年 365 日、24 時間稼働させる必要がありません。EventBridge Scheduler と Lambda、Systems Manager Automation、AWS Instance Scheduler を組み合わせれば、業務開始前に起動し、終了後に停止できます。

例えば、平日に 1 日 10 時間だけ必要な環境であれば、休日を除くことで EC2 の稼働時間を大幅に減らせます。ただし、次の点には注意が必要です。

- EC2 の停止後も、EBS など存続するリソースには料金が発生する。
- Elastic IP に関連付けていない Public IPv4 は、再起動後に変わる可能性がある。
- Instance Store 上のデータは Stop/Start 後に保持されない。
- RDS の停止中も、ストレージ、Provisioned IOPS、バックアップなどの料金が発生する。
- 通常の RDS DB Instance を連続して停止できるのは最大 7 日で、その後は自動的に起動する。

停止スケジュールは、起動時間を許容できる非本番環境に最も適しています。明確なピークとオフピークがある本番環境では、固定時刻にインスタンスを停止するのではなく、Auto Scaling で需要に応じてキャパシティを調整する方が一般的です。

### ネットワークとログの費用を見落とさない

コンピューティング料金を抑えると、NAT Gateway、Data Transfer、CloudWatch Logs の費用が目立つようになります。

次の点を確認できます。

- Private Subnet から S3、DynamoDB、その他の AWS サービスへの大量のトラフィックが NAT Gateway を経由していないか、VPC Endpoint に変更できないか
- AZ 間通信がアーキテクチャ上必要なのか、Service Discovery やトラフィックルーティングによる迂回なのか
- Container が利用価値のない Debug Log を出力し続けていないか
- CloudWatch Log Group に Retention Policy がなく、永久保存になっていないか
- ECR Image と Snapshot に Lifecycle Policy が設定されているか

この種の費用を変更する前に、トラフィック経路を理解する必要があります。AZ 間料金を避けるためだけに Multi-AZ の可用性を犠牲にするのは、通常、適切なトレードオフではありません。

## コスト最適化を継続可能にする

一度限りのコスト削減プロジェクトでは、半年後に元の状態へ戻りがちです。より効果的なのは、コストを日常のエンジニアリングプロセスへ組み込むことです。

1. すべてのリソースに、作成時から Owner、Application、Environment Tag を必須とする。
2. 製品、財務、プラットフォームの各チームで、毎月コストの推移と異常を確認する。
3. 各改善について、変更前のコスト、削減見込み、リスク、Owner、完了日を記録する。
4. RI と Savings Plans の Coverage と Utilization を定期的に確認する。
5. Log Retention、S3 Lifecycle、非本番環境のスケジュールなどを、Terraform や Policy のデフォルトに組み込む。
6. Owner のないリソース、トラフィックのないリソース、期限切れのリソースは、自動削除するのではなく、Owner へ自動通知する。

コスト指標を「今月いくら減ったか」だけにすべきではありません。製品が成長しているなら、請求総額の増加は合理的な場合があります。アクティブユーザー、注文、API Request、テナントあたりの単位コストの方が、より意味のある指標になることがあります。

## まとめ

AWS のコスト最適化は、月末に請求額を見て、慌てていくつかのインスタンスを停止することではありません。Savings Plans を購入すれば終わりというものでもありません。コストを可視化し、遊休リソースを削除し、構成を Rightsizing し、料金モデルを選び、再び監視と検証に戻る継続的なサイクルです。

最初に 3 つだけ実施できるなら、私は次を選びます。

1. 主要なコストすべてに Owner と用途を設定する。
2. 価値がないと確認できたリソースを削除し、データの保持期限を定める。
3. Rightsizing を完了してから、長期コミットメントを段階的に購入する。

削減額は重要です。しかし、チームが「なぜこの費用を使っているのか」を理解できる仕組みを作ることは、さらに重要です。コストを信頼性、性能、製品価値と同じテーブルで議論できるようになれば、FinOps は単なるリソース削除ではなく、本当のエンジニアリング判断になります。

## 参考資料

- [AWS Billing：Activating user-defined cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html)
- [AWS Compute Optimizer：Supported resources](https://docs.aws.amazon.com/compute-optimizer/latest/ug/supported-resources.html)
- [AWS Savings Plans：What are Savings Plans?](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html)
- [AWS Savings Plans：Understanding recommendation calculations](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-rec-calculations.html)
- [Amazon EC2：Spot interruption notices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html)
- [Amazon S3：Transitioning objects using Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html)
- [Elastic Load Balancing：Listeners for Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [Amazon EC2：How instance stop and start works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-stop-start-works.html)
- [Amazon RDS：Stopping a DB instance temporarily](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)
