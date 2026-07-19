---
layout: post
title: "使用 State Manager 自動化 EC2 設定管理"
description: "本文介紹 AWS Systems Manager 的 State Manager 功能，示範如何透過 Association 持續維護 EC2 的期望狀態，並實作定期密碼更新等自動化任務。"
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, SSM, State Manager]
keywords: [AWS State Manager, Run Command, EC2, Association, 自動化]
lang: zh-TW
date: 2026-05-16
---

在上一篇文章中，

我們介紹了如何使用 `Run Command` 對多台 EC2 批次執行指令。

但如果你希望某些設定能夠「持續維持」，

或是需要「定期執行」某些任務，

單純使用 Run Command 就會顯得不夠方便。

這時候，`State Manager` 就是你需要的工具。

## 什麼是 State Manager

`State Manager` 是 AWS Systems Manager 的一項功能，

它可以讓你定義 EC2 的「期望狀態」，

並透過排程或事件觸發的方式，

自動執行指定的 SSM Document 來維持這個狀態。

簡單來說，

State Manager 就是「可排程、可版本管理的 Run Command」。

## State Manager 與 Run Command 的差異

| 特性 | Run Command | State Manager |
|------|-------------|---------------|
| 執行方式 | 手動觸發或透過 EventBridge 排程 | 建立 Association 後自動執行 |
| 版本管理 | 無內建版本控制 | 可管理不同版本的 Association |
| 執行歷史 | 保留執行記錄 | 保留執行記錄並追蹤合規狀態 |
| 目標管理 | 每次需重新指定 | 可透過 Tag 或 Resource Group 動態選擇 |
| 適用場景 | 一次性或臨時性任務 | 持續性、週期性任務 |

## State Manager 的核心概念：Association

在 State Manager 中，

你建立的每個自動化任務稱為 `Association`（關聯）。

一個 Association 包含：

1. **SSM Document**：要執行的腳本或指令
2. **目標（Targets）**：要套用的 EC2 實例
3. **排程（Schedule）**：多久執行一次
4. **參數（Parameters）**：Document 所需的輸入值

建立 Association 後，

Systems Manager 會根據你設定的排程自動執行，

並追蹤每次執行的狀態。

## 實際案例：定期更新 EC2 密碼

假設你需要每個月自動更新所有 Web Server 的本機帳號密碼，

使用 State Manager 會比單純用 EventBridge + Run Command 更容易管理。

### 步驟 1：準備 SSM Document

你可以使用 AWS 內建的 `AWS-RunShellScript`（Linux）或 `AWS-RunPowerShellScript`（Windows），

或是自己建立一個 Custom Document。

以 Linux 為例，假設要更新 `webuser` 的密碼：

```yaml
schemaVersion: '2.2'
description: Update webuser password
parameters:
  NewPassword:
    type: String
    description: New password for webuser
    noEcho: true
mainSteps:
  - action: aws:runShellScript
    name: updatePassword
    inputs:
      runCommand:
        - |
          echo 'webuser:{{NewPassword}}' | chpasswd
          echo "Password updated successfully"
```

### 步驟 2：建立 Association

透過 AWS Console：

1. 打開 **Systems Manager** > **State Manager**
2. 點選 **Create association**
3. 選擇你的 Document（例如上面建立的 Custom Document）
4. 在 **Targets** 區塊，選擇目標方式：
   - 可以直接選擇特定 Instance ID
   - 或透過 Tag 動態選擇（例如 `Environment=Production` 且 `Role=WebServer`）
5. 設定 **Schedule**：
   - 例如 `cron(0 2 1 * ? *)` 表示每月 1 號凌晨 2 點執行
6. 在 **Parameters** 填入新密碼（或從 Parameter Store / Secrets Manager 取得）
7. 點選 **Create association**

透過 AWS CLI：

```bash
aws ssm create-association \
  --name "UpdateWebUserPassword" \
  --document-name "Custom-UpdatePassword" \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "cron(0 2 1 * ? *)" \
  --parameters "NewPassword=SecurePass123!" \
  --association-name "MonthlyPasswordRotation"
```

### 步驟 3：查看執行狀態

建立 Association 後，

你可以在 State Manager 頁面看到：

- **Status**：Success / Failed / Pending
- **Last execution time**：上次執行時間
- **Compliance status**：有多少實例符合期望狀態

如果有執行失敗，

可以點進去查看詳細的錯誤訊息。

## Association 的版本管理

State Manager 的一大優勢是支援版本控制。

當你需要調整 Association 的設定時，

例如改變排程、更新參數、調整目標範圍，

每次修改都會產生一個新版本。

你可以：

1. 查看歷史版本的設定
2. 比較不同版本的差異
3. 回復到先前的版本

這在大規模環境中非常實用，

因為你可以清楚追蹤「什麼時候改了什麼」。

## 為什麼不直接用 EventBridge + Run Command？

你可能會問：

> 我用 EventBridge 定時觸發 Run Command 不就好了嗎？

技術上確實可行，

但 State Manager 提供了幾個額外的好處：

1. **統一管理介面**：所有排程任務都在 State Manager 看得到
2. **版本控制**：可以追蹤每次修改的歷史
3. **合規追蹤**：可以看到有多少實例執行成功或失敗
4. **動態目標**：透過 Tag 自動套用到新增的 EC2
5. **內建重試機制**：執行失敗時可自動重試

如果你只有一兩個簡單任務，

用 EventBridge 也沒問題；

但當管理的任務變多、目標機器變複雜時，

State Manager 會讓你的維運工作更有條理。

## 常見的 State Manager 使用場景

### 1. 定期安裝安全更新

```bash
aws ssm create-association \
  --name "AWS-RunPatchBaseline" \
  --targets "Key=tag:Environment,Values=Production" \
  --schedule-expression "cron(0 3 ? * SUN *)"
```

每週日凌晨 3 點自動執行 Patch Manager。

### 2. 確保特定服務持續運行

```yaml
mainSteps:
  - action: aws:runShellScript
    name: ensureServiceRunning
    inputs:
      runCommand:
        - |
          if ! systemctl is-active --quiet nginx; then
            systemctl start nginx
            echo "Nginx was down, restarted"
          else
            echo "Nginx is running"
          fi
```

每 30 分鐘檢查一次 Nginx 是否運行，若停止則自動啟動。

### 3. 定期清理暫存檔案

```bash
aws ssm create-association \
  --name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=i-1234567890abcdef0" \
  --schedule-expression "rate(7 days)" \
  --parameters 'commands=["find /tmp -type f -mtime +7 -delete"]'
```

每 7 天清理一次超過 7 天的暫存檔案。

## 如何查看 Association 執行歷史

### 透過 Console

1. 進入 **Systems Manager** > **State Manager**
2. 點選目標 Association
3. 切換到 **Execution history** 分頁
4. 可以看到每次執行的時間、狀態、目標數量

### 透過 CLI

```bash
aws ssm describe-association-execution-targets \
  --association-id "<association-id>" \
  --execution-id "<execution-id>"
```

## 常見問題與排查

### 1. Association 一直顯示 Pending

可能原因：

- 目標 EC2 的 SSM Agent 未連線
- IAM Role 權限不足
- 排程尚未到達執行時間

### 2. 執行失敗但沒有錯誤訊息

檢查步驟：

1. 確認 Document 的語法正確
2. 檢查參數是否正確傳遞
3. 查看 EC2 上的 SSM Agent 日誌：`/var/log/amazon/ssm/amazon-ssm-agent.log`

### 3. 想要立即執行 Association 而不等排程

可以使用 `apply-association-now`：

```bash
aws ssm start-associations-once \
  --association-ids "<association-id>"
```

## 與 Parameter Store 整合

如果你的 Document 需要敏感參數（例如密碼），

建議不要直接寫在 Association 裡，

而是存在 Parameter Store 或 Secrets Manager。

範例：

```bash
# 先將密碼存入 Parameter Store
aws ssm put-parameter \
  --name "/app/webuser/password" \
  --value "SecurePass123!" \
  --type "SecureString"

# 建立 Association 時引用
aws ssm create-association \
  --name "Custom-UpdatePassword" \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "NewPassword={{ssm:/app/webuser/password}}"
```

這樣可以：

1. 集中管理敏感資料
2. 透過 KMS 加密保護
3. 使用 IAM 精確控制存取權限

## 小結

State Manager 是 Systems Manager 中非常強大的功能，

它讓你可以：

1. 定義 EC2 的期望狀態並持續維護
2. 透過版本控制追蹤每次變更
3. 使用動態目標自動套用到新增的實例
4. 集中查看所有自動化任務的執行狀態

相較於單純使用 Run Command 或 EventBridge，

State Manager 提供了更完整的管理能力，

特別適合需要長期維護、定期執行的任務。

建議從簡單的場景開始，

例如定期清理日誌、確保服務運行，

逐步擴展到更複雜的自動化流程。

---

## 參考資料

1. AWS Systems Manager State Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html
2. 使用 State Manager 關聯: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/sysman-state-about.html
3. 建立關聯 (主控台): https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/sysman-state-assoc.html
4. SSM Document 語法: https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-syntax.html
