---
layout: post
title: "AWS WAF & Shield 入門：Web ACL の仕組みと設定方法"
description: "AWS WAF の Web ACL をどこに関連付けるか、マネージドルールをどう選ぶか、WCU の上限と料金をどう確認するかを整理します。"
author: Mark_Mew
categories: [AWS, WAF & Shield]
tags: [AWS WAF, AWS Shield, Web ACL, Managed Rules, WCU]
keywords: [AWS WAF Web ACL, AWS Shield, ALB WAF, API Gateway WAF, AWS Managed Rules, OWASP Top 10, WordPress Rule Set, WCU]
lang: ja
date: 2026-11-07
---

WAF と Shield は AWS のセキュリティサービスです。AWS WAF はアプリケーションに対する Web 攻撃への対策に使い、AWS Shield は主にネットワーク層とトランスポート層の攻撃に対応します。セキュリティ製品というと、高価で導入が難しい印象があるかもしれません。しかし、アプリケーションに AWS WAF を組み合わせるところからなら、比較的簡単に防御を始められます。オンプレミスのファイアウォールでは、従来、ネットワークの入口に機器を置いてトラフィックを通します。ルールを誤るとネットワーク全体に影響が及び、変更のテストや展開にも時間がかかります。一方 AWS WAF では、保護したい AWS リソースに Web ACL を関連付けます。関連付けていないリソースには影響しないので、まずテスト環境で試し、サービスの動作を確認してから本番環境に広げられます。

## Web ACL とは何か？

AWS コンソールで WAF と Shield が並んでいると、Web ACL が両方に共通する設定のように見えるかもしれません。実際には、**Web ACL は AWS WAF の設定**です。検査したいルールを入れ、Web サイトや API の入口に関連付けると、WAF が受信した HTTP(S) リクエストをルールに照らして評価します。Shield Standard は、主にネットワーク層とトランスポート層を対象とする基本的な DDoS 防御を自動で提供します。Shield Advanced には追加の防御機能があります。両サービスは関連していますが、Web ACL を作ることで Shield を「有効化」するわけではありません。[AWS：WAF と Shield の違い](https://docs.aws.amazon.com/decision-guides/latest/decision-guides/waf-or-shield.html)、[AWS：Shield Standard の概要](https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html)

Web ACL には自分で作ったルールも、AWS が用意したマネージドルールグループ も入れられます。ルールは送信元 IP、国、URL パス、リクエストの内容などで判定でき、一致したリクエストを許可・ブロックしたり、**Count** で一致回数だけ記録したりできます。どのルールにも一致しない場合は、Web ACL のデフォルトアクションに従います。新しいルールはまず Count で様子を見ると安心です。正規の利用者がどんなリクエストを送るかは、実際のトラフィックを見ないと分からないことが多いからです。[AWS：Web ACL](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)、[AWS：ルールのテストと調整](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## Web ACL はどこに関連付ける？

Web サイトの前段に **Application Load Balancer（ALB）** があれば、ALB に Web ACL を関連付けられます。**API Gateway の REST API** なら、対象のステージに関連付けます。バックエンドへ届く前に **CloudFront** を通るサイトでは、CloudFront ディストリビューションに関連付け、オリジンに届く前にリクエストを検査できます。[AWS：関連付け可能なリソース](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)

ここには見落としやすい点が二つあります。ALB と API Gateway REST API にはリージョン型の Web ACL を使い、対象リソースと同じリージョンに置く必要があります。CloudFront は別のスコープを使い、`us-east-1` で管理します。また、AWS の文書で API Gateway の対象となっているのは **REST API のステージ** です。HTTP API も同じ方法で関連付けられると考えないようにしてください。一つの Web ACL を複数の対象リソースに関連付けることはできますが、一つのリソースに同時に関連付けられる Web ACL は一つだけです。[AWS：関連付けの制約](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)、[AWS：API Gateway REST API の保護](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html)

## AWS が用意しているルール

ルールを一から書くこともできますが、WAF を使い始めるなら AWS Managed Rules を見てみるとよいでしょう。一般的な Web サイトでは、**Core Rule Set（CRS）** がよく使われる出発点です。ルールグループ名は `AWSManagedRulesCommonRuleSet` で、現在の文書では **700 WCU** とされています。AWS は、OWASP Top 10 などで取り上げられる高リスクの脆弱性の*一部*を対象にすると説明しています。CRS を追加しただけで、OWASP Top 10 のすべてに対処できたという意味ではありません。[AWS：Core Rule Set](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)

**WordPress** サイトには `AWSManagedRulesWordPressRuleSet` もあり、現在は **100 WCU** です。WordPress に関係する悪用可能なパスやリクエストを検査します。AWS はサイトの構成に応じて、SQL Database や PHP Application のルールグループとの併用も検討するよう勧めています。ルールグループは増やせばよいというものではありません。サイトで実際に何を使っているか、正常な機能に影響しないかを確認する必要があります。[AWS：WordPress ルールグループ](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)

**Java** については補足が必要です。現在の AWS 公式 Managed Rules 一覧には、「Java Rule Set」という独立したルールグループはありません。近いものとして **Known Bad Inputs**（`AWSManagedRulesKnownBadInputsRuleSet`、現在 **200 WCU**）があり、Java のデシリアライズや Log4j に関する攻撃パターンを検査するルールが含まれます。コンソールで別のベンダーによる Java 向けルールグループを見つけたら、AWS Marketplace のサブスクリプションかどうかを確認してください。提供元や料金が異なる場合があります。WAF はアプリケーションや依存ライブラリのパッチ適用の代わりにはなりません。[AWS：Managed Rules 一覧](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html)、[AWS：Known Bad Inputs](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)、[AWS：Marketplace ルールグループ](https://docs.aws.amazon.com/waf/latest/developerguide/marketplace-rule-groups.html)

## ルールを追加すると料金は急に高くなる？

AWS は、ルールが使用する容量を **WCU（Web ACL Capacity Units）** で表します。ACU ではなく WCU です。現在、一つの Web ACL で使用できる上限は **5,000 WCU**、基本料金に含まれるのは **1,500 WCU** までです。1,500 WCU を超えても使用できますが、超過分の容量に応じてリクエスト処理料金が段階的に加算されます。つまり、1,500 は料金上のしきい値、5,000 は容量の上限です。[AWS：WCU と容量制限](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)

先ほどの三つを足すと、CRS が 700、Known Bad Inputs が 200、WordPress が 100 で、合計 **1,000 WCU** です。これは容量の見方を示す例で、すべてのサイトに三つとも入れるという意味ではありません。コンソールではルールを追加しながら Web ACL の WCU 使用量を確認できます。[AWS：WCU の計算](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)

もう一点、**1,500 WCU 以下だから WAF が無料になるわけではありません。** Web ACL、ルール、リクエスト数には基本料金があり、一部の高度なルールグループ、Marketplace ルール、その他の機能には追加料金が発生する場合があります。本番に適用する前にトラフィック量を見積もり、[AWS WAF の公式料金ページ](https://aws.amazon.com/waf/pricing/)を確認しましょう。新しいルールはしばらく Count で観察し、特にログイン、アップロード、API の特殊なパラメータが誤判定されないかを見ます。正常なリクエストへの影響がないことを確認してから Block に切り替えます。[AWS：適用前のテスト](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## Terraform で Web ACL を作る

ALB や API Gateway をすでに Terraform で管理しているなら、WAF もコードに含めると、いつルールを追加したか追いやすくなります。次の例では、**リージョン型** Web ACL を作り、CRS と Known Bad Inputs を追加して、既存のリソースに関連付けます。この二つで現在 **900 WCU** です。まずは結果を **Count** にして、一致するリクエストを確認してからブロックするか判断します。

```terraform
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "aws_region" {
  type = string
}

variable "target_arn" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

resource "aws_wafv2_web_acl" "app" {
  name  = "app-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "app-crs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "app-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "app" {
  resource_arn = var.target_arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}
```

> **Info：** Terraform の例を探すと、`aws_waf_*`、`aws_wafregional_*`、この記事で使う `aws_wafv2_*` が見つかります。最初の二つは **AWS WAF Classic** 用で、それぞれ CloudFront とリージョン型リソースに対応します。最後のものが現行の AWS WAF 用です。リソース名だけでなくルールの書き方や関連付け方も違うため、名前を `wafv2` に変えるだけでは移行できません。AWS の文書では、WAF Classic のサポート終了日が **2025 年 9 月 30 日**とされています。古い文書や既存の設定は残っていても、新規の Web ACL には `aws_wafv2_*` を使います。Classic のリソースがある場合は、公式の移行手順と AWS Health に表示される該当リージョンのスケジュールを確認してください。[AWS：WAF Classic の移行](https://docs.aws.amazon.com/waf/latest/developerguide/waf-migrating-from-classic.html)、[AWS：WAFV2 API](https://docs.aws.amazon.com/waf/latest/APIReference/)
{: .prompt-info}

`target_arn` には保護するリソースの ARN を指定します。ALB なら既存の `aws_lb` の `arn`、API Gateway REST API なら既存の `aws_api_gateway_stage` の `arn` など、**ステージの ARN** を使います。API の `execution_arn` は用途が異なるため、ここには指定しません。対象リソースと Web ACL は同じリージョンに置き、対象に別の Web ACL が関連付けられていないことも確認してください。[Terraform：Web ACL](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)、[Terraform：Web ACL の関連付け](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)、[Terraform：API Gateway Stage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)

たとえば ALB と Web ACL がどちらも東京にあるなら、`aws_region = "ap-northeast-1"` と ALB の ARN を渡します。REST API のステージに変える場合は、`target_arn` をそのステージの ARN に変更します。二つのリソースで同じルールを共有したい場合は、同じ Web ACL を参照する `aws_wafv2_web_acl_association` をもう一つ作れます。**CloudFront には上記の association リソースを使いません。** Terraform では `aws_cloudfront_distribution` の `web_acl_id` を設定し、Web ACL の `scope` を `CLOUDFRONT` に変え、`us-east-1` のプロバイダー を使います。[Terraform：CloudFront の関連付け](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)

例の `override_action { count {} }` は、**ルールグループ全体の結果**を Count に変えます。グループがリクエストに影響しそうかを見ることはできますが、グループ内部の評価は、最初の終端アクションを持つルールに一致すると止まります。内部の各ルールの一致状況を見たい場合は、`rule_action_override` で個別に Count を設定します。元のアクションを使う段階になったら、`override_action { none {} }` に変更します。[AWS：グループ単位の Count の制約](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-rule-group-override-options.html)、[Terraform：Managed Rule Group の設定](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

WordPress サイトなら、同じ `aws_wafv2_web_acl.app` に次の `rule` を追加できます。WordPress を使っていなければ追加する必要はありません。

```terraform
rule {
  name     = "AWSManagedRulesWordPressRuleSet"
  priority = 2

  override_action {
    count {}
  }

  statement {
    managed_rule_group_statement {
      vendor_name = "AWS"
      name        = "AWSManagedRulesWordPressRuleSet"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-wordpress"
    sampled_requests_enabled   = true
  }
}
```

追加すると、三つのグループで合計 **1,000 WCU** になります。ブロックに切り替える前に、しばらくサンプルリクエストとメトリクスを見て、ログイン、管理画面、プラグインの機能が妨げられないか確認してください。[AWS：WordPress ルールグループ](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)、[AWS：WAF ルールのテスト](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## まとめ

Web サイトや API の防御を一段増やすことは、思ったほど難しくありません。最初に述べたように、まずは Web ACL から始め、テスト環境の ALB や API Gateway に関連付けて、正常なリクエストに影響しないか確かめられます。問題がなければ、少しずつ本番環境へ広げます。こうすれば、防御を始めながら変更の影響も把握しやすくなります。

## 参考資料

### AWS 公式ドキュメント

- [AWS WAF と Shield の違い](https://docs.aws.amazon.com/decision-guides/latest/decision-guides/waf-or-shield.html)
- [Shield Standard の概要](https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html)
- [Web ACL の設定](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)
- [関連付け可能なリソースと制約](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)
- [WAF による API Gateway REST API の保護](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html)
- [WAF ルールのテストと調整](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)
- [AWS Managed Rules 一覧](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html)
- [Core Rule Set と Known Bad Inputs](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)
- [WordPress などの用途別ルールグループ](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)
- [AWS Marketplace のルールグループ](https://docs.aws.amazon.com/waf/latest/developerguide/marketplace-rule-groups.html)
- [WCU の容量と計算](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)
- [AWS WAF の料金](https://aws.amazon.com/waf/pricing/)
- [ルールグループの Count Override の動作](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-rule-group-override-options.html)
- [WAF Classic からの移行](https://docs.aws.amazon.com/waf/latest/developerguide/waf-migrating-from-classic.html)
- [AWS WAFV2 API リファレンス](https://docs.aws.amazon.com/waf/latest/APIReference/)

### Terraform AWS Provider 公式ドキュメント

- [aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [aws_wafv2_web_acl_association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)
- [aws_api_gateway_stage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)
