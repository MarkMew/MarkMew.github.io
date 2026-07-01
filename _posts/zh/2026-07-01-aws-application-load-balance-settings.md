---
layout: post
title: "那些你在 AWS Application Load Balancer 上容易忽略的設定"
description: "整理 AWS Application Load Balancer 建立後常見但容易被忽略的設定，包括 Global Accelerator、WAF fail open、HTTP/2、idle timeout、X-Forwarded-For、Host header、TLS header 與 response security headers。"
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, Load Balancer, WAF, HTTP, Security]
keywords: [AWS, ALB, AWS ALB, Application Load Balancer, WAF, HTTP/2, X-Forwarded-For, HSTS, CSP]
lang: zh-TW
date: 2026-07-01
---

剛開始使用 AWS Application Load Balancer（ALB）時，

大部分人會先注意幾件事：

1. ALB 是 Internet-facing 還是 internal
2. Listener 要開 `80` 還是 `443`
3. Target group 要接 EC2、IP、Lambda 還是 Kubernetes service
4. Health check path 要怎麼設
5. Security Group 有沒有放對

這些都很重要，

但 ALB 真正有趣的地方，

其實藏在建立完成後的各種 attributes 裡。

有些設定會影響安全性，

有些會影響後端看到的 request header，

有些會影響 WebSocket、長連線、HTTP/2，

有些則是你要接 WAF、Global Accelerator、OIDC 或 mTLS 時才會突然遇到。

這篇就整理幾個我覺得容易被忽略，

但實務上很常需要理解的 ALB 設定。

## 先釐清 ALB、NLB、GLB 的差異

在看設定前，

先把三種 Load Balancer 的定位分清楚。

| 類型 | 層級 | 適合情境 |
| --- | --- | --- |
| Application Load Balancer | Layer 7 | HTTP、HTTPS、路徑導向、Host 導向、OIDC 驗證、Header 操作 |
| Network Load Balancer | Layer 4 | TCP、UDP、TLS passthrough、極低延遲、固定 IP、保留來源 IP |
| Gateway Load Balancer | Layer 3 / 4 | 將流量導到防火牆、IDS/IPS、封包檢查設備等網路安全 appliance |

如果你的應用是網站、API、內部系統，

而且需要根據 Host、Path、Header 做路由，

或希望在入口層處理 HTTPS、WAF、OIDC authentication，

通常會選 ALB。

如果你要處理的是非 HTTP 協定，

或你希望 TLS 完全 passthrough 到後端，

那就比較像 NLB 的場景。

如果你的需求是讓流量經過一層網路檢查，

例如集中導到防火牆、入侵偵測、入侵防禦、封包檢查或第三方安全設備，

那就比較像 GLB，也就是 Gateway Load Balancer 的場景。

GLB 不是拿來做一般網站的 Host 或 Path routing，

它比較像是把網路流量透明地導入檢查設備群，

讓安全 appliance 可以水平擴展，

也可以避免每台設備變成單點瓶頸。

這篇後面談的設定，

主要都集中在 ALB。

## ALB 設定可以先分成幾個層級

ALB 的設定如果全部攤開來看，

會很容易變成一串沒有脈絡的 checkbox。

比較好理解的方式是先分層：

| 層級 | 主要負責什麼 |
| --- | --- |
| Load Balancer | ALB 本體屬性、整體連線行為、WAF、access log、HTTP header 處理 |
| Listener | 對外接收流量的 port、protocol、TLS policy、憑證、listener attributes |
| Rule | 決定 request 符合什麼條件時，要執行什麼 action |
| Target Group | 後端服務、health check、protocol version、負載分配與 stickiness |

所以這篇後面會照這個順序整理。

先看 Load Balancer 層級的 attributes，

再看 Listener 層級的 attributes，

接著把 Rule 拉出來獨立看，

最後再看常見建議與 IaC 設定方式。

## Load Balancer 層級

Load Balancer 層級的設定，

影響的是整個 ALB 本體。

這一層可以先拆成兩大類：

1. Traffic configuration：流量入口、WAF fail open、client 到 ALB 的連線行為
2. Packet handling：ALB 怎麼處理 request、header、forwarded information

### Traffic configuration

這一類設定會影響流量怎麼進入 ALB，

以及 client 和 ALB 之間的連線行為。

常見會一起看的設定有 Global Accelerator、WAF fail open、HTTP/2、idle timeout、client keepalive。

> Global Accelerator 不是 ALB 的必要配件。
> 只有在需要固定 Anycast IP、跨 Region 或多 endpoint 流量切換、全球入口加速時才比較需要考慮。
> 如果只是單一 Region 的一般網站或 API，用 Route 53 alias 指向 ALB 通常就夠了。
{: .prompt-info}

#### WAF Fail Open 要不要打開

如果 ALB 有掛 AWS WAF，

你會看到一個設定叫做 `waf.fail_open.enabled`。

這個設定在問一件很直白的事情：

當 ALB 無法把 request 交給 AWS WAF 檢查時，

要不要仍然把 request 放行到後端？

| 設定 | 行為 | 取向 |
| --- | --- | --- |
| `false` | 無法檢查 WAF 時，不放行 | 安全優先 |
| `true` | 無法檢查 WAF 時，仍轉送到 target | 可用性優先 |

AWS 預設是 `false`。

這代表當 WAF 路徑出問題時，

系統寧可不要讓未檢查的流量進入後端。

對公開網站、登入入口、管理後台、付款流程來說，

通常維持預設比較合理。

但如果你的服務是強可用性導向，

例如某些內部 API、查詢服務、非敏感讀取入口，

而且你可以接受短時間內 request 沒有經過 WAF 檢查，

才會考慮打開 fail open。

這裡沒有絕對答案，

但要避免一件事：

不要在不了解風險的情況下，

只是因為看到 `fail open` 好像可以避免故障就打開。

這個設定本質上是在安全性與可用性之間選邊站。

#### HTTP/2 預設是開啟的

ALB 支援 HTTP/2，

而且 `routing.http2.enabled` 預設是 `true`。

這表示 client 到 ALB 之間可以使用 HTTP/2，

client 也仍然可以用 HTTP/1.1。

要注意的是，

這個設定說的是前端連線，也就是 client 到 ALB 這段。

後端 ALB 到 target group 要用什麼協定版本，

會另外受到 target group 的 protocol version 設定影響。

一般網站或 API 通常維持開啟就好，

因為 HTTP/2 可以讓同一條連線上並行多個 request，

減少 client 端建立大量連線的需求。

但如果你遇到非常老的 client、proxy 或特殊設備，

懷疑它和 HTTP/2 行為不相容，

才需要考慮關閉。

#### Connection Idle Timeout 不是 Request Timeout

ALB 的 `idle_timeout.timeout_seconds` 預設是 `60` 秒。

這個設定很常被誤會。

它不是「後端處理 request 最多只能處理 60 秒」。

比較精準地說，

它是在說一條連線如果在指定時間內沒有資料傳輸，

ALB 就會關閉這條 idle connection。

常見會遇到 idle timeout 的場景有：

1. WebSocket
2. Server-Sent Events
3. 長輪詢
4. 大檔案上傳或下載
5. 後端需要較長時間才開始回應的 API

如果是一般 API，

60 秒通常很夠。

但如果你有 WebSocket 或串流回應，

就可能需要調高，

例如 `120`、`300` 或更高。

不過調高也不是免費的，

因為連線保留越久，

ALB 和後端都需要維持更多連線狀態。

所以比較好的做法是：

讓應用程式定期送出 heartbeat 或 keep-alive 資料，

而不是單純把 timeout 拉到很大。

#### Client Keepalive 和 Idle Timeout 不一樣

除了 idle timeout，

ALB 也有 `client_keep_alive.seconds`。

它預設是 `3600` 秒。

這個設定是控制 ALB 願意和 client 維持 HTTP client keepalive 連線多久。

idle timeout 看的是「這段時間內有沒有資料」，

client keepalive 看的是「這條 client 連線最多可以被保留多久」。

如果你在做藍綠切換、IP address type 變更，

或希望 client 不要太久黏在舊連線上，

這個設定就會開始有感。

一般情境通常不需要先改，

但它和 idle timeout 是兩個不同維度，

不要混在一起看。

### Packet handling

這一類設定會影響 ALB 怎麼處理 request packet、

HTTP header、forwarded information，

以及哪些資訊會被傳到後端。

如果你在整理安全基線或排查後端看到的 request 資訊，

這一組通常會一起看。

#### Desync Mitigation Mode

ALB 有一個設定叫 `routing.http.desync_mitigation_mode`，

用來處理可能造成 HTTP desync 或 request smuggling 風險的 request。

可選值有三種：

| 模式 | 說明 |
| --- | --- |
| `monitor` | 只監控，不積極阻擋 |
| `defensive` | 預設值，兼顧相容性與防護 |
| `strictest` | 最嚴格，可能擋掉更多不標準 request |

大多數正式環境維持 `defensive` 就合理。

如果你在整理安全基線，

而應用程式與 client 都相對可控，

可以評估 `strictest`。

但如果你的 client 來源很複雜，

例如有舊版設備、舊版 SDK、客戶自建 proxy，

就不要一開始直接切到最嚴格。

比較穩的做法是先觀察 ALB access log 和應用程式 log，

確認是否有非標準 request 會被影響。

#### Drop Invalid Header Fields

`routing.http.drop_invalid_header_fields.enabled` 用來控制 ALB 是否移除不合法的 HTTP header field。

預設是 `false`。

如果打開，

ALB 會移除不符合規則的 header，

只把合法 header 往後端送。

這個設定和 desync mitigation 有點關聯，

都和 request 格式安全性有關。

如果你的後端框架、proxy、application server 對怪異 header 的處理方式不同，

那就可能出現前後端解析不一致的風險。

對新系統來說，

我會傾向評估打開。

對舊系統來說，

則要先確認是否有 client 真的送了不標準 header，

避免一打開就造成某些整合突然失效。

#### Preserve Host Header

`routing.http.preserve_host_header.enabled` 控制 ALB 要不要保留原始的 `Host` header。

預設是 `false`。

這個設定會影響後端應用看到的 Host。

如果你的應用程式需要根據原始 Host 做判斷，

例如：

1. 多租戶系統依照 domain 分 tenant
2. 應用程式需要產生完整 callback URL
3. 後端框架依賴 Host 判斷 canonical URL
4. 同一組 target group 同時服務多個 domain

那就要特別注意這個設定。

有些人會在應用程式裡看到 Host 不是預期的值，

然後開始改 Nginx 或 application config，

但真正原因可能是在 ALB 這層就已經改過了。

如果你希望後端明確知道使用者原本打到哪個 domain，

通常會搭配：

1. 開啟 preserve host header
2. 確認應用程式正確信任 proxy header
3. 限制後端只能被 ALB 存取

第三點很重要。

如果後端可以被外部直接打到，

那任何人都可以偽造 Host 或 forwarded header，

應用程式就不能再把這些 header 當成可信來源。

#### X-Forwarded-For 要選 Append、Preserve 還是 Remove

ALB 會處理 `X-Forwarded-For` header，

讓後端知道原始 client IP。

相關設定是 `routing.http.xff_header_processing.mode`，

可選值有三種：

| 模式 | 行為 | 常見用途 |
| --- | --- | --- |
| `append` | 在既有 `X-Forwarded-For` 後面加上 client IP | 預設，多數情境 |
| `preserve` | 保留原始 header，不修改 | 前面已有可信 proxy 處理 |
| `remove` | 移除 `X-Forwarded-For` | 不希望後端使用來源鏈資訊 |

預設是 `append`。

這也是最常見、最符合直覺的行為。

例如 request 原本沒有 `X-Forwarded-For`，

ALB 會加上 client IP。

如果 request 進 ALB 前已經經過其他 proxy，

ALB 會把它看到的上一跳 client IP append 到後面。

但這裡有一個安全重點：

`X-Forwarded-For` 本質上是 HTTP header，

client 可以自己送。

所以如果你的後端直接信任第一個 IP，

又沒有確認 request 一定只從可信 proxy 進來，

就可能被偽造來源 IP。

比較穩的做法是：

1. 後端只允許 ALB 存取
2. 應用程式明確設定 trusted proxy 範圍
3. 從可信 proxy 鏈中解析真正 client IP

不要只是看到 `X-Forwarded-For` 第一個值，

就直接當成使用者真實 IP。

#### X-Forwarded-For Client Port

`routing.http.xff_client_port.enabled` 控制 ALB 是否把 client 的來源 port 也加進 `X-Forwarded-For`。

預設是 `false`。

一般應用程式很少需要來源 port。

比較可能用到的場景是：

1. 精細除錯網路連線問題
2. 需要和其他網路設備 log 對齊
3. 特定稽核需求

如果沒有明確需求，

通常維持關閉即可。

因為多數後端框架、log parser、SIEM 規則，

比較習慣 `X-Forwarded-For` 裡是 IP 清單，

加上 port 後反而可能需要調整解析規則。

#### TLS Version 與 Cipher Suite Header

如果你的 ALB listener 是 HTTPS，

可以開啟 `routing.http.x_amzn_tls_version_and_cipher_suite.enabled`。

開啟後，

ALB 會把 client 與 ALB 協商出來的 TLS 版本與 cipher suite 放進 request header，

再送給後端。

常見 header 是：

1. `x-amzn-tls-version`
2. `x-amzn-tls-cipher-suite`

這對應用程式除錯與安全稽核很有幫助。

例如你想知道是否還有 client 使用舊版 TLS，

或想在後端 log 中保留 TLS 協商資訊，

就可以打開。

不過要記得：

這些 header 是 ALB 加上的資訊，

前提仍然是後端只能被 ALB 存取。

如果後端也能被外部直接連線，

外部 request 同樣可以偽造這些 header。

## Listener 層級

Listener 層級的設定，

影響的是某個 port 和 protocol 的入口。

例如 `443` listener 會有 HTTPS、憑證、TLS policy，

而 `80` listener 常見用途是 redirect 到 HTTPS。

Listener 本身除了基本設定外，

也有自己的 attributes。

這些 attributes 常見分成兩類：

1. request 進到後端前，ALB 要用什麼 header 名稱傳 TLS/mTLS 資訊
2. response 回到 client 前，ALB 要不要補上或覆寫某些 response headers

### TLS 與 mTLS Request Header 類 attributes

#### Listener Attributes 可以改 TLS 與 mTLS Header 名稱

在 listener attributes 裡，

你可能會看到一整排 `X-Amzn-*` header name 的設定，

例如：

1. `X-Amzn-Tls-Version`
2. `X-Amzn-Tls-Cipher-Suite`
3. `X-Amzn-Mtls-Clientcert`
4. `X-Amzn-Mtls-Clientcert-Subject`
5. `X-Amzn-Mtls-Clientcert-Issuer`
6. `X-Amzn-Mtls-Clientcert-Serial-Number`
7. `X-Amzn-Mtls-Clientcert-Validity`

這些設定不是讓你填 header 的值，

而是讓你修改 ALB 傳給後端時使用的 header 名稱。

什麼時候會需要改？

常見有幾種：

1. 後端框架已經使用固定 header name
2. 公司內部 proxy 規範要求特定命名
3. 避免和既有 header 衝突
4. mTLS 資訊要交給既有應用程式讀取

如果沒有這類需求，

維持預設值就好。

不要為了「看起來比較整齊」去改 header 名稱，

因為後續文件、除錯、交接都會增加一層轉換成本。

### Response Header 類 attributes

#### ALB 可以加 Response Headers

ALB listener attributes 也支援加入部分 HTTP response headers。

這個功能很適合處理一些入口層統一規則，

例如安全 header 或 CORS header。

常見可設定的 response headers 包含：

| Header | 常見用途 |
| --- | --- |
| `Strict-Transport-Security` | 要求瀏覽器後續只用 HTTPS 存取 |
| `Access-Control-Allow-Origin` | CORS 允許來源 |
| `Access-Control-Allow-Headers` | CORS 允許 request headers |
| `Access-Control-Allow-Methods` | CORS 允許 methods |
| `Access-Control-Allow-Credentials` | CORS 是否允許 credentials |
| `Access-Control-Expose-Headers` | CORS 可暴露給瀏覽器的 response headers |
| `Access-Control-Max-Age` | CORS preflight cache 秒數 |
| `Content-Security-Policy` | 限制瀏覽器可載入的資源來源 |
| `X-Content-Type-Options` | 降低 MIME sniffing 風險 |
| `X-Frame-Options` | 控制頁面是否可被 iframe 嵌入 |

這裡最容易上手的是 `X-Content-Type-Options`。

它的值只允許 `nosniff`。

如果應用程式本身沒有加，

可以考慮在 ALB 這層統一補上。

`Strict-Transport-Security` 也很常見，

例如：

```text
max-age=31536000; includeSubDomains
```

但 HSTS 要謹慎。

如果你加上 `includeSubDomains`，

代表子網域也會被瀏覽器要求走 HTTPS。

一旦某個子網域還沒準備好 HTTPS，

使用者可能會連不上。

`Content-Security-Policy` 更要小心。

CSP 設太鬆沒有意義，

設太緊又可能讓前端資源、第三方 script、圖片、字型突然失效。

我會建議 CSP 優先由應用程式或前端平台管理，

ALB 比較適合用來補一些穩定且跨服務一致的 header。

#### Server Header 可以移除

listener attributes 裡也有 `routing.http.response.server.enabled`。

它控制 ALB response 是否帶出 `server` header。

如果你的安全掃描工具要求減少服務指紋資訊，

可以評估移除。

但也要理解，

移除 `server` header 不是主要防線。

真正重要的還是：

1. WAF 規則
2. TLS policy
3. 後端安全更新
4. 權限與網路隔離
5. 正確的 logging 與 monitoring

不要把移除 header 當成安全性的核心。

它比較像是安全基線裡的一個小整理。

## Rule 層級

Rule 是 ALB 很重要的一層。

Listener 決定 ALB 從哪個 port 收流量，

Rule 則決定收到 request 後要怎麼判斷、怎麼處理。

很多人會把 rule 當成單純的 path routing，

但實際上 rule 裡同時包含兩件事：

1. condition：什麼 request 會命中這條 rule
2. action：命中後要做什麼

### Condition 類設定

Rule condition 常見有幾種：

| Condition | 用途 |
| --- | --- |
| Host header | 依照網域分流，例如 `api.example.com`、`admin.example.com` |
| Path | 依照路徑分流，例如 `/api/*`、`/admin/*` |
| HTTP header | 依照指定 header 分流 |
| HTTP request method | 依照 GET、POST 等 method 分流 |
| Query string | 依照 query string 分流 |
| Source IP | 依照來源 IP 分流 |

最常見的是 Host header 和 Path。

例如：

1. `api.example.com` forward 到 API target group
2. `admin.example.com` 先做 OIDC authentication，再 forward 到 admin target group
3. `/static/*` forward 到另一組 target group

Rule 的 priority 也很重要。

數字越小，優先順序越高。

ALB 會依照 priority 從小到大檢查 rule，

第一條符合的 rule 就會被執行。

如果都沒有命中，

才會走 listener 的 default action。

### Action 類設定

Rule action 常見有幾種：

| Action | 用途 |
| --- | --- |
| Forward | 把 request 轉送到 target group |
| Redirect | 回傳重新導向，例如 HTTP 轉 HTTPS |
| Fixed response | 直接由 ALB 回固定 response |
| Authenticate | 先透過 OIDC 或 Cognito 做登入驗證 |

Forward 是最常見的 action。

如果只有一組 target group，

ALB 會直接把流量轉送過去。

如果有多組 target group，

也可以設定 weighted target groups，

用來做簡單的藍綠部署或 canary release。

Redirect 常見用在 `80` listener：

```text
HTTP:80 -> HTTPS:443
```

Fixed response 則適合做一些簡單的阻擋或維護頁。

例如特定 path 直接回 `403`，

或在後端還沒準備好時先回一個固定訊息。

Authenticate action 是比較容易被忽略但很實用的功能。

它可以放在 forward 前面，

讓 ALB 先透過 OIDC 或 Amazon Cognito 驗證使用者，

驗證通過後才把 request 送到後端。

我在另一篇 Uptime Kuma SSO 的文章中就是用這個做法。

### Rule 的 action 順序

Rule 可以有多個 action，

但順序很重要。

以 OIDC authentication 為例，

常見順序會是：

| Order | Action |
| --- | --- |
| 1 | Authenticate |
| 2 | Forward |

也就是先驗證，

再轉送。

如果順序搞錯，

就可能變成 request 沒有經過驗證就被 forward，

或 rule 行為不符合預期。

### Rule 和 attributes 的差別

Rule 不是 attribute。

它比較像 ALB 的路由邏輯。

Attributes 則是控制 ALB、listener 或 target group 本身的行為。

可以這樣記：

1. attributes 決定 ALB 怎麼處理連線、header、安全行為
2. rules 決定 request 符合條件時要去哪裡、要不要先驗證、要不要 redirect

所以排查 ALB 問題時，

我會先問兩件事：

1. request 有沒有命中預期 rule
2. 命中後，相關 attributes 會不會改變 request 或 response 的行為

這樣比較不會把 listener、rule、target group、attributes 全部混在一起。

## Target Group 層級

Target group 是 ALB 後端服務的集合。

這篇主要談 ALB 和 listener attributes，

但 target group 仍然要放進整體階層裡看。

常見需要注意的 target group 設定有：

1. target type：instance、ip、lambda
2. protocol 與 port
3. protocol version：HTTP/1.1、HTTP/2、gRPC
4. health check path、interval、timeout、threshold
5. deregistration delay
6. stickiness

其中 protocol version 很容易和前面的 HTTP/2 混淆。

`routing.http2.enabled` 說的是 client 到 ALB 這段是否支援 HTTP/2。

Target group 的 protocol version 則是 ALB 到後端 target 這段要怎麼溝通。

如果你在做 gRPC，

或希望後端 target 接 HTTP/2，

就要特別看 target group 的 protocol version。

## 常見建議設定

如果是一般公開網站或 API，

我通常會先這樣看：

| 設定 | 建議 |
| --- | --- |
| `routing.http2.enabled` | 維持 `true` |
| `idle_timeout.timeout_seconds` | 一般 API 維持 `60`，WebSocket 或串流再調高 |
| `client_keep_alive.seconds` | 通常先維持預設 |
| `waf.fail_open.enabled` | 多數公開服務維持 `false` |
| `routing.http.desync_mitigation_mode` | 維持 `defensive`，安全需求高再評估 `strictest` |
| `routing.http.drop_invalid_header_fields.enabled` | 新系統可評估開啟，舊系統先測 |
| `routing.http.preserve_host_header.enabled` | 需要原始 Host 時才開 |
| `routing.http.xff_header_processing.mode` | 多數情境使用 `append` |
| `routing.http.xff_client_port.enabled` | 沒需求就維持 `false` |
| `routing.http.x_amzn_tls_version_and_cipher_suite.enabled` | 需要 TLS 稽核或除錯時開啟 |

如果是內部系統，

還要額外注意：

1. ALB 是 internal 還是 internet-facing
2. 後端 Security Group 是否只允許 ALB 進入
3. 是否需要 OIDC authentication
4. 是否需要透過 WAF 做基本防護
5. Access log 與 connection log 是否有開

很多 ALB 問題不是 listener rule 寫錯，

而是「信任邊界」沒有畫清楚。

只要後端可以被繞過 ALB 直接存取，

前面做的 OIDC、WAF、header、TLS 資訊都會被削弱。

## Terraform 設定範例

下面是一段示意，

展示怎麼在 Terraform 中設定部分 ALB attributes。

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

不同 Terraform AWS Provider 版本支援的參數名稱可能會不同，

所以實作時要以你專案目前的 provider 版本文件為準。

如果 provider 還沒有包到某些比較新的 listener attribute，

可能需要暫時透過 AWS CLI、CloudFormation，

或等 provider 更新後再納入 IaC 管理。

## AWS CLI 檢查方式

如果想快速看某個 ALB 目前的 attributes，

可以用：

```bash
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <alb-arn>
```

如果想看 listener attributes，

可以用：

```bash
aws elbv2 describe-listener-attributes \
  --listener-arn <listener-arn>
```

修改 load balancer attributes 時，

可以用：

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <alb-arn> \
  --attributes Key=routing.http.drop_invalid_header_fields.enabled,Value=true
```

實務上我會建議：

正式環境不要只在 Console 點一點。

至少要把目前設定匯出留存，

最好還是回到 Terraform、CloudFormation 或 CDK 管理。

因為 ALB 這些小設定很多，

而且有些安全差異不是一眼看得出來。

## 小結

ALB 不只是把流量分到 target group 的工具。

它其實是很多 AWS Web 架構的入口控制點。

它可以處理：

1. HTTPS termination
2. HTTP/2
3. WebSocket
4. WAF
5. OIDC authentication
6. Header forwarding
7. Response security headers
8. Global Accelerator 入口整合

也因為它站在入口，

ALB 的設定會直接影響安全、除錯、稽核與應用程式行為。

如果只是把 ALB 當成「有 health check 的反向代理」，

就很容易漏掉這些細節。

我的建議是：

每次建立 ALB 後，

除了 listener、rule、target group 之外，

也要固定檢查 attributes。

特別是 WAF fail open、desync mitigation、invalid header、Host header、X-Forwarded-For、idle timeout、response headers 這幾項。

它們平常很安靜，

但真的遇到安全掃描、登入導向、真實 IP 判斷、WebSocket 斷線或跨網域問題時，

往往就是排查的關鍵。

## 參考資料

1. [Application Load Balancers - Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html)
2. [Listeners for your Application Load Balancers - Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
3. [How AWS Global Accelerator works](https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-how-it-works.html)
4. [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html)
