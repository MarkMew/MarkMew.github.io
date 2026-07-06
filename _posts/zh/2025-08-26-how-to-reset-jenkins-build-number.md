---
layout: post
title: "如何重置 Jenkins 建置編號：清除 Build History 與設定 Next Build Number"
description: "說明如何透過 Jenkins Script Console 清除指定 Job 的建置紀錄並重設下一個 Build Number，以及執行前必須確認的風險與限制。"
author: Mark_Mew
category: [CICD, Jenkins]
tags: [CICD, Jenkins]
date: 2025-8-26
---

在部分 Jenkins Pipeline 中，建置編號會被放進應用程式的版本字串，例如：

```text
0.0.${BUILD_NUMBER}
```

其中最後一段直接使用 Jenkins 的 `BUILD_NUMBER`。當 major 或 minor version 提升後，團隊有時會希望 patch number 重新從 1 開始，因此產生重置 Jenkins 建置編號的需求。

不過，Jenkins 的建置編號原本就是單調遞增的識別碼。重置編號不是一般的版本發布流程，而且若要將下一個編號降回 1，必須先刪除該 Job 的既有建置紀錄。這是一項具破壞性的管理操作，不能只把它當成版面整理功能。

## 執行前需要確認的事項

本文使用 Jenkins Script Console 執行 Groovy 腳本。Script Console 具有完整的 Jenkins controller 權限，只有擁有 `Overall/Administer` 權限的管理者才能使用。

執行前應先確認：

- Job 目前沒有正在執行或排隊中的建置。
- 已備份仍需保留的 Console Log、Artifact、測試報告與稽核紀錄。
- 其他系統沒有持續引用既有的 Jenkins Build URL 或 Build Number。
- 已確認 Job 的完整名稱，特別是位於 Folder 或 Multibranch Pipeline 下的 Job。
- 最好先在非正式環境測試腳本並備份 Jenkins 設定。

刪除 Build History 後，原有建置頁面、紀錄與保存在 Build 目錄中的 Artifact 都可能無法復原。若只是想清理過舊紀錄，應優先考慮設定 Build Discarder，而不是重置編號。

## 使用 Script Console 重置編號

以具備管理權限的帳號登入 Jenkins，前往：

```text
Manage Jenkins → Script Console
```

以下是我當時實際執行的 Groovy 腳本。執行前，必須將 `your-job-name-here` 替換成目標 Pipeline 的名稱：

```groovy
item = Jenkins.instance.getItemByFullName("your-job-name-here")
// THIS WILL REMOVE ALL BUILD HISTORY
item.builds.each() { build ->
  build.delete()
}
item.updateNextBuildNumber(1)
```

這段腳本會取得指定的 Pipeline、逐一刪除所有 Build History，最後將下一次建置編號設定為 1。它沒有額外檢查 Job 名稱是否正確，也不會詢問是否確認刪除，因此應在執行前自行確認目標與備份狀態。

## 確認執行結果

執行完成後，回到 Job 頁面，可以看到原本的 Build History 已清空。再次觸發 Pipeline 時，新建置的編號會從 `#1` 開始。若 Pipeline 使用 `${BUILD_NUMBER}` 組合版本字串，也要確認產生的版本沒有和既有 Artifact、Container Image 或已發布套件重複。

## 是否真的需要重置？

如果建置編號已被外部系統當作唯一識別碼，重複使用 `#1` 可能造成追蹤與稽核上的混淆。較穩定的設計是讓 Jenkins Build Number 持續遞增，再將應用程式版本與建置識別碼分開，例如：

```text
Application version: 2.0.0
Build metadata:      Jenkins #183
```

只有在確定歷史紀錄可以刪除，而且外部系統不依賴舊編號時，才建議執行重置。若需求只是將下一個編號調高，可以考慮 Next Build Number Plugin；Jenkins 不允許在保留較大歷史編號的同時，將下一個編號設定成更小的值。

---

## 參考資料

- [Jenkins Script Console](https://www.jenkins.io/doc/book/managing/script-console/)
- [Jenkins Job API：updateNextBuildNumber](https://javadoc.jenkins.io/hudson/model/Job.html)
- [How to reset build number in Jenkins?](https://stackoverflow.com/questions/20901791/how-to-reset-build-number-in-jenkins)
