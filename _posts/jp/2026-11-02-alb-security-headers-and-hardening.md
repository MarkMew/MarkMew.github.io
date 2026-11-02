---
layout: post
title: "バックエンドを変更せずに、ALB の設定で脆弱性スキャンの指摘 7 項目に対処する"
description: "HTTP Request Smuggling、無効なヘッダー、弱い暗号スイート、HSTS、X-Content-Type-Options、X-Frame-Options、CSP という 7 つの代表的なスキャン指摘について、ALB の属性、リスナー属性、セキュリティポリシーでどこまで対処できるかを、AWS CLI、Terraform、確認方法とあわせて整理します。"
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, Security, HTTP, TLS, Terraform]
keywords: [ALB desync mitigation mode, ALB drop invalid header fields, ALB HSTS, ALB X-Frame-Options, ALB Content-Security-Policy, ALB リスナー属性, ALB レスポンスヘッダー, ALB セキュリティヘッダー Terraform]
lang: ja
date: 2026-11-02
---

**脆弱性スキャンの指摘のうち、いくつかの代表的な項目は、バックエンドのコードを変更しなくても ALB の設定で対処できます。** HTTP Request Smuggling、無効な HTTP ヘッダー、弱い暗号スイート、そして HSTS、`X-Content-Type-Options`、`X-Frame-Options`、`Content-Security-Policy` といったレスポンスヘッダーの未設定が該当します。ただし、これらの設定でできるのはリスクの低減までです。アプリケーション自体のセキュリティ設計の代わりにはなりませんし、特に CSP は汎用的な値をそのまま適用することはできません。[Application Load Balancer の HTTP ヘッダー変更（AWS）](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html)

TLS については前回の記事 [ALB のセキュリティポリシーを見直す](/posts/alb-security-policy-upgrade-from-2016-08/) で詳しく扱っているため、この記事では暗号スイートの項目で要点だけを紹介します。残りの 6 項目は ALB の設定を中心に、AWS CLI と Terraform の両方で紹介します。

## ALB のアーキテクチャ上の位置づけ

ALB は、クライアントとバックエンドの間にある終端です。クライアントの HTTP リクエストをまず ALB が解析してからターゲットに転送し、TLS も ALB で終端し、レスポンスを ALB がクライアントに返します。この 3 つを ALB が担っているため、リクエストの解析方法、TLS ポリシー、レスポンスのヘッダーを、この層で調整できます。

設定の階層は 3 種類あり、それぞれ設定場所が異なります。

| 階層 | 設定場所 | この記事で使う項目 |
|---|---|---|
| ロードバランサー属性 | ALB 全体 | `routing.http.desync_mitigation_mode`、`routing.http.drop_invalid_header_fields.enabled` |
| リスナー | HTTPS リスナーのセキュリティポリシー | `ssl-policy` |
| リスナー属性 | 個別のリスナー | `routing.http.response.*.header_value`（HSTS、X-Content-Type-Options、X-Frame-Options、CSP） |

レスポンスヘッダーの 4 項目は**リスナー属性**です。ロードバランサーではなく、リスナーごとに設定します。ヘッダーの変更機能はデフォルトで無効になっており、リスナーごとに有効化する必要があります。

## 設定の一覧

| スキャンの指摘 | ALB の設定 | 階層 | 推奨値 | ほかに必要な対応 |
|---|---|---|---|---|
| HTTP Request Smuggling | `routing.http.desync_mitigation_mode` | ロードバランサー | `defensive`（デフォルト）または `strictest` | バックエンド Web サーバーの HTTP 解析、WAF |
| Invalid HTTP Headers | `routing.http.drop_invalid_header_fields.enabled` | ロードバランサー | `true` | 規格に合わないその他のリクエストへのバックエンド側の対応 |
| Weak SSL Cipher Suites | セキュリティポリシー | リスナー | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` | ALB の前段の CloudFront やプロキシ、ALB からターゲットへの HTTPS |
| HSTS 未設定 | `routing.http.response.strict_transport_security.header_value` | リスナー属性 | `max-age=31536000` | サイト全体で HTTPS が使える状態 |
| X-Content-Type-Options 未設定 | `routing.http.response.x_content_type_options.header_value` | リスナー属性 | `nosniff` | バックエンドが正しい `Content-Type` を返すこと |
| X-Frame-Options 未設定 | `routing.http.response.x_frame_options.header_value` | リスナー属性 | `SAMEORIGIN` または `DENY` | 埋め込みが必要な場合は CSP の `frame-ancestors` を使う |
| CSP 未設定 | `routing.http.response.content_security_policy.header_value` | リスナー属性 | サイトのリソースに合わせて調整 | アプリケーション側の出力エスケープとリソース管理 |

## 1. HTTP Request Smuggling

HTTP Request Smuggling（HTTP Desync とも呼ばれます）は、フロントエンドのプロキシとバックエンドの Web サーバーで、同じリクエストの境界の判断が食い違うことで起こります。たとえば、`Content-Length` が複数ある場合や、`Content-Length` と `Transfer-Encoding` が同時にある場合、2 つの層がそれぞれ異なる数のリクエストとして解釈することがあり、攻撃者は同じ接続の中に余分なリクエストを紛れ込ませることができます。

ALB の **Desync mitigation mode** は、各リクエストを脅威レベルで分類し、選択したモードに応じて処理を決めます。

| 分類 | 説明 | `monitor` | `defensive` | `strictest` |
|---|---|---|---|---|
| Compliant | RFC 7230 に準拠しており、既知のリスクがない | 許可 | 許可 | 許可 |
| Acceptable | RFC 7230 に準拠していないが、既知のリスクはない | 許可 | 許可 | ブロック |
| Ambiguous | RFC 7230 に準拠しておらず、Web サーバーやプロキシによって解釈が異なる可能性がある | 許可 | 許可（ただしクライアントとターゲットの接続を閉じる） | ブロック |
| Severe | セキュリティリスクが高い | 許可 | ブロック | ブロック |

ブロックされたリクエストには 400 が返され、クライアントの接続は閉じられます。[Desync mitigation mode（AWS）](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html)

運用上のポイントは次のとおりです。

- **デフォルトがすでに `defensive` です。** そのため多くの ALB では特別な設定は不要です。ただし IaC で明示しておくと、あとから気づかないうちに変更されることを防げます。
- `monitor` は何もブロックしないため、観察用途にだけ向いています。準拠していないリクエストがあると CloudWatch メトリクスの `DesyncMitigationMode_NonCompliant_Request_Count` が増え、アクセスログにも分類結果が記録されます。
- `strictest` は RFC 7230 に準拠したリクエストだけを通します。古いクライアントや特殊なツールが Acceptable レベルのリクエストを送っている場合は拒否されます。切り替える前に `monitor` や `defensive` の状態でアクセスログを確認し、準拠していないトラフィックがないことを確かめてください。
- `defensive` モードで Ambiguous なリクエストが大量に届くと、追加料金が発生する可能性があります。詳細は上記の AWS ドキュメントを参照してください。

> この設定で下がるのは、ALB の層で Desync が起きるリスクです。バックエンド Web サーバー自身の HTTP 解析が安全になるわけではありません。AWS のドキュメントには、ALB がどの攻撃パターンを具体的にカバーするかは記載されていないため、「完全に修正できる」とは書きません。
{: .prompt-warning}

## 2. Invalid HTTP Headers

HTTP ヘッダーのフィールド名には形式の制約があります。Elastic Load Balancing は、ヘッダー名に英数字とハイフン（`-`）だけを使うことを要求しています。アンダースコアや空白などの文字が含まれていると、プロキシや Web サーバーによって扱いが異なり、無視するものもあれば、正規化して転送するものもあります。この差がチェックの回避に悪用される可能性があります。

`routing.http.drop_invalid_header_fields.enabled` を `true` にすると、ALB は無効なフィールド名を持つヘッダーを削除します。デフォルトは `false` で、そのままターゲットに転送されます。[modify-load-balancer-attributes（AWS）](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-load-balancer-attributes.html)

この設定の対象範囲には注意が必要です。

- 対象は「**ヘッダーのフィールド名が無効な場合**」だけで、HTTP 規格に反するすべてのリクエストではありません。リクエスト自体の形式の問題（前の項目の Content-Length の競合など）には Desync mitigation で対応します。
- 有効にすると、アンダースコアを含むフィールド名（たとえば独自の `X_Api_Key`）を使っているクライアントや社内システムのヘッダーは ALB で削除され、バックエンドに届かなくなる可能性があります。有効化の前に、クライアントが実際に送っているヘッダー名を確認してください。

この 2 つの設定はよくセットで語られますが、対処している問題は別のものです。両方を有効にすることをおすすめします。

## 3. Weak SSL Cipher Suites

ALB の TLS バージョンと暗号スイートは、HTTPS リスナーのセキュリティポリシーで決まります。カスタマイズはできず、AWS が提供する一覧から選ぶ形になります。スキャナーが指摘しやすいのは、TLS 1.0、TLS 1.1、CBC モードの暗号スイート、Forward Secrecy を持たない RSA 鍵交換です。TLS 1.3 では AEAD 暗号だけが残り、Forward Secrecy を持つ鍵交換が必須になります。

一般的な現代の Web システムであれば、`ELBSecurityPolicy-TLS13-1-2-Res-2021-06` が適しています。TLS 1.3 と 1.2 に対応し、TLS 1.0/1.1 と CBC の暗号スイートを含みません。AWS が現在推奨しているのは PQ 系の `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` です。両者の選び方、クライアントの互換性の確認、切り替えの手順は[前回の記事](/posts/alb-security-policy-upgrade-from-2016-08/)を参照してください。[Application Load Balancer のセキュリティポリシー（AWS）](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)

この設定が影響するのは、クライアントから ALB までの区間だけです。CloudFront、ほかの CDN、プロキシの TLS 設定は別に確認する必要があります。

## 4. HSTS 未設定

HSTS（HTTP Strict Transport Security）は、「このサイトには HTTPS だけでアクセスする」とブラウザーに伝えるレスポンスヘッダーです。ブラウザーはこのヘッダーを受け取ると、`max-age` の期間中は、ユーザーが `http://` と入力したり古い HTTP のリンクをクリックしたりしても、HTTP リクエストを送らずに自動的に HTTPS に切り替えます。これにより、HTTPS ダウングレードや SSL Stripping のリスクを下げられます。

| ディレクティブ | 説明 |
|---|---|
| `max-age=<秒>` | ブラウザーが「HTTPS のみ」を記憶する期間 |
| `includeSubDomains` | すべてのサブドメインにもポリシーを適用する |
| `preload` | ブラウザーに組み込まれた HSTS Preload リストへの登録を申請する。`max-age` が `31536000` 以上で、`includeSubDomains` が必須 |

[Strict-Transport-Security — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security)

導入前に確認しておくこと：

- **サイト全体（`includeSubDomains` を付ける場合はサブドメインも）が HTTPS で利用できること。** ブラウザーが一度記憶すると、証明書の期限切れや HTTPS の障害が起きたときに、ユーザーは警告を無視して先に進むことができません。
- HSTS が有効になるのは HTTPS のレスポンスだけです。ブラウザーは HTTP のレスポンスに含まれるこのヘッダーを無視します。
- `preload` に一度登録されると、削除するのは容易ではありません。すべてのサブドメインを洗い出すまでは `preload` を付けないことをおすすめします。

本番環境では、`max-age` を段階的に長くすることをおすすめします。たとえば次のようにします。

| 段階 | 値 |
|---|---|
| 1 | `max-age=300`（5 分） |
| 2 | `max-age=86400`（1 日） |
| 3 | `max-age=604800`（1 週間） |
| 4 | `max-age=31536000`（1 年） |

各段階でしばらく様子を見て、問題がなければ次に進みます。バックエンドがすでに同じヘッダーを返している場合、ALB で有効にすると設定値で**上書き**されるため、HSTS ヘッダーが重複することはありません。

> Terraform の公式ドキュメントでは、`routing_http_response_strict_transport_security_header_value` の説明に、デフォルト値が `max-age=31536000; includeSubDomains; preload` であると書かれていますが、このデフォルト値がどのような場合に適用されるかは説明されていません。**この点は未確認です。** デフォルトに頼らず、設定したい値を明示してください。
{: .prompt-warning}

## 5. X-Content-Type-Options 未設定

`Content-Type` と実際の内容が一致しない場合、ブラウザーによっては内容の種類を自分で推測しようとします。これを MIME タイプスニッフィングと呼びます。たとえば、サーバーがユーザーのアップロードしたファイルを `text/plain` としていても、ブラウザーが HTML や JavaScript のようだと判断して実行可能なコンテンツとして扱うと、悪用される可能性があります。

`X-Content-Type-Options: nosniff` は、推測せずに `Content-Type` に従うようブラウザーに指示します。ALB の対応する属性が受け付ける値は `nosniff` だけです。

7 項目の中で互換性のリスクが最も低い設定です。前提は、バックエンドが正しい `Content-Type` を返していることだけです。そうでないと、ブラウザーが推測してくれたおかげで読み込めていた JS や CSS が拒否されるようになります。このヘッダーで下がるのは MIME の混同によるリスクで、XSS を防ぐ設定ではありません。

## 6. X-Frame-Options 未設定

クリックジャッキングは、攻撃者が対象サイトを自分のページの `iframe` に埋め込み、透明なレイヤーを重ねてユーザーにクリックさせる攻撃です。ユーザーは攻撃者のページを操作しているつもりでも、実際には対象サイト上のボタンをクリックしています。

`X-Frame-Options` は、ページを埋め込んでよいかどうかを制御します。

| 値 | 説明 |
|---|---|
| `DENY` | 同一オリジンを含め、どのサイトからも埋め込めない |
| `SAMEORIGIN` | 同一オリジンのページだけが埋め込める |
| `ALLOW-FROM <origin>` | 廃止済み。最近のブラウザーはヘッダー全体を無視する |

[X-Frame-Options — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options)

Terraform のフィールドの説明には `ALLOW-FROM` が載っていますが、最近のブラウザーでは無視されるため、**使わないことをおすすめします。**

この設定はすべてのサイトに合うわけではありません。

- ほかのドメインから iframe で埋め込まれるサイト（たとえばパートナー向けに提供するウィジェット）では、`DENY` も `SAMEORIGIN` も埋め込みができなくなります。その場合は CSP の `frame-ancestors` を使い、埋め込みを許可するオリジンを指定してください。
- サイト内で同一オリジンの iframe を使っている場合（たとえば管理画面でレポートを iframe で読み込んでいる場合）は、`SAMEORIGIN` を使います。
- ALB のこの属性は値を 1 つしか持てず、**すべてのパスで共通**です。パスごとに値を変えたい場合は、バックエンドで対応する必要があります。

MDN は、`X-Frame-Options` に代わるものとして CSP の `frame-ancestors` ディレクティブを推奨しています。複数のオリジンを指定できるため、柔軟性が高くなります。両方が同時にある場合の優先順位は、MDN の 2 つのページには書かれていません。両方を設定する場合は、利用するブラウザーで実際に確認することをおすすめします。

## 7. Content-Security-Policy 未設定

CSP は、どのオリジンのリソースの読み込みと実行を許可するかをサイトがブラウザーに伝える仕組みです。XSS が成功した場合の影響を小さくしたり、悪意のあるリソースの読み込みを制限したりできますが、**多層防御の 1 つであり、XSS の修正ではありません。** アプリケーション側での適切な出力エスケープと入力検証は引き続き必要です。

主なディレクティブ：

| ディレクティブ | 用途 |
|---|---|
| `default-src` | 個別に指定しなかったリソースの種類のデフォルトの許可元 |
| `script-src` | JavaScript の許可元 |
| `style-src` | CSS の許可元 |
| `img-src` | 画像の許可元 |
| `connect-src` | `fetch`、XHR、WebSocket が接続できる先 |
| `frame-ancestors` | このページを iframe に埋め込んでよい許可元 |
| `object-src` | `<object>` と `<embed>` の許可元 |
| `base-uri` | `<base>` 要素で使える URL |

CSP には**汎用的な設定がありません**。サイトごとに読み込むリソースが異なるためです。利用している CDN、Google Analytics、フォントサービス、インラインスクリプト、外部のログインサービスなどを、すべて列挙する必要があります。厳しすぎると、画像が表示されない、スタイルが崩れる、ログインや決済の外部コンポーネントが動かなくなる、といった問題が起きます。緩すぎる（たとえば `'unsafe-inline'` を多用する）と、保護の効果はあまり期待できません。

### Report-Only で段階的にテストする

一般的な進め方は、まず `Content-Security-Policy-Report-Only` を使うことです。違反を報告するだけでブロックはしないため、しばらくレポートを集めてから、本番のポリシーに切り替えます。

> **ALB には `Content-Security-Policy-Report-Only` に対応するリスナー属性がありません。** AWS のヘッダー変更のドキュメントを確認したところ、CSP のレスポンスヘッダーの属性は `content_security_policy` だけで、Report-Only 版はありませんでした。Report-Only でテストするには、バックエンドのアプリケーションや Web サーバーからこのヘッダーを返す必要があります。あるいは、テスト環境で先に ALB の設定を適用し、問題がないことを確認してから本番に反映します。
{: .prompt-warning}

また、ALB の `content_security_policy` 属性が `report-to` などの指定に対応しているかはドキュメントに書かれておらず、ヘッダーの値には使える文字の制限もあります（後述の注意事項を参照）。レポート機能を使う場合は、先にテスト環境で確認してください。

### デモ用の CSP

以下はあくまで例です。**そのまま本番で使わないでください。** 実際のサイトのリソースに合わせて調整する必要があります。

```text
default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'
```

この設定では同一オリジンからの読み込みだけが許可されます。インラインスクリプトとインラインスタイルはブロックされるため、それらを使っているページでは表示が崩れます。

## 実際の設定手順

### コンソール

**ロードバランサー属性**（Desync mitigation mode、Drop invalid header fields）：

EC2 → ロードバランサー → ALB を選択 → 属性 → 編集 → **パケット処理** で Desync mitigation mode と Drop invalid header fields を設定 → 変更を保存。

**セキュリティポリシー**：

EC2 → ロードバランサー → ALB を選択 → リスナーとルール → HTTPS:443 を選択 → リスナーの管理 → リスナーの編集 → セキュリティポリシー。

**リスナー属性**（レスポンスヘッダー）：

EC2 → ロードバランサー → ALB を選択 → リスナーとルール → リスナーを開く → 属性 → 編集 → **レスポンスヘッダーを追加** を展開し、追加するヘッダーを有効にして値を入力 → 変更を保存。

### AWS CLI

ロードバランサー属性：

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN> \
  --attributes \
    Key=routing.http.desync_mitigation_mode,Value=defensive \
    Key=routing.http.drop_invalid_header_fields.enabled,Value=true
```

セキュリティポリシー：

```bash
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

リスナー属性。CSP の値には空白とセミコロンが含まれるため、JSON 形式のほうがミスが起きにくくなります。

```bash
aws elbv2 modify-listener-attributes \
  --listener-arn <LISTENER_ARN> \
  --attributes '[
    {"Key":"routing.http.response.strict_transport_security.header_value","Value":"max-age=31536000"},
    {"Key":"routing.http.response.x_content_type_options.header_value","Value":"nosniff"},
    {"Key":"routing.http.response.x_frame_options.header_value","Value":"SAMEORIGIN"},
    {"Key":"routing.http.response.content_security_policy.header_value","Value":"default-src '\''self'\''; img-src '\''self'\'' data:; script-src '\''self'\''; style-src '\''self'\''; object-src '\''none'\''; base-uri '\''self'\''; frame-ancestors '\''self'\''"}
  ]'
```

> CSP の値にはシングルクォートが含まれるため、Bash のシングルクォートで囲んだ文字列の中では `'\''` と書く必要があり、読みにくくなります。避けたい場合は、JSON をファイルに保存して `--attributes file://listener-attributes.json` で渡すこともできます。
{: .prompt-info}

### Terraform

ロードバランサー属性は `aws_lb` に、リスナー属性は `aws_lb_listener` の引数として直接指定します。別のブロックではありません。

```terraform
resource "aws_lb" "main" {
  name               = "my-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  desync_mitigation_mode     = "defensive"
  drop_invalid_header_fields = true
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  routing_http_response_strict_transport_security_header_value = "max-age=31536000"
  routing_http_response_x_content_type_options_header_value    = "nosniff"
  routing_http_response_x_frame_options_header_value           = "SAMEORIGIN"
  routing_http_response_content_security_policy_header_value   = "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
```

これらのフィールド名は、`hashicorp/terraform-provider-aws` の `aws_lb_listener` のドキュメントで確認しています。**どのバージョン以降の provider が対応しているかは確認できておらず、未確認です。** `terraform validate` でこれらの引数が認識されないと表示された場合は、先に provider をアップグレードしてください。

## 設定の確認

### AWS CLI

```bash
# ロードバランサー属性
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN> \
  --query "Attributes[?Key=='routing.http.desync_mitigation_mode' || Key=='routing.http.drop_invalid_header_fields.enabled']"

# リスナー属性
aws elbv2 describe-listener-attributes \
  --listener-arn <LISTENER_ARN>

# セキュリティポリシー
aws elbv2 describe-listeners \
  --listener-arns <LISTENER_ARN> \
  --query "Listeners[0].SslPolicy"
```

### レスポンスヘッダーの確認

```bash
curl -sI https://example.com
```

次のようなヘッダーが返ってくるはずです。

```text
strict-transport-security: max-age=31536000
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
content-security-policy: default-src 'self'; ...
```

ブラウザーでも、デベロッパーツールの Network タブで任意のリクエストを選び、Headers でレスポンスヘッダーを確認できます。CSP が厳しすぎる場合、違反は Console タブに表示されます。

### TLS の確認

```bash
# 失敗するはず：TLS 1.1
openssl s_client -connect example.com:443 -tls1_1 </dev/null

# 成功するはず：TLS 1.2 と 1.3
openssl s_client -connect example.com:443 -tls1_2 </dev/null
openssl s_client -connect example.com:443 -tls1_3 </dev/null
```

対応しているすべての暗号スイートを一覧にするには、`nmap --script ssl-enum-ciphers -p 443 example.com` や SSL Labs を使います。

### 簡単なツールで確認できる設定

| 設定 | `describe-*` | `curl -I` | `openssl` | その他 |
|---|---|---|---|---|
| Desync mitigation | 設定値を確認できる | 不可 | 不可 | アクセスログの分類と CloudWatch メトリクス、または専用のセキュリティテストツール |
| Drop invalid header | 設定値を確認できる | 不向き | 不可 | 無効なフィールド名を含むリクエストを送り、バックエンドに届くか確認する |
| セキュリティポリシー | ポリシー名を確認できる | 不可 | 可 | `nmap`、SSL Labs |
| HSTS、nosniff、XFO、CSP | 設定値を確認できる | 可 | 不可 | ブラウザーのデベロッパーツール |

Request Smuggling を実際に検証するには、リクエストを手作業で組み立てて、各層での解析結果を比べる必要があります。`curl -I` ではできません。適切なセキュリティテストツールを使い、テストの許可を得た環境でのみ実施してください。

## 注意事項と制限

- **スキャンの指摘、設定の不備、実際の悪用可能性を区別してください。** ヘッダーが付いていないのは設定上の不備であり、サイトが必ず攻撃されるという意味ではありません。逆に、ヘッダーを追加しても脆弱性が修正されたことにはなりません。
- **ヘッダー値の制限**：値に使えるのは英数字と特定の記号だけで、1K バイトを超えることはできません。ALB は基本的な形式のチェックしか行わず、その値がそのヘッダーとして意味を持つかは確認しないため、誤った値でも拒否されません。空の値を設定するとデフォルトの動作に戻ります。[ヘッダー変更の制限事項（AWS）](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html)
- **バックエンドがすでに同じヘッダーを返している場合**：ALB が設定値で上書きします。パスごとに異なる値が必要な場合（たとえばページごとに異なる `X-Frame-Options`）は、ALB の単一の設定では対応できません。
- **ALB 自身が生成するレスポンス**（固定レスポンスや 5xx のエラーページなど）にこれらのヘッダーが付くかどうかは、公式ドキュメントに説明が見つからなかったため、**未確認です。**
- **HTTP リスナー**：レスポンスヘッダーの属性が HTTPS のみ対象かどうかは、ドキュメントに明確な記載がありません。HSTS は HTTP のレスポンスではブラウザーに無視されるため、実際には HTTPS リスナーにだけ設定すれば十分です。
- **ALB の設定は、アプリケーションのセキュリティ設計や AWS WAF の代わりにはなりません。** SQL インジェクション、XSS、アクセス制御の問題には、引き続きアプリケーションと WAF で対応する必要があります。
- **IaC で明示的に指定してください。** Desync mitigation のデフォルトは `defensive` ですが、`drop_invalid_header_fields` のデフォルトは `false` で、CLI や CloudFormation でのセキュリティポリシーのデフォルトも古い `ELBSecurityPolicy-2016-08` のままです。デフォルト値に頼らないでください。

## よくある質問

### これらの設定を変更すると、既存の接続は切断されますか？

ロードバランサー属性とリスナー属性の変更は、新しいリクエストに適用されます。実際のリスクは互換性です。`strictest` では準拠していないクライアントがブロックされる可能性があり、無効なヘッダーの削除では独自のヘッダーが消える可能性があり、CSP ではページの機能が崩れる可能性があります。HSTS は、設定を誤ると、ブラウザーがしばらくその内容を記憶し続けます。

### ALB の設定だけで脆弱性スキャンに通りますか？

必ずしもそうとは限りません。スキャナーによって判定基準が異なり、CSP の内容が緩すぎないか、といった項目はサイトのリソースに合わせた調整が必要です。ALB で対処できるのは一部で、残りはバックエンドと WAF に依存します。

### CSP を最も厳しい設定にしてはいけませんか？

最も厳しい CSP は、インラインスクリプト、外部リソース、`eval` をブロックします。サイトが使っているリソースを洗い出さずに適用すると、ページが簡単に壊れてしまいます。まずテスト環境で違反を集め、段階的に調整することをおすすめします。

## まとめ

7 項目のうち、Desync mitigation、無効なヘッダーの削除、セキュリティポリシーは ALB の層の設定で、HSTS、`X-Content-Type-Options`、`X-Frame-Options`、CSP は ALB が付与を手伝うレスポンスヘッダーです。`nosniff` はリスクが最も低く、HSTS は `max-age` を段階的に長くし、`X-Frame-Options` は iframe を使うかどうかで判断し、CSP は必ずサイトのリソースに合わせて調整したうえで、ALB 以外の場所で Report-Only を使ってテストする必要があります。

ALB の設定は補強であり、代替ではありません。バックエンドの HTTP 解析、アプリケーションのセキュリティ設計、WAF も、引き続き全体の防御の一部です。

## 参考ドキュメント

- [HTTP header modification for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html)：レスポンスヘッダーの属性、値の制限、上書きの動作。
- [Enable HTTP header modification](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-header-modification.html)：コンソールの手順とヘッダー変更の属性一覧。
- [Edit load balancer attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html)：Desync mitigation mode の分類と各モードの動作。
- [modify-load-balancer-attributes — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-load-balancer-attributes.html)：`drop_invalid_header_fields` などの属性の説明。
- [modify-listener-attributes — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-listener-attributes.html)：リスナー属性の CLI の構文。
- [Security policies for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)：ALB が対応するセキュリティポリシー。
- [HTTP Request Smuggling on AWS — Virtue Security](https://www.virtuesecurity.com/kb/http-request-smuggling-aws/)：ALB の無効なヘッダー設定についての第三者による解説（2022 年の記事）。
- [Strict-Transport-Security — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security)：HSTS のディレクティブと preload の条件。
- [X-Frame-Options — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options)：指定できる値と `frame-ancestors` との関係。
- [Content Security Policy — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP)：CSP と Report-Only の使い方。
- [aws_lb_listener — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener)：Terraform のリスナーの引数。
- [aws_lb — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb)：Terraform の `desync_mitigation_mode` と `drop_invalid_header_fields`。
