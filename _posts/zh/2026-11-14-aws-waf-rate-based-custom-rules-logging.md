---
layout: post
title: "AWS WAF 進階：Rate-based Rule、自訂規則、WAF Logs，以及從 Count 切到 Block"
description: "接續 Web ACL 入門，說明 AWS WAF Rate-based Rule 怎麼設限流、自訂規則怎麼處理誤判、WAF Logs 要送 CloudWatch 還是 S3，以及規則從 Count 改成 Block 前該看哪些資料。"
author: Mark_Mew
categories: [AWS, WAF & Shield]
tags: [AWS WAF, Rate-based Rule, Web ACL, CloudWatch Logs, Terraform]
keywords: [AWS WAF Rate-based Rule, AWS WAF 限流, AWS WAF 自訂規則, AWS WAF Logs, WAF CloudWatch Logs Insights, WAF Logs S3 Athena, WAF Count 改 Block, WAF 誤判, SizeRestrictions_BODY, aws_wafv2_web_acl_logging_configuration]
lang: zh-TW
date: 2026-11-14
---

[上一篇](/posts/aws-waf-web-acl-managed-rules-wcu/)建好了 Web ACL，也把 AWS Managed Rules 設成 Count。接下來的問題通常是：登入頁一直被暴力嘗試要怎麼擋？規則擋到上傳功能怎麼辦？Count 了一陣子，到底什麼時候可以改成 Block？

這篇的結論先放前面：**Rate-based Rule 負責「同一個來源太頻繁」，自訂規則負責「特定條件的例外或限制」，WAF Logs 則是決定能不能從 Count 改成 Block 的依據。** 沒有開 Logs 就改 Block，等於是猜。

## Rate-based Rule：替登入頁加上次數限制

Rate-based Rule 會在一段時間內統計每個來源的請求數，超過上限就套用指定動作。最常見的用法是限制同一個 IP 打登入 API 的次數。[AWS：Rate-based Rule](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)

幾個設定值需要先弄清楚：

| 設定 | 說明 |
|---|---|
| 統計時間（Evaluation window） | 可選 60、120、300、600 秒，預設 300 秒 |
| 上限（Limit） | 統計時間內允許的請求數，最低可設 10 |
| 彙總方式（Aggregation） | 依來源 IP、依 Header 裡的 IP（例如 `X-Forwarded-For`）、依自訂鍵，或不分來源全部一起算 |
| 範圍限縮（Scope-down statement） | 只統計符合條件的請求，例如只算 `/login` |
| 動作 | Block、Count、CAPTCHA、Challenge |

[AWS：Rate-based Rule 設定項目](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)

我會建議**一定要加 Scope-down**。不加的話，整個網站的請求都會被算進去：一個頁面載入時發出幾十個靜態資源請求，正常使用者也可能被擋。只統計登入、註冊、忘記密碼這類容易被濫用的路徑，上限比較好抓，也比較不會誤傷。

另外要知道，Rate-based Rule 不是逐筆即時計算，從超過上限到開始阻擋會有一小段延遲，阻擋的請求數也不會剛好等於設定值。它適合擋明顯的大量請求，不適合當成精確的計次功能。[AWS：Rate-based Rule 的注意事項](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)

### ALB 前面還有 CloudFront 的話

如果架構是 CloudFront → ALB，而 Web ACL 掛在 ALB 上，ALB 看到的來源 IP 會是 CloudFront 節點的 IP，不是使用者的 IP。這時用「來源 IP」彙總，等於是把一大群使用者算成同一個來源。

改用 `X-Forwarded-For` 彙總可以解決這個問題，但 WAF 取的是 Header 裡的**第一個** IP，而這個值是 Client 自己可以塞的，攻擊者每次換一個假 IP 就能繞過限制。比較穩的做法是把 Web ACL 改掛在 CloudFront 上，讓 WAF 直接看到真實來源 IP。[AWS：Forwarded IP 設定](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-forwarded-ip-address.html)

### Terraform 範例

下面這段加在上一篇的 `aws_wafv2_web_acl.app` 裡：同一個 IP 在 5 分鐘內對 `/api/login` 發出超過 100 次請求，就回應 `429 Too Many Requests`。預設的 Block 會回 `403`，前端很難分辨是被限流還是權限不足，所以我習慣改成 429。

```terraform
rule {
  name     = "rate-limit-login"
  priority = 10

  action {
    block {
      custom_response {
        response_code = 429
      }
    }
  }

  statement {
    rate_based_statement {
      limit                 = 100
      evaluation_window_sec = 300
      aggregate_key_type    = "IP"

      scope_down_statement {
        byte_match_statement {
          search_string         = "/api/login"
          positional_constraint = "STARTS_WITH"

          field_to_match {
            uri_path {}
          }

          text_transformation {
            priority = 0
            type     = "LOWERCASE"
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-rate-limit-login"
    sampled_requests_enabled   = true
  }
}
```

`100` 只是範例。實際數字要看正常使用者的行為，例如公司內部系統大家共用同一個出口 IP，上限就要放寬很多。不確定的話，先把 `action` 改成 `count {}` 跑一陣子，從 Logs 看正常尖峰大概落在多少再決定。[Terraform：rate_based_statement](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

> **Info：** `evaluation_window_sec` 是比較新的參數，Terraform AWS Provider 版本太舊的話會不認得，遇到時先升級 Provider。
{: .prompt-info}

## 自訂規則：處理 Managed Rules 管不到的事

Managed Rules 是通用規則，總會碰到不適合自己網站的情況。這時候就要自己寫規則，常見的有兩種。

### 例子一：後台只允許公司 IP

先用 IP Set 存公司出口 IP，再寫一條規則：**路徑是 `/admin` 開頭，而且來源不在 IP Set 裡，就 Block。**

```terraform
resource "aws_wafv2_ip_set" "office" {
  name               = "office-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["203.0.113.0/24"]
}
```

```terraform
rule {
  name     = "admin-office-only"
  priority = 5

  action {
    block {}
  }

  statement {
    and_statement {
      statement {
        byte_match_statement {
          search_string         = "/admin"
          positional_constraint = "STARTS_WITH"

          field_to_match {
            uri_path {}
          }

          text_transformation {
            priority = 0
            type     = "LOWERCASE"
          }
        }
      }

      statement {
        not_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.office.arn
            }
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-admin-office-only"
    sampled_requests_enabled   = true
  }
}
```

這裡刻意寫成「不是公司 IP 就擋」，而不是「是公司 IP 就放行」。原因跟規則的評估順序有關：WAF 依 `priority` 由小到大評估，**遇到 Allow 或 Block 就會停止**，後面的規則都不會再看。如果寫一條優先順序很高的 Allow，公司 IP 的請求就會跳過所有 Managed Rules，等於替這些來源關掉了防護。[AWS：規則的評估順序與動作](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html)

### 例子二：上傳功能被 CRS 擋住

這大概是導入 CRS 後最常遇到的誤判。CRS 裡的 `SizeRestrictions_BODY` 會檢查 Request Body 是否超過 8 KB，上傳檔案或送出較長表單的 API 很容易命中。

直接把整組 CRS 關掉太可惜。比較好的做法是用 **Label**：Managed Rules 命中時會在請求上加 Label，即使該條規則設成 Count 也一樣。所以可以：

1. 在 CRS 裡用 `rule_action_override` 把 `SizeRestrictions_BODY` 單獨改成 Count。
2. 在 CRS **後面**加一條自訂規則：帶有這個 Label，而且路徑不是上傳 API，才 Block。

```terraform
# 在 AWSManagedRulesCommonRuleSet 的 managed_rule_group_statement 裡加上
rule_action_override {
  name = "SizeRestrictions_BODY"

  action_to_use {
    count {}
  }
}
```

```terraform
rule {
  name     = "block-large-body-except-upload"
  priority = 20

  action {
    block {}
  }

  statement {
    and_statement {
      statement {
        label_match_statement {
          scope = "LABEL"
          key   = "awswaf:managed:aws:core-rule-set:SizeRestrictions_Body"
        }
      }

      statement {
        not_statement {
          statement {
            byte_match_statement {
              search_string         = "/api/upload"
              positional_constraint = "STARTS_WITH"

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-block-large-body"
    sampled_requests_enabled   = true
  }
}
```

這樣其他路徑仍然受到 Body 大小的限制，只有上傳 API 例外。Label 規則的 `priority` 一定要比 CRS 大（也就是排在後面），否則評估時 Label 還沒被加上，規則永遠不會命中。[AWS：Label Match 規則](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-label-match.html)、[AWS：CRS 規則與 Label 清單](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)

## WAF Logs：送 CloudWatch 還是 S3？

Console 上的 Sampled Requests 只看得到最近 3 小時的取樣，不夠用來判斷誤判。要認真調整規則，就需要開 WAF Logs。[AWS：Sampled Requests](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing-view-sample.html)

WAF Logs 可以送到三種目的地，一個 Web ACL 一次只能選一種：

| 目的地 | 適合情境 | 查詢方式 |
|---|---|---|
| CloudWatch Logs | 正在調整規則、需要馬上查 | Logs Insights |
| S3 | 長期保存、稽核留存 | Athena |
| Data Firehose | 要轉送到 SIEM 或其他分析平台 | 依目的地而定 |

不論選哪一種，**名稱都必須以 `aws-waf-logs-` 開頭**，例如 Log Group 叫 `aws-waf-logs-app`。這個限制很容易忘，名稱不對就會設定失敗。[AWS：WAF Logs 目的地](https://docs.aws.amazon.com/waf/latest/developerguide/logging-destinations.html)

我的習慣是：調整規則的那幾週先送 CloudWatch Logs，查起來最快；規則穩定之後，如果有稽核需要長期保存，再改送 S3，保存成本比較低。費用的部分，WAF Logs 送 CloudWatch Logs 是用 Vended Logs 計價，流量大的網站一個月下來不便宜，正式開之前先看一下[CloudWatch 定價](https://aws.amazon.com/cloudwatch/pricing/)。

### 只記錄需要的 Log

流量大的話，可以用 Logging Filter 只保留 Block 和 Count 的請求，正常放行的不記錄，Log 量會少很多：

```terraform
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-app"
  retention_in_days = 30
}

resource "aws_wafv2_web_acl_logging_configuration" "app" {
  resource_arn            = aws_wafv2_web_acl.app.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
```

`redacted_fields` 會把 `Authorization` Header 從 Log 裡遮掉，避免 Token 被寫進 Log。Cookie 裡如果有 Session，也可以一起遮。[Terraform：Logging Configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration)、[AWS：Log 欄位遮蔽與過濾](https://docs.aws.amazon.com/waf/latest/developerguide/logging-management.html)

> **Warning：** 這裡有個陷阱。Managed Rule Group 用 `override_action { count {} }` 整組改成 Count 時，請求最後的 `action` 是 Web ACL 的預設動作 `ALLOW`，**不是 `COUNT`**，所以會被上面的 Filter 丟掉。觀察期如果主要是看整組 Count 的 Managed Rules，先不要加 Logging Filter，或者改用 Label 條件（`label_name_condition`）來保留。
{: .prompt-warning}

### 用 Logs Insights 找誤判

Log 進來之後，在 CloudWatch Logs Insights 選 `aws-waf-logs-app`，可以先看哪些規則擋最多、擋在哪些路徑：

```sql
fields @timestamp, terminatingRuleId, httpRequest.clientIp, httpRequest.uri
| filter action = "BLOCK"
| stats count(*) as requests by terminatingRuleId, httpRequest.uri
| sort requests desc
| limit 20
```

觀察期間要看的是 CRS 在 Count 模式下「會擋到什麼」，可以用 Label 找：

```sql
fields @timestamp, httpRequest.clientIp, httpRequest.uri
| filter @message like /awswaf:managed:aws:core-rule-set/
| stats count(*) as hits, count_distinct(httpRequest.clientIp) as ips by httpRequest.uri
| sort hits desc
| limit 20
```

讀結果時我會這樣判斷：**命中次數多、但來源 IP 很分散，而且路徑是自己的正常功能**，誤判的可能性很高；**命中集中在少數 IP，路徑是 `/wp-login.php`、`/.env` 這種根本不存在的東西**，那就是掃描器，擋掉沒有問題。[AWS：WAF Log 欄位說明](https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html)、[AWS：Logs Insights 查詢語法](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)

### 送 S3 的話

Log 會依 `AWSLogs/{帳號}/WAFLogs/{Region}/{Web ACL 名稱}/年/月/日/時/分` 的路徑存放，大約每 5 分鐘寫入一次。要查詢的話，在 Athena 建立 Table 後用 SQL 查，建表語法 AWS 有現成範例，建議搭配 Partition Projection，不然資料一多，每次查詢都會掃整個 Bucket。[AWS：送到 S3 的 WAF Logs](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)、[Athena：查詢 WAF Logs](https://docs.aws.amazon.com/athena/latest/ug/waf-logs.html)

## 從 Count 切到 Block：我的檢查流程

前面的設定都是為了這一步。我自己的流程大致如下：

**1. 觀察期至少涵蓋一個完整的業務週期。** 一般網站兩週左右，但如果有月底結帳、季度報表這類只在特定時間出現的功能，就要等它們跑過一次。誤判最常出現在平常沒人用的功能。

**2. 每一條命中的規則都要有結論。** 用上一節的查詢列出所有在 Count 模式下命中的規則與路徑，逐一判斷是攻擊還是誤判。誤判的處理方式有三種，由好到壞排：

| 做法 | 適合情境 |
|---|---|
| 用 Label + 自訂規則做例外 | 只有特定路徑誤判，其他地方仍需要這條規則 |
| 在規則組加 Scope-down statement | 整組規則都不適合某些路徑，例如 Webhook 接收端 |
| 用 `rule_action_override` 長期保持 Count | 這條規則對自己的網站完全沒意義 |

**3. 一次只切一組。** 先切誤判最少的那一組，例如 Known Bad Inputs；CRS 這種規則多、誤判機率高的放最後。一次全切，出問題時很難知道是哪一組造成的。

**4. 挑離峰時段，並準備好回復方式。** 用 Terraform 管理的好處在這裡：回復就是把 `override_action` 從 `none {}` 改回 `count {}` 再 `apply`。切換前先確認這個 PR 能馬上被合併。

**5. 切換後盯著 Metrics。** WAF 的 CloudWatch Metrics 在 `AWS/WAFV2` 命名空間，可以看 `BlockedRequests` 有沒有突然增加；同時看 ALB 的 `HTTPCode_ELB_4XX_Count` 與客服、使用者回報。也可以替 `BlockedRequests` 設一個 Alarm，數量異常時通知。[AWS：WAF CloudWatch Metrics](https://docs.aws.amazon.com/waf/latest/developerguide/waf-metrics.html)

> **Tip：** AWS 會不定期更新 Managed Rules 的內容。如果怕規則更新後突然出現新的誤判，可以在 `managed_rule_group_statement` 裡用 `version` 固定版本，等測試過再升級。代價是新的防護也要等你手動升級才會生效。[AWS：Managed Rule Group 版本管理](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-rule-groups-versioning.html)
{: .prompt-tip}

## 常見問題

### Rate-based Rule 的上限要設多少？

沒有標準答案。先用 Count 跑一段時間，從 Logs 找出正常使用者在統計時間內的最大請求數，再往上留一些空間。共用出口 IP 的情境（公司、學校、行動網路）要特別放寬。

### 被 Rate-based Rule 擋住的 IP 多久會解除？

不用手動解除。WAF 會持續統計，當該來源在統計時間內的請求數降回上限以下，就不再套用動作。

### WAF 擋掉的請求，後端的 Access Log 看得到嗎？

看不到。請求在 WAF 就被處理掉了，不會到後端應用程式。如果是掛在 ALB 上，ALB Access Log 會有紀錄，但要找完整的原因（命中哪條規則）還是要看 WAF Logs。

### 開 WAF Logs 會影響網站效能嗎？

不會。Log 是 WAF 非同步寫出的，不會增加請求的延遲。主要的考量是 Log 的儲存與查詢費用。

## 結語

WAF 的規則本身不難寫，難的是確定它不會擋到自己人。所以這一篇大部分篇幅花在 Logs 和切換流程，而不是規則語法。先把 Log 開起來，用 Count 收集資料，有了數據再決定要擋什麼，比一開始就全部 Block、等使用者回報再修，來得輕鬆很多。

## 參考資料

### AWS 官方文件

- [Rate-based Rule 概覽](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)
- [Rate-based Rule 設定項目](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)
- [Rate-based Rule 的注意事項](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)
- [Forwarded IP 設定](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-forwarded-ip-address.html)
- [規則動作與評估順序](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html)
- [Label Match 規則](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-label-match.html)
- [Core Rule Set 規則與 Label](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)
- [Sampled Requests](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing-view-sample.html)
- [WAF Logs 目的地](https://docs.aws.amazon.com/waf/latest/developerguide/logging-destinations.html)
- [Log 欄位遮蔽與過濾](https://docs.aws.amazon.com/waf/latest/developerguide/logging-management.html)
- [WAF Log 欄位說明](https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html)
- [送到 S3 的 WAF Logs](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)
- [WAF CloudWatch Metrics](https://docs.aws.amazon.com/waf/latest/developerguide/waf-metrics.html)
- [Managed Rule Group 版本管理](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-rule-groups-versioning.html)
- [CloudWatch Logs Insights 查詢語法](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Athena：查詢 WAF Logs](https://docs.aws.amazon.com/athena/latest/ug/waf-logs.html)
- [CloudWatch 定價](https://aws.amazon.com/cloudwatch/pricing/)

### Terraform AWS Provider 官方文件

- [aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [aws_wafv2_ip_set](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set)
- [aws_wafv2_web_acl_logging_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration)
