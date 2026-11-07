---
layout: post
title: "AWS WAF & Shield 入門：從 Web ACL 開始"
description: "接著聊聊 AWS WAF 的 Web ACL 要放在哪裡、AWS 現成規則怎麼選，以及規則容量和費用要怎麼看。"
author: Mark_Mew
categories: [AWS, WAF & Shield]
tags: [AWS WAF, AWS Shield, Web ACL, Managed Rules, WCU]
keywords: [AWS WAF Web ACL, AWS Shield, ALB WAF, API Gateway WAF, AWS Managed Rules, OWASP Top 10, WordPress Rule Set, WCU]
lang: zh-TW
date: 2026-11-07
---

WAF & Shield 是 AWS 安全防護中的產品，其底下 AWS WAF 專門抵禦應用程式的攻擊，也有 AWS Shield 用來抵禦網路層和傳輸層的攻擊。很多人總以為，安全防護產品必然是貴且高不可攀，事實上如果為應用程式搭配 AWS WAF 是能夠簡單且快速達成安全防護的產品。傳統上，我們在地端使用防火牆的時候，都是需要接在數據機上，所有的網路流量都需要過行火牆，防火牆的規則一旦沒有設置好，將造成公司內網路全斷，亦或是無法達到抵禦效果，這類的變更往往需要比較長的陣痛期且缺乏測試環境可應用，而 AWS WAF & Shield 則是屬於非侵入式，採用的是與資源關聯的方式，來將流量轉送至防火牆，有關連到的資源才會採用規則，未關連到的則不受影響，方便先關聯到測試環境，待服務運作及測試妥當後，再關聯到正式環境的資源，可說是相當方便。

## Web ACL 到底是什麼？

看到 AWS Console 把 WAF 和 Shield 放在一起，很容易以為 Web ACL 是兩邊共用的東西。其實 **Web ACL 是 AWS WAF 的設定**：把想檢查的規則放進去，再關聯到網站或 API 的入口，WAF 就會依規則檢查進來的 HTTP(S) 請求。Shield Standard 則是 AWS 自動提供的基礎 DDoS 防護，主要處理網路層和傳輸層的攻擊；Shield Advanced 還有進一步的防護功能。兩者有關聯，但不是建立 Web ACL 才會「開啟」Shield。[AWS：WAF 與 Shield 的差異](https://docs.aws.amazon.com/decision-guides/latest/decision-guides/waf-or-shield.html)、[AWS：Shield Standard](https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html)

Web ACL 裡可以放自己寫的規則，也可以放 AWS 已經準備好的 Managed Rule Groups。規則能依來源 IP、國家、URL 路徑或請求內容來判斷；符合條件時可以放行、阻擋，或先用 **Count** 只記錄命中次數。沒有命中任何規則的請求，則由 Web ACL 的預設動作決定。剛加規則時，先用 Count 看看會比較安心，因為正常使用者的請求長什麼樣，通常要看過實際流量才知道。[AWS：Web ACL](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)、[AWS：測試與調整規則](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## 要把 Web ACL 放在哪裡？

如果網站前面有 **Application Load Balancer（ALB）**，可以把 Web ACL 關聯到 ALB；如果是 **API Gateway REST API**，則是關聯到指定的 Stage。網站若先經過 **CloudFront** 才到後端，也能在 CloudFront Distribution 上關聯 Web ACL，讓請求進入 Origin 前先接受檢查。[AWS：可關聯的資源](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)

這裡有兩個容易踩到的地方。ALB 和 API Gateway REST API 用的是區域型 Web ACL，必須和資源在同一個 Region；CloudFront 使用另一種範圍，建立時對應 `us-east-1`。另外，AWS 文件寫的 API Gateway 支援對象是 **REST API Stage**，不能直接把 HTTP API 當成同一種設定。一個 Web ACL 可以關聯多個符合條件的資源，但單一資源一次只能關聯一個 Web ACL。[AWS：關聯限制](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)、[AWS：保護 API Gateway REST API](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html)

## AWS 已經準備了哪些規則？

自己從零寫規則當然可以，不過剛開始使用 WAF，通常會先看看 AWS Managed Rules。一般網站常從 **Core Rule Set（CRS）** 開始，規則組名稱是 `AWSManagedRulesCommonRuleSet`，目前占 **700 WCU**。AWS 說它涵蓋 OWASP Top 10 等資料提到的*部分*常見高風險漏洞；加上 CRS 並不表示網站已經防住整份 OWASP Top 10。[AWS：Core Rule Set](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)

如果是 **WordPress** 網站，還有 `AWSManagedRulesWordPressRuleSet`，目前占 **100 WCU**，會檢查一些與 WordPress 有關的可利用路徑和請求。AWS 也建議依網站架構，搭配 SQL Database 與 PHP Application 規則組一起評估。規則組不是加得越多越好，還是要看網站實際用了什麼，以及會不會擋到正常功能。[AWS：WordPress 規則組](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)

至於 **Java**，這裡需要特別說明：AWS 目前的官方 Managed Rules 清單裡，沒有獨立叫做「Java Rule Set」的規則組。比較接近的是 **Known Bad Inputs**（`AWSManagedRulesKnownBadInputsRuleSet`，目前 **200 WCU**），裡面有檢查 Java 反序列化和 Log4j 相關攻擊特徵的規則。如果 Console 裡看到其他供應商的 Java 規則組，先確認它是不是 AWS Marketplace 的訂閱項目，費用與維護者可能不同。WAF 也不能代替程式和套件本身的修補。[AWS：Managed Rules 清單](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html)、[AWS：Known Bad Inputs](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)、[AWS：Marketplace 規則組](https://docs.aws.amazon.com/waf/latest/developerguide/marketplace-rule-groups.html)

## 規則加上去，會不會突然變很貴？

AWS 用 **WCU（Web ACL Capacity Units）** 計算規則占用的容量；名稱是 WCU，不是 ACU。每個 Web ACL 目前最多可以使用 **5,000 WCU**，其中 **1,500 WCU** 已包含在基本價格內。超過 1,500 WCU 仍然可以使用，只是會依超出的容量級距增加請求處理費。所以 1,500 是計費門檻，5,000 才是容量上限。[AWS：WCU 與容量上限](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)

拿剛剛提到的三組來算，CRS 700、Known Bad Inputs 200、WordPress 100，加起來是 **1,000 WCU**。這只是示範怎麼看容量，並不是建議每個網站都要一次裝上三組。實際加入規則時，Console 會顯示 Web ACL 使用了多少 WCU，可以邊加邊確認。[AWS：WCU 計算方式](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)

最後還有一件事：**WCU 沒超過 1,500，不代表 WAF 不收費。** Web ACL、規則與請求量本來就有基本費用，部分進階規則組、Marketplace 規則或其他功能也可能另外計費。正式套用前，先估流量、查[官方 WAF 定價頁](https://aws.amazon.com/waf/pricing/)，再讓新規則以 Count 觀察一段時間，特別留意登入、上傳和 API 請求有沒有被誤判。確定正常流量不會受影響，再改成 Block。[AWS：上線前測試建議](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## 用 Terraform 建立 Web ACL

如果原本就用 Terraform 管理 ALB 或 API Gateway，把 WAF 一起寫進去會比較容易追蹤規則是何時加上的。下面先建立一個**區域型** Web ACL，放入 CRS 和 Known Bad Inputs 兩組規則，然後關聯到一個既有資源。這兩組目前合計 **900 WCU**。範例先讓規則只 **Count**，確認沒有誤判後，再決定是否改成阻擋。

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

> **Info：** 查 Terraform 範例時，可能會同時看到 `aws_waf_*`、`aws_wafregional_*` 和本文使用的 `aws_wafv2_*`。前兩種對應 **AWS WAF Classic**（分別用於 CloudFront 和區域型資源），後者對應新版 AWS WAF；資源名稱、規則寫法與關聯方式都不完全一樣，不能只把名稱改成 `wafv2` 就直接沿用。AWS 官方文件將 WAF Classic 列入終止支援流程，並列出 **2025 年 9 月 30 日**為支援終止日；舊版文件或既有設定仍可能看得到，但現在新建 Web ACL 應使用 `aws_wafv2_*`。若手上已有 Classic 資源，先參考官方遷移說明，並查看 AWS Health 裡該 Region 的時程。[AWS：WAF Classic 遷移與時程](https://docs.aws.amazon.com/waf/latest/developerguide/waf-migrating-from-classic.html)、[AWS：新版 WAF API](https://docs.aws.amazon.com/waf/latest/APIReference/)
{: .prompt-info}

`target_arn` 填要保護的資源 ARN。如果是 ALB，可以填現有 `aws_lb` 的 `arn`；如果是 API Gateway REST API，則填 **Stage ARN**，例如現有 `aws_api_gateway_stage` 的 `arn`。不要填 API 的 `execution_arn`，那是另一種用途。這兩種資源都要與 Web ACL 在同一個 Region；也要先確認目標資源目前沒有關聯其他 Web ACL。[Terraform：Web ACL](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)、[Terraform：Web ACL Association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)、[Terraform：API Gateway Stage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)

假設 ALB 和 Web ACL 都在東京，套用時可以傳入 `aws_region = "ap-northeast-1"`，以及 ALB 的 ARN；換成 REST API Stage 時，只要把 `target_arn` 改成該 Stage 的 ARN。若兩個資源真的要共用同一套規則，可以另外建立第二個 `aws_wafv2_web_acl_association`，並讓兩個 association 都指向同一個 Web ACL。**CloudFront 不適用上面的 association 資源**；Terraform 要在 `aws_cloudfront_distribution` 裡設定 `web_acl_id`，Web ACL 的 `scope` 也要改成 `CLOUDFRONT` 並使用 `us-east-1` 的 Provider。[Terraform：CloudFront 關聯方式](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)

範例裡的 `override_action { count {} }` 是把**整個規則組的結果**改成 Count，適合先看它會不會影響請求，但規則組內部仍會在遇到第一條終止規則時停止評估。如果要觀察每條內部規則的命中情況，需要改用 `rule_action_override` 逐條設為 Count。確認後，把規則組改成 `override_action { none {} }`，就會依它原本的動作處理。[AWS：規則組 Count 的限制](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-rule-group-override-options.html)、[Terraform：Managed Rule Group 設定](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

WordPress 網站若要加上專用規則組，可以在同一個 `aws_wafv2_web_acl.app` 裡再加這段 `rule`。不是 WordPress 的網站就不用加：

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

加上後三組合計就是 **1,000 WCU**。改成正式阻擋前，先看一段時間的取樣請求與 Metrics，特別確認登入、後台和外掛功能會不會被擋住。[AWS：WordPress 規則組](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)、[AWS：測試 WAF 規則](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## 結語

想要讓網站或 API 多一層安全防護，其實沒有想像中困難。就像前面說的，可以先從 Web ACL 開始，關聯到測試環境的 ALB 或 API Gateway，看看規則會不會影響正常請求。確認沒問題，再逐步用到正式環境。這樣就能先做起來，也比較容易控制變更帶來的影響。

## 參考資料

### AWS 官方文件

- [AWS WAF 與 Shield 的差異](https://docs.aws.amazon.com/decision-guides/latest/decision-guides/waf-or-shield.html)
- [Shield Standard 概覽](https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html)
- [Web ACL 的設定與運作](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)
- [Web ACL 可關聯的資源與限制](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)
- [使用 WAF 保護 API Gateway REST API](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html)
- [測試與調整 WAF 規則](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)
- [AWS Managed Rules 清單](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html)
- [Core Rule Set 與 Known Bad Inputs](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)
- [WordPress 等應用程式規則組](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)
- [AWS Marketplace 規則組](https://docs.aws.amazon.com/waf/latest/developerguide/marketplace-rule-groups.html)
- [WCU 容量與計算方式](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)
- [AWS WAF 定價](https://aws.amazon.com/waf/pricing/)
- [規則組 Count Override 的行為](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-rule-group-override-options.html)
- [WAF Classic 遷移說明](https://docs.aws.amazon.com/waf/latest/developerguide/waf-migrating-from-classic.html)
- [AWS WAFV2 API 參考](https://docs.aws.amazon.com/waf/latest/APIReference/)

### Terraform AWS Provider 官方文件

- [aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [aws_wafv2_web_acl_association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)
- [aws_api_gateway_stage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)
