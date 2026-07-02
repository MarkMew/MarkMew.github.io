---
layout: post
title: "AWS 成本優化實戰：從資產盤點到 Savings Plans"
description: "AWS 成本優化不只是購買 RI。本文從成本盤點、閒置資源清理、Rightsizing、S3 Lifecycle、Spot、ALB 合併與排程關機，整理一套能持續執行的 FinOps 方法。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, Cost Management]
keywords: [AWS, Cost Management, FinOps, Savings Plans, Reserved Instances, Spot Instance]
lang: zh-TW
date: 2026-07-03
---

雲端服務降低了建置基礎設施的門檻。現在要啟動一台 EC2、建立一個 RDS，往往只需要幾分鐘；但也正因為建立資源太容易，過期的測試環境、沒有人使用的磁碟，以及不再需要的備份，很容易在帳單裡留上幾個月。

當系統逐步搬上 AWS，成本增加不一定代表浪費。使用者變多、可用性提高、備援變完整，本來就會產生費用。真正需要處理的是：我們能不能說明每一筆成本的用途，並以合理的價格取得需要的效能與可靠性？

這篇文章整理我實際參與成本優化時使用的方法。核心順序是：

1. 先讓成本可以被看見與歸屬。
2. 清除沒有價值的資源。
3. 依真實用量調整規格。
4. 最後才用 Reserved Instances 或 Savings Plans 換取折扣。

順序很重要。若一開始就購買長期承諾，等於先把目前可能過度配置的用量鎖住，後面即使關掉機器，承諾費用仍然存在。

## 背景：帳單變高，不等於知道錢花在哪裡

和許多進行數位轉型的公司一樣，我們為了提高系統韌性，開始制定 SLA、SLO，並逐步把服務搬上雲端。隨著系統增加，AWS 帳單也逐年成長。

一開始最常遇到的問題不是「怎麼省」，而是沒有人能立即回答下面幾件事：

- 哪個產品、部門或環境產生了這筆費用？
- 成本增加是流量成長，還是某項資源忘了關閉？
- 這台 EC2 是必要容量，還是當初為了保險而開得太大？
- 關掉一個服務後，EBS、Snapshot、Elastic IP 或 Log 是否仍在收費？

因此，成本優化的第一步不是修改架構，而是建立可觀測性。

## 第一步：建立成本基準

### 統一資源標籤

EC2、RDS、S3、ECR 等資源至少應標示用途與負責人。實際的 Tag Key 可以依組織調整，例如：

| Tag Key | 範例 | 用途 |
| --- | --- | --- |
| `Application` | `order-service` | 對應產品或系統 |
| `Environment` | `prod`、`staging` | 區分正式與非正式環境 |
| `Owner` | `platform-team` | 找到維護單位 |
| `CostCenter` | `CC-1001` | 對應內部成本中心 |
| `ManagedBy` | `terraform` | 判斷資源如何建立與維護 |

Tag 建立後，還要到 Billing and Cost Management 啟用為 Cost Allocation Tag，才能在 Cost Explorer 或 Cost and Usage Report 中分析。新建的 Tag Key 最多可能需要 24 小時才會出現在啟用頁面，啟用也可能再花 24 小時，因此它不適合拿來即時追查當天的費用。

更重要的是，Cost Allocation Tag 不會替過去沒有標記的用量補資料。若現有資源很多，可以先從帳單占比最高的服務人工盤點，再把標籤規則寫入 Terraform、CloudFormation 或建立資源的 Pipeline，避免問題再次發生。

### 找出真正的成本驅動因子

在 Cost Explorer 先查看近 3 到 6 個月的趨勢，分別以 Service、Linked Account、Region、Usage Type 和 Tag 分組。不要只看「EC2 花了多少」，還要展開觀察：

- EC2 執行時間與執行個體類型
- EBS 容量、IOPS、Snapshot
- NAT Gateway 的處理流量
- 跨 Availability Zone、跨 Region 與對外 Data Transfer
- RDS 執行個體、儲存空間與備份
- Load Balancer 執行時間與 LCU
- CloudWatch Logs 的寫入量與保存時間

建議把分析當下的月成本、服務數量和關鍵指標記錄下來。沒有基準值，優化完成後就只能說「感覺有變便宜」，卻無法證明改動帶來多少效果。

另外可以設定 AWS Budgets 和 Cost Anomaly Detection。Budget 適合追蹤成本是否超過預期；Anomaly Detection 則用來發現與歷史型態不同的異常支出。兩者都只是警報，不能取代資產管理，但能縮短問題留在帳單裡的時間。

## 第二步：先清除沒有商業價值的資源

刪除一項完全不需要的資源，通常比替它尋找 20% 折扣更有效。我的習慣是先列出候選清單，由 Owner 確認，再設定觀察期和刪除日，避免為了省錢直接破壞仍在使用的服務。

### 清除閒置 EC2，而不是只看規格大小

公司內常會留下 `t3.small`、`t3.medium` 之類的測試機。單台費用看起來不高，所以很少有人特別處理；但同類資源累積數十台、運行數月後，仍會形成穩定支出。

不過，規格小不代表可以刪除。判斷時至少要確認：

- 最近 30 天 CPU、Network、Disk I/O 是否長期接近零
- 是否還有連線、排程或部署紀錄
- DNS、Target Group、Auto Scaling Group 是否仍指向它
- Owner 是否能說明用途與保留期限

確認不再需要後，才建立 Snapshot 或 AMI、停止觀察，最後 Terminate。單純 Stop EC2 只會停止執行個體運算費，掛載的 EBS 和部分 IP 資源仍可能計費。

同樣的檢查也應套用在未掛載 EBS、過期 Snapshot、閒置 Elastic IP、舊版 AMI、無流量的 Load Balancer，以及測試結束後留下的 RDS。

### 清除 S3 舊版本並設定 Lifecycle

CI/CD 經常把 JavaScript、CSS、安裝包或報表上傳到 S3。如果每次 Build 都保存一份，專案越多、部署越頻繁，Bucket 裡就會累積大量不再讀取的物件。啟用 Versioning 的 Bucket 還要特別檢查 Noncurrent Version，因為從畫面上看不到，不代表它沒有占用容量。

比起定期人工刪除，更好的方法是依資料特性設定 S3 Lifecycle：

- CI Artifact：只保留最近幾個版本，其餘在 30 或 90 天後刪除。
- 存取模式不明：考慮轉入 S3 Intelligent-Tiering。
- 法規要求長期保存且幾乎不讀取：評估 Glacier 儲存類別。
- Multipart Upload 失敗留下的片段：設定數日後自動清除。

Lifecycle 不是越快轉 Glacier 越省。部分儲存類別有最短保存期間、取回費與每個物件的額外成本；大量極小檔案也不一定適合封存。應先根據物件大小、存取頻率、保存期限和復原時間目標試算，再制定規則。

## 第三步：Rightsizing，而不是一律降規

完成清理後，接著處理仍有用途但配置過大的資源。AWS Compute Optimizer 可以根據既有規格與使用指標，提供 EC2、Auto Scaling Group、EBS、ECS on Fargate，以及部分 RDS 與 Aurora 資源的建議。

不要只看平均 CPU。以下指標都可能成為瓶頸：

- CPU 的平均值與尖峰值
- 記憶體使用量與 Swap
- Network PPS 與 Throughput
- EBS IOPS、Throughput、Queue Length
- RDS Connection、Freeable Memory、Read/Write Latency
- T 系列的 CPU Credit Balance

記憶體不是 EC2 預設送到 CloudWatch 的標準指標，需要安裝 CloudWatch Agent 或由既有監控系統提供。若只憑 CPU 判斷，很容易把記憶體密集型服務縮得太小。

調整規格時應保留足夠 Headroom，先在非正式環境驗證，再於低風險時段修改。正式環境還要確認啟動時間、Auto Scaling、容錯與回復方案。成本優化的目標是移除浪費，不是把系統壓到沒有任何緩衝。

### 標準化規格，但不要限制得過頭

如果團隊同時維護太多 EC2 Family、作業系統與資料庫版本，監控、Patch、映像檔和容量規劃都會變複雜。把相似工作負載收斂到少數經過驗證的規格，有助於維運與購買長期折扣。

但不需要硬性規定所有服務只能用三種 Instance Type。運算密集、記憶體密集和一般用途的工作負載本來就不同；過度限制還可能錯過新世代 Instance 或 Graviton 帶來的 Price Performance。標準化的目的，是減少無意義的差異，不是讓所有工作負載穿同一雙鞋。

## 第四步：選擇合適的計價方式

完成清理與 Rightsizing 後，才比較能看出真正穩定的基礎用量。這時再決定哪些使用 On-Demand、Reserved Instances、Savings Plans 或 Spot。

### Reserved Instances 與 Savings Plans

Savings Plans 是承諾未來 1 年或 3 年，每小時使用固定金額的運算資源，以換取低於 On-Demand 的價格。它不是預付一包「可用時數」；即使某個小時沒有足夠用量，該小時的承諾金額仍然要支付。

實務上可依下面方式思考：

- 長期且穩定的 RDS、ElastiCache、OpenSearch 等服務：評估各服務對應的 Reserved Instance 或 Reserved Node。
- EC2 Family 與 Region 穩定、希望取得較高折扣：評估 EC2 Instance Savings Plans。
- 工作負載可能跨 Family、Region，或使用 Fargate、Lambda：評估彈性較高的 Compute Savings Plans。
- 短期專案、需求仍不明確或可能下線：保留 On-Demand，不急著承諾。

購買前可參考 Cost Explorer 的建議，但必須確認它使用的 Lookback Period 是否能代表未來。AWS 的建議是根據過去用量計算，不會預測產品下線、架構遷移或下個月的流量變化。

比較穩健的作法是分批購買：先覆蓋確定會持續存在的基礎用量，觀察 Coverage 與 Utilization，再逐步增加承諾。不要為了追求 100% Coverage，讓自己同時背上低 Utilization 的風險。

### Spot Instance

Spot 適合可中斷、可重試、可水平擴展的工作負載，例如 Batch、CI Runner、影像轉檔或 Stateless Worker。它不適合把一台無法復原的單點正式機器直接換成 Spot，然後期待永遠不被收回。

使用 Spot 時，應從系統設計處理中斷：

- 工作狀態存放在外部儲存，不依賴單台機器的本機磁碟。
- 任務具備 Idempotency，失敗後可以安全重試。
- 收到中斷通知時，能停止接收新工作並完成 Drain。
- Auto Scaling Group 同時提供多個可接受的 Instance Type 與 Availability Zone。
- 使用 Capacity-Optimized 等配置策略，避免只選當下最便宜但容量不足的 Pool。
- 關鍵服務保留一部分 On-Demand 作為基礎容量。

[EC2 Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/) 可以用來了解各 Instance Pool 的歷史中斷頻率，但不能把某個 Family 永久視為安全或危險。Spot 可用容量會隨 Region、Availability Zone、規格與時間改變，多樣化選擇通常比押注單一 Instance Type 更可靠。

## 第五步：從架構減少固定成本

有些費用不是調小機器就能改善，而是來自架構中重複存在的基礎元件。

### 合併低流量系統的 ALB

ALB 可以用 Host Header 或 Path Pattern，把請求導向不同 Target Group。因此，同一套低流量系統的前台、後台、訂單或會員模組，不一定要各自配置一個 ALB。

如果六個低流量模組原本各有一個 ALB，合併後確實能減少 Load Balancer 的固定小時費。不過，實際帳單不一定剛好變成六分之一，因為 ALB 還會依 LCU 計費，Listener Rule、Certificate、WAF 和跨 AZ 流量也可能影響成本。

更重要的是，合併會擴大 Blast Radius。以下情況仍適合分開：

- 系統屬於不同安全邊界或帳號
- 需要不同的 WAF、TLS 或存取政策
- 發布與維護週期不同
- 單一系統流量很大，可能影響其他服務
- 需要獨立觀測、配額或故障隔離

因此，ALB 合併適合流量不高、生命週期接近且安全需求相同的服務，而不是所有系統一律共用。

### 為非正式環境設定開關機排程

開發、測試與教育環境通常不需要全年 24 小時運行。可以使用 EventBridge Scheduler 搭配 Lambda、Systems Manager Automation 或 AWS Instance Scheduler，在上班前啟動、下班後停止。

假設環境平日每天只需要 10 小時，排除假日後，EC2 的運行時間可以明顯降低。但要記住：

- EC2 停止後仍會收取 EBS 等持續存在資源的費用。
- 沒有綁定 Elastic IP 的 Public IPv4 可能在重新啟動後改變。
- Instance Store 上的資料不會在 Stop/Start 後保留。
- RDS 停止時仍會收取儲存、Provisioned IOPS 與備份等費用。
- 一般 RDS DB Instance 最多只能連續停止 7 天，之後會自動啟動。

排程關機最適合可以接受啟動時間的非正式環境。正式環境若有明顯尖峰與離峰，通常應優先使用 Auto Scaling 依需求調整容量，而不是在固定時間直接關閉機器。

### 別忽略網路與日誌費用

當運算費已經壓低，NAT Gateway、Data Transfer 和 CloudWatch Logs 往往會開始變得顯眼。

可檢查的方向包括：

- Private Subnet 是否有大量流量經 NAT Gateway 存取 S3、DynamoDB 或其他 AWS 服務，能否改用 VPC Endpoint
- 跨 AZ 呼叫是否是架構必要，還是服務發現或流量路由造成的繞路
- Container 是否不斷輸出無法使用的 Debug Log
- CloudWatch Log Group 是否缺少 Retention Policy，導致永久保存
- ECR Image 與 Snapshot 是否有 Lifecycle Policy

這類費用必須先理解流量路徑再修改。為了省跨 AZ 費用而犧牲 Multi-AZ 可用性，通常不是好的交換。

## 如何讓成本優化持續運作

一次性的成本專案很容易在半年後回到原點。比較有效的方式，是把成本變成日常工程流程的一部分：

1. 每個資源建立時就必須有 Owner、Application 與 Environment Tag。
2. 每月由產品、財務與平台團隊共同檢查成本趨勢與異常。
3. 每項改善記錄調整前成本、預估節省、風險、Owner 與完成日。
4. 定期檢查 RI、Savings Plans 的 Coverage 與 Utilization。
5. 在 Terraform 或 Policy 中加入 Log Retention、S3 Lifecycle 和非正式環境排程等預設值。
6. 對無 Owner、無流量或到期的資源建立自動通知，而不是直接自動刪除。

成本指標也不應只有「本月少花多少」。如果產品正在成長，總帳單增加可能完全合理。更有意義的指標通常是每位活躍使用者、每筆訂單、每次 API Request 或每個租戶的單位成本。

## 結論

AWS 成本優化不是在月底看到帳單太高，臨時關掉幾台機器；也不是買完 Savings Plans 就結束。它是一個持續循環：先建立成本可見性，再移除閒置資源、調整規格、選擇計價方式，最後回到監控與驗證。

如果只能先做三件事，我會選擇：

1. 讓每筆主要成本都有 Owner 與用途。
2. 刪除確認沒有價值的資源，並替資料設定保存期限。
3. 完成 Rightsizing 後，再分批購買長期承諾。

省下來的費用很重要，但更重要的是建立一套讓團隊知道「為什麼花這筆錢」的機制。當成本和可靠性、效能、產品價值能放在同一張桌上討論，FinOps 才不只是刪資源，而是真正的工程決策。

## 參考資料

- [AWS Billing：Activating user-defined cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html)
- [AWS Compute Optimizer：Supported resources](https://docs.aws.amazon.com/compute-optimizer/latest/ug/supported-resources.html)
- [AWS Savings Plans：What are Savings Plans?](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html)
- [AWS Savings Plans：Understanding recommendation calculations](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-rec-calculations.html)
- [Amazon EC2：Spot interruption notices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html)
- [Amazon S3：Transitioning objects using Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html)
- [Elastic Load Balancing：Listeners for Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [Amazon EC2：How instance stop and start works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-stop-start-works.html)
- [Amazon RDS：Stopping a DB instance temporarily](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)
