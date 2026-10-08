---
layout: post
title: "Amazon S3 跨 AWS 帳號存取教學：Bucket Policy 與 IAM 權限設定"
image: https://fastly.picsum.photos/id/905/1200/630.jpg?hmac=ZWehW4CmzynIJ9lxyGHPkwHnki7vekeNFaXiaJWJaeo
description: "示範如何透過 IAM Policy 與 S3 Bucket Policy 設定跨 AWS 帳號唯讀存取，限制指定 Prefix，使用 AWS CLI 驗證，並排查常見的 AccessDenied 權限問題。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, IAM]
keywords: [S3 跨帳號存取, S3 cross account access, S3 Bucket Policy, IAM Policy, AccessDenied]
lang: zh-TW
date: 2026-10-09
---

**讓來源帳號的 IAM 身分直接存取另一個 AWS 帳號的 S3 Bucket，需要同時設定來源端的 IAM Policy 與目標端的 Bucket Policy，讓兩端都允許對應操作。** 即使來源端已經有 S3 讀取權限，目標 Bucket 沒有授權該身分，請求仍會被拒絕；反過來，只設定 Bucket Policy 也不夠。[AWS 跨帳號存取說明](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html)

兩端授權完成後，請求還必須符合其他適用的權限限制，且不能受到明確的 `Deny` 阻擋。

本文以「帳號 A 的應用程式，需要讀取帳號 B 的 S3 檔案」為例，示範如何設定指定路徑的唯讀權限、使用 AWS CLI 驗證，以及排查常見的 AccessDenied 權限問題。

## 為什麼 IAM Policy 和 Bucket Policy 都要設定？

跨帳號存取涉及兩個帳號各自管理的權限：來源帳號決定自己的 IAM 身分可以做什麼，目標帳號則決定自己的 Bucket 開放給誰。

| 設定位置 | Policy | 授權的內容 |
|---|---|---|
| 來源帳號 A 的 IAM Role | IAM Policy | 允許這個 Role 讀取帳號 B 的指定 S3 物件 |
| 目標帳號 B 的 S3 Bucket | Bucket Policy | 允許帳號 A 的指定 Role 讀取這些物件 |

例如，要下載 `reports/sample.txt`，來源 Role 的 IAM Policy 必須允許對該物件執行 `s3:GetObject`，目標 Bucket Policy 也必須允許同一個 Role 執行這個操作。整個請求都使用帳號 A 的身分。

## 本文範例與前置條件

假設應用程式使用帳號 A 的 `AppReadReportsRole`，讀取帳號 B 的 `reports/` 路徑。

| 項目 | 範例值 |
|---|---|
| 來源帳號 A | `111111111111` |
| 目標帳號 B | `222222222222` |
| 帳號 A 的 Role | `AppReadReportsRole` |
| 帳號 B 的 Bucket | `example-cross-account-reports-222222222222` |
| 允許讀取的 Prefix | `reports/` |
| 測試物件 | `reports/sample.txt` |
| CLI Profile | `account-a-app` |

以上都是示意值，請替換成實際設定。本文假設：

- 帳號 A 的 Role 已存在，應用程式或操作人員能合法取得該 Role 的臨時憑證。
- 帳號 B 已建立 Bucket，並放入 `reports/sample.txt` 測試檔案。
- CLI Profile `account-a-app` 已設定為使用上述 Role。
- Bucket 的 Object Ownership 使用 **Bucket owner enforced**。
- 範例的測試物件使用 S3 管理的加密金鑰（SSE-S3）。

`Bucket owner enforced` 會停用 ACL，並由 Bucket 擁有者擁有其中的物件，適合以 Policy 統一管理存取權限。AWS 新建 Bucket 預設使用此設定。[S3 Object Ownership 官方說明](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

本文提供設定範例與預期驗證結果；實際結果仍需在你的 AWS 環境中確認。

## 步驟一：在帳號 A 授予 Role 存取權限

在帳號 A 的 IAM 中，找到 `AppReadReportsRole`，新增以下 IAM Policy：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListReportsPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222",
      "Condition": {
        "StringLike": {
          "s3:prefix": "reports/*"
        }
      }
    },
    {
      "Sid": "ReadReportObjects",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222/reports/*"
    }
  ]
}
```

這份 Policy 分別允許兩種操作：

| 權限 | 用途 | Resource |
|---|---|---|
| `s3:ListBucket` | 列出指定 Prefix 的物件 | Bucket ARN |
| `s3:GetObject` | 讀取指定路徑下的物件 | Object ARN |

`ListBucket` 的 Resource 是 Bucket 本身，因此透過 `s3:prefix` 限制列舉範圍；`GetObject` 則直接把物件路徑寫進 Resource。

此處 `reports/*` 也能匹配 `reports/`，所以稍後的列舉請求會明確帶入 `--prefix reports/`。S3 的 Prefix 是物件名稱前綴，例如 `reports/2026/report.csv`，不是真正的檔案系統目錄。[AWS Prefix 權限範例](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html)

## 步驟二：在帳號 B 設定 Bucket Policy

切換到帳號 B，開啟目標 Bucket 的 **Permissions → Bucket policy**，加入以下授權。

如果 Bucket 已經有 Policy，請將以下 Statement 合併到既有設定，保留原本仍需要的規則。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARoleToListReports",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppReadReportsRole"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222",
      "Condition": {
        "StringLike": {
          "s3:prefix": "reports/*"
        }
      }
    },
    {
      "Sid": "AllowAccountARoleToReadReports",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppReadReportsRole"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222/reports/*"
    }
  ]
}
```

`Principal` 指定允許存取的來源 Role。若你的 Role 有 Path，請從 IAM 複製完整 ARN，避免手動組合時漏掉路徑。

這兩份 Policy 各自回答不同問題：

- 帳號 A 的 IAM Policy：這個 Role 可以操作哪些資源？
- 帳號 B 的 Bucket Policy：這個 Bucket 接受誰的哪些操作？

**這些 Allow 規則只授予列出的權限，不代表撤銷既有的其他授權。** 如果 Role 或 Bucket 原本已有更廣的權限，仍需一起檢查。

## 步驟三：使用 AWS CLI 驗證

### 先確認目前身分

```shell
aws sts get-caller-identity --profile account-a-app
```

預期 `Account` 是 `111111111111`，且 ARN 類似：

```text
arn:aws:sts::111111111111:assumed-role/AppReadReportsRole/example-session
```

若顯示其他 Role，請先修正 Profile 或憑證來源，再測試 S3。

這裡看到的是 STS Role Session ARN；Bucket Policy 中填入的仍是前面的 IAM Role ARN。

### 列出允許路徑中的物件

```shell
aws s3api list-objects-v2 --bucket example-cross-account-reports-222222222222 --prefix reports/ --profile account-a-app
```

如果設定正確，請求應成功，並列出 `reports/` 下的物件。若成功但沒有物件，請確認 Bucket 中是否存在相符的 Object Key。

### 下載測試物件

```shell
aws s3api get-object --bucket example-cross-account-reports-222222222222 --key reports/sample.txt --profile account-a-app ./downloaded-sample.txt
```

預期檔案會儲存為本機的 `downloaded-sample.txt`。`get-object` 的最後一個參數是下載目的檔案。[AWS CLI GetObject 文件](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html)

### 驗證路徑限制

再嘗試列出未授權的 Prefix：

```shell
aws s3api list-objects-v2 --bucket example-cross-account-reports-222222222222 --prefix private/ --profile account-a-app
```

若沒有其他適用的授權，預期會收到 `AccessDenied`。

這個反向驗證可以確認權限是否符合預期。若請求成功，應檢查 Role 與 Bucket 是否還存在其他較寬鬆的 Policy。

## 遇到 AccessDenied，該從哪裡查起？

先確認失敗的是「列出物件」還是「下載物件」，再依序檢查：

| 檢查項目 | 要確認的內容 |
|---|---|
| 實際呼叫身分 | `get-caller-identity` 是否顯示預期的帳號與 Role？ |
| 來源 IAM Policy | 是否允許對應 Action 與 Resource？ |
| 目標 Bucket Policy | Principal 是否為正確的 Role ARN？ |
| Bucket 與 Object ARN | `ListBucket` 是否用 Bucket ARN，`GetObject` 是否用 Object ARN？ |
| Prefix 條件 | 請求是否帶入 `reports/`？大小寫與斜線是否一致？ |
| 明確拒絕與權限邊界 | SCP、RCP、Permissions Boundary、Session Policy 或其他 Policy 是否限制請求？ |
| 網路相關條件 | 是否要求特定 VPC Endpoint、來源 IP，或受到 Endpoint Policy 限制？ |
| 物件擁有權 | 舊 Bucket 若仍啟用 ACL，物件是否由其他帳號擁有？ |

新增一條 `Allow` 不會覆蓋適用的明確 `Deny`。若環境有組織層級控管或網路條件，應一起檢查。[AWS S3 403 排查文件](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-403-errors.html)

兩種常見現象也能協助縮小範圍：

**可以列出檔案，但無法下載**

代表 `ListBucket` 請求已通過，接著應檢查兩端是否都允許 `GetObject`、授權的物件範圍是否正確，以及物件是否存在。

**可以下載已知檔案，但無法列出清單**

可能只有 `GetObject` 權限，或列舉請求的 Prefix 不符合條件。列舉與下載是不同操作，權限需要分別確認。

## 常見問題

### 跨帳號存取需要關閉 S3 Block Public Access 嗎？

不需要。本文授權的是明確指定的 IAM Role，可以保留 Block Public Access。

不過，如果 Bucket Policy 的其他部分被 S3 判定為公開政策，`RestrictPublicBuckets` 可能影響跨帳號存取；因此應檢查整份 Policy。[S3 Block Public Access 官方說明](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)

### 一定要給 s3:ListBucket 嗎？

不一定。如果應用程式知道完整 Object Key，只需下載指定物件，可以只授予 `s3:GetObject`。本文加入 `ListBucket`，是為了支援列舉 `reports/` 下的檔案。[GetObject 權限說明](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html)

**如果使用 IAM User credentials（Access Key ID 與 Secret Access Key），搭配 WinSCP 或 FileZilla Pro 這類 S3 Client 瀏覽資料夾，就需要 `s3:ListBucket`。** 工具必須列出 Bucket 或指定 Prefix 下的內容，才能顯示資料夾與檔案。缺少這項權限時，即使能連線或看到 Bucket，也可能無法點進 Folder 瀏覽內容，並收到 `AccessDenied`。這項需求來自「列出內容」的操作，使用 IAM Role 時也一樣。[WinSCP 官方支援說明](https://winscp.net/forum/viewtopic.php?t=34760)

在跨帳號情境下，需在來源 IAM User 的 IAM Policy 與目標 Bucket Policy 中都允許對應的 `s3:ListBucket` 操作，Bucket Policy 的 `Principal` 也要改為實際使用的 IAM User ARN。

另外，本文範例只允許列出 `reports/` 及其下層 Prefix，沒有授權列出 Bucket 根目錄。即使已加入 `s3:ListBucket`，Client 若先讀取根目錄，仍可能被拒絕；可將預設遠端目錄設為 `/Bucket名稱/reports/`，讓列舉請求符合授權範圍。列出「有哪些 Bucket」與列出「Bucket 裡有哪些物件」是不同操作；跨帳號 Bucket 也可能需要直接指定路徑。[WinSCP S3 連線設定](https://winscp.net/eng/docs/guide_amazon_s3)、[FileZilla Pro S3 連線設定](https://filezillapro.com/docs/v3/cloud/configure-filezilla-pro-to-connect-to-s3/)

### 需要設定 ACL 嗎？

本文使用 `Bucket owner enforced`，ACL 已停用，透過 IAM Policy 與 Bucket Policy 管理權限即可。舊環境若仍啟用 ACL，則需額外確認物件擁有權。[S3 Object Ownership 官方說明](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

### 如果還需要上傳檔案呢？

需在來源 IAM Policy 與目標 Bucket Policy 中，對指定 Object ARN 加入 `s3:PutObject`。

### CLI 成功，為什麼 Console 仍無法正常瀏覽？

本文授予的是指定 Bucket、指定 Prefix 的 API 存取權限。Console 的導覽與畫面可能會呼叫其他 API，因此不保證具有完整的 Console 瀏覽體驗。驗證本文設定時，請以提供的 CLI 指令為準。[S3 IAM Policy 範例與 Console 權限說明](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-policies-s3.html)
