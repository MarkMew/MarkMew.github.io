---
layout: post
title: "ECR 跨 AWS 帳號存取教學：Repository Policy 與 IAM 權限設定"
image: https://fastly.picsum.photos/id/776/1200/630.jpg?hmac=Lb8y0-sLk2uqC_rjc_vHCUEnR1NLKPZjFgwq2FtfAoQ
description: "示範如何透過 ECR Repository Policy 與 IAM Policy，授予指定跨帳號 IAM Role 拉取私有映像檔的權限，並使用 AWS CLI 與 Docker 驗證。"
author: Mark_Mew
categories: [AWS, ECR]
tags: [AWS, ECR, IAM]
keywords: [ECR 跨帳號存取, ECR cross account access, ECR Repository Policy, IAM Policy, Docker pull]
lang: zh-TW
date: 2026-10-12
---

**讓來源帳號的 IAM Role 拉取另一個 AWS 帳號的 ECR 私有映像檔，需要在目標 Repository Policy 授權來源身分，並在來源 Role 的 IAM Policy 授予相應 ECR 操作。** 此外，來源 Role 必須有 `ecr:GetAuthorizationToken` 權限，才能向 ECR 登入。即使登入成功，若 Repository 沒有授權，拉取映像檔仍會失敗。[ECR Repository Policy 官方說明](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html)

本文以「帳號 A 的應用程式，需要唯讀拉取帳號 B 的私有 Repository」為例，示範如何設定最小權限、登入目標 Registry、拉取映像檔，以及排查常見錯誤。若要了解另一種跨帳號儲存服務授權，可參考[S3 跨帳號存取教學](/posts/s3-cross-account-access-iam-bucket-policy/)。

## Repository Policy 與 IAM Policy 的分工

ECR 使用 Repository Policy（資源型政策）控制個別 Repository 接受哪些身分的操作；IAM Policy（身分型政策）則附加在來源帳號的 Role 上，授予該身分可執行的操作。跨帳號存取時，目標帳號必須透過 Repository Policy 授權來源帳號；來源 Role 也需具有相應的身分權限。兩邊的 Allow 都不能被適用的明確 `Deny` 覆蓋。[ECR IAM 整合說明](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_service-with-iam.html)

| 設定位置 | Policy | 本文用途 |
|---|---|---|
| 帳號 A 的 IAM Role | IAM Policy | 允許登入 ECR，並拉取帳號 B 指定 Repository 的映像檔 |
| 帳號 B 的 ECR Repository | Repository Policy | 允許帳號 A 指定 Role 存取該 Repository |

## 範例與前置條件

| 項目 | 範例值 |
|---|---|
| 來源帳號 A | `111111111111` |
| 目標帳號 B | `222222222222` |
| AWS Region | `ap-northeast-1` |
| 帳號 A 的 Role | `AppPullImageRole` |
| 帳號 B 的 Repository | `backend-api` |
| 映像 Tag | `2026.10.12` |
| CLI Profile | `account-a-app` |

請將範例值換成實際帳號、Region、Repository 與 Tag。本文假設目標 Repository 已存在，Role 也已建立，且操作環境已安裝並設定 AWS CLI、Docker。ECR Registry URI 的格式為 `<account-id>.dkr.ecr.<region>.amazonaws.com`；Repository URI 則再加上 Repository 名稱。

本文僅設定拉取既有映像檔的權限，不授予推送、建立或刪除 Repository 的權限。ECR 的跨帳號與跨 Region replication 是另一種將映像複製到目的地的方式；若需要共用同一份來源映像並由消費端直接拉取，可採用本文的 Repository Policy。[ECR 跨帳號與跨 Region 複製](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html)

## 步驟一：在帳號 A 授予 Role 必要權限

在帳號 A 的 IAM 中，將以下 Policy 附加到 `AppPullImageRole`。其中 `ecr:GetAuthorizationToken` 必須使用 `Resource: "*"`；其餘拉取操作限制在帳號 B 的指定 Repository ARN。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetECRAuthorizationToken",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PullFromAccountBRepository",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:ap-northeast-1:222222222222:repository/backend-api"
    }
  ]
}
```

`GetAuthorizationToken` 是登入 Registry 所需的權限，不能只放在目標 Repository Policy。三個 Repository 操作則用於檢查 Layer、取得映像 Manifest 與下載 Layer。若工具還會列出映像或讀取 Repository 資訊，再依需求加入 `ecr:ListImages`、`ecr:DescribeImages` 或 `ecr:DescribeRepositories`；本文的 `docker pull` 範例不需要因此擴大權限。[ECR IAM 權限與推拉映像範例](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html)

### Terraform：來源 Role 的 IAM Policy

下列 Terraform 範例建立 GitLab Runner 拉取 `dockerdind` 與 `devtool` 兩個 Repository 所需的身分政策；請將建立的 Policy 附加至帳號 A 的 Runner Role。

```terraform
resource "aws_iam_policy" "pull_ecr_from_other_account_policy" {
  name = "PullECRFromOtherAccountPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PullCrossAccountRunnerImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:ap-northeast-1:222222222222:repository/dockerdind",
          "arn:aws:ecr:ap-northeast-1:222222222222:repository/devtool"
        ]
      }
    ]
  })
}
```

## 步驟二：在帳號 B 設定 Repository Policy

切換到帳號 B 與 `ap-northeast-1` Region，開啟 ECR Repository `backend-api` 的 **Permissions**，新增以下 Repository Policy。若已有 Policy，請合併 Statement，不要覆蓋仍需要的規則。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARoleToPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppPullImageRole"
      },
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "*"
    }
  ]
}
```

`Principal` 使用來源 IAM Role ARN。若 Role 設有 Path，請填入完整 ARN，例如 `arn:aws:iam::111111111111:role/team/AppPullImageRole`。本文授權單一 Role；若改為授權整個帳號，Principal 可指定 `arn:aws:iam::111111111111:root`，但此時來源帳號仍須透過 IAM Policy 決定哪些身分可以使用這項跨帳號授權。請避免在不需要時直接授權整個帳號或使用萬用 Principal。[ECR Repository Policy 範例](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)

### Terraform：目標帳號的 Repository Policy

以下設定會將跨帳號拉取權限加入帳號 B 的 `devtool` 與 `dockerdind` Repository。請依實際 Repository 名稱與來源 Role ARN 調整。

```terraform
resource "aws_ecr_repository_policy" "devtool" {
  repository = aws_ecr_repository.devtool.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountGitLabRunnerPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::111111111111:role/DummyRole"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "dockerdind" {
  repository = aws_ecr_repository.dockerdind.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountGitLabRunnerPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::111111111111:role/DummyRole"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}
```

## 步驟三：驗證來源身分並登入 ECR

先確認 AWS CLI 使用的是帳號 A 的預期 Role：

```shell
aws sts get-caller-identity --profile account-a-app
```

輸出的 `Account` 應為 `111111111111`，ARN 類似：

```text
arn:aws:sts::111111111111:assumed-role/AppPullImageRole/example-session
```

接著使用該 Profile 取得登入密碼，並登入帳號 B 位於 `ap-northeast-1` 的 Registry：

```shell
aws ecr get-login-password --region ap-northeast-1 --profile account-a-app | docker login --username AWS --password-stdin 222222222222.dkr.ecr.ap-northeast-1.amazonaws.com
```

成功時 Docker 會回報 `Login Succeeded`。ECR 登入憑證有時效；遇到授權權杖過期時，重新執行登入命令即可。[AWS CLI get-login-password 文件](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html)

## 步驟四：拉取映像檔

登入成功後，使用完整 Repository URI 與 Tag 拉取映像：

```shell
docker pull 222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/backend-api:2026.10.12
```

URI 中的帳號 ID 與 Region 必須對應目標帳號 B 的 Registry 和 Repository 所在 Region，Repository 名稱及 Tag 也必須存在。跨 Region 時，請以映像實際所在的 Region 登入並拉取。

## 遇到拒絕存取時的檢查方式

| 現象或錯誤 | 檢查方向 |
|---|---|
| `get-login-password` 回傳 `AccessDeniedException` | 檢查來源 Role 的 IAM Policy 是否允許 `ecr:GetAuthorizationToken`，以及 SCP、Permissions Boundary、Session Policy 等限制 |
| Docker 登入失敗或 `no basic auth credentials` | 確認登入的 Registry URI、Region 與帳號 ID 一致，並確認 `docker login` 使用 `AWS` 作為帳號名稱 |
| 登入成功但 `docker pull` 回傳 `denied` | 檢查來源 IAM Policy 與目標 Repository Policy 的 Pull Actions、Repository ARN、Principal Role ARN 是否正確 |
| 找不到映像或 Tag | 確認 Repository 名稱、Tag 是否存在，以及完整 URI 指向正確 Registry 與 Region |
| Policy 看似正確仍被拒絕 | 檢查明確 `Deny`、SCP、Resource Control Policy、VPC Endpoint Policy |

來源 Role 的 IAM Policy 中，Resource ARN 必須精確對應 Repository；Repository Policy 的 Resource 使用 `"*"`，並以 Principal 指定來源 IAM Role ARN，而不是 `get-caller-identity` 顯示的 STS assumed-role session ARN。新增 Allow 不會排除其他政策中的明確拒絕。[ECR 設定 Repository Policy](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html)

## 常見問題

### 只設定 Repository Policy 可以嗎？

跨帳號情況下，請同時檢查目標 Repository Policy 與來源 Role 的 IAM Policy。無論如何，`ecr:GetAuthorizationToken` 都需要來源身分的 IAM 權限，Repository Policy 無法代替這項登入權限。

### 這樣會授予推送映像檔的權限嗎？

不會。本文只允許拉取所需操作。推送需要另外授予 `ecr:CompleteLayerUpload`、`ecr:InitiateLayerUpload`、`ecr:PutImage`、`ecr:UploadLayerPart` 等操作，請依需求另行設計並限制 Repository 範圍。[ECR Repository Policy 推送範例](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)

### 一定要使用 IAM Role 嗎？

本文使用 Role，讓應用程式透過臨時憑證取得權限。其他 IAM 身分也能依需求授權，但應避免將長期 Access Key 寫入映像、原始碼或部署設定；在 AWS 運算環境中，優先使用其執行 Role 或工作負載身分機制。

---

設定完成後，帳號 A 的 `AppPullImageRole` 可以登入帳號 B 的 ECR Registry，並拉取 `backend-api` 中指定的映像。若要讓其他 Role 使用，請在兩端 Policy 明確加入對應身分與 Repository 權限，再以實際 AWS 環境驗證。



## 參考文件

- [Private repository policies in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html)：Repository Policy 與 IAM Policy 的差異、授權原則。
- [Private repository policy examples in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)：ECR Repository Policy 範例，包含跨帳號授權。
- [Amazon ECR identity-based policy examples](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html)：IAM 身分政策與 Repository 權限範例。
- [Setting a private repository policy statement in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html)：透過 AWS Console 設定 Repository Policy。
- [get-login-password — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html)：取得登入私有 ECR Registry 的授權密碼。
- [aws_iam_policy — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy)：Terraform IAM Policy 資源文件。
- [aws_ecr_repository_policy — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy)：Terraform ECR Repository Policy 資源文件。
