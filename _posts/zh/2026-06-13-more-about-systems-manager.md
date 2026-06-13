---
layout: post
title: "更多關於 AWS Systems Manager：Inventory、Compliance 與組態管理"
description: "深入探討 AWS Systems Manager 的進階功能，包括 Inventory 軟體清單、Compliance 合規管理、Maintenance Window 維護窗口，以及 AppConfig 和 Parameter Store 的組態管理應用，幫助企業實現自動化運維與 ISO 稽核合規。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, SSM, State Manager, Systems Manager, ISO, Audit, Inventory, Compliance]
keywords: [AWS Systems Manager, Inventory, Compliance, AppConfig, Parameter Store, ISO 稽核, 自動化, 組態管理, AWS 運維]
lang: zh-TW
date: 2026-06-13
---

前幾篇我們提到 Systems Manager 的相關應用

可以啟用 Session Manager 讓不同使用者可以登入同一台機械

可以排成上 Patch 做漏洞修補

可以在目標機械上執行 script 語法

可以做狀態合規管理

其實最終目的是相同的

都是為了讓我們對於管理的機械有更高的掌握度

而這些更高的掌握度直接關聯的就是 ISO 稽核

當然我們清楚 ISO 要做的事情不僅僅是這些

因此這篇我將補足介紹剩下能夠協助做到管理的部分


## Inventory（軟體清單）

### 什麼是 Inventory

`Inventory` 是 AWS Systems Manager 中用於收集和管理 EC2 實例資訊的功能。它能夠定期掃描受管機械，收集作業系統、安裝的應用程式、網路配置等詳細資訊。

### 使用 State Manager 定期執行 AWS-GatherSoftwareInventory

透過在 State Manager 中建立 Association，指定 `AWS-GatherSoftwareInventory` 文件，可以定期執行軟體清單收集任務：

1. **自動化收集**：無需手動逐台檢查，系統自動定期執行
2. **完整的軟體列表**：不僅記錄作業系統版本，更詳細列出每台機械安裝的軟體及版本
3. **雲端版本的資產管理工具**：相當於企業級 IT 資產管理工具（如 Lansweeper）的雲端實現

### Inventory 的優勢

- **合規審計**：快速生成機械資產清單供稽核使用
- **安全漏洞追蹤**：了解所有機械上安裝的軟體版本，便於識別安全漏洞
- **成本優化**：掌握軟體授權使用情況，避免過度購買或授權風險

## Compliance（合規管理）

### 什麼是 Compliance

`Compliance` 是 Systems Manager 提供的合規監控儀表板，用於追蹤所有 Association 的執行狀態和合規情況。

### Compliance 的核心功能

在 State Manager 建立的 Association，包含以下內容的執行狀態都會在 Compliance 中明確呈現：

1. **Patch Manager 執行結果**
   - 哪些機械已成功執行補丁更新
   - 哪些機械因故未能正確套用補丁
   - 詳細的補丁安裝失敗原因

2. **Association 執行追蹤**
   - 每個 Association 的最後執行時間
   - 執行是否成功或失敗
   - 機械是否正確關連到相關文件

3. **合規儀表板**
   - 快速概覽所有受管機械的合規狀態
   - 識別不合規的機械，進行針對性修正
   - 生成合規報告供 ISO 稽核使用

### 實踐建議

建立清晰的 Compliance 追蹤策略：
- 定義明確的合規基線標準
- 定期檢視 Compliance 報告
- 針對不合規項目設定告警和自動修復策略

## Maintenance Window（維護窗口）

### 什麼是 Maintenance Window

`Maintenance Window` 允許你定義特定的時間段，在這些時間內執行維護任務（如補丁更新、軟體安裝等）。

### Maintenance Window 的價值

1. **避免業務中斷**：在預定維護窗口執行關鍵更新，減少對業務的影響
2. **符合變更管理流程**：確保維護任務在經過核准的時間進行
3. **自動化維護排程**：無需手動協調，系統自動在維護窗口執行任務

### 設定 Maintenance Window 的關鍵步驟

- 定義維護窗口的開始時間和持續時間
- 指定要執行的任務（如 Patch Manager）
- 設定目標機械的選擇方式（按 Tag 或 Resource Group）
- 配置失敗時的重試策略

## 組態管理（Configuration Management）

組態管理是現代 IT 運維的核心，AWS Systems Manager 提供了多層次的組態管理解決方案。

### AppConfig（應用程式組態管理）

`AppConfig` 用於管理應用程式的組態設定，特別適合於動態修改應用行為的場景。

#### AppConfig 的主要特性

1. **動態組態更新**
   - 無需重新部署應用程式，動態修改組態
   - 支援功能開關（Feature Flags）
   - 支援 A/B 測試的組態分發

2. **分階段部署**
   - 驗證組態變更前進行測試
   - 漸進式部署新組態到所有實例
   - 自動回滾機制

3. **與應用程式無縫集成**
   - SDK 支援主流程式語言（Java、Python、Node.js 等）
   - 應用程式可即時獲取最新組態

#### AppConfig 的使用場景

- 功能開關管理：快速啟用或關閉新功能
- A/B 測試：為不同使用者群組提供不同的應用行為
- 動態限流配置：根據系統負載動態調整限流閾值

### Parameter Store（參數儲存）

`Parameter Store` 是 Systems Manager 提供的鍵值對存儲服務，用於集中管理應用程式和伺服器的設定組態。

#### Parameter Store 的主要特性

1. **集中式參數管理**
   - 儲存資料庫連線字串、API 密鑰等敏感資訊
   - 支援加密儲存（使用 KMS）
   - 版本控制，便於回滾

2. **靈活的參數類型**
   - String：普通字串參數
   - StringList：字串列表
   - SecureString：加密敏感資訊（密碼、API 密鑰等）

3. **與 IAM 無縫集成**
   - 使用 IAM 策略控制參數存取權限
   - 審計日誌完整記錄參數存取情況

#### Parameter Store 與環境變數的對比

| 特性 | 環境變數 | Parameter Store |
|------|---------|-----------------|
| 存儲位置 | 本地作業系統 | AWS 雲端 |
| 安全性 | 需要手動加密 | 支援 KMS 加密 |
| 版本控制 | 不支援 | 支援多版本管理 |
| 集中管理 | 不支援 | 支援跨應用程式集中管理 |
| 變更通知 | 無 | 可透過 EventBridge 通知 |

#### Parameter Store 的最佳實踐

```
/myapp/prod/db/hostname
/myapp/prod/db/port
/myapp/prod/db/username
/myapp/prod/api/key
/myapp/prod/cache/ttl
```

使用分層結構組織參數，便於管理和查詢。

## Systems Manager 與 ISO 稽核合規

### 為何 Systems Manager 對 ISO 稽核很重要

1. **完整的審計追蹤**
   - Inventory：証明系統資產清單完整可控
   - Compliance：証明系統維護和補丁管理有序執行
   - CloudTrail 集成：完整的操作日誌

2. **自動化符合要求**
   - State Manager：確保定期執行合規檢查
   - Maintenance Window：確保變更管理流程受控
   - Parameter Store：敏感資訊管理有跡可尋

3. **降低人為錯誤**
   - 自動化執行減少手動操作遺漏
   - 版本控制確保配置一致性
   - 執行記錄提供完整的稽核證據

### ISO 稽核實踐建議

1. **建立完整的組態基線**
   - 使用 Inventory 記錄初始資產狀態
   - 定期比對當前狀態與基線

2. **建立合規監控**
   - 定期檢視 Compliance 儀表板
   - 設定告警規則追蹤不合規項目

3. **文件化管理流程**
   - 記錄所有 Association 和 Maintenance Window 設定
   - 保留執行日誌供稽核查詢

4. **實施變更管理**
   - 所有組態變更透過 Parameter Store 進行
   - 使用版本控制追蹤變更歷史

## 總結

AWS Systems Manager 不僅提供了強大的運維自動化工具，更重要的是為企業提供了完整的合規管理和審計追蹤能力。通過組合使用 Inventory、Compliance、Maintenance Window、AppConfig 和 Parameter Store 等功能，企業可以：

- **提高運維效率**：自動化日常維護任務
- **增強安全性**：集中管理敏感資訊，完整追蹤變更
- **確保合規**：生成審計證據，簡化稽核流程
- **降低風險**：最小化人為錯誤，確保配置一致性

這正是現代雲端運維的核心價值所在。
