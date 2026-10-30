---
layout: post
title: "ALB のデフォルト ELBSecurityPolicy-2016-08 は危険？監査に対応するセキュリティポリシーの見直し方"
description: "AWS CLI、CloudFormation、Terraform で作成した ALB の HTTPS リスナーは ELBSecurityPolicy-2016-08 のままの場合があり、TLS 1.0/1.1 や CBC 暗号スイートを許可します。新しいセキュリティポリシーの選び方、切り替え方、確認方法を整理します。"
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, ELB, TLS, Security]
keywords: [ALB セキュリティポリシー, ELBSecurityPolicy-2016-08, ELBSecurityPolicy-TLS13-1-2-Res-2021-06, ALB TLS 1.0 無効化, ALB TLS 1.3 有効化, ALB TLS 監査, ALB Post-Quantum TLS]
lang: ja
date: 2026-10-30
---

**`ELBSecurityPolicy-2016-08` は危険なのでしょうか。一概にそうとは言えませんが、今の監査では指摘される可能性が高いポリシーです。** AWS CLI、CloudFormation、CDK、Terraform などで ALB の HTTPS リスナーを作成し、ポリシーを指定しなかった場合、このポリシーが適用されます。TLS 1.0、1.1、1.2 に対応しているため互換性は高いものの、CBC 暗号スイートや Forward Secrecy を持たない RSA 鍵交換も許可しており、脆弱性スキャンやコンプライアンスチェックで指摘の対象になります。

多くの場合は `ELBSecurityPolicy-TLS13-1-2-Res-2021-06`（TLS 1.3 と 1.2、AEAD 暗号スイートのみ）への変更が適切です。AWS の最新の推奨に合わせるなら `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` を選びます。[Application Load Balancer のセキュリティポリシー（AWS）](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)

なお、デフォルト値はリスナーの作成方法によって異なります。コンソールでは `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` ですが、CLI、CloudFormation、CDK などでポリシーを指定しない場合は、今でも `ELBSecurityPolicy-2016-08` です。確認が必要なのは、以前から運用している ALB と、IaC で作成した ALB です。

## 2016-08 が監査で指摘される理由

| 項目 | ELBSecurityPolicy-2016-08 |
|---|---|
| TLS バージョン | TLS 1.0、1.1、1.2（1.3 は非対応） |
| 暗号スイート | 18 種。`AES128-SHA`、`AES256-SHA256` などの CBC スイートを含む |
| Forward Secrecy | 一部のスイート（`AES128-GCM-SHA256`、`AES256-SHA` など）は RSA 鍵交換のみで、Forward Secrecy がない |

> **Forward Secrecy**（前方秘匿性）とは、将来サーバーの秘密鍵が漏えいしても、過去に記録された暗号化通信を復号できないという性質です。
> TLS 1.3 では Forward Secrecy を持つ鍵交換が必須です。TLS 1.2 では TLS handshake で選ばれる暗号スイート次第です。2016-08 には ECDHE のスイートと RSA 鍵交換のみのスイートが両方含まれるため、クライアントによっては Forward Secrecy のない組み合わせが選ばれることがあります。
{: .prompt-info}

PCI DSS などの基準では TLS 1.0/1.1 の無効化が一般的に求められます。CIS ベンチマークや各種クラウドのコンプライアンススキャナー（Datadog、Trend Micro Cloud One など）も、リスナーが比較的新しいセキュリティポリシーを使っているかを確認します。判定基準はツールごとに異なるため、実際に監査を受ける基準とバージョンに照らして確認してください。

## セキュリティポリシーの選び方

ALB では**カスタムのセキュリティポリシーは使えません**。AWS が用意した一覧から選びます。よく使われるものは次のとおりです。

| 要件 | ポリシー | TLS バージョン |
|---|---|---|
| 一般的な公開サービスで、互換性と安全性を両立したい | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` | 1.3、1.2 |
| 上記に加え、Post-Quantum TLS（PQ-TLS）を導入し始めたい | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` | 1.3、1.2 |
| すべてのクライアントが TLS 1.3 に対応している | `ELBSecurityPolicy-TLS13-1-3-2021-06` | 1.3 のみ |
| FIPS 140 検証済みモジュールが必要 | `ELBSecurityPolicy-TLS13-1-2-Res-FIPS-2023-04` | 1.3、1.2 |
| CNSA 1.0 / RFC 9151 が必要 | まず `ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP4-FIPS-2023-07` | 1.3、1.2 |
| CBC を必要とする古いクライアントが残っている | `ELBSecurityPolicy-TLS13-1-2-2021-06`、または `Ext1`／`Ext2` シリーズ | 1.3、1.2 |

名前の `Res` は Restricted の略で、`TLS_AES_*`、`TLS_CHACHA20_POLY1305_SHA256`、ECDHE と GCM の組み合わせだけに絞った計 7 種のスイートを使い、CBC は一切含みません。`PQ` は Post-Quantum の略で、将来の量子コンピューターによる攻撃にも耐えるよう設計された鍵交換を指します。このポリシーには、`X25519MLKEM768`（従来の X25519 と ML-KEM を組み合わせたもの）のようなハイブリッドの Post-Quantum 鍵交換グループが追加されています。クライアントが対応していない場合は従来の鍵交換にフォールバックするため、接続できなくなることはありません。

監査の要件が「TLS 1.0/1.1 の無効化」だけなら、`ELBSecurityPolicy-TLS13-1-2-2021-06` で満たせて、互換性も高く保てます。「強力な暗号スイートのみ」が求められる場合は `Res` シリーズを選びます。

## 切り替え前にクライアントの互換性を確認する

この変更で怖いのは設定そのものではなく、古い TLS バージョンや暗号スイートを使うクライアントが残っていて、切り替えた途端に接続できなくなることです。まず[接続ログ（Connection logs）](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-connection-logs.html)を S3 に出力し、しばらく観察します。月次処理やバッチの周期を一通りカバーできる期間が目安です。見るのは次の 3 つのフィールドです。

- `tls_protocol`：`TLSv1` や `TLSv1.1` が残っていないか
- `tls_cipher`：CBC や `AES128-SHA` のようなスイートが使われていないか
- `tls_keyexchange`：どの鍵交換方式か

Athena で検索すれば、古いバージョンを使っている送信元 IP を特定できます。あとは担当者に連絡するか、そのクライアントを入れ替えます。該当しやすいのは、Java 7、古い Android、組み込み機器、古い監視ツールやスキャンツールなどです。

## 切り替え方法

### コンソール

EC2 → ロードバランサー → 対象の ALB を選択 → リスナーとルール → HTTPS:443 を選択 → リスナーを管理 → リスナーを編集 → セキュリティポリシーで新しいポリシーを選んで保存します。

### AWS CLI

```bash
aws elbv2 modify-listener \
  --listener-arn arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:listener/app/my-alb/xxxxxxxx/yyyyyyyy \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

利用できるポリシーと、それぞれの対応内容を調べるには次のようにします。

```bash
# TLS 1.3 に対応するポリシー名だけを一覧表示
aws elbv2 describe-ssl-policies \
  --query "SslPolicies[?contains(SslProtocols,'TLSv1.3')].Name"

# 特定のポリシーの暗号スイートを確認
aws elbv2 describe-ssl-policies \
  --names ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

### Terraform

`aws_lb_listener` で `ssl_policy` を省略した場合に新しいポリシーになると期待せず、明示的に指定しておくのが安全です。

```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
```

### CloudFormation

```yaml
HttpsListener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    LoadBalancerArn: !Ref LoadBalancer
    Port: 443
    Protocol: HTTPS
    SslPolicy: ELBSecurityPolicy-TLS13-1-2-Res-2021-06
    Certificates:
      - CertificateArn: !Ref Certificate
    DefaultActions:
      - Type: forward
        TargetGroupArn: !Ref TargetGroup
```

セキュリティポリシーの変更に ALB の再作成は不要で、確立済みの接続も切断されません。変更後に始まる TLS handshake から新しいポリシーが適用されます。

## 設定が反映されたか確認する

`openssl` で、古いバージョンが拒否され、新しいバージョンで接続できることを確認します。

```bash
# 失敗するはず：TLS 1.1
openssl s_client -connect example.com:443 -tls1_1 </dev/null

# 成功するはず：TLS 1.2
openssl s_client -connect example.com:443 -tls1_2 </dev/null

# 成功するはず：TLS 1.3
openssl s_client -connect example.com:443 -tls1_3 </dev/null
```

監査の証跡が必要な場合は、`nmap` で実際に受け付けるバージョンと暗号スイートを一覧にできます。

```bash
nmap --script ssl-enum-ciphers -p 443 example.com
```

SSL Labs や社内の脆弱性スキャナーで再スキャンし、レポートを保管しておく方法もあります。

## 複数のリスナーとバックエンド接続の注意点

- 1 つの ALB に複数の HTTPS リスナーがある場合、それぞれのセキュリティポリシーは互いに互換性がなければならず、自由に組み合わせることはできません。
- ALB からバックエンドのターゲットへの HTTPS 接続のポリシーは、**直接指定できません**。フロント側のリスナーのポリシーによって決まります。たとえば TLS 1.3 系のポリシーを使う場合、バックエンドには `ELBSecurityPolicy-TLS13-1-0-2021-06` が使われます。ターゲットが HTTPS の場合は、これらのバージョンと暗号スイートに対応しているか確認が必要です。
- ALB の前段に CloudFront、WAF、他の CDN がある場合、TLS の設定は層ごとに独立しているため、それぞれ確認してください。CloudFront の最低 TLS バージョンは、ディストリビューションのセキュリティポリシーで設定します。
- NLB は別のポリシー一覧を持ち、デフォルト値も異なります。ALB の設定をそのまま NLB に当てはめることはできません。

## 元に戻されないようにする

監査では現状だけでなく、設定が悪化しないための仕組みがあるかも見られます。次のような対策が考えられます。

1. **IaC で明示する**：すべてのリスナーに `ssl_policy` を書き、デフォルト値に頼らない。
2. **AWS Config**：マネージドルールまたはカスタムルールで、リスナーのポリシーを継続的にチェックする。
3. **IAM／SCP の条件**：Elastic Load Balancing には、ユーザーが選べるセキュリティポリシーを制限する条件キーがあります。キー名と書き方は [ELB の IAM ドキュメント](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-authentication-access-control.html)を参照してください。
4. **定期的に見直す**：2025 年に追加された PQ シリーズのように、AWS は新しいポリシーを追加していきます。年に一度は見直すとよいでしょう。

## よくある質問

### セキュリティポリシーを切り替えると ALB は停止しますか？

停止しません。ALB は再作成されず、確立済みの接続にも影響しません。新しい接続だけが新しいポリシーでネゴシエーションされるので、実際のリスクは、古いクライアントが接続できなくなることです。事前に接続ログを確認して把握しておきます。

### TLS 1.0/1.1 を無効にしたいだけなら、どれを選べばよいですか？

`ELBSecurityPolicy-TLS13-1-2-2021-06` です。TLS 1.3 と 1.2 に対応し、`Res` シリーズより互換性が高くなります。監査で CBC の使用も禁止されている場合は、`Res` シリーズにします。

> 私自身の環境では、**ELBSecurityPolicy-TLS-1-2-2017-01** と **ELBSecurityPolicy-TLS13-1-2-Res-2021-06** の両方を使っています。
{: .prompt-info}

### TLS 1.3 だけにできますか？

できます。`ELBSecurityPolicy-TLS13-1-3-2021-06` を使います。ただし、すべてのクライアントが TLS 1.3 に対応していると確認できている場合に限ります。一般公開のサービスでは、通常 TLS 1.2 も残します。

### PQ ポリシーでクライアント側の変更は必要ですか？

不要です。PQ ポリシーは従来の鍵交換にも対応しています。ML-KEM に対応したクライアントではハイブリッドの Post-Quantum 鍵交換が使われ、対応していないクライアントはこれまでどおりの動作になります。

### 切り替えたのに、スキャナーが古いバージョンをまだ許可していると報告するのはなぜですか？

スキャン対象が同じリスナーやドメインか、前段に CloudFront や他のプロキシがないかを確認してください。リスナーのポリシーが実際に適用されているかも確認が必要です。SSL Labs はキャッシュされた結果を返すことがあるため、再スキャン時はキャッシュをクリアするオプションを選びます。
