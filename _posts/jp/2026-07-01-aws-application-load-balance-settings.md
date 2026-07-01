---
layout: post
title: "見落としやすい AWS Application Load Balancer の設定"
description: "Application Load Balancer で見落としやすい設定を整理します。WAF fail open、HTTP/2、idle timeout、X-Forwarded-For、Host header、TLS header、リスナー属性、リスナールール、レスポンスセキュリティヘッダーを扱います。"
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, Load Balancer, WAF, HTTP, Security]
keywords: [AWS, ALB, AWS ALB, Application Load Balancer, WAF, HTTP/2, X-Forwarded-For, HSTS, CSP]
lang: ja
date: 2026-07-01
---

AWS Application Load Balancer（ALB）を使い始めるとき、多くの人はまず次のような点を確認します。

1. ALB を internet-facing にするか internal にするか
2. リスナーを `80` にするか `443` にするか
3. ターゲットグループを EC2、IP、Lambda、Kubernetes service のどれに向けるか
4. Health check path をどう設定するか
5. Security Group が正しいか

もちろん、これらは重要です。

ただし ALB の本当に面白いところは、作成後に見えるさまざまな attributes や rule 設定にあります。

セキュリティに影響するものもあります。

バックエンドが受け取る request header を変えるものもあります。

WebSocket、長時間接続、HTTP/2 に影響するものもあります。

WAF、Global Accelerator、OIDC、mTLS と組み合わせたときに初めて意識する設定もあります。

この記事では、見落としやすいけれど実務では理解しておきたい ALB の設定を整理します。

## ALB、NLB、GLB の違い

設定に入る前に、まず Load Balancer の種類を分けて考えます。

| 種類 | レイヤー | よくある用途 |
| --- | --- | --- |
| Application Load Balancer | Layer 7 | HTTP、HTTPS、Path routing、Host routing、OIDC authentication、Header handling |
| Network Load Balancer | Layer 4 | TCP、UDP、TLS passthrough、低レイテンシー、固定 IP、送信元 IP の保持 |
| Gateway Load Balancer | Layer 3 / 4 | Firewall、IDS/IPS、packet inspection、ネットワークセキュリティ appliance へのトラフィック転送 |

Web サイト、API、社内 Web システムのように、Host、Path、Header を見てルーティングしたい場合は、通常 ALB を選びます。

HTTP 以外のプロトコルを扱う場合や、TLS をロードバランサーで終端せず、そのままバックエンドに passthrough したい場合は、NLB に近いユースケースです。

トラフィックをネットワーク検査レイヤーに通したい場合、たとえば firewall、侵入検知、侵入防御、packet inspection、サードパーティーの security appliance に集約したい場合は、GLB、つまり Gateway Load Balancer のユースケースです。

GLB は通常の Web サイト向けの Host routing や Path routing を行うものではありません。ネットワークトラフィックを透過的に検査 appliance 群へ流し、水平スケールできるようにするための仕組みに近いです。

以降は ALB を中心に見ていきます。

## ALB の設定をまず階層で見る

ALB の設定をすべて一度に見ると、文脈のない checkbox の一覧になりがちです。

理解しやすくするには、まず階層で分けます。

| 階層 | 主な役割 |
| --- | --- |
| Load Balancer | ALB 本体の属性、全体の接続動作、WAF、access log、HTTP header handling |
| Listener | 外部から traffic を受ける port、protocol、TLS policy、証明書、listener attributes |
| Rule | request がどの condition に一致したとき、どの action を実行するか |
| Target Group | バックエンドサービス、health check、protocol version、負荷分散、stickiness |

この記事もこの順番で整理します。

まず Load Balancer 階層の attributes を見ます。

次に Listener 階層の attributes を見ます。

その後、Rule を独立した階層として扱い、最後に Target Group と IaC の設定例を見ます。

## Load Balancer 階層

Load Balancer 階層の設定は、ALB 全体に影響します。

この階層は大きく二つに分けて考えるとわかりやすいです。

1. Traffic configuration：traffic entry、WAF fail open、client から ALB までの接続動作
2. Packet handling：ALB が request、header、forwarded information をどう扱うか

### Traffic Configuration

この分類は、traffic が ALB にどう入るか、そして client と ALB の接続がどう動くかに影響します。

よく一緒に確認する設定は Global Accelerator、WAF fail open、HTTP/2、idle timeout、client keepalive です。

> Global Accelerator は ALB の必須コンポーネントではありません。
> 固定 Anycast IP、複数 Region や複数 endpoint 間の traffic 切り替え、global entry point が必要な場合に検討します。
> 単一 Region の一般的な Web サイトや API であれば、Route 53 alias record で ALB を指すだけで十分なことが多いです。
{: .prompt-info}

#### WAF Fail Open を有効にするか

ALB に AWS WAF を関連付けている場合、`waf.fail_open.enabled` という設定があります。

これはとても直接的な問いです。

ALB が request を AWS WAF に転送して検査できない場合、それでも request を target にルーティングするかどうか、という設定です。

| 値 | 動作 | 優先するもの |
| --- | --- | --- |
| `false` | WAF 検査できない場合は request を通さない | セキュリティ |
| `true` | WAF 検査できない場合でも target に転送する | 可用性 |

デフォルトは `false` です。

つまり WAF の検査経路に問題が起きた場合、未検査の traffic をバックエンドへ送らない選択になります。

公開 Web サイト、ログイン入口、管理画面、決済フローでは、通常デフォルトのままが安全です。

一方で、内部 API、検索系サービス、非機密の read-only 入口など、可用性を強く優先するサービスでは、短時間 WAF 検査なしで request が通ることを許容できる場合に限り、fail open を検討できます。

絶対的な正解はありません。

ただし、`fail open` という名前だけを見て「障害を避けられそう」と思い、リスクを理解せず有効化するのは避けるべきです。

これはセキュリティと可用性のトレードオフです。

#### HTTP/2 はデフォルトで有効

ALB は HTTP/2 をサポートしており、`routing.http2.enabled` はデフォルトで `true` です。

これは client から ALB への接続で HTTP/2 を利用できるという意味です。HTTP/1.1 も引き続き利用できます。

注意点は、この設定が frontend connection、つまり client から ALB までの区間を指していることです。

ALB から target group までの protocol version は、target group 側の protocol version 設定で別に決まります。

一般的な Web サイトや API では、有効のままで問題ありません。

HTTP/2 では 1 本の接続で複数の request を並列に扱えるため、client が大量の接続を作る必要を減らせます。

非常に古い client、proxy、特殊な機器が HTTP/2 と相性が悪い場合にだけ、無効化を検討します。

#### Connection Idle Timeout は Request Timeout ではない

`idle_timeout.timeout_seconds` のデフォルトは `60` 秒です。

この設定はよく誤解されます。

これは「バックエンドが request を処理できる最大時間が 60 秒」という意味ではありません。

より正確には、指定した時間の間に接続上でデータ転送がない場合、ALB がその idle connection を閉じるという設定です。

idle timeout が問題になりやすい場面は次のようなものです。

1. WebSocket
2. Server-Sent Events
3. Long polling
4. 大きなファイルの upload / download
5. バックエンドが最初の response bytes を返すまで時間がかかる API

通常の API であれば 60 秒で十分なことが多いです。

WebSocket や streaming response がある場合は、`120`、`300`、またはそれ以上に調整することがあります。

ただし値を大きくすることは無料ではありません。

接続を長く保持するほど、ALB とバックエンドはより多くの connection state を維持する必要があります。

単に timeout を大きくするより、application 側で heartbeat や keep-alive data を定期的に送るほうがよい場合もあります。

#### Client Keepalive と Idle Timeout は別物

idle timeout とは別に、ALB には `client_keep_alive.seconds` があります。

デフォルトは `3600` 秒です。

これは ALB が HTTP client keepalive connection をどれくらい保持するかを制御します。

idle timeout は「この時間内にデータが流れたか」を見ます。

client keepalive は「この client connection を最大でどれくらい保持できるか」を見ます。

Blue-green deployment、IP address type の変更、または client が古い connection に長く残らないようにしたい場合、この設定が効いてきます。

通常はすぐに変更する必要はありません。

ただし idle timeout とは別の軸であることは覚えておくとよいです。

### Packet Handling

この分類は、ALB が request packet、HTTP header、forwarded information をどう扱い、どの情報をバックエンドへ渡すかに影響します。

セキュリティ基準を整理するときや、バックエンドが見ている request 情報を調査するときは、この一連の設定をまとめて確認します。

#### Desync Mitigation Mode

ALB には `routing.http.desync_mitigation_mode` という設定があります。

HTTP desync や request smuggling のリスクがある request を ALB がどう扱うかを制御します。

選択肢は三つです。

| モード | 説明 |
| --- | --- |
| `monitor` | 監視のみで積極的にはブロックしない |
| `defensive` | デフォルト。互換性と保護のバランスを取る |
| `strictest` | 最も厳格。より多くの非標準 request をブロックする可能性がある |

多くの本番環境では `defensive` が妥当です。

application と client が十分に管理されており、より厳しい security baseline を作る場合は `strictest` を評価できます。

ただし client の種類が多い場合、たとえば古い機器、古い SDK、顧客管理の proxy がある場合は、いきなり最も厳格なモードにしないほうが安全です。

まず ALB access log と application log を見て、影響を受ける非標準 request がないか確認するのがよいです。

#### Drop Invalid Header Fields

`routing.http.drop_invalid_header_fields.enabled` は、ALB が無効な HTTP header fields を削除するかどうかを制御します。

デフォルトは `false` です。

有効にすると、ALB はルールに合わない header を削除し、有効な header だけをバックエンドへ送ります。

この設定は desync mitigation と関連しています。

どちらも request format の安全性に関わるためです。

バックエンド framework、proxy、application server が変わった header をそれぞれ別の方法で処理すると、レイヤー間で解釈がずれるリスクがあります。

新しいシステムでは有効化を評価する価値があります。

古いシステムでは、非標準 header を送っている client が実際に存在しないか確認してからにしたほうが安全です。

#### Preserve Host Header

`routing.http.preserve_host_header.enabled` は、ALB が元の `Host` header を保持するかどうかを制御します。

デフォルトは `false` です。

この設定は、バックエンド application が見る Host に影響します。

たとえば次のような場合に重要です。

1. Multi-tenant system が domain で tenant を判定する
2. application が完全な callback URL を生成する必要がある
3. backend framework が canonical URL 判定に Host を使う
4. 同じ target group が複数 domain を処理する

application 側で Host が想定と違う値になっているとき、Nginx や application config を変えたくなります。

しかし原因は ALB 側で Host が変わっていることかもしれません。

バックエンドが元の domain を明確に知る必要がある場合は、通常次の組み合わせで考えます。

1. preserve host header を有効にする
2. application が proxy header を正しく信頼するよう設定する
3. バックエンドは ALB からのみ到達できるようにする

三つ目が重要です。

バックエンドへ外部から直接到達できる場合、誰でも Host や forwarded header を偽造できます。

その場合、application はそれらの header を信頼できる情報として扱うべきではありません。

#### X-Forwarded-For は Append、Preserve、Remove のどれにするか

ALB は `X-Forwarded-For` header を処理し、バックエンドが元の client IP を把握できるようにします。

関連する設定は `routing.http.xff_header_processing.mode` です。

選択肢は三つあります。

| モード | 動作 | よくある用途 |
| --- | --- | --- |
| `append` | 既存の `X-Forwarded-For` に client IP を追加する | デフォルト。多くのケース |
| `preserve` | 元の header を変更せず保持する | 前段の信頼できる proxy がすでに処理している |
| `remove` | `X-Forwarded-For` を削除する | source chain 情報をバックエンドで使わせたくない |

デフォルトは `append` です。

これは最も一般的で直感的な動作です。

request に `X-Forwarded-For` がなければ、ALB が client IP を追加します。

request が ALB に到達する前に別の proxy を通っていた場合、ALB は自分が見た前段の client IP を末尾に追加します。

ただし重要なセキュリティ上の注意があります。

`X-Forwarded-For` は単なる HTTP header なので、client が自分で送信できます。

バックエンドが最初の IP を無条件に信頼し、request が必ず信頼できる proxy から来ることを保証していない場合、送信元 IP は偽造できます。

安全な考え方は次のとおりです。

1. バックエンドは ALB からのみ到達できるようにする
2. application に trusted proxy range を明示的に設定する
3. 信頼できる proxy chain から本当の client IP を解析する

`X-Forwarded-For` の最初の値をそのまま実ユーザー IP とみなすのは避けたほうがよいです。

#### X-Forwarded-For Client Port

`routing.http.xff_client_port.enabled` は、ALB が client の source port を `X-Forwarded-For` に含めるかどうかを制御します。

デフォルトは `false` です。

一般的な application では source port はほとんど不要です。

使う可能性がある場面は次のようなものです。

1. 詳細なネットワーク接続調査
2. 他のネットワーク機器 log との照合
3. 特定の監査要件

明確な要件がなければ無効のままでよいです。

多くの backend framework、log parser、SIEM rule は、`X-Forwarded-For` に IP address のリストが入ることを期待しています。

port を追加すると parser の調整が必要になることがあります。

#### TLS Version と Cipher Suite Header

ALB listener が HTTPS の場合、`routing.http.x_amzn_tls_version_and_cipher_suite.enabled` を有効にできます。

有効にすると、ALB は client と ALB の間でネゴシエートされた TLS version と cipher suite を request header に追加してから backend に送ります。

よく使われる header は次の二つです。

1. `x-amzn-tls-version`
2. `x-amzn-tls-cipher-suite`

これは debugging や security audit に役立ちます。

たとえば古い TLS version を使っている client が残っていないか確認したり、backend log に TLS negotiation 情報を残したりできます。

ただし、これらの header は ALB が追加する情報です。

前提として、backend は ALB からのみ到達できるようにしておくべきです。

backend に外部から直接到達できる場合、外部 client がこれらの header を偽造できます。

## Listener 階層

Listener 階層の設定は、特定の port と protocol の入口に影響します。

たとえば `443` listener には HTTPS、証明書、TLS policy があります。

`80` listener は HTTPS への redirect に使われることがよくあります。

Listener には基本設定に加えて、listener attributes もあります。

これらは大きく二つに分けられます。

1. backend に TLS / mTLS 情報を渡すとき、ALB がどの header 名を使うか
2. response を client に返す前に、ALB が response header を追加または上書きするか

### TLS と mTLS Request Header の attributes

#### Listener Attributes で TLS と mTLS Header 名を変更できる

Listener attributes には、いくつかの `X-Amzn-*` header name 設定があります。

たとえば次のようなものです。

1. `X-Amzn-Tls-Version`
2. `X-Amzn-Tls-Cipher-Suite`
3. `X-Amzn-Mtls-Clientcert`
4. `X-Amzn-Mtls-Clientcert-Subject`
5. `X-Amzn-Mtls-Clientcert-Issuer`
6. `X-Amzn-Mtls-Clientcert-Serial-Number`
7. `X-Amzn-Mtls-Clientcert-Validity`

これらは header の値を設定するものではありません。

ALB が backend に情報を渡すときに使う header 名を変更するための設定です。

どのような場合に変更するのでしょうか。

よくある理由は次のとおりです。

1. backend framework が固定の header 名を期待している
2. 社内 proxy 標準で特定の命名が決まっている
3. 既存 header との衝突を避けたい
4. mTLS 情報を既存 application に読ませたい

このような要件がなければ、デフォルトのままで十分です。

「見た目がきれいだから」という理由だけで header 名を変えるのはおすすめしません。

後から document、debug、引き継ぎのたびに変換コストが増えます。

### Response Header の attributes

#### ALB は Response Headers を追加できる

ALB listener attributes では、一部の HTTP response headers を追加できます。

入口レイヤーで共通ルールを適用したい場合、たとえば security header や CORS header を統一したい場合に便利です。

設定できる代表的な response headers は次のとおりです。

| Header | よくある用途 |
| --- | --- |
| `Strict-Transport-Security` | ブラウザに今後 HTTPS のみでアクセスさせる |
| `Access-Control-Allow-Origin` | CORS で許可する origin |
| `Access-Control-Allow-Headers` | CORS で許可する request headers |
| `Access-Control-Allow-Methods` | CORS で許可する methods |
| `Access-Control-Allow-Credentials` | CORS で credentials を許可するか |
| `Access-Control-Expose-Headers` | ブラウザに公開する response headers |
| `Access-Control-Max-Age` | CORS preflight cache の秒数 |
| `Content-Security-Policy` | ブラウザが読み込める resource source を制限する |
| `X-Content-Type-Options` | MIME sniffing のリスクを下げる |
| `X-Frame-Options` | ページを frame に埋め込めるか制御する |

最も始めやすいのは `X-Content-Type-Options` です。

許可される値は `nosniff` のみです。

application 側で付与していない場合、ALB で一括して補うことを検討できます。

`Strict-Transport-Security` もよく使われます。

例：

```text
max-age=31536000; includeSubDomains
```

ただし HSTS は慎重に扱う必要があります。

`includeSubDomains` を付けると、subdomain もブラウザから HTTPS を要求されます。

HTTPS 準備ができていない subdomain があると、ユーザーがアクセスできなくなる可能性があります。

`Content-Security-Policy` はさらに注意が必要です。

緩すぎる CSP は意味が薄く、厳しすぎる CSP は frontend resource、third-party script、画像、font を壊す可能性があります。

私は CSP は application や frontend platform 側で管理し、ALB ではサービス横断で安定して付与できる header を扱うほうがよいと考えています。

#### Server Header は削除できる

Listener attributes には `routing.http.response.server.enabled` もあります。

これは ALB response に `server` header を含めるかどうかを制御します。

Security scanner が service fingerprint の削減を求める場合、削除を検討できます。

ただし `server` header の削除は主要な防御策ではありません。

本当に重要なのは次のようなものです。

1. WAF rules
2. TLS policy
3. backend の security update
4. 権限とネットワーク分離
5. 正しい logging と monitoring

これは security baseline の小さな整理として扱うべきで、セキュリティの中心ではありません。

## リスナールール階層

Rule は ALB の重要な階層です。

Listener はどの port で traffic を受けるかを決めます。

Rule は受け取った request をどう判定し、どう処理するかを決めます。

Rule を単なる path routing だと思いがちですが、実際には二つの要素があります。

1. condition：どのような request がこの rule に一致するか
2. action：一致したあとに何をするか

### 条件

よく使う rule condition は次のとおりです。

| Condition | 用途 |
| --- | --- |
| Host header | `api.example.com`、`admin.example.com` のように domain で分流する |
| Path | `/api/*`、`/admin/*` のように path で分流する |
| HTTP header | 特定 header で分流する |
| HTTP request method | GET、POST などの method で分流する |
| Query string | query string で分流する |
| Source IP | source IP で分流する |

最もよく使うのは Host header と Path です。

たとえば：

1. `api.example.com` は API target group へ forward
2. `admin.example.com` は OIDC authentication 後に admin target group へ forward
3. `/static/*` は別の target group へ forward

Rule の priority も重要です。

数字が小さいほど優先度が高くなります。

ALB は priority の小さいものから順に rule を評価します。

最初に一致した rule が実行されます。

どの rule にも一致しない場合は、listener の default action が実行されます。

### アクション

よく使う rule action は次のとおりです。

| Action | 用途 |
| --- | --- |
| Forward | request を target group に転送する |
| Redirect | HTTP から HTTPS などへ redirect する |
| Fixed response | ALB から固定 response を直接返す |
| Authenticate | OIDC または Cognito で先に認証する |

Forward は最も一般的な action です。

target group が一つだけなら、ALB は traffic をそのまま転送します。

複数の target group がある場合、weighted target groups を設定して、簡単な blue-green deployment や canary release に使うこともできます。

Redirect は `80` listener でよく使います。

```text
HTTP:80 -> HTTPS:443
```

Fixed response は簡単なブロックや maintenance response に向いています。

たとえば特定 path に直接 `403` を返したり、backend 準備前に固定メッセージを返したりできます。

Authenticate action は見落とされがちですが便利です。

Forward の前に置くことで、ALB が OIDC または Amazon Cognito でユーザーを認証し、認証後に request を backend へ送れます。

Uptime Kuma SSO の記事ではこの方法を使いました。

### リスナールールのアクション順序

Rule には複数の action を持たせることができます。

ただし順序が重要です。

OIDC authentication の場合、よくある順序は次のとおりです。

| Order | Action |
| --- | --- |
| 1 | Authenticate |
| 2 | Forward |

つまり、先に認証し、その後で転送します。

順序を間違えると、認証されていない request が forward されたり、rule が期待どおり動かなかったりします。

### リスナールールと attributes の違い

Rule は attribute ではありません。

ALB の routing logic に近いものです。

Attributes は load balancer、listener、target group 自体の動作を制御します。

簡単に分けると次のようになります。

1. attributes は ALB が connection、header、security behavior をどう扱うかを決める
2. rules は一致した request をどこへ送るか、先に認証するか、redirect するかを決める

ALB の問題を調査するとき、私はまず二つを確認します。

1. request は想定した rule に一致しているか
2. 一致した後、関連する attributes が request や response の動作を変えていないか

こうすると listener、rule、target group、attributes の問題を混ぜて考えにくくなります。

## Target Group 階層

Target group は ALB の後ろにある backend service の集合です。

この記事では主に ALB と listener attributes を扱っていますが、target group も全体の階層に含めて見る必要があります。

よく確認する target group 設定は次のとおりです。

1. target type：instance、ip、lambda
2. protocol と port
3. protocol version：HTTP/1.1、HTTP/2、gRPC
4. health check path、interval、timeout、threshold
5. deregistration delay
6. stickiness

特に protocol version は、前述の HTTP/2 設定と混同しやすいです。

`routing.http2.enabled` は client から ALB までの区間で HTTP/2 をサポートするかどうかです。

Target group の protocol version は、ALB が backend target とどう通信するかを決めます。

gRPC を使う場合や、backend target に HTTP/2 で接続したい場合は、target group の protocol version を確認します。

## よくある推奨設定

一般的な公開 Web サイトや API であれば、私はまず次のように見ます。

| 設定 | 推奨 |
| --- | --- |
| `routing.http2.enabled` | `true` のまま |
| `idle_timeout.timeout_seconds` | 一般 API は `60`、WebSocket や streaming は必要に応じて増やす |
| `client_keep_alive.seconds` | 通常はデフォルトのまま |
| `waf.fail_open.enabled` | 多くの公開サービスでは `false` のまま |
| `routing.http.desync_mitigation_mode` | `defensive` のまま。厳格な security 要件では `strictest` を評価 |
| `routing.http.drop_invalid_header_fields.enabled` | 新規システムでは有効化を評価。旧システムは先に検証 |
| `routing.http.preserve_host_header.enabled` | backend が元の Host を必要とする場合のみ有効 |
| `routing.http.xff_header_processing.mode` | 多くのケースでは `append` |
| `routing.http.xff_client_port.enabled` | 必要がなければ `false` |
| `routing.http.x_amzn_tls_version_and_cipher_suite.enabled` | TLS audit や debugging が必要な場合に有効 |

内部システムの場合は、さらに次を確認します。

1. ALB が internal か internet-facing か
2. backend Security Group が ALB からの traffic のみ許可しているか
3. OIDC authentication が必要か
4. WAF で基本的な保護を行う必要があるか
5. Access log と connection log を有効にしているか

多くの ALB 問題は listener rule のミスではありません。

信頼境界が曖昧なことが原因です。

backend に ALB を経由せず直接到達できる場合、ALB で処理している OIDC、WAF、header、TLS 情報の信頼性は弱くなります。

## Terraform 設定例

以下は Terraform でいくつかの ALB attributes を設定する例です。

```terraform
resource "aws_lb" "app" {
  name               = "example-app-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  idle_timeout               = 60
  client_keep_alive          = 3600
  enable_http2               = true
  enable_waf_fail_open       = false
  drop_invalid_header_fields = true
  preserve_host_header       = false
  enable_xff_client_port     = false

  xff_header_processing_mode = "append"

  desync_mitigation_mode = "defensive"

  enable_tls_version_and_cipher_suite_headers = true

  tags = {
    Service = "example-app"
  }
}
```

Terraform AWS Provider の version によって、対応している argument 名が異なる場合があります。

実装時は、プロジェクトで使っている provider version の document を確認してください。

Provider がまだ新しい listener attribute に対応していない場合、一時的に AWS CLI や CloudFormation を使うか、provider の対応後に IaC 管理へ戻すことになります。

## AWS CLI で確認する

ALB の現在の attributes を確認するには：

```bash
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <alb-arn>
```

Listener attributes を確認するには：

```bash
aws elbv2 describe-listener-attributes \
  --listener-arn <listener-arn>
```

Load balancer attributes を変更するには：

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <alb-arn> \
  --attributes Key=routing.http.drop_invalid_header_fields.enabled,Value=true
```

本番環境では、Console でただクリックして終わりにしないほうがよいです。

少なくとも現在の設定を export して残します。

できれば Terraform、CloudFormation、CDK で管理します。

ALB には細かい設定が多く、セキュリティ上の差分が一目でわからないこともあります。

## まとめ

ALB は単に traffic を target group に分散するだけのものではありません。

多くの AWS Web architecture における入口制御点です。

ALB は次のようなことを扱えます。

1. HTTPS termination
2. HTTP/2
3. WebSocket
4. WAF
5. OIDC authentication
6. Header forwarding
7. Response security headers
8. Global Accelerator integration

ALB は入口にあるため、その設定は security、debugging、audit、application behavior に直接影響します。

ALB を「health check 付きの reverse proxy」程度に考えていると、重要な細部を見落とします。

私のおすすめは、ALB を作成した後、listener、rule、target group だけでなく attributes も確認することです。

特に WAF fail open、desync mitigation、invalid header、Host header、X-Forwarded-For、idle timeout、response headers は確認しておく価値があります。

普段は静かな設定ですが、security scan、login redirect、real client IP の判定、WebSocket 切断、CORS 問題に遭遇したとき、原因調査の鍵になることがよくあります。

## 参考資料

1. [Application Load Balancers - Elastic Load Balancing](https://docs.aws.amazon.com/ja_jp/elasticloadbalancing/latest/application/application-load-balancers.html)
2. [Application Load Balancer のリスナー - Elastic Load Balancing](https://docs.aws.amazon.com/ja_jp/elasticloadbalancing/latest/application/load-balancer-listeners.html)
3. [Application Load Balancer のリスナールール - Elastic Load Balancing](https://docs.aws.amazon.com/ja_jp/elasticloadbalancing/latest/application/listener-rules.html)
4. [Gateway Load Balancer とは？ - Elastic Load Balancing](https://docs.aws.amazon.com/ja_jp/elasticloadbalancing/latest/gateway/introduction.html)
5. [AWS Global Accelerator の働き](https://docs.aws.amazon.com/ja_jp/global-accelerator/latest/dg/introduction-how-it-works.html)
6. [AWS WAF デベロッパーガイド](https://docs.aws.amazon.com/ja_jp/waf/latest/developerguide/waf-chapter.html)
