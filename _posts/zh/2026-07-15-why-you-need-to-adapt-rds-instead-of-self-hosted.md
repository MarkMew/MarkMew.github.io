---
layout: post
title: "為什麼你該考慮使用 RDS，而不是繼續自建 EC2 維運 Database"
image: https://fastly.picsum.photos/id/388/1200/630.jpg?hmac=3X4hBgiMUuCq4LWzGXpRr8aLv-ruGrEdVjJ5GJ_NBWc
description: "把資料庫架在 EC2 上看似自由，實際上要自行處理容量、備份、還原、連線、監控與 Patch。本文整理為什麼多數團隊應該優先考慮 Amazon RDS，以及導入時需要注意的限制。"
author: Mark_Mew
categories: [AWS, RDS]
tags: [RDS, Database, AWS]
keywords: [RDS, Database, EC2, Self-hosted Database, PITR, RDS Proxy, CloudWatch, AWS Backup]
lang: zh-TW
date: 2026-07-15
---

很多團隊一開始使用 AWS 時，會很自然地把資料庫裝在 EC2 上。

原因也很直覺：以前在 IDC 或 VM 上就是這樣做的；自己安裝 MySQL、PostgreSQL 或 SQL Server，看起來比較自由，也比較容易沿用既有的維運方式。只要開一台 EC2、掛上 EBS、設定 Security Group，再把資料庫安裝起來，服務就可以開始連線。

但資料庫真正困難的地方，通常不是「安裝」。

真正困難的是持續維運：

- 磁碟快滿時，能不能在出事前擴容？
- 備份是否每天成功？真的還原過嗎？
- 發生誤刪資料時，能不能回到指定時間點？
- 連線數暴增時，是應用程式先倒，還是資料庫先倒？
- OS、資料庫版本與安全 Patch 要誰排程、誰驗證、誰負責回復？
- 監控是只看 CPU，還是能看出 IOPS、Latency、Connection 與 FreeStorageSpace 的異常？

如果這些事情都要自己處理，EC2 上的資料庫就不是一台便宜的 VM，而是一套需要長期投入人力的資料庫平台。

這篇文章不是說「所有資料庫都必須搬到 RDS」。而是想整理：在大多數常見的 Web、內部系統與企業應用場景中，為什麼應該優先考慮 RDS，而不是繼續把資料庫當成一台普通 EC2 來維運。

## 自建資料庫最大的成本不是 EC2 費用

自建資料庫常見的誤判，是只比較帳單上的 Instance 價格。

例如：

- 一台 EC2 + EBS 好像比同規格 RDS 便宜。
- 自己裝資料庫不用被 RDS 的限制綁住。
- 既有備份腳本可以沿用，不需要額外學習。

這些都不一定錯，但它們只看到了資源成本，沒有把維運成本放進去。

當資料庫放在 EC2 上，你至少要自己負責：

| 維運項目 | 自建 EC2 Database | Amazon RDS |
| --- | --- | --- |
| OS 維護 | 自行更新、重啟、排程 | 由 RDS 管理底層 OS 維護 |
| 資料庫安裝 | 自行安裝與設定 | 建立時選擇 Engine 與版本 |
| 儲存擴容 | 自行擴 EBS、檔案系統與資料庫設定 | 可使用 Storage Autoscaling |
| 備份 | 自行排程、保存、清理、告警 | Automated Backup、Manual Snapshot、AWS Backup |
| PITR | 自行管理 Binlog/WAL/Archive Log | 可還原到備份保存期間內的時間點 |
| 高可用 | 自行建 Standby、Replication、Failover | 可選 Multi-AZ 部署 |
| 監控 | 自行安裝 Agent 與整合工具 | CloudWatch、Enhanced Monitoring、Performance Insights |
| Patch | 自行追蹤 CVE、測試與套用 | RDS 提供 Maintenance Window 與 Pending Maintenance |

當然，RDS 不是免費幫你處理所有事情。你仍然要決定規格、備份保存期、維護時段、參數設定、監控告警與權限控管。但 RDS 把許多底層工作從「你要自己設計並執行」變成「你要設定策略並驗證結果」。

這兩件事的差異非常大。

## 磁碟容量：不要等到 storage full 才處理

資料庫最怕的狀況之一，是磁碟被寫滿。

EC2 自建資料庫雖然也可以擴 EBS，但實際流程通常不只按一個按鈕：

1. 發現磁碟快滿。
2. 擴大 EBS Volume。
3. 擴充 Partition 或 File System。
4. 確認資料庫使用的目錄能看到新容量。
5. 觀察 IOPS、Throughput 與延遲是否跟得上。

這些步驟並不難，但在半夜警報響起、磁碟只剩 2% 時，任何手動步驟都會變成風險。

RDS 提供 Storage Autoscaling。啟用後，當 RDS 偵測到可用空間不足，會依條件自動增加儲存容量。它不是萬靈丹，因為 RDS 儲存擴容後不能直接縮小，而且大型資料匯入仍可能讓資料庫短時間進入 storage full 狀態。因此還是要設定合理的初始容量、最大容量，以及針對 `FreeStorageSpace` 建立告警。

但它至少把最常見的「忘記擴容量」風險降下來。

> Storage Autoscaling 是保護機制，不是容量規劃的替代品。資料庫若持續快速成長，仍要定期檢查成長率、保留策略、索引膨脹與歸檔機制。
{: .prompt-warning}

## 備份與 PITR：有備份不代表能還原

很多系統都有備份，但真正發生事故時才發現：

- 備份其實失敗好幾天了。
- 備份檔存在，但沒有人知道還原步驟。
- 還原時間太長，超過系統能接受的 RTO。
- 只能還原到昨天凌晨，無法回到誤刪前 5 分鐘。
- 備份和正式資料放在同一個權限邊界，誤刪或被入侵時一起消失。

自建資料庫當然也能做得很好。MySQL 可以搭配 mysqldump、XtraBackup、Binary Log；PostgreSQL 可以使用 pg_dump、pg_basebackup、WAL archive；SQL Server 也有完整備份、差異備份與交易紀錄備份。

問題是，這些都需要團隊自己設計、實作、監控、演練與交接。

RDS 的 Automated Backup 會在備份視窗建立 Snapshot，並保存交易紀錄，讓你可以在備份保存期間內做 Point-in-Time Recovery。對一般 RDS DB Instance，備份保存期可以設定為 0 到 35 天；設定為 0 代表停用自動備份。

這裡最重要的觀念是：PITR 還原不是覆蓋原本的 DB，而是建立一個新的 DB Instance。這反而是好事，因為你可以先驗證資料，再決定要讓應用程式切換到新資料庫、抽資料補回原庫，或只拿它來查詢事故前狀態。

如果組織已經使用 AWS Backup，也可以把 RDS 納入統一的 Backup Plan。AWS Backup 可以集中管理備份策略、保存週期、跨帳號或跨區複製，以及 Vault Lock 等治理需求。對有稽核、合規或多帳號管理需求的公司來說，這比每個團隊各自設定備份更容易治理。

### 備份策略至少要回答三個問題

不論使用 RDS 原生備份或 AWS Backup，都應該先定義：

| 問題 | 代表意義 |
| --- | --- |
| RPO 是多少？ | 最多能接受遺失多久的資料 |
| RTO 是多少？ | 最久能接受多久恢復服務 |
| 還原演練多久做一次？ | 確認備份真的可用，而不是只看狀態成功 |

很多團隊會設定每天備份，卻沒有做還原演練。這樣只能證明「有產生備份」，不能證明「事故時能恢復」。

我會建議至少在非正式環境定期做一次還原演練，並記錄：

1. 還原一份指定時間點的 DB 需要多久。
2. 應用程式切換連線字串需要多久。
3. 權限、Parameter Group、Option Group、Security Group 是否有遺漏。
4. 還原後的資料是否符合預期。

這些結果會比「我們有開備份」更有價值。

## RDS Proxy：不要讓連線數成為第一個瓶頸

資料庫連線不是免費資源。

每一條連線都會消耗資料庫端的記憶體與 CPU。當應用程式水平擴展、Container 數量增加，或 Lambda 在短時間內大量啟動時，很容易出現 Connection Storm。結果不是查詢真的太重，而是資料庫忙著建立、驗證與維持大量連線。

在自建資料庫上，你可能會使用 PgBouncer、ProxySQL、HAProxy 或應用程式內建 Connection Pool。這些工具很好，但同樣要自己部署、監控與維護。

RDS Proxy 則是 AWS 提供的 Managed Proxy。它可以在應用程式和 RDS 之間維持連線池，重複使用既有連線，降低頻繁建立連線的成本。搭配 Multi-AZ 或故障切換時，RDS Proxy 也能協助應用程式更穩定地重新連到可用的 DB。

RDS Proxy 特別適合：

- Lambda 或短生命週期工作負載。
- 連線數容易暴增的 API 服務。
- 應用程式端 Connection Pool 設定不一致的環境。
- 希望搭配 Secrets Manager 管理資料庫憑證的系統。

但它不是查詢效能優化工具。如果 SQL 本身很慢、索引設計不良、交易持有太久，RDS Proxy 不會神奇地讓查詢變快。它主要處理的是連線管理與故障切換時的穩定性。

## CloudWatch 與 Enhanced Monitoring：資料庫要看對指標

自建資料庫常見的監控方式，是先看 EC2 的 CPU、Memory、Disk Usage。這些很重要，但對資料庫來說還不夠。

資料庫問題經常出現在：

- Connection 數量持續升高。
- FreeStorageSpace 快速下降。
- ReadLatency 或 WriteLatency 變高。
- ReadIOPS、WriteIOPS 或 Throughput 撞到儲存限制。
- CPU Credit 耗盡。
- Replica Lag 擴大。
- Lock 或慢查詢增加。

RDS 預設會把多種指標送到 CloudWatch，並可搭配 CloudWatch Alarm 建立告警。需要更細的 OS 層級資訊時，可以啟用 Enhanced Monitoring；需要分析 DB Load、等待事件與 SQL 層級瓶頸時，可以使用 Performance Insights 或 CloudWatch Database Insights。

這裡的重點不是「工具越多越好」，而是要先建立 Baseline。

例如，CPU 70% 在某些系統可能很健康，因為它本來就是 CPU-bound；但在另一個平常只有 15% 的系統，突然升到 70% 可能就代表查詢計畫改變或流量異常。沒有 Baseline，告警門檻就容易變成猜測。

我通常會先針對正式資料庫設定這些基本告警：

| 指標 | 觀察目的 |
| --- | --- |
| `CPUUtilization` | 是否長期高於平常基準 |
| `FreeableMemory` | 記憶體是否不足或發生壓力 |
| `FreeStorageSpace` | 儲存空間是否接近告警門檻 |
| `DatabaseConnections` | 連線數是否異常增加 |
| `ReadLatency` / `WriteLatency` | 儲存延遲是否惡化 |
| `ReadIOPS` / `WriteIOPS` | I/O 是否接近瓶頸 |
| `ReplicaLag` | Read Replica 是否追不上 Primary |

如果只有一個告警，我會先選 `FreeStorageSpace`。因為資料庫磁碟滿掉時，修復壓力通常最大，而且可能影響寫入、備份與後續維護。

## Patch 與 Maintenance Window：維護不能靠記憶

資料庫不只要維護資料庫引擎，還要維護底層 OS、硬體與憑證。

在 EC2 自建資料庫時，這些事情通常會落到團隊自己身上：

- 追蹤 OS 安全更新。
- 判斷資料庫 Minor Version 是否需要升級。
- 安排停機或滾動更新。
- 準備回復方案。
- 更新後驗證應用程式相容性。

如果團隊有成熟的 SRE 或 DBA 流程，這些可以做得很好。但如果資料庫只是某個應用團隊「順手維護」的資源，它很容易變成長期沒有人敢動的基礎設施。

RDS 提供 Maintenance Window，讓你控制維護事件啟動的時間。某些更新可以選擇立即套用或排到下一個維護窗口；必要的安全或可靠性更新則不能無限期延後。對 Multi-AZ 部署，RDS 在部分維護場景下可以先處理 Standby，再進行 Failover，以降低影響。

這不代表 RDS Patch 完全沒有風險。你仍然應該：

1. 把 Maintenance Window 設在流量最低的時段。
2. 開啟事件通知，知道何時有 Pending Maintenance。
3. 在非正式環境先測試 Engine 升級。
4. 確認應用程式 Driver 與 ORM 是否相容。
5. 對正式環境保留 Snapshot 與回復流程。

RDS 的價值是讓維護流程變得可被管理，而不是讓你完全不用管維護。

## Multi-AZ：高可用不是自己架一台 Standby 就結束

自建資料庫要做到高可用，通常會牽涉：

- Primary 與 Standby 的同步或非同步複寫。
- Failover 判斷。
- DNS 或連線端點切換。
- Split-brain 防護。
- 備份要從哪一台執行。
- 維護期間如何避免長時間中斷。

這些都是很專業的工作。最危險的是「看起來有一台備機」，但從來沒有演練過 Failover。等 Primary 出事時，才發現 Standby 延遲太多、權限不完整、應用程式不會自動重連，或 DNS TTL 讓切換時間超出預期。

RDS Multi-AZ 可以讓資料庫在不同 Availability Zone 之間具備更好的可用性與耐久性。它不是用來分擔讀取流量的功能；如果要讀寫分離，通常要另外使用 Read Replica。Multi-AZ 的主要價值，是在基礎設施故障、維護或某些更新情境下，降低單點故障造成的影響。

正式環境若資料庫是關鍵元件，我會把 Multi-AZ 視為預設選項，而不是事後有預算才補的項目。

## 什麼情況仍然適合自建資料庫？

RDS 很適合多數場景，但不是所有場景。

以下情況仍可能需要自建：

- 需要 RDS 不支援的資料庫引擎、版本或 Extension。
- 需要 OS 層級權限或特殊 Kernel、檔案系統、Agent。
- 需要非常客製化的備份、複寫或拓樸。
- 授權模式或商業合約不適合 RDS。
- 延遲、效能或硬體需求超出 RDS 可提供的範圍。
- 團隊本身已有成熟 DBA/SRE 能力，且自建能帶來明確收益。

這些都是真實理由。但如果理由只是「我們以前都這樣做」或「RDS 看起來比較貴」，就應該重新把人力、事故風險、維護成熟度與還原能力一起算進去。

## 導入 RDS 前應該先確認的事

如果要從 EC2 自建資料庫搬到 RDS，我建議先做一份檢查表。

### 規格與容量

- 目前資料庫大小與近 3 到 6 個月成長率。
- CPU、Memory、IOPS、Throughput 與 Connection 基準值。
- 是否需要 Provisioned IOPS 或 gp3 的指定 IOPS / Throughput。
- Storage Autoscaling 的初始容量與最大容量。

### 可用性與還原

- 是否啟用 Multi-AZ。
- Automated Backup 保存天數。
- 是否需要 AWS Backup 做跨帳號、跨區或長期保存。
- RPO 與 RTO 是否已文件化。
- 是否完成還原演練。

### 應用程式相容性

- Driver、ORM 與資料庫版本是否相容。
- 是否使用 RDS 不支援的權限、Plugin、Extension 或系統資料表操作。
- 連線字串、DNS、TLS、憑證是否需要調整。
- 是否需要 RDS Proxy。

### 維運與安全

- Parameter Group 與 Option Group 如何管理。
- Maintenance Window 與 Backup Window 是否避開高峰。
- CloudWatch Alarm、Event Notification、Log Export 是否完成。
- IAM、Security Group、KMS、Secrets Manager 是否符合公司規範。

遷移本身可以用多種方式完成，例如 Dump/Restore、Snapshot Restore、原生複寫、AWS Database Migration Service。真正要先釐清的不是工具，而是停機時間、資料一致性與回復方案。

## 結論

把資料庫架在 EC2 上不是錯。錯的是低估資料庫維運的重量。

資料庫不是一般應用程式伺服器。它牽涉資料正確性、備份還原、容量成長、效能瓶頸、安全修補與事故回復。當團隊沒有足夠時間持續處理這些事情時，自建資料庫看似省下 RDS 費用，實際上可能只是把成本藏到未來的事故與人力裡。

RDS 的價值，不只是「AWS 幫你裝好資料庫」。它真正提供的是一套受管理的資料庫維運基礎：

1. Storage Autoscaling 降低容量不足風險。
2. Automated Backup 與 PITR 讓還原策略更容易落地。
3. AWS Backup 可以集中治理備份與保存政策。
4. RDS Proxy 改善連線管理與故障切換韌性。
5. CloudWatch、Enhanced Monitoring 與 Performance Insights 提供可觀測性。
6. Maintenance Window 讓 Patch 和維護更可控。

如果你的團隊已經有成熟 DBA 能力，自建可能仍然有它的價值。但對多數產品團隊來說，把時間花在資料模型、查詢效能、資料生命週期與應用穩定性，通常比自己維護底層資料庫平台更值得。

能被託管的基礎工作，就交給 Managed Service。把工程能量留給真正需要你理解業務與系統脈絡的地方。

## 參考資料

- [Amazon RDS：Managing capacity automatically with Amazon RDS storage autoscaling](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.Autoscaling.html)
- [Amazon RDS：Introduction to backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html)
- [Amazon RDS：Backup retention period](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html)
- [Amazon RDS：Restoring a DB instance to a specified time](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html)
- [AWS Backup：Amazon Relational Database Service backups](https://docs.aws.amazon.com/aws-backup/latest/devguide/rds-backup.html)
- [AWS Backup：Continuous backups and point-in-time recovery](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html)
- [Amazon RDS：Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [Amazon RDS：Monitoring Amazon RDS metrics with Amazon CloudWatch](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [Amazon RDS：Monitoring OS metrics with Enhanced Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html)
- [Amazon RDS：Maintaining a DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.Maintenance.html)
