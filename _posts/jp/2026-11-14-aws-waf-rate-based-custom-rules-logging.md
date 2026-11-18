---
layout: post
title: "AWS WAF 応用編：レートベースのルール、カスタムルール、WAF ログ、Count から Block への切り替え"
description: "Web ACL 入門の続きとして、AWS WAF のレートベースのルールによるレート制限、カスタムルールでの誤検知対策、WAF ログを CloudWatch Logs と S3 のどちらに送るか、ルールを Count から Block に切り替える前に確認すべきデータを整理します。"
author: Mark_Mew
categories: [AWS, WAF & Shield]
tags: [AWS WAF, Rate-based Rule, Web ACL, CloudWatch Logs, Terraform]
keywords: [AWS WAF レートベースのルール, AWS WAF レート制限, AWS WAF カスタムルール, AWS WAF ログ, WAF CloudWatch Logs Insights, WAF ログ S3 Athena, WAF Count Block 切り替え, WAF 誤検知, SizeRestrictions_BODY, aws_wafv2_web_acl_logging_configuration]
lang: ja
date: 2026-11-14
---

[前回の記事](/ja/posts/aws-waf-web-acl-managed-rules-wcu/)では Web ACL を作成し、AWS Managed Rules を Count に設定しました。次に出てくる疑問は、だいたい次のようなものです。ログインページへのブルートフォース攻撃はどう防ぐのか。ルールがファイルアップロードを止めてしまったらどうするのか。しばらく Count で運用したあと、いつ Block に切り替えればよいのか。

先に結論を書いておきます。**レートベースのルールは「同じ送信元からのリクエストが多すぎる」場合に、カスタムルールは「特定の条件での例外や制限」に使います。そして、Count から Block に切り替えられるかどうかを判断する根拠になるのが WAF ログです。** ログを見ずに Block に切り替えるのは、当てずっぽうと変わりません。

## レートベースのルール：ログインページにリクエスト数の上限を設ける

レートベースのルールは、一定時間内のリクエスト数を送信元ごとに数え、上限を超えたら指定したアクションを適用します。よくある使い方は、同じ IP からログイン API へのリクエスト数を制限することです。[AWS：レートベースのルールステートメント](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)

まず押さえておきたい設定項目は次のとおりです。

| 設定 | 内容 |
|---|---|
| 評価ウィンドウ（Evaluation window） | 60、120、300、600 秒から選択。デフォルトは 300 秒 |
| レート制限（Rate limit） | 評価ウィンドウ内に許可するリクエスト数。最小値は 10 |
| 集約（Aggregation） | 送信元 IP、ヘッダー内の IP（`X-Forwarded-For` など）、カスタムキー、またはすべてのリクエストをまとめてカウント |
| スコープダウンステートメント | 条件に一致するリクエストだけをカウント。例：`/login` へのリクエストのみ |
| アクション | Block、Count、CAPTCHA、Challenge |

[AWS：レートベースのルールの主な設定](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)

**スコープダウンステートメントは必ず付ける**ことをおすすめします。付けないと、サイトへのすべてのリクエストがカウント対象になります。1 回のページ表示で静的ファイルへのリクエストが何十件も発生するので、普通の利用者までブロックされかねません。ログイン、会員登録、パスワードリセットなど、悪用されやすいパスだけをカウントすれば、上限値も決めやすく、正規の利用者を巻き込みにくくなります。

もう一つ知っておきたいのは、レートベースのルールはリクエストを 1 件ずつリアルタイムに数えているわけではない、という点です。上限を超えてからアクションが適用されるまでに少し遅延があり、ブロックされるリクエスト数も設定値とぴったり一致するわけではありません。明らかな大量リクエストを止める用途に向いていて、厳密なカウンターとして使うものではありません。[AWS：レートベースのルールの注意事項](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)

### ALB の前に CloudFront がある場合

構成が CloudFront → ALB で、Web ACL を ALB に関連付けている場合、ALB から見える送信元 IP は利用者ではなく CloudFront のエッジサーバーの IP になります。この状態で送信元 IP で集約すると、大勢の利用者を一つの送信元として数えてしまいます。

`X-Forwarded-For` で集約すれば解決しそうに見えますが、WAF が使うのはこのヘッダーの**先頭**の IP で、この値はクライアント側で自由に設定できます。攻撃者がリクエストごとに偽の IP を付ければ、制限をすり抜けられてしまいます。より確実なのは、Web ACL を CloudFront に関連付けて、WAF が実際のクライアント IP を直接見られるようにする方法です。[AWS：転送された IP アドレス](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-forwarded-ip-address.html)

### Terraform の例

前回の `aws_wafv2_web_acl.app` に次のルールを追加します。同じ IP から 5 分以内に `/api/login` へ 100 件を超えるリクエストがあると、`429 Too Many Requests` を返します。デフォルトの Block は `403` を返すため、フロントエンドからはレート制限なのか権限エラーなのか区別しにくくなります。そのため、私は 429 に変えることが多いです。

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

`100` はあくまで例です。実際の値は、正規の利用者がどう使っているかで決まります。たとえば社内システムで全員が同じ送信元 IP を共有しているなら、上限はかなり緩める必要があります。迷ったら、`action` を `count {}` にしてしばらく動かし、通常のピークがどのくらいかをログで確認してから決めてください。[Terraform：rate_based_statement](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

> **Info：** `evaluation_window_sec` は比較的新しい引数です。Terraform AWS Provider のバージョンが古いと認識されないので、エラーになった場合はまず Provider をアップグレードしてください。
{: .prompt-info}

## カスタムルール：マネージドルールでは対応できないこと

マネージドルールは汎用的なルールなので、自分のサイトに合わないケースはいずれ出てきます。そのときは自分でルールを書くことになります。よくあるのは次の二つです。

### 例 1：管理画面へのアクセスを社内 IP に限定する

まず社内の送信元 IP を IP セットに登録し、**パスが `/admin` で始まり、かつ送信元が IP セットに含まれていなければ Block する**というルールを書きます。

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

ここではあえて「社内 IP なら許可」ではなく「社内 IP でなければブロック」と書いています。理由はルールの評価順序です。WAF は `priority` の小さい順にルールを評価し、**Allow か Block に当たった時点で評価を終了**します。それ以降のルールは見られません。優先度の高い Allow ルールを書くと、社内 IP からのリクエストはマネージドルールをすべて素通りすることになり、その送信元に対する防御を事実上オフにしてしまいます。[AWS：ルールアクションと評価順序](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html)

### 例 2：CRS がファイルアップロードをブロックする

CRS を導入したあと、おそらく最もよく出会う誤検知です。CRS の `SizeRestrictions_BODY` はリクエストボディが 8 KB を超えていないかをチェックするため、ファイルアップロードや長いフォームを受け付ける API はすぐに引っかかります。

CRS を丸ごと外してしまうのはもったいないです。よりよい方法は**ラベル**を使うことです。マネージドルールは一致したリクエストにラベルを付けます。そのルールを Count に設定していても同じです。そこで、次のようにします。

1. CRS で `rule_action_override` を使い、`SizeRestrictions_BODY` だけを Count にする。
2. CRS の**後ろ**にカスタムルールを追加し、このラベルが付いていて、かつパスがアップロード API でない場合だけ Block する。

```terraform
# AWSManagedRulesCommonRuleSet の managed_rule_group_statement の中に追加
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

これで、ほかのパスには引き続きボディサイズの制限がかかり、アップロード API だけが例外になります。ラベルを使うルールの `priority` は、必ず CRS より大きく（つまり後に評価されるように）してください。そうしないと、評価の時点でまだラベルが付いておらず、ルールが一致することはありません。[AWS：ラベル一致ルールステートメント](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-label-match.html)、[AWS：CRS のルールとラベル](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)

## WAF ログ：CloudWatch Logs と S3 のどちらに送る？

コンソールのサンプリングされたリクエストで見られるのは直近 3 時間分だけで、誤検知を判断するには足りません。ルールをきちんと調整するなら、WAF のログ記録を有効にする必要があります。[AWS：サンプリングされたリクエストの表示](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing-view-sample.html)

WAF ログの送信先は 3 種類あり、1 つの Web ACL で同時に使えるのは 1 つだけです。

| 送信先 | 向いている用途 | 検索方法 |
|---|---|---|
| CloudWatch Logs | ルールを調整中で、すぐに調べたい | Logs Insights |
| S3 | 長期保存、監査用の保管 | Athena |
| Data Firehose | SIEM やほかの分析基盤に転送したい | 転送先による |

どれを選んでも、**名前は `aws-waf-logs-` で始める必要があります**。たとえばロググループなら `aws-waf-logs-app` のようにします。忘れやすい制約で、名前が合っていないと設定に失敗します。[AWS：ログの送信先](https://docs.aws.amazon.com/waf/latest/developerguide/logging-destinations.html)

私の場合、ルールを調整している数週間は、検索がいちばん速い CloudWatch Logs に送ります。ルールが安定し、監査のために長期保存が必要になったら、保存コストの安い S3 に切り替えます。費用面では、CloudWatch Logs に送る WAF ログは Vended Logs として課金され、トラフィックの多いサイトでは 1 か月でそれなりの金額になります。本番で有効にする前に [CloudWatch の料金](https://aws.amazon.com/cloudwatch/pricing/)を確認しておきましょう。

### 必要なログだけを記録する

トラフィックが多い場合は、ログフィルターで Block と Count のリクエストだけを残し、通常どおり許可されたリクエストは記録しないようにできます。ログの量はかなり減ります。

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

`redacted_fields` を使うと `Authorization` ヘッダーがログ上でマスクされ、トークンがログに残りません。Cookie にセッション情報が入っている場合は、それも一緒にマスクできます。[Terraform：ログ設定](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration)、[AWS：ログのマスクとフィルタリング](https://docs.aws.amazon.com/waf/latest/developerguide/logging-management.html)

> **Warning：** ここには落とし穴があります。`override_action { count {} }` でマネージドルールグループ全体を Count にしている場合、リクエストの最終的な `action` は Web ACL のデフォルトアクションである `ALLOW` になり、**`COUNT` にはなりません**。そのため、上のフィルターでは捨てられてしまいます。観察期間に主にグループ全体を Count にしたマネージドルールを確認したいなら、ログフィルターはまだ付けないか、ラベル条件（`label_name_condition`）で残すようにしてください。
{: .prompt-warning}

### Logs Insights で誤検知を探す

ログが届き始めたら、CloudWatch Logs Insights で `aws-waf-logs-app` を選び、まずはどのルールがどのパスで多くブロックしているかを確認します。

```sql
fields @timestamp, terminatingRuleId, httpRequest.clientIp, httpRequest.uri
| filter action = "BLOCK"
| stats count(*) as requests by terminatingRuleId, httpRequest.uri
| sort requests desc
| limit 20
```

観察期間中に知りたいのは、Count モードの CRS が「何をブロックすることになるか」です。これはラベルで探せます。

```sql
fields @timestamp, httpRequest.clientIp, httpRequest.uri
| filter @message like /awswaf:managed:aws:core-rule-set/
| stats count(*) as hits, count_distinct(httpRequest.clientIp) as ips by httpRequest.uri
| sort hits desc
| limit 20
```

結果は次のように読んでいます。**一致件数が多く、送信元 IP がばらけていて、パスが自分のサイトの通常機能である**なら、誤検知の可能性が高いです。**一致が少数の IP に集中していて、パスが `/wp-login.php` や `/.env` のようにそもそも存在しないもの**なら、スキャナーなのでブロックして問題ありません。[AWS：ログのフィールド](https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html)、[AWS：Logs Insights のクエリ構文](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)

### S3 に送る場合

ログは `AWSLogs/{アカウント ID}/WAFLogs/{リージョン}/{Web ACL 名}/YYYY/MM/dd/HH/mm` というパスに、おおむね 5 分ごとに書き込まれます。検索するには Athena でテーブルを作成して SQL で問い合わせます。テーブル定義は AWS が用意しています。あわせてパーティション射影を使うのがおすすめです。使わないと、データが増えるにつれて毎回のクエリでバケット全体をスキャンすることになります。[AWS：S3 への WAF ログの送信](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)、[Athena：AWS WAF ログのクエリ](https://docs.aws.amazon.com/athena/latest/ug/waf-logs.html)

## Count から Block へ：私のチェックリスト

ここまでの設定は、すべてこのステップのためのものです。私の進め方はおおよそ次のとおりです。

**1. 観察期間は少なくとも業務サイクル 1 回分をカバーする。** 一般的なサイトなら 2 週間ほどですが、月末の締め処理や四半期レポートなど、特定の時期にしか動かない機能があるなら、それが一度動くまで待ちます。誤検知が出やすいのは、普段あまり使われない機能です。

**2. 一致したルールすべてに結論を出す。** 前の節のクエリで、Count モードで一致したルールとパスをすべて洗い出し、それぞれ攻撃なのか誤検知なのかを判断します。誤検知への対処方法は 3 つあり、望ましい順に並べると次のとおりです。

| 対処方法 | 向いているケース |
|---|---|
| ラベル + カスタムルールで例外を作る | 特定のパスだけが誤検知で、ほかのパスにはそのルールが必要 |
| ルールグループにスコープダウンステートメントを追加する | Webhook の受信エンドポイントなど、特定のパスにはルールグループ全体が合わない |
| `rule_action_override` で恒久的に Count のままにする | そのルールが自分のサイトにはまったく意味がない |

**3. 一度に切り替えるのは 1 グループだけ。** Known Bad Inputs のように誤検知の少ないグループから始め、ルール数が多く誤検知も出やすい CRS は最後にします。まとめて切り替えると、問題が起きたときにどのグループが原因か分かりにくくなります。

**4. オフピークの時間帯を選び、ロールバック手段を用意しておく。** Terraform で管理しているメリットはここで効いてきます。ロールバックは、`override_action` を `none {}` から `count {}` に戻して `apply` するだけです。切り替える前に、その PR をすぐマージできる状態にしておきましょう。

**5. 切り替えたあとはメトリクスを見る。** WAF の CloudWatch メトリクスは `AWS/WAFV2` 名前空間にあります。`BlockedRequests` が急に増えていないかを確認し、ALB の `HTTPCode_ELB_4XX_Count` や、サポートへの問い合わせ、利用者からの報告もあわせて見ます。`BlockedRequests` にアラームを設定して、数値がおかしいときに通知させることもできます。[AWS：WAF の CloudWatch メトリクス](https://docs.aws.amazon.com/waf/latest/developerguide/waf-metrics.html)

> **Tip：** AWS はマネージドルールの内容を不定期に更新します。更新で新しい誤検知が出るのが心配なら、`managed_rule_group_statement` の `version` で静的バージョンに固定し、テストしてからアップグレードできます。その代わり、新しい防御も手動でアップグレードするまで有効になりません。[AWS：マネージドルールグループのバージョン管理](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-rule-groups-versioning.html)
{: .prompt-tip}

## よくある質問

### レートベースのルールの上限値はいくつにすべき？

決まった答えはありません。しばらく Count で動かし、評価ウィンドウ内で正規の利用者が送る最大リクエスト数をログから調べ、そこに余裕を持たせて設定します。オフィスや学校、モバイル回線など、送信元 IP を多くの利用者が共有する環境では特に緩めにしてください。

### レートベースのルールでブロックされた IP は、いつ解除されますか？

手動で解除する必要はありません。WAF はカウントを続けていて、その送信元の評価ウィンドウ内のリクエスト数が上限を下回れば、アクションは適用されなくなります。

### WAF がブロックしたリクエストは、バックエンドのアクセスログに残りますか？

残りません。リクエストは WAF の段階で処理され、バックエンドのアプリケーションには届きません。ALB に関連付けている場合は ALB のアクセスログに記録されますが、どのルールに一致したかといった詳しい理由を知るには、やはり WAF ログを見る必要があります。

### WAF のログ記録を有効にすると、サイトのパフォーマンスに影響しますか？

しません。WAF はログを非同期で書き出すため、リクエストのレイテンシーは増えません。主に気にすべきなのは、ログの保存と検索にかかる費用です。

## まとめ

WAF のルールを書くこと自体は難しくありません。難しいのは、自分たちの利用者をブロックしていないと確信できるかどうかです。そのため、この記事ではルールの書き方よりも、ログと切り替えの手順に多くの分量を割きました。まずログを有効にし、Count でデータを集め、そのデータをもとに何をブロックするか決める。最初から全部 Block にして、利用者から報告が来るたびに直すよりも、ずっと楽に進められます。

## 参考資料

### AWS 公式ドキュメント

- [レートベースのルールステートメント](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)
- [レートベースのルールの主な設定](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)
- [レートベースのルールの注意事項](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)
- [転送された IP アドレス](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-forwarded-ip-address.html)
- [ルールアクションと評価順序](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html)
- [ラベル一致ルールステートメント](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-label-match.html)
- [Core Rule Set のルールとラベル](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)
- [サンプリングされたリクエストの表示](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing-view-sample.html)
- [ログの送信先](https://docs.aws.amazon.com/waf/latest/developerguide/logging-destinations.html)
- [ログのマスクとフィルタリング](https://docs.aws.amazon.com/waf/latest/developerguide/logging-management.html)
- [ログのフィールド](https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html)
- [S3 への WAF ログの送信](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)
- [WAF の CloudWatch メトリクス](https://docs.aws.amazon.com/waf/latest/developerguide/waf-metrics.html)
- [マネージドルールグループのバージョン管理](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-rule-groups-versioning.html)
- [CloudWatch Logs Insights のクエリ構文](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Athena：AWS WAF ログのクエリ](https://docs.aws.amazon.com/athena/latest/ug/waf-logs.html)
- [CloudWatch の料金](https://aws.amazon.com/cloudwatch/pricing/)

### Terraform AWS Provider 公式ドキュメント

- [aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [aws_wafv2_ip_set](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set)
- [aws_wafv2_web_acl_logging_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration)
