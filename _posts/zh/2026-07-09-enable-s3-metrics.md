---
layout: post
title: "如何啟用 Amazon S3 Request Metrics：用 CloudWatch 監控請求、錯誤與延遲"
image: https://fastly.picsum.photos/id/403/1200/630.jpg?hmac=s8l5rkJ33EaYe1pNzAO8voSUhrQoQlScUq0cxuPM2bk
description: "介紹 Amazon S3 Storage Metrics 與 Request Metrics 的差異，並示範透過 AWS Console、AWS CLI、Terraform 和 CloudFormation 啟用請求指標。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, CloudWatch, Terraform]
keywords: [AWS, Amazon S3, CloudWatch, S3 Metrics, S3 Request Metrics, Terraform]
date: 2026-07-09
---

Amazon S3 是 AWS 歷史最悠久、也最常使用的服務之一。除了存放檔案，它也經常作為備份空間、靜態網站來源、Data Lake，或應用程式上傳檔案的目的地。

建立 bucket 後，可以在 Metrics 頁面看到 `BucketSizeBytes` 和 `NumberOfObjects` 等容量指標，但如果要回答以下問題，只有容量資料就不夠了：

- 最近每分鐘有多少次 `GET` 或 `PUT`？
- 使用者遇到的 `4xx` 或 `5xx` 錯誤是否增加？
- S3 回應時間是否變慢？
- 哪一個 prefix 的流量最大？

這時便需要啟用 Amazon S3 Request Metrics。本文會先說明不同 S3 指標的差異，再分別示範如何透過 AWS Management Console、AWS CLI、Terraform 與 CloudFormation 啟用它。

## S3 有哪些 CloudWatch 指標？

S3 傳送至 CloudWatch 的指標大致可以分成以下幾類：

| 類型 | 更新頻率 | 是否預設啟用 | 常見用途 |
| --- | --- | --- | --- |
| Storage Metrics | 每日一次 | 是，不另外收費 | 查看 bucket 容量與物件數量 |
| Request Metrics | 一分鐘 | 否，需要建立 metrics configuration | 監控請求量、錯誤率、流量與延遲 |
| Replication Metrics | 一分鐘 | 需在 replication rule 啟用 | 監控複寫延遲、待複寫資料與失敗操作 |
| S3 Storage Lens | 每日彙整，可選進階方案 | 有免費與付費方案 | 跨帳號、Region 或組織分析儲存與活動狀況 |

所以，S3 並不是只有兩個指標，而是預設只提供每日更新的 Storage Metrics。要取得接近即時的請求資訊，必須額外建立 Request Metrics configuration。

> Request Metrics 依 CloudWatch 標準費率計價，而且採 best-effort 傳送。它適合觀察趨勢、建立 Dashboard 與 Alarm，但不應當作逐筆請求稽核或精確計費資料。需要完整記錄時，應搭配 S3 Server Access Logging 或 CloudTrail Data Events。
{: .prompt-warning }

## 啟用後可以看到哪些資料？

Request Metrics 會將資料送到 CloudWatch 的 `AWS/S3` namespace，常用指標包括：

- `AllRequests`：所有 HTTP 請求數量。
- `GetRequests`、`PutRequests`、`DeleteRequests`：依操作類型統計請求。
- `ListRequests`：列出 bucket 內容的請求。
- `BytesDownloaded`、`BytesUploaded`：下載與上傳的位元組數。
- `4xxErrors`、`5xxErrors`：Client 與 Server 端錯誤。
- `FirstByteLatency`：從收到請求到開始回傳第一個 byte 的時間。
- `TotalRequestLatency`：從收到請求到完成回應的時間。

每個 metrics configuration 都會啟用完整的一組 Request Metrics；不能只打開其中一個指標。沒有發生過的操作也可能暫時不會出現在 CloudWatch 中。

## 篩選整個 bucket 或指定物件

建立 configuration 時，可以監控整個 bucket，也可以使用以下條件縮小範圍：

- Object key prefix，例如 `uploads/` 或 `logs/production/`。
- Object tag，例如 `environment=production`。
- S3 Access Point ARN。
- 同時組合多個條件；物件必須符合全部條件才會被納入。

如果 bucket 由多個系統共用，建議依應用程式或 prefix 分開建立 configuration，例如 `production-uploads` 與 `audit-logs`。這樣 CloudWatch 的 `FilterId` 維度便能區分不同工作負載，也能避免收集不需要的資料。

需要留意：使用 filter 時，只有符合條件的單一物件操作會被計入。`ListObjects`、`DeleteObjects` 這類無法對應至單一物件的請求，不會出現在有 filter 的 configuration 中。如果要掌握 bucket 的完整請求量，應另外建立一個不含 filter 的 configuration。

## 方法一：使用 AWS Management Console

在 Console 中啟用最直觀，操作步驟如下：

1. 開啟 Amazon S3 Console，進入目標 general purpose bucket。
2. 選擇 **Metrics** 頁籤。
3. 在 **Bucket metrics** 區域選擇 **View additional charts**。
4. 切換至 **Request metrics**，選擇 **Create filter**。
5. 輸入 Filter name，例如 `EntireBucket`。
6. 若要監控整個 bucket，不設定篩選條件；若只監控部分物件，則加入 prefix、object tags 或 S3 Access Point。
![建立S3篩選器](/assets/img/amazon_s3_create_filter.png)
7. 儲存設定。

建立完成後不會立刻看到圖表。AWS 文件指出，CloudWatch 開始追蹤後大約需要 15 分鐘才會出現資料；如果 bucket 當下沒有任何請求，也不會產生相對應的指標。

## 方法二：使用 AWS CLI

透過 AWS CLI 可以把操作納入 Script 或 CI/CD。以下設定會啟用整個 bucket 的 Request Metrics：

```bash
aws s3api put-bucket-metrics-configuration \
  --bucket example-bucket \
  --id EntireBucket \
  --metrics-configuration '{"Id":"EntireBucket"}'
```

如果只想監控 `uploads/` prefix，可以加入 `Filter`：

```bash
aws s3api put-bucket-metrics-configuration \
  --bucket example-bucket \
  --id Uploads \
  --metrics-configuration '{"Id":"Uploads","Filter":{"Prefix":"uploads/"}}'
```

執行後可列出目前的設定：

```bash
aws s3api list-bucket-metrics-configurations \
  --bucket example-bucket
```

若要移除設定，可執行：

```bash
aws s3api delete-bucket-metrics-configuration \
  --bucket example-bucket \
  --id Uploads
```

建立、更新或刪除設定的 IAM principal 需要 `s3:PutMetricsConfiguration` 權限；讀取與列出設定則需要 `s3:GetMetricsConfiguration`。

## 方法三：使用 Terraform

若 bucket 已由 Terraform 管理，建議也用 Terraform 建立 Request Metrics，避免 Console 設定無法被版本控制。

### 監控整個 bucket

```hcl
resource "aws_s3_bucket" "example" {
  bucket = "example-bucket"
}

resource "aws_s3_bucket_metric" "entire_bucket" {
  bucket = aws_s3_bucket.example.id
  name   = "EntireBucket"
}
```

`aws_s3_bucket_metric` 的 `name` 會成為 metrics configuration ID，也就是 CloudWatch 中的 `FilterId`。

### 依 prefix 與 object tag 篩選

```hcl
resource "aws_s3_bucket_metric" "production_uploads" {
  bucket = aws_s3_bucket.example.id
  name   = "ProductionUploads"

  filter {
    prefix = "uploads/"

    tags = {
      environment = "production"
    }
  }
}
```

套用前先檢查預計變更，再建立資源：

```bash
terraform plan
terraform apply
```

如果 bucket 已經存在、但目前不由同一份 Terraform 管理，可以直接把 bucket 名稱填入 `bucket`，不必為了啟用 metrics 重新建立 bucket：

```hcl
resource "aws_s3_bucket_metric" "entire_bucket" {
  bucket = "existing-example-bucket"
  name   = "EntireBucket"
}
```

## 方法四：使用 AWS CloudFormation

CloudFormation 可在 `AWS::S3::Bucket` 的 `MetricsConfigurations` 中宣告設定：

```yaml
Resources:
  ExampleBucket:
    Type: AWS::S3::Bucket
    Properties:
      BucketName: example-bucket
      MetricsConfigurations:
        - Id: EntireBucket
        - Id: Uploads
          Prefix: uploads/
```

如果要加入 object tag filter，可以使用 `TagFilters`：

```yaml
MetricsConfigurations:
  - Id: ProductionUploads
    Prefix: uploads/
    TagFilters:
      - Key: environment
        Value: production
```

CloudFormation 更新 metrics configuration 時會完整取代原本的設定。因此修改 template 時，要保留仍然需要的 configuration，否則未列出的項目會被刪除。

## 如何在 CloudWatch 找到指標？

Request Metrics 開始產生資料後，可依以下路徑查看：

1. 開啟 Amazon CloudWatch Console。
2. 進入 **Metrics** → **All metrics**。
3. 選擇 **S3**。
4. 選擇 **Request metrics**，或依 `BucketName` 與 `FilterId` 尋找資料。

CloudWatch 必須切換到 bucket 所在的 Region。若找不到指標，可依序檢查：

1. metrics configuration 是否已成功建立。
2. 查詢的 AWS 帳號與 Region 是否正確。
3. bucket 是否在啟用後真的收到請求。
4. prefix 或 tag filter 是否與實際物件相符。
5. 是否已等待約 15 分鐘。

實務上可以先對測試物件執行幾次 `PUT`、`GET`，再查看 `AllRequests`、`PutRequests` 與 `GetRequests`。如果要建立告警，常見做法是監控 `5xxErrors`、`FirstByteLatency`，或搭配 Metric Math 計算 `4xxErrors / AllRequests` 的比例。

## 費用與使用建議

Request Metrics 按 CloudWatch metrics 計價。每新增一個 configuration，都可能產生一整組指標，因此不要為每個細小 prefix 建立 filter，也不要在大量 bucket 上未經評估便全部啟用。

建議先從重要的 production bucket 開始，並依照真正需要告警或排錯的工作負載建立 configuration：

- 想掌握 bucket 整體健康狀況：建立一個不含 filter 的 `EntireBucket`。
- 多個應用程式共用 bucket：按 prefix 或 Access Point 分組。
- 只關心特定資料：使用 prefix 加 object tag 限縮範圍。
- 需要逐筆稽核：改用 CloudTrail Data Events 或 S3 Server Access Logging。
- 需要跨 bucket、帳號或組織的長期分析：評估 S3 Storage Lens。

單一 bucket 最多可以建立 1,000 個 metrics configurations，但配額上限不代表適合建立這麼多。configuration 越多，Dashboard、Alarm 與費用管理也會越複雜。

## 小結

S3 預設的 Storage Metrics 適合觀察容量，卻無法即時反映應用程式的請求量、錯誤與延遲。啟用 Request Metrics 後，就能在 CloudWatch 以一分鐘的粒度查看 `GET`、`PUT`、`4xx`、`5xx`、傳輸量與 latency，並進一步建立 Dashboard 和 Alarm。

測試或單次設定可使用 AWS Console；需要自動化時可使用 AWS CLI；正式環境則建議用 Terraform 或 CloudFormation 納入版本控制。最後別忘了 Request Metrics 並非免費且採 best-effort 傳送：它是維運監控工具，不是完整的存取稽核紀錄。

---

## 參考資料

- [Monitoring metrics with Amazon CloudWatch](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-dimensions.html)
- [CloudWatch metrics configurations](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-configurations.html)
- [Creating a metrics configuration that filters by prefix, object tag, or access point](https://docs.aws.amazon.com/AmazonS3/latest/userguide/metrics-configurations-filter.html)
- [PutBucketMetricsConfiguration API](https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutBucketMetricsConfiguration.html)
- [AWS::S3::Bucket MetricsConfiguration](https://docs.aws.amazon.com/AWSCloudFormation/latest/TemplateReference/aws-properties-s3-bucket-metricsconfiguration.html)
- [Terraform `aws_s3_bucket_metric`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_metric)
