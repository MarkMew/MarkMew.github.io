---
layout: post
title: "不改後端程式，用 ALB 設定改善 7 項常見 Web 弱點掃描警告"
description: "整理 HTTP Request Smuggling、Invalid Header、弱 Cipher Suites、HSTS、X-Content-Type-Options、X-Frame-Options 與 CSP 這 7 項常見掃描警告，哪些能用 ALB 的 Attribute、Listener Attribute 與 Security Policy 處理，並提供 AWS CLI、Terraform 與驗證方式。"
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, Security, HTTP, TLS, Terraform]
keywords: [ALB desync mitigation mode, ALB drop invalid header fields, ALB HSTS, ALB X-Frame-Options, ALB Content-Security-Policy, ALB listener attributes, ALB response header, ALB security headers Terraform]
lang: zh-TW
date: 2026-11-02
---

**弱點掃描報告裡有一部分常見項目，可以直接在 ALB 上調整設定來處理，不一定要改後端程式。** 例如 HTTP Request Smuggling、Invalid HTTP Headers、弱 Cipher Suites，以及缺少 HSTS、`X-Content-Type-Options`、`X-Frame-Options`、`Content-Security-Policy` 這幾個 Response Header。不過 ALB 設定只能降低風險，不能取代應用程式本身的安全設計，其中 CSP 更是沒辦法直接套一組通用值。[AWS：ALB 的 HTTP header modification](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html)

TLS 的部分上一篇已經寫過 [ALB Security Policy 升級](/posts/alb-security-policy-upgrade-from-2016-08/)，本文只在 Cipher Suites 的章節簡述，其餘 6 項以 ALB 的設定為主，並提供 AWS CLI 與 Terraform。

## ALB 在架構中的位置

ALB 是 Client 與後端之間的終點：Client 的 HTTP 請求先由 ALB 解析，再轉送給 Target；TLS 也在 ALB 終止；回應則由 ALB 回傳給 Client。因為 ALB 同時負責這三件事，所以請求的解析方式、TLS 政策與回應的 Header，都可以在這一層調整。

要注意設定所屬的層級，三種設定的位置不同：

| 層級 | 設定位置 | 本文用到的項目 |
|---|---|---|
| Load Balancer Attribute | 整個 ALB | `routing.http.desync_mitigation_mode`、`routing.http.drop_invalid_header_fields.enabled` |
| Listener | HTTPS Listener 的 Security Policy | `ssl-policy` |
| Listener Attribute | 單一 Listener | `routing.http.response.*.header_value`（HSTS、X-Content-Type-Options、X-Frame-Options、CSP） |

Response Header 這四項是 **Listener Attribute**，必須在每個 Listener 上各自設定，不是設在 Load Balancer 上。Header modification 預設關閉，每個 Listener 要分別啟用。

## 設定總覽

| 掃描警告 | ALB 設定 | 層級 | 建議值 | 仍需後端或其他元件配合 |
|---|---|---|---|---|
| HTTP Request Smuggling | `routing.http.desync_mitigation_mode` | Load Balancer | `defensive`（預設）或 `strictest` | 後端 Web Server 的 HTTP 解析、WAF |
| Invalid HTTP Headers | `routing.http.drop_invalid_header_fields.enabled` | Load Balancer | `true` | 後端對其他不合規請求的處理 |
| Weak SSL Cipher Suites | Security Policy | Listener | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` | ALB 之前的 CloudFront 或其他 Proxy、ALB 到後端的 HTTPS |
| Missing HSTS | `routing.http.response.strict_transport_security.header_value` | Listener Attribute | `max-age=31536000` | 全站 HTTPS 已就緒 |
| Missing X-Content-Type-Options | `routing.http.response.x_content_type_options.header_value` | Listener Attribute | `nosniff` | 後端仍應回傳正確的 `Content-Type` |
| Missing X-Frame-Options | `routing.http.response.x_frame_options.header_value` | Listener Attribute | `SAMEORIGIN` 或 `DENY` | 需要被嵌入時改用 CSP `frame-ancestors` |
| Missing CSP | `routing.http.response.content_security_policy.header_value` | Listener Attribute | 依網站資源調整 | 應用程式本身的輸出編碼與資源管理 |

## 1. HTTP Request Smuggling

HTTP Request Smuggling（又稱 HTTP Desync）的成因是：前端 Proxy 與後端 Web Server 對同一個請求的邊界判斷不一致。例如請求同時帶有多個 `Content-Length`，或 `Content-Length` 與 `Transfer-Encoding` 並存，兩層可能各自解讀出不同的請求數量，攻擊者就能在同一條連線中夾帶額外的請求。

ALB 的 **Desync mitigation mode** 會依風險把每個請求分成四類，再依模式決定如何處理：

| 分類 | 說明 | `monitor` | `defensive` | `strictest` |
|---|---|---|---|---|
| Compliant | 符合 RFC 7230，沒有已知風險 | 允許 | 允許 | 允許 |
| Acceptable | 不符合 RFC 7230，但沒有已知風險 | 允許 | 允許 | 阻擋 |
| Ambiguous | 不符合 RFC 7230，且不同 Web Server 或 Proxy 可能解讀不同 | 允許 | 允許，但關閉與 Client 和 Target 的連線 | 阻擋 |
| Severe | 高風險 | 允許 | 阻擋 | 阻擋 |

阻擋的請求會回傳 400 並關閉 Client 連線。[AWS：Desync mitigation mode](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html)

幾個實務上的重點：

- **預設值就是 `defensive`**，所以多數 ALB 不需要特地設定；用 IaC 明確寫出來，可以避免日後被改掉。
- `monitor` 不會阻擋任何請求，只適合用來觀察。不合規的請求會增加 `DesyncMitigationMode_NonCompliant_Request_Count` 這個 CloudWatch Metric，Access Log 也會記錄分類結果。
- `strictest` 只讓符合 RFC 7230 的請求通過。如果有舊 Client 或奇怪的工具送出 Acceptable 等級的請求，會被直接擋下，建議先用 `monitor` 或查 Access Log，確認沒有不合規流量再切換。
- `defensive` 模式下，大量的 Ambiguous 請求可能產生額外費用，細節請看上面的官方文件。

> 這個設定降低的是 ALB 這一層造成 Desync 的風險，不代表後端 Web Server 本身的 HTTP 解析就沒問題。官方文件沒有列出 ALB 能涵蓋哪些具體的攻擊變體，所以我不會把它寫成「完全修復」。
{: .prompt-warning}

## 2. Invalid HTTP Headers

HTTP Header 的欄位名稱有格式限制。Elastic Load Balancing 要求 Header 名稱只能包含英數字與連字號（`-`）。如果名稱含有底線、空白或其他字元，不同的 Proxy 與 Web Server 可能有不同的處理方式，有些會忽略，有些會正規化後轉送，這個落差就可能被拿來繞過檢查。

`routing.http.drop_invalid_header_fields.enabled` 設為 `true` 時，ALB 會移除含有無效欄位名稱的 Header；預設值是 `false`，也就是照常轉送給 Target。[AWS：modify-load-balancer-attributes](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-load-balancer-attributes.html)

要注意這個設定的範圍：

- 它處理的是「**Header 欄位名稱無效**」的情況，不是所有不符合 HTTP 規範的請求。請求本身的格式問題（例如前一節的 Content-Length 衝突）要靠 Desync mitigation。
- 啟用後，如果既有的 Client 或內部系統使用底線之類的欄位名稱（例如自訂的 `X_Api_Key`），這些 Header 會被 ALB 丟掉，後端可能因此收不到。啟用前先確認 Client 實際送出的 Header 名稱。

這兩個設定經常一起被提到，但它們處理的是不同層面的問題，建議同時開啟。

## 3. Weak SSL Cipher Suites

ALB 的 TLS 版本與 Cipher Suites 是由 HTTPS Listener 的 Security Policy 決定，不能自訂，只能從 AWS 提供的清單選擇。TLS 1.0、1.1 與 CBC 模式、不具 Forward Secrecy 的 RSA 金鑰交換套件，是掃描器最常標記的對象。TLS 1.3 則只保留 AEAD 加密套件，並強制使用具 Forward Secrecy 的金鑰交換。

一般現代 Web 系統可以使用 `ELBSecurityPolicy-TLS13-1-2-Res-2021-06`：支援 TLS 1.3 與 1.2，不含 TLS 1.0/1.1，也沒有 CBC 套件。AWS 目前建議的是 PQ 系列的 `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`，兩者的選擇、相容性評估與完整切換流程，請參考[上一篇](/posts/alb-security-policy-upgrade-from-2016-08/)。[AWS：ALB Security Policy](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)

這項設定只影響 Client 到 ALB 這一段。CloudFront、其他 CDN 或 Proxy 的 TLS 設定要另外檢查。

## 4. Missing HSTS Header

HSTS（HTTP Strict Transport Security）是 Response Header，告訴瀏覽器「這個網站只能用 HTTPS 存取」。瀏覽器收到後，在 `max-age` 期間內，即使使用者輸入 `http://` 或點到舊的 HTTP 連結，也會自動改用 HTTPS，不會先送出 HTTP 請求，因此可以降低 HTTPS Downgrade 與 SSL Stripping 的風險。

| 指令 | 說明 |
|---|---|
| `max-age=<秒>` | 瀏覽器記住「只用 HTTPS」的時間 |
| `includeSubDomains` | 政策同時套用到所有子網域 |
| `preload` | 申請加入瀏覽器內建的 HSTS Preload List。要求 `max-age` 至少 `31536000` 且必須有 `includeSubDomains` |

[MDN：Strict-Transport-Security](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security)

導入前要確認：

- **全站（含子網域，如果加了 `includeSubDomains`）都能用 HTTPS**。瀏覽器記住之後，憑證過期或 HTTPS 壞掉時，使用者無法點擊忽略警告直接進入。
- HSTS 只在 HTTPS 回應中有效，瀏覽器會忽略 HTTP 回應中的這個 Header。
- `preload` 一旦被收錄，要移除相當困難，不建議在沒有完整盤點所有子網域前加上。

正式環境建議逐步拉長 `max-age`，例如：

| 階段 | 值 |
|---|---|
| 1 | `max-age=300`（5 分鐘） |
| 2 | `max-age=86400`（1 天） |
| 3 | `max-age=604800`（1 週） |
| 4 | `max-age=31536000`（1 年） |

每一階段觀察一段時間，沒有問題再往下調。如果後端已經送出同名 Header，ALB 啟用後會**覆寫**為設定值，所以不會出現重複的 HSTS。

> Terraform 官方文件中，`routing_http_response_strict_transport_security_header_value` 的說明提到預設值為 `max-age=31536000; includeSubDomains; preload`，但沒有說明這個預設值在什麼情境下生效。**這點待確認**，建議不要依賴它，明確指定想要的值。
{: .prompt-warning}

## 5. Missing X-Content-Type-Options

瀏覽器在 `Content-Type` 與實際內容不一致時，有些會嘗試自己猜測內容類型，這叫 MIME Type Sniffing。例如伺服器把使用者上傳的檔案標成 `text/plain`，瀏覽器可能判斷內容像 HTML 或 JavaScript 而當成可執行內容處理，就可能被利用。

`X-Content-Type-Options: nosniff` 告訴瀏覽器要照 `Content-Type` 處理，不要自行猜測。ALB 對應的屬性只接受 `nosniff` 這一個值。

這是相容性風險最低的一項。唯一的前提是後端的 `Content-Type` 必須正確，否則原本靠瀏覽器猜測才能正常載入的 JS 或 CSS 會被拒絕。這個 Header 降低的是 MIME 混淆的風險，不是防止 XSS 的設定。

## 6. Missing X-Frame-Options

Clickjacking 是攻擊者把目標網站用 `iframe` 嵌入自己的頁面，再用透明圖層誘導使用者點擊，使用者以為在操作攻擊者的頁面，實際點的是目標網站上的按鈕。

`X-Frame-Options` 控制頁面是否允許被嵌入：

| 值 | 說明 |
|---|---|
| `DENY` | 任何網站都不能嵌入，包含同源 |
| `SAMEORIGIN` | 只有同源的頁面可以嵌入 |
| `ALLOW-FROM <origin>` | 已廢棄，現代瀏覽器會忽略整個 Header |

[MDN：X-Frame-Options](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options)

Terraform 的欄位說明列出了 `ALLOW-FROM`，但因為現代瀏覽器已忽略，**不建議使用**。

這個設定不是所有網站都適用：

- 如果網站會被其他網域用 iframe 嵌入（例如提供給合作夥伴的內嵌元件），`DENY` 與 `SAMEORIGIN` 都會讓嵌入失效，這時要改用 CSP 的 `frame-ancestors`，指定允許嵌入的來源。
- 如果網站內有同源的 iframe（例如後台把報表用 iframe 載入），用 `SAMEORIGIN`。
- ALB 這個屬性的值只有一個，**所有路徑共用同一個值**。需要依路徑區分時，要在後端處理。

`frame-ancestors` 是 MDN 建議用來取代 `X-Frame-Options` 的 CSP 指令，可以指定多個來源，彈性比較高。MDN 的兩個頁面沒有說明兩者同時存在時的優先順序，需要同時設定時，建議自己用瀏覽器測試確認。

## 7. Missing Content-Security-Policy

CSP 是讓網站告訴瀏覽器「哪些來源的資源可以載入與執行」。它能降低 XSS 被成功利用後的影響，也能限制惡意資源的載入，但**它是縱深防禦，不是修好 XSS**，應用程式本身仍要做輸出編碼與輸入驗證。

常見的 Directive：

| Directive | 用途 |
|---|---|
| `default-src` | 沒有另外指定的資源類型的預設來源 |
| `script-src` | JavaScript 的來源 |
| `style-src` | CSS 的來源 |
| `img-src` | 圖片的來源 |
| `connect-src` | `fetch`、XHR、WebSocket 可連線的目標 |
| `frame-ancestors` | 哪些來源可以用 iframe 嵌入本頁 |
| `object-src` | `<object>`、`<embed>` 的來源 |
| `base-uri` | `<base>` 標籤可以使用的 URL |

CSP **沒有通用設定**，因為每個網站載入的資源不同：用了哪些 CDN、Google Analytics、字型服務、Inline Script、第三方登入，都要列進去。設得太嚴，圖片不顯示、樣式跑掉、登入或金流的第三方元件壞掉；設得太鬆（例如大量 `'unsafe-inline'`），則保護力有限。

### 用 Report-Only 逐步測試

正常的做法是先用 `Content-Security-Policy-Report-Only`，只回報違規、不阻擋，收集一段時間後再調整成正式政策。

> **ALB 沒有對應 `Content-Security-Policy-Report-Only` 的 Listener Attribute。** 我查過 AWS 的 header modification 文件，列出的 Response Header 屬性只有 `content_security_policy`，沒有 Report-Only 版本。所以要先用 Report-Only 測試，只能在後端應用程式或 Web Server 先送出這個 Header，或在測試環境直接用 ALB 設定，確認沒問題再套用到正式環境。
{: .prompt-warning}

另外，ALB 的 `content_security_policy` 屬性沒有指定是否支援 `report-to` 之類的設定，Header 值有字元限制（見下方注意事項），要用到報告功能前請先在測試環境確認。

### 僅供示範的 CSP

下面這組只是示範，**不能直接用在正式環境**，必須依實際網站的資源調整：

```text
default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'
```

這組設定只允許同源載入，Inline Script 與 Inline Style 都會被擋下，如果網站有用到，頁面會出現異常。

## 實際操作

### Console

**Load Balancer Attribute**（Desync mitigation mode、Drop invalid header fields）：

EC2 → Load Balancers → 選擇 ALB → Attributes → Edit → 在 **Packet handling** 區塊設定 Desync mitigation mode 與 Drop invalid header fields → Save changes。

**Security Policy**：

EC2 → Load Balancers → 選擇 ALB → Listeners and rules → 選擇 HTTPS:443 → Manage listener → Edit listener → Security policy。

**Listener Attribute**（Response Header）：

EC2 → Load Balancers → 選擇 ALB → Listeners and rules → 點進 Listener → Attributes → Edit → 展開 **Add response headers**，啟用要加的 Header 並填入值 → Save changes。

### AWS CLI

Load Balancer Attribute：

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN> \
  --attributes \
    Key=routing.http.desync_mitigation_mode,Value=defensive \
    Key=routing.http.drop_invalid_header_fields.enabled,Value=true
```

Security Policy：

```bash
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

Listener Attribute。因為 CSP 的值含有空白與分號，改用 JSON 格式比較不容易出錯：

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

> CSP 的值包含單引號，在 Bash 的單引號字串中要寫成 `'\''`，看起來比較亂。若不想處理，可以把 JSON 存成檔案，再用 `--attributes file://listener-attributes.json` 傳入。
{: .prompt-info}

### Terraform

Load Balancer Attribute 設在 `aws_lb`，Listener Attribute 則直接是 `aws_lb_listener` 的引數，不是另外的區塊：

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

這些欄位名稱是對照 `hashicorp/terraform-provider-aws` 的 `aws_lb_listener` 文件確認的。**需要哪個版本以上的 provider 才支援，我沒有查到，待確認**，如果 `terraform validate` 回報不認得這些引數，請先升級 provider。

## 驗證

### AWS CLI

```bash
# Load Balancer Attribute
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN> \
  --query "Attributes[?Key=='routing.http.desync_mitigation_mode' || Key=='routing.http.drop_invalid_header_fields.enabled']"

# Listener Attribute
aws elbv2 describe-listener-attributes \
  --listener-arn <LISTENER_ARN>

# Security Policy
aws elbv2 describe-listeners \
  --listener-arns <LISTENER_ARN> \
  --query "Listeners[0].SslPolicy"
```

### 檢查 Response Header

```bash
curl -sI https://example.com
```

回應中應該看到：

```text
strict-transport-security: max-age=31536000
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
content-security-policy: default-src 'self'; ...
```

瀏覽器也可以開啟 Developer Tools → Network → 點選任一請求 → Headers，確認 Response Headers。CSP 若設得太嚴，違規會顯示在 Console 分頁。

### 檢查 TLS

```bash
# 應失敗：TLS 1.1
openssl s_client -connect example.com:443 -tls1_1 </dev/null

# 應成功：TLS 1.2 與 1.3
openssl s_client -connect example.com:443 -tls1_2 </dev/null
openssl s_client -connect example.com:443 -tls1_3 </dev/null
```

完整列出支援的套件，可使用 `nmap --script ssl-enum-ciphers -p 443 example.com` 或 SSL Labs。

### 哪些設定能用簡單的工具驗證

| 設定 | `describe-*` | `curl -I` | `openssl` | 其他 |
|---|---|---|---|---|
| Desync mitigation | 能確認設定值 | 不能 | 不能 | 看 Access Log 的分類與 CloudWatch Metric，或使用專門的安全測試工具 |
| Drop invalid header | 能確認設定值 | 不適合 | 不能 | 需要送出含無效欄位名稱的請求，確認後端是否收到 |
| Security Policy | 能確認政策名稱 | 不能 | 能 | `nmap`、SSL Labs |
| HSTS、nosniff、XFO、CSP | 能確認設定值 | 能 | 不能 | 瀏覽器 Developer Tools |

Request Smuggling 的實際驗證需要手動構造請求並比對前後端的解析結果，不是 `curl -I` 能完成的，請使用適當的安全測試工具，並且只對有授權的環境測試。

## 注意事項與限制

- **區分掃描警告、設定缺失與實際可被利用。** 缺少某個 Header 是設定上的缺失，不代表網站一定能被攻擊；反過來，加上 Header 也不代表漏洞被修好。
- **Header 值的限制**：只能包含英數字與一組特定的符號，長度不能超過 1K bytes。ALB 只做基本的格式驗證，不會確認這個值對該 Header 是否有意義，所以值寫錯不會被擋下。設定空值會回到預設行為。[AWS：Header modification 的 Limitations](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html)
- **後端已送出同名 Header**：ALB 會以設定值覆寫。如果有些路徑需要不同的值（例如不同頁面的 `X-Frame-Options`），ALB 的單一設定無法處理。
- **ALB 自己產生的回應**（例如固定回應或 5xx 錯誤頁面）是否會加上這些 Header，我沒有在官方文件中找到說明，**待確認**。
- **HTTP Listener**：官方文件沒有明確說明 Response Header 屬性是否只適用 HTTPS。HSTS 在 HTTP 回應中會被瀏覽器忽略，所以實際上只需要設定在 HTTPS Listener。
- **ALB 設定不能取代應用程式的安全設計與 AWS WAF。** SQL Injection、XSS、存取控制等問題，仍要靠應用程式與 WAF 處理。
- **用 IaC 明確指定**。Desync mitigation 的預設值是 `defensive`，但 `drop_invalid_header_fields` 預設是 `false`，Security Policy 在 CLI 與 CloudFormation 的預設也是舊的 `ELBSecurityPolicy-2016-08`，不要依賴預設值。

## 常見問題

### 這些設定會中斷既有連線嗎？

Load Balancer Attribute 與 Listener Attribute 的變更是套用在新的請求上。真正的風險是相容性：`strictest` 可能擋掉不合規的 Client、Drop invalid header 可能丟掉自訂 Header、CSP 可能讓頁面功能異常、HSTS 則是設定錯誤後瀏覽器會記住一段時間。

### 可以只靠 ALB 設定就通過弱點掃描嗎？

不一定。掃描器的判斷標準各不相同，而且有些項目（例如 CSP 的內容是否過於寬鬆）需要依網站資源調整。ALB 能處理的是其中一部分，其他仍要靠後端與 WAF。

### 為什麼不直接把 CSP 設成最嚴格？

最嚴格的 CSP 會擋掉 Inline Script、第三方資源與 `eval`。沒有先盤點網站使用的資源就直接套用，很容易讓頁面壞掉。建議先在測試環境收集違規，再逐步調整。

## 結語

這 7 項裡，Desync mitigation、Invalid header 與 Security Policy 是 ALB 這一層的設定，HSTS、`X-Content-Type-Options`、`X-Frame-Options` 與 CSP 則是 ALB 協助補上的 Response Header。其中 `nosniff` 風險最低，HSTS 要逐步加長 `max-age`，`X-Frame-Options` 要看有沒有 iframe 的需求，CSP 則一定要依網站資源調整，並且在 ALB 以外的地方先用 Report-Only 測試。

ALB 設定是補強而不是替代，後端的 HTTP 解析、應用程式的安全設計與 WAF，仍然是整體防護的一部分。

## 參考資料

- [HTTP header modification for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html)：Response Header 屬性、值的限制與覆寫行為。
- [Enable HTTP header modification](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-header-modification.html)：Console 操作步驟與 Header modification attributes 清單。
- [Edit load balancer attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html)：Desync mitigation mode 的分類與各模式行為。
- [modify-load-balancer-attributes — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-load-balancer-attributes.html)：`drop_invalid_header_fields` 等屬性說明。
- [modify-listener-attributes — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-listener-attributes.html)：Listener Attribute 的 CLI 語法。
- [Security policies for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)：ALB 支援的 Security Policy。
- [HTTP Request Smuggling on AWS — Virtue Security](https://www.virtuesecurity.com/kb/http-request-smuggling-aws/)：ALB 與 Invalid header 設定的第三方說明（2022 年文章）。
- [Strict-Transport-Security — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security)：HSTS 指令與 preload 條件。
- [X-Frame-Options — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options)：可用值與 `frame-ancestors` 的關係。
- [Content Security Policy — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP)：CSP 與 Report-Only 的用法。
- [aws_lb_listener — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener)：Terraform 的 Listener 欄位。
- [aws_lb — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb)：Terraform 的 `desync_mitigation_mode` 與 `drop_invalid_header_fields`。
