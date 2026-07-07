---
layout: post
title: "將檔案上傳到 S3 的 5 種方法：Console、CLI、API、SFTP 與 Presigned URL"
description: "比較使用 AWS Management Console、AWS CLI、API Gateway、AWS Transfer Family 與 Presigned URL 上傳檔案到 Amazon S3 的方式、適用情境、安全限制與實作範例。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3]
keywords: [AWS, S3, AWS Management Console, AWS CLI, API Gateway, Transfer Family, Presigned URL]
date: 2026-07-08
---

把檔案上傳到 S3 幾乎是 AWS 最常見的基本操作之一。

但「上傳檔案」背後可能是完全不同的使用情境：工程師從本機上傳、CI 發布靜態檔案、後端接收使用者附件、瀏覽器直接上傳大型檔案，或合作廠商仍然只能使用 SFTP。這些需求雖然最後都把物件寫入 S3，適合的入口卻不相同。

這篇文章比較 5 種實務上常見的做法：

1. AWS Management Console 直接上傳
2. 使用 AWS CLI
3. API Gateway 直接整合 S3，或由後端上傳
4. AWS Transfer Family（SFTP/FTPS 對外交換檔案）
5. Presigned URL（前端或外部客戶端直傳）

## 快速選擇

| 方法 | 適合情境 | 優點 | 主要限制 |
| --- | --- | --- | --- |
| AWS Management Console | 臨時操作、少量檔案、初次接觸 S3 | 不需要安裝工具，操作直觀 | 仰賴人工操作，不適合自動化與大量重複作業 |
| AWS CLI | 工程師、本機維運、CI/CD | 簡單直接，支援目錄與大型檔案 | 執行環境需要 AWS 身分與 IAM 權限 |
| API Gateway／後端 | 小型附件、需要商業邏輯與驗證的 API | 驗證、授權、審計與命名規則集中管理 | 受 API payload 限制；經過後端時也會占用運算資源 |
| AWS Transfer Family | 合作夥伴、舊系統、SFTP/FTPS 流程 | 不必要求對方改用 AWS API | 需要管理端點、使用者、網路與服務成本 |
| Presigned URL | Web、App、第三方系統直接上傳 | 檔案不經過後端，容易擴展 | 必須處理 URL 有效期、CORS、檔名與上傳條件 |

## 方法 1：AWS Management Console

在還沒開始使用 CLI 或 IaC 工具以前，最直觀的做法就是登入 AWS Management Console，開啟 Amazon S3，進入目標 bucket 後選擇「Upload」上傳檔案。

這種方式不需要先安裝工具或撰寫指令，適合臨時上傳、測試，或剛開始熟悉 S3 的情境。上傳時也能在介面中設定 metadata、儲存類別與其他物件屬性。

不過，Console 操作依賴人工執行，難以重複與自動化，因此不適合 CI/CD 或需要固定排程的工作。Amazon S3 Console 目前支援上傳最大 160 GB 的單一檔案；更大的檔案應改用 AWS CLI、AWS SDK 或 S3 REST API。

## 方法 2：AWS CLI

適合工程師在本機、跳板機，或 CI 流程直接上傳檔案。做法簡單、上手快，但要留意 IAM 權限與金鑰管理。

### 上傳單一檔案

```bash
aws s3 cp ./report.csv s3://example-bucket/uploads/report.csv
```

上傳完成後，可以確認物件是否存在：

```bash
aws s3 ls s3://example-bucket/uploads/report.csv
```

### 上傳整個目錄

若要遞迴上傳目錄，可使用 `--recursive`：

```bash
aws s3 cp ./dist s3://example-bucket/site/ --recursive
```

如果需求是讓來源與目的端長期保持同步，則可使用 `sync`：

```bash
aws s3 sync ./dist s3://example-bucket/site/
```

AWS CLI 的高階 S3 指令會在檔案達到 multipart threshold 時，自動改用 Multipart Upload，不需要自行切割每個 part。正式環境建議讓本機使用 AWS IAM Identity Center，而 EC2、ECS、EKS 或 CI Runner 則使用 IAM Role 或短期憑證，避免把長期 Access Key 寫進程式碼與 Pipeline 變數。

> 如果 Bastion 或其他 EC2 instance 上有需要備份的檔案，可以透過 `cron` 定期執行 `aws s3 sync`。建議使用 EC2 的 IAM Role，並將權限限制在專用的 S3 prefix，不要在主機上存放長期 Access Key。
{: .prompt-info }

### 權限設定

#### 透過 WinSCP 或 S3 Browser 上傳

WinSCP、S3 Browser 這類圖形化工具是透過 S3 API 存取物件，並不是在底層執行 AWS CLI。除了上傳物件所需的 `s3:PutObject`，介面若要顯示指定 bucket 內的物件，還需要 `s3:ListBucket`。

有些工具會先列出帳號中的所有 buckets，此時才需要 `s3:ListAllMyBuckets`。這個權限會讓使用者看到帳號內的 bucket 名稱；如果工具能直接設定目標 bucket，便可省略此權限。以下是允許使用者瀏覽並上傳至 `uploads/` 的範例：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListUploadPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uploads", "uploads/*"]
        }
      }
    },
    {
      "Sid": "UploadObjects",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    },
    {
      "Sid": "ListBucketsInClient",
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

如果還要讓使用者下載或刪除物件，再依實際需求加入 `s3:GetObject` 或 `s3:DeleteObject`，不必一開始就全部開放。

#### 透過 CLI 上傳

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListUploadPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uploads", "uploads/*"]
        }
      }
    },
    {
      "Sid": "UploadObjects",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    }
  ]
}
```

這份權限足以上傳並查看 `uploads/`。如果要執行前面以 `site/` 為目標的目錄上傳，必須把該 prefix 一併加入 policy；若只需要上傳、不需要列出物件，則可以移除 `s3:ListBucket`。

## 方法 3：API Gateway 直接整合 S3，或由後端上傳

### API Gateway 直接上傳到 S3

API Gateway 不只能呼叫 Lambda。使用 REST API 的 AWS service integration，也能將請求直接交給 S3，不必先經過 Lambda：

```text
Client → API Gateway REST API → Amazon S3
```

設定時需要建立 API Gateway 的 execution role，允許它對指定位置執行 `s3:PutObject`。例如只允許寫入 `uploads/`：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    }
  ]
}
```

接著在 REST API 建立 `PUT` method，選擇 S3 作為 AWS service integration，將 URL 中的檔名映射到 S3 object key，並傳遞上傳所需的 `Content-Type`。若要接收二進位檔案，還必須設定 API 的 binary media types。

execution role 只代表 API Gateway 有權寫入 S3，並不等於呼叫者已通過驗證；對外提供 API 時，仍要另外設定 IAM、Cognito Authorizer 或其他授權機制。這個做法雖然省去 Lambda，但檔案內容仍會經過 API Gateway，因此依然受到 10 MB 的 payload 上限限制。

### 透過 Lambda 或後端上傳

適合要由後端統一控管驗證、授權與審計的場景。彈性高，但系統複雜度也會提高。

```text
Client → API Gateway → Lambda／Backend → Amazon S3
```

在這個架構中，後端可以先確認登入身分、檔案類型、業務單號與物件名稱，再透過 AWS SDK 呼叫 `PutObject`。核心操作大致如下；實際的 HTTP request 解析與錯誤處理會依框架而不同：

```python
import boto3

s3 = boto3.client("s3")

s3.put_object(
    Bucket="example-bucket",
    Key="uploads/report.pdf",
    Body=file_bytes,
    ContentType="application/pdf",
)
```

這種方式的優點是所有規則都集中在後端。例如只有訂單擁有者可以上傳附件、資料庫寫入成功後才能建立物件，或必須在上傳後觸發掃毒與審核流程。

缺點是檔案內容會先經過 API Gateway 與後端，占用兩段網路流量及運算資源。以 API Gateway HTTP API 為例，payload size 上限為 10 MB，而且不能提高；如果請求還需要 Base64 編碼，實際可承載的原始檔案會更小。因此，這種方式比較適合小型附件，不適合大型影片、備份或資料集。

大型檔案通常應改用 Presigned URL，讓 API Gateway 只負責驗證使用者並產生上傳授權，而不是傳送檔案本體。

## 方法 4：AWS Transfer Family

適合需要 SFTP/FTPS 與外部系統交換檔案的場景，能讓既有流程較平順地接上 S3。

AWS Transfer Family 是 AWS 代管的檔案傳輸服務，支援 SFTP、FTPS、FTP、AS2 與瀏覽器式傳輸，後端可以使用 S3 或 EFS。對方仍然可以使用熟悉的 WinSCP、Cyberduck、FileZilla 或 OpenSSH，不需要先學會 AWS CLI 或取得 AWS 憑證。

基本流程如下：

1. 建立 S3 bucket 與 Transfer Family 使用的 IAM Role。
2. 建立支援 SFTP 或 FTPS 的 Transfer Family Server。
3. 選擇 Service managed、Microsoft AD 或自訂 Identity Provider。
4. 為使用者設定 Home Directory 與可存取的 S3 prefix。
5. 將 Transfer Family endpoint 提供給合作夥伴。

使用 SFTP client 上傳時，操作方式和一般 SFTP server 相同：

```bash
sftp -i ~/.ssh/partner-key partner@s-0123456789abcdef0.server.transfer.ap-northeast-1.amazonaws.com
sftp> put report.csv /uploads/report.csv
```

要注意的是，S3 本身沒有真正的目錄階層，SFTP client 顯示的目錄實際上是 object key prefix。`chmod`、symbolic link 等檔案系統操作，也不一定能對應到 S3。

Transfer Family 適合既有 B2B 檔案交換、固定來源 IP、企業身分驗證或不容易修改的舊系統。若只是偶爾讓單一使用者上傳一個檔案，建置 Transfer Family 往往比 Presigned URL 更複雜，也要評估 endpoint 與資料傳輸成本。

## 方法 5：Presigned URL

適合前端或第三方客戶端直接上傳，減少後端流量壓力。需要設定合理的過期時間與上傳條件。

```text
1. Client 向 Backend 請求上傳授權
2. Backend 驗證身分並產生 Presigned URL
3. Client 使用 URL 直接把檔案 PUT 到 S3
4. S3 Event 通知後續處理流程
```

產生 Presigned URL 的 IAM principal 必須擁有對目標 object key 的上傳權限。以下 Python 範例建立一個 15 分鐘內有效、只用於指定 object key 的 `PUT` URL：

```python
import boto3

s3 = boto3.client("s3")

upload_url = s3.generate_presigned_url(
    ClientMethod="put_object",
    Params={
        "Bucket": "example-bucket",
        "Key": "uploads/8f6c2f4a/report.pdf",
        "ContentType": "application/pdf",
    },
    ExpiresIn=900,
)
```

Client 取得 URL 後即可直接上傳：

```bash
curl --request PUT \
  --header "Content-Type: application/pdf" \
  --upload-file ./report.pdf \
  "<presigned-url>"
```

如果 `Content-Type` 被納入簽章，Client 上傳時必須使用相同的 header，否則 S3 會回傳簽章不符。瀏覽器直接上傳時，也要在 bucket 設定允許指定網域與 HTTP method 的 CORS 規則。

Presigned URL 應視為短期的 Bearer Token：拿到 URL 的人，在過期前都能使用它。實作時至少要注意：

- 由後端決定 bucket 與 object key，不要直接信任使用者提交的完整路徑。
- 使用 UUID 或 tenant prefix，避免不同使用者覆寫同一個 key。
- 設定短而合理的有效期限，不要把 URL 寫進公開 Log 或分析工具。
- 上傳前驗證可接受的副檔名、MIME type 與業務狀態，上傳後再驗證實際內容。
- 如果需要限制檔案大小或表單欄位，可考慮 Presigned POST 與 policy condition。
- 大型檔案可進一步使用 Presigned Multipart Upload，讓 Client 分段、平行與重試上傳。

同一個 Presigned URL 在過期前可以重複使用；如果目標 key 已存在，未啟用 Versioning 時可能覆寫原物件，啟用 Versioning 時則會建立新版本。它不是一次性 URL，因此不能只依賴「使用過一次」來保證安全。

## 共通的安全與維運考量

無論選擇哪一種方法，都應該檢查以下項目：

### IAM 最小權限

限制可存取的 bucket、prefix 與操作。只負責上傳的程式通常只需要 `s3:PutObject`；確實需要查詢、下載或刪除時，再加入 `s3:ListBucket`、`s3:GetObject` 或 `s3:DeleteObject`。修改 bucket policy 或 Lifecycle rule 等管理權限，不應交給一般的上傳程式。

### 避免物件被意外覆寫

S3 的 object key 就是物件識別名稱。同一個 key 再次上傳時可能覆寫原物件；需要保留歷史時，應啟用 S3 Versioning，或使用不可重複的 key。

### 加密與敏感資料

S3 會自動使用 SSE-S3 加密新上傳的物件。若法規、稽核或權限分離要求使用客戶管理金鑰，可以設定 bucket 預設使用 SSE-KMS，並補上需要的 KMS 權限。

### 檔案內容不能只相信副檔名

`.jpg`、`.pdf` 或 `Content-Type` 都由 Client 提供，不能證明內容安全。外部上傳應先進入隔離 prefix，再透過事件驅動流程進行格式檢查、掃毒或人工審核，確認後才移到正式區域。

### 大型檔案與未完成上傳

S3 單次 `PUT` 最多可上傳 5 GB；更大的物件要使用 Multipart Upload，目前單一 S3 object 最大可達 50 TB。Multipart Upload 若未完成，已上傳的 parts 仍會產生儲存費用，應設定 Lifecycle rule 自動清除逾期且未完成的上傳。

## 小結

沒有單一最佳方案，重點是誰在上傳、檔案多大、是否需要相容既有協定，以及檔案內容是否必須經過後端。

- 臨時上傳少量檔案：使用 AWS Management Console。
- 受信任的工程師或 CI/CD：先從 AWS CLI 開始。
- 小型檔案只需要轉送至 S3：可使用 API Gateway 的 AWS service integration。
- 小型檔案且必須由後端執行商業邏輯：使用 API Gateway + Backend。
- 合作夥伴只能使用 SFTP/FTPS：使用 AWS Transfer Family。
- Web、App 或第三方直接上傳：優先考慮 Presigned URL。

多數面向終端使用者的上傳功能，可以讓後端負責「授權與決定 object key」，再讓 Client 透過 Presigned URL 將檔案直接送到 S3。這通常能在安全、效能與系統複雜度之間取得較好的平衡。

---

## 參考資料

- [AWS CLI `s3 cp` Command Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html)
- [Uploading objects - Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/upload-objects.html)
- [Listing Amazon S3 general purpose buckets](https://docs.aws.amazon.com/AmazonS3/latest/userguide/list-buckets.html)
- [Tutorial: Create a REST API as an Amazon S3 proxy](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-s3.html)
- [Quotas for configuring and running a REST API in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html)
- [Quotas for configuring and running an HTTP API in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html)
- [What is AWS Transfer Family?](https://docs.aws.amazon.com/transfer/latest/userguide/what-is-aws-transfer-family.html)
- [Download and upload objects with presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)
- [Configuring cross-origin resource sharing (CORS)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ManageCorsUsing.html)
- [Configuring default encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html)
- [Deleting incomplete multipart uploads with a Lifecycle rule](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-abort-incomplete-mpu-lifecycle-config.html)
