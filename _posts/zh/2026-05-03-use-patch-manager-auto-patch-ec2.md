---
layout: post
title: "使用 Patch Manager 排程幫 EC2 上 Patch"
description: "本文承接 Systems Manager 的 Session Manager 設定，進一步介紹 Patch Manager，讓 EC2 自動定期掃描與安裝補修程式。"
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, IAM, SSM]
keywords: [AWS Systems Manager, Patch Manager, EC2, Auto Patching]
lang: zh-TW
date: 2026-05-03
---

前一篇介紹完 Systems Manager 的 Session Manager 設定後，

裝完 SSM Agent 的機械，

就進一步可以使用 Patch Manager 自動管理補修程式。

這次就來看怎麼做排程與設定。

## Patch Manager 是什麼

`Patch Manager` 是 AWS Systems Manager 底下的一個功能，

可以幫你集中管理多台主機的作業系統與應用程式補修程式。

核心功能包括：

1. Patch 掃描：檢查主機需要哪些補修
2. Patch 安裝：定期或手動安裝補修程式
3. Patch 報告：匯總各主機的 Patch 狀況
4. 排除規則：可以設定某些補修跳過安裝

相比於手動登入每台主機更新，

或者自己寫 cron job，

Patch Manager 提供的優勢是：

1. 集中控管政策
2. 可稽核與合規性報告
3. 彈性排程（維護時間視窗）
4. 故障時能自動回滾

## 使用前需要先準備什麼

和 Session Manager 類似，

Patch Manager 需要你準備好：

1. EC2 已通過 Session Manager 設定（IAM Role、Agent 都好）
2. EC2 可以連到 SSM 相關 Endpoint（已有的話無需額外設定）
3. IAM Role 有 Patch Manager 權限

## 設定 IAM Policy

如果你已經綁定 `AmazonSSMManagedInstanceCore`，

Patch Manager 基本權限已包含在內。

但如果你想更精準控制，可以搭配下面的自訂 Policy：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:DescribeDocumentParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:document/AWS-RunPatchBaseline"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetAutomationExecution",
        "ssm:StartAutomationExecution",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:ListCommands"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:*:*:aws-patch-manager-*"
    }
  ]
}
```

通常 Patch Manager 不需要額外的 S3 或其他服務權限，

除非你有特殊的補修來源設定。

## Patch Manager 的運作方式

Patch Manager 基本上有兩種工作模式：

1. **Scan Only**：只掃描，告訴你哪些補修可用，不安裝
2. **Scan and Install**：邊掃邊裝

通常實務上會先用 Scan Only 了解狀況，

再轉成 Scan and Install 定期更新。

## 實際設定補修排程

### 步驟 1：建立 Patch Baseline

進到 AWS Console，

打開 Systems Manager > Patch Manager > Patch Baselines。

建立一個新的 Baseline：

1. Baseline 名稱：例如 `linux-standard`
2. 作業系統：選 Linux 或 Windows
3. Approval rules：
   - 選擇「自動批准符合分類的補修」
   - 常見分類：`Security`、`Bugfix`、`Enhancement`
   - 也可以設定「在補修發佈後多久批准」（例如 7 天）

如果有特定補修要排除，

可以在「Patch exceptions」列舉，

例如排除某些 kernel 版本更新。

### 步驟 2：建立維護時間（Maintenance Window）

回到 Systems Manager 主頁，

找到 Maintenance Windows。

建立新的維護時間：

1. 名稱：例如 `weekly-patch-sunday`
2. 排程：Cron 格式，例如每週日凌晨 2 點
   ```
   cron(0 2 ? * SUN *)
   ```
3. 持續時間：例如 2 小時（預留緩衝）
4. 時區：選你的營運時區

### 步驟 3：建立 Patch Task

在維護時間內加入一個 Task：

1. Task type：選 `Run command`
2. Document name：`AWS-RunPatchBaseline`
3. Service role：選你的 Patch Manager 角色
4. Targets：選要 Patch 的 EC2
   - 可以用 tag 選，例如 `Environment: Production`
   - 也可以用 Instance ID 直接指定
5. Parameters：
   - Operation：選 `Install`（如果要邊掃邊裝）或 `Scan`（只掃）
   - Baseline Override：如果有多個 baseline，在這指定

### 步驟 4：等待排程執行

Patch Manager 會在你設定的維護時間執行，

你可以去 Patch Manager > Compliance 查看狀況。

每個 EC2 的 Patch 狀態會顯示：

- Compliant：已安裝所有補修
- Non-compliant：還有補修未裝
- Failed：本次執行失敗

## 常見設定與最佳實踐

### 1. 先從 Scan Only 開始

不要一上來就 `Install`，

先用 `Scan` 跑一陣子，

確認補修清單符合預期，

再切成 `Install`。

### 2. 分環境管理

例如分 Dev、Staging、Production 三個 Patch Baseline，

Production 可以設更保守的批准規則（例如延後 2-4 週），

Dev 就可以激進一些。

### 3. 使用 Patch Groups

如果要把 EC2 分組做不同補修策略，

可以在 EC2 tag 上加 `Patch Group`，

然後在 Baseline 對應設定。

### 4. 設定通知

可以搭配 SNS 或 EventBridge 發送補修完成通知，

這樣有個稽核軌跡。

基本上，EventBridge 會擷取 Scan 或 Install 後 EC2 的狀態變化，

然後推送事件。

直接用 EventBridge + SNS 的組合可以發送基礎通知，

但如果需要高度客製化的內容（例如包含 Patch 名單、失敗原因等詳細資訊），

就需要再搭配 Lambda 做額外處理，才能寄出更完整的通知。

## 常見問題與排查

### 1) 維護時間已到，但 Patch 沒執行

通常檢查：

1. EC2 的 IAM Role 是否有 Patch 權限
2. EC2 是否 Online（用 `aws ssm describe-instance-information` 確認）
3. Maintenance Window 的 Target 是否有納入該 EC2

### 2) Patch 執行失敗（Failed 狀態）

原因通常是：

1. 補修安裝需要重啟，但沒開啟「自動重啟」
2. 補修套件本身在該系統不相容
3. 磁碟空間不夠

去 Compliance 的執行紀錄看詳細 log。

### 3) Patch 安裝後系統變慢或異常

建議在 Staging 環境先測，

確認補修不會造成相容性問題，

再推到 Production。

### 4) 想暫時跳過某次 Patch

可以暫時停用 Maintenance Window，

或者直接移除該 EC2 的 target。

## 小結

Patch Manager 的核心價值是：

你無須手動進每台主機，

可以統一排程、統一報告、統一稽核。

建議導入流程：

1. 先用 Scan 了解現狀
2. 在非關鍵環境測試 Install
3. 建立 Dev / Staging / Prod 的分級政策
4. 持續監控 Compliance 報告

這樣就能建立一套穩健的自動補修管制。

---

## 參考資料

1. AWS Patch Manager: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/patch-manager.html
2. AWS-RunPatchBaseline Document: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/documents-ssm-docs-run-command.html
3. Patch Baselines: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/patch-baselines.html
4. Maintenance Windows: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/maintenance-windows.html