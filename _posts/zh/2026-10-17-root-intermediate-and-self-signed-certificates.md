---
layout: post
title: "根憑證、中繼憑證與網站憑證：建立自簽憑證與檢查有效期限"
description: "了解根憑證、中繼憑證與網站憑證的關係，使用 OpenSSL 建立自簽憑證、檢查有效日期與憑證鏈，並排查缺少中繼憑證的問題。"
author: Mark_Mew
categories: [Security]
tags: [TLS, HTTPS, OpenSSL, Certificate]
keywords: [根憑證, 中繼憑證, 自簽憑證, OpenSSL, 憑證有效期限, 憑證鏈]
lang: zh-TW
date: 2026-10-17
---

當瀏覽器連上 HTTPS 網站時，伺服器會提供憑證，讓瀏覽器確認網站身分。這個過程通常涉及根憑證、中繼憑證與網站憑證。本文先說明三者的關係，再示範如何用 OpenSSL 建立自簽憑證、檢查憑證資訊與排查憑證鏈問題。

## 根憑證、中繼憑證與網站憑證

常見的憑證鏈如下：

```text
根憑證（Root CA）
  └─ 中繼憑證（Intermediate CA）
       └─ 網站憑證（Server / Leaf Certificate）
```

**根憑證**是信任的起點，通常已收錄在作業系統或瀏覽器的信任清單中。根憑證一般是自簽的，但「自簽」本身不代表可信任；用戶端必須先信任這張根憑證。

**中繼憑證**由根憑證或另一張中繼憑證簽發，再用來簽發網站憑證。它把網站憑證連到可信任的根憑證。

**網站憑證**是伺服器實際使用的憑證，包含適用網域、公開金鑰及有效期間。伺服器持有對應的私鑰，私鑰不應傳給用戶端。

驗證時，用戶端會嘗試從網站憑證往上建立憑證鏈，並檢查簽章、有效期間、用途及網域名稱等條件。詳見 [OpenSSL 憑證驗證文件](https://docs.openssl.org/3.4/man1/openssl-verification-options/)。

## 用 OpenSSL 產生自簽憑證

以下範例建立一張供本機測試使用、有效期為 365 天的自簽網站憑證。執行前請先確認已安裝 OpenSSL。

```bash
openssl req -x509 -newkey rsa:2048 -sha256 -noenc \
  -keyout localhost.key \
  -out localhost.crt \
  -days 365 \
  -subj "/CN=localhost" \
  -addext "subjectAltName=DNS:localhost" \
  -addext "basicConstraints=critical,CA:FALSE"
```

執行後會得到 `localhost.key`（私鑰）和 `localhost.crt`（憑證）。`-x509` 讓指令直接產生自簽憑證；`-days 365` 設定有效天數；`subjectAltName` 指定憑證適用的名稱。若要測試其他網域，請調整 `subjectAltName`，並同步調整範例中的 `CN`。這裡使用 `-noenc` 產生未加密的私鑰，適合本機測試；請妥善保管私鑰，不要提交到公開儲存庫。參數說明可參考 [OpenSSL `req` 文件](https://docs.openssl.org/3.4/man1/openssl-req/)。

這張憑證沒有連到瀏覽器原本信任的根憑證，因此瀏覽器通常會顯示信任警告。**憑證仍在有效期內，不代表它受到信任。**

## 檢查憑證資訊與有效日期

查看憑證的持有人、簽發者和有效日期：

```bash
openssl x509 -in localhost.crt -noout -subject -issuer -dates
```

輸出中的 `notBefore` 是開始有效時間，`notAfter` 是到期時間。若要檢查網域名稱、用途及其他詳細欄位：

```bash
openssl x509 -in localhost.crt -noout -text
```

檢查憑證是否會在未來 30 天內到期：

```bash
openssl x509 -in localhost.crt -noout -checkend 2592000
```

`2592000` 是 30 天的秒數。結束碼為 `0` 代表 30 天後仍未到期；非 `0` 代表屆時會過期。這只檢查單張憑證的到期時間，不能取代完整的憑證鏈驗證。詳見 [OpenSSL `x509` 文件](https://docs.openssl.org/3.2/man1/openssl-x509/)。

## 驗證憑證鏈與線上網站

若手上有網站憑證 `server.crt`、中繼憑證 `intermediate.crt` 及可信任的根憑證 `root.crt`，可驗證憑證鏈與網域名稱：

```bash
openssl verify -CAfile root.crt \
  -untrusted intermediate.crt \
  -verify_hostname example.com \
  server.crt
```

成功時會顯示 `server.crt: OK`。`-CAfile` 指定信任的根憑證；`-untrusted` 提供建立憑證鏈所需的中繼憑證，不會因此直接信任該中繼憑證。詳見 [OpenSSL 憑證驗證選項](https://docs.openssl.org/3.4/man1/openssl-verification-options/)。

若要查看線上伺服器實際送出哪些憑證：

```bash
openssl s_client -connect example.com:443 \
  -servername example.com \
  -showcerts \
  -verify_hostname example.com \
  -verify_return_error
```

`-showcerts` 顯示伺服器傳送的憑證清單，但這份清單本身不代表驗證成功。`-servername` 指定連線的網站名稱，對共用同一 IP 的 HTTPS 網站尤其重要。詳見 [OpenSSL `s_client` 文件](https://docs.openssl.org/3.4/man1/openssl-s_client/)。

## 常見 QA

### 自簽憑證和根憑證是一樣的嗎？

不是。根憑證通常是自簽的，但自行產生的自簽憑證不會自動成為用戶端信任的根憑證。

### 網站一定要送出根憑證嗎？

通常不需要。用戶端一般透過自己的信任清單取得根憑證；網站主要需要提供網站憑證，以及建立憑證鏈所需的中繼憑證。

### 少了中繼憑證會怎麼樣？

如果 API 伺服器只送出網站憑證，卻漏送必要的中繼憑證，呼叫端可能無法把它連到自己信任的根憑證。這時憑證驗證會在 TLS 握手階段失敗，HTTP 請求還沒送出，程式就可能報錯，例如 `unable to get local issuer certificate` 或 `certificate verify failed`。因此看起來像是「API 呼叫失敗」，實際上問題可能出在 HTTPS 憑證鏈，而不是 API 的程式邏輯。

有些用戶端可能已快取該中繼憑證，或能從其他來源取得它，因此同一個 API 可能在瀏覽器正常，卻在某些程式、容器或執行環境失敗。應在 API 伺服器設定中提供必要的中繼憑證，並用 `openssl s_client -showcerts` 檢查伺服器實際送出的內容；不要以關閉呼叫端憑證驗證作為正式修復方式。


> 這問題通常不常發生，會發生情況常見於更換憑證時，忘了匯入中繼憑證。
{: .prompt-info}
![Certificate Manager import certificate](/assets/img/aws_certificate_manager.png)

### 憑證還沒過期，為什麼瀏覽器仍顯示警告？

到期時間只是檢查項目之一。網域名稱不符、憑證鏈不完整、根憑證不受信任，或憑證尚未到生效時間，都可能使驗證失敗。
