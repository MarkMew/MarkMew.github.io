---
layout: post
title: "如何使用 Amazon S3 架設靜態網站"
image: https://fastly.picsum.photos/id/954/1200/630.jpg?hmac=c_eAwJdG1uf9VexIXGqgw1DL9Rrtj96kbFIedSnoV7U
description: "使用 Amazon S3 建立靜態網站，介紹 Bucket 建立、靜態網站託管、公開存取政策、重新導向，以及網站檔案上傳與測試。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, Static Website]
keywords: [AWS, Amazon S3, S3 Static Website, S3 Website Hosting, S3 Bucket Policy]
lang: zh-TW
date: 2026-08-13
---

Amazon S3 除了可以存放檔案，也能用來快速架設靜態網站。

如果網站只包含 HTML、CSS、JavaScript、圖片等靜態檔案，便不需要先建立 EC2、安裝 Web Server，日後也不用自行負責作業系統與伺服器的維運。

因此，S3 不只是適合用來展示概念驗證（PoC），也是一個設定簡單、維運成本低的靜態網站託管服務。

不過，S3 靜態網站託管有一個重要限制：S3 的 Website endpoint 只支援 HTTP，不支援 HTTPS。這篇文章先以簡單可運作的 S3 靜態網站為主，說明基本設定與存取方式。

## 建立 S3 Bucket

首先進入 Amazon S3 Console，建立一個新的 Bucket。

Bucket 名稱必須符合 DNS 命名規則，而且在 AWS 的所有帳號與 Region 中都必須是唯一的。這個名稱除了是 Bucket 的識別名稱，也會成為之後網站網址的一部分，因此建議一開始就使用不容易變動的名稱。

![S3 Create Bucket](/assets/img/s3/s3-create-bucket.png)

### 物件擁有權

在「物件擁有權」設定中，通常保留預設的「ACL 停用」即可。

停用 ACL 後，物件的存取權限會集中由 Bucket policy 或 IAM policy 管理，權限邏輯會比較容易理解，也能避免不同上傳者造成物件擁有權不一致的問題。

只有在確定需要使用舊式 ACL，或是必須針對個別物件設定 ACL 時，才需要考慮啟用 ACL。

![S3 Object Owner](/assets/img/s3/s3-object-owner.png)

### 封鎖公開存取

如果要直接透過 S3 Website endpoint 讓任何訪客讀取網站內容，就必須取消「封鎖所有公開存取」。

![S3 Block Public Access](/assets/img/s3/s3-block-public-access.png)

取消後，AWS 會要求確認此 Bucket 可能被公開存取。請先確認 Bucket 只會存放可以公開提供的網站檔案，不要把密碼、私密金鑰、備份檔或其他敏感資料放在裡面。

如果帳號層級的 Block Public Access 仍然開啟，Bucket 層級的設定可能仍無法讓公開 policy 生效。這時需要依照組織的安全規範，檢查帳號或 Organization 層級的公開存取設定。

其餘設定先維持預設值，接著按下「建立 Bucket」即可。

## 啟用靜態網站託管

建立 Bucket 後，進入 Bucket 的「屬性」分頁，拉到頁面最下方，找到「靜態網站託管」。

![S3 Host static website](/assets/img/s3/s3-host-static-website.png)

按下「編輯」，啟用靜態網站託管，並設定以下內容：

- 索引文件：`index.html`
- 錯誤文件：`error.html`

索引文件是使用者進入網站根目錄時，S3 預設回傳的頁面；錯誤文件則是在找不到檔案時顯示的頁面。錯誤文件可以依照網站需求改成其他檔名，但檔案必須實際存在於 Bucket 中。

![S3 Edit host static website settings](/assets/img/s3/s3-edit-host-static-website.png)

設定完成後，S3 會在同一個頁面顯示 Website endpoint。建議直接複製 Console 顯示的網址，因為不同 Region 的 endpoint 格式可能略有差異。

## 設定網站重新導向

如果網站路徑有變更，可以使用重新導向規則，避免原本的網址直接變成 404。

例如，網站中的 `docs` 資料夾改名為 `documents`，就可以把原本以 `docs/` 開頭的請求導向新的路徑：

```json
[
  {
    "Condition": {
      "KeyPrefixEquals": "docs/"
    },
    "Redirect": {
      "ReplaceKeyPrefixWith": "documents/"
    }
  }
]
```

這類規則適合處理網站路徑調整或舊網址相容問題。若只是單一頁面的變更，也可以在網站程式中處理導向，或直接保留一個舊檔案來轉址。

## 設定 Bucket policy

S3 預設不會讓網際網路上的匿名使用者讀取物件。若要讓靜態網站公開，必須建立一個只允許讀取物件的 Bucket policy。

進入 Bucket 的「權限」分頁，在「Bucket policy」中貼上以下內容，並將 `YOUR_BUCKET_NAME` 替換成實際的 Bucket 名稱：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicReadForWebsite",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/*"
    }
  ]
}
```

這個 policy 的作用是允許任何人讀取 Bucket 中的物件，但不包含上傳、修改或刪除權限。若只想公開某個資料夾，也可以把 Resource 限縮成特定 prefix，例如：

```json
"Resource": "arn:aws:s3:::YOUR_BUCKET_NAME/public/*"
```

如果覺得每個物件都要設定存取權限很麻煩，使用 Bucket policy 會比較適合。之後上傳新的檔案，只要檔案位於 policy 的範圍內，就會自動套用相同的讀取規則，不需要逐一設定物件權限。

> 將 Bucket 設為公開，代表任何人都可能讀取範圍內的物件。請確認 Bucket 只存放可公開的網站資源，並定期檢查 Bucket policy 與存取紀錄。
{: .prompt-warning}

## 上傳網站檔案並測試

接著將 `index.html`、`error.html`、CSS、JavaScript 與圖片等網站檔案上傳到 Bucket。

完成後，使用 S3 Console 顯示的 Website endpoint 開啟網站。一般會是以下其中一種格式：

```text
http://YOUR_BUCKET_NAME.s3-website-YOUR_REGION.amazonaws.com
```

或：

```text
http://YOUR_BUCKET_NAME.s3-website.YOUR_REGION.amazonaws.com
```

例如，網站根目錄會自動載入先前設定的 `index.html`；如果直接輸入一個不存在的路徑，則會顯示 `error.html`。

### Website endpoint 與 REST endpoint 的差異

這兩種網址很容易混淆：

| Endpoint | 用途 | HTTPS | 是否套用網站設定 |
| --- | --- | --- | --- |
| S3 Website endpoint | 存取靜態網站 | 不支援 | 支援 index、error 與 redirect |
| S3 REST endpoint | 存取指定物件或使用 S3 API | 支援 | 不套用 Website endpoint 的網站行為 |

例如，`https://YOUR_BUCKET_NAME.s3.YOUR_REGION.amazonaws.com/index.html` 是 REST endpoint 的物件網址。它可以用 HTTPS 讀取指定的 `index.html`，但不等同於 S3 靜態網站的 Website endpoint，也不會完整套用網站根目錄、錯誤頁面與重新導向設定。

## 監控請求與成本

S3 的費用不只包含儲存空間，也可能包含請求次數、資料傳出與其他相關服務費用。網站流量增加時，建議定期檢查 S3 的儲存量、請求數與資料傳出量。

如果需要更細緻地觀察請求數、錯誤與延遲，可以參考之前的文章：[如何啟用 Amazon S3 Request Metrics：用 CloudWatch 監控請求、錯誤與延遲](/posts/enable-s3-metrics)。

監控之外，也建議設定 AWS Budgets 或 CloudWatch Alarm，在流量或費用異常時及早收到通知。若網站內容是公開的，還要留意檔案被大量下載或遭到惡意請求的情況。

## 結語

使用 S3 架設靜態網站的流程並不複雜：建立 Bucket、啟用靜態網站託管、設定公開讀取 policy，再上傳網站檔案，就能快速得到一個可以存取的網站。

這種方式很適合個人網站、文件頁面、產品展示頁與概念驗證。由於直接公開 S3 Website endpoint 只支援 HTTP，使用前請先確認網站內容不涉及需要加密傳輸的敏感資訊。

在啟用公開存取前，先確認 Bucket 裡沒有敏感資料；網站上線後，再搭配成本監控與請求監控，就能在維持簡單架構的同時，降低誤設權限與流量異常造成的風險。

## 參考資料

- [Tutorial: Configuring a static website on Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/HostingWebsiteOnS3Setup.html)
- [Website endpoints for Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteEndpoints.html)
- [Setting permissions for website access](https://docs.aws.amazon.com/AmazonS3/latest/userguide/WebsiteAccessPermissionsReqd.html)
