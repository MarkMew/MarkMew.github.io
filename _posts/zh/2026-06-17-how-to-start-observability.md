---
layout: post
title: "我該如何開始導入可觀測性"
description: "從 Logs、Metrics 到 Traces，整理導入可觀測性時可以採取的實作順序與注意事項。"
author: Mark_Mew
categories: [Observability]
tags: [DevOps, Observability]
keywords: [DevOps, Observability, logs, metrics, traces]
date: 2026-06-17
---

前幾年提到 DevOps、SRE，

近兩年又開始聽到平台工程（Platform Engineering），

這些議題常常最後都會落到 DevOps 工程師或公司的 Infra 團隊身上。

Observability，也就是可觀測性，已經被討論了好一陣子。

它到底是不是 buzzword？

公司或部門應不應該開始導入？

聽到大家都在說 Observability 時，

我到底該如何開始，

又該如何幫公司導入，

今天我們一樣不先談複雜的理論，

而是從實務角度出發，

整理一條可以開始導入可觀測性的路線。

## 從三本柱開始

可觀測性常見的三本柱是：

- `日誌（logs）`
- `指標（metrics）`
- `追蹤（traces）`

如果用比較直覺的方式來看，

Logs 用來回答「發生了什麼事」，

Metrics 用來回答「狀態是不是變差了」，

Traces 則用來回答「一次請求經過哪些服務，以及卡在哪裡」。

導入可觀測性時，

不一定要一開始就把三件事情全部做到滿。

比較實際的做法是：

先讓團隊能查得到事件，

再讓團隊看得到趨勢，

最後才進一步追蹤跨服務的請求路徑。

### 日誌

#### 先從能查 Logs 開始

可觀測性的第一步，

通常會從 `Logs` 開始。

如果有事件發生，

或是臨時狀況需要做障礙排除，

第一件事通常就是查看 `Logs`，

確認是否有足夠的資訊可以理解事件本身，

並協助後續排查。

說到這裡，

可能有人會說：

「就這樣？」

沒錯，如果你已經有 Logs 蒐集器，

並且有一個可以查詢 Logs 的平台，

恭喜你，你已經完成可觀測性的 1/3。

#### 建立 Logs 蒐集平台

我相信產生 `Logs` 對絕大部分工程師和系統來說都不是問題。

但有 Logs 不代表就有可觀測性。

如果 Logs 只散落在各台機器、各個 container 或不同服務裡，

事故發生時還是很難快速查詢。

有了日誌之後，

接著需要建立一個統一的日誌蒐集與查詢平台。

它可以是 `Loki`、`ELK`、`Splunk`，

也可以是雲端平台提供的 CloudWatch Logs 這類服務。

重點不是工具名稱，

而是團隊能不能在需要的時候，

用時間、服務名稱、request id、錯誤訊息等條件快速找到相關 Logs。

#### 格式化 Logs 輸出

系統在輸出 `Logs` 的時候，

如果只是把訊息隨意印出來，

很容易產生不容易查詢的內容。

```
***************
json value is {"foo": "bar"}
***************
```

尚未集中管理前，

也許在單一檔案裡還算容易識別，

不過在集中管理並需要搭配系統查詢後，

很容易被`查詢條件`或`正規表示式`卡住。

以上面的輸出為例，

如果查詢工具想把每一行都當成一筆事件處理，

那麼上下兩行 `***************` 也會被當成獨立 Log。

這時候像下面這類查詢就很容易失效：

- 查詢 `foo = "bar"` 這類 JSON 欄位
- 用 `json` parser 直接解析整行 Log
- 依照 request id 或 trace id 串起同一次請求
- 用正規表示式擷取 `json value is ...` 後面的內容
- 統計 error 次數時，被裝飾行或多行輸出干擾

看起來只是多了幾行裝飾字，

但對集中式 Logs 平台來說，

它可能會讓一筆事件被拆成多筆資料，

也可能讓原本可以結構化查詢的內容變成純文字搜尋。

因此，將 Logs 格式化輸出是必要的。

例如轉成 JSON 或 one line log，

並去除非必要的 emoji、分隔線和裝飾字。

Logs 不是寫給人眼慢慢欣賞的文章，

而是要讓系統可以穩定解析、過濾與查詢的資料。

#### 查詢工具

如果是使用 Loki 管理，

通常會搭配 Grafana 作為儀表板工具查詢，

CloudWatch Logs、ELK 和 Splunk 則是內建就有相關的查詢介面可以使用，

由於每個工具的使用方式不同，

因此至少需要熟悉幾個常用查詢語法，

以便快速排查問題。

例如：

- 依服務名稱查詢
- 依錯誤等級查詢
- 依 request id 查詢
- 依特定錯誤訊息查詢
- 依時間範圍縮小問題發生區間

做到這一步後，

Logs 才不只是被收起來，

而是真的能在事故發生時派上用場。

### 指標

當 Logs 已經能被集中查詢後，

就可以開始進行指標的建置。

不過在開始之前，

還是要先了解目前的環境是什麼，

以及想解決什麼樣的問題。

#### 資產盤點

目前的基礎設施是實體機、虛擬機，還是 Kubernetes？

如果是地端自架 Kubernetes 或雲端托管 Kubernetes，

基本上會優先選擇 Prometheus。

如果是實體機、虛擬機，

除了 Prometheus 以外，

如果流量不大，也沒有太多維運量能，

也可以考慮先使用 Munin 這類比較簡單的工具。

#### 為什麼是 Prometheus

Munin 也是 Pull 模式向 Node 拉取，

Prometheus 也是 Pull 模式向 Node Exporter 拉取資訊，

那為什麼現在主流常常推薦 `Prometheus`？

其中一個差異在於拉取頻率與資料模型。

Munin 的設計除了依賴 OS 底層 cronjob 運行外，

圖表產生方式本來也比較偏分鐘級的監控設計。

Munin 的流程如下，

```
Master
   ↓
連線 Node
   ↓
執行 Plugin
   ↓
取得數值
   ↓
更新 RRD
   ↓
重新產生圖表
```

即使可以突破 cronjob 每分鐘的設計，

串接的 Node 一多，很容易造成 Server 負擔，

因此通常不會這樣做。

Prometheus 則是 Pull 資料後，

存進時間序的資料庫中，

查詢資料時再透過 PromQL 運算並交給 Grafana 這類工具視覺化。

所以如果是 Kubernetes，

或是需要以秒級粒度蒐集資訊，

會直接使用 `Prometheus`。

#### 安裝 Node Exporter

##### 容器

如果服務跑在 Kubernetes 上，

通常不會逐台進入 Node 安裝 `Node Exporter`，

而是透過 `DaemonSet` 的方式，

讓每一台 Worker Node 都自動部署一個 `Node Exporter`。

這樣做的好處是，

當 Kubernetes 叢集新增或移除節點時，

`Node Exporter` 也會跟著自動建立或回收，

不需要額外維護每一台機器上的安裝狀態。

如果不想一開始就自己手刻 YAML，

可以先使用 `kube-prometheus-stack` 這類 Helm Chart，

它通常會一起安裝 Prometheus、Grafana、Alertmanager，

以及 Kubernetes 常用的 Exporter。

對於剛開始導入可觀測性的團隊來說，

這會比從零開始組每一個元件更容易看見成果。

##### 虛擬機

如果是一般虛擬機或實體機，

則可以直接在主機上安裝 `Node Exporter`，

讓它負責暴露 CPU、Memory、Disk、Network 等基礎指標。

如果是 Debian、Ubuntu 系列，

可以使用 `apt` 安裝：

```bash
sudo apt update
sudo apt install -y prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

如果是 RHEL、CentOS、Rocky Linux 或 Amazon Linux 這類系統，

可以使用 `yum` 安裝：

```bash
sudo yum install -y epel-release
sudo yum install -y node_exporter
sudo systemctl enable --now node_exporter
```

實際套件名稱可能會依發行版與套件庫略有不同，

如果安裝時找不到套件，

可以先確認是否已啟用對應的 repository，

或改用官方 release binary 安裝。

安裝完成後，

預設會開啟 `9100` port，

Prometheus Server 之後就可以透過這個 endpoint 拉取資料。

這邊要特別注意的是，

`Node Exporter` 本身只是把主機指標暴露出來，

它不負責儲存資料，也不負責畫圖。

真正負責定期抓取、儲存和查詢資料的，

會是後面的 `Prometheus Server`。

#### Prometheus Server 串接

當每一台主機或每一個 Kubernetes Node 都有 Exporter 後，

下一步就是讓 Prometheus Server 知道要去哪裡抓資料。

在虛擬機環境中，

可以先從靜態設定開始，

把每一台主機的 `IP:9100` 寫進 Prometheus 的 scrape config。

如果 Prometheus Server 也是安裝在虛擬機上，

通常會修改 `/etc/prometheus/prometheus.yml`。

例如：

```yaml
scrape_configs:
  - job_name: "node-exporter"
    static_configs:
      - targets:
          - "10.0.1.10:9100"
          - "10.0.1.11:9100"
```

修改完成後，

可以先檢查設定檔語法：

```bash
promtool check config /etc/prometheus/prometheus.yml
```

確認沒有問題後，

重新啟動 Prometheus：

```bash
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

如果 Prometheus 不是透過套件安裝，

而是使用 Docker 或其他方式啟動，

重點也是一樣：

把 `prometheus.yml` 掛進 Prometheus Server，

並確認設定檔內有包含要抓取的 VM `IP:9100`。

如果是在 Kubernetes 裡，

通常會透過 Service Discovery 或 `ServiceMonitor` 讓 Prometheus 自動發現目標，

避免每新增一個服務或節點就要手動修改設定。

一開始不用急著把所有指標都收進來，

先確認幾件事就好：

- Prometheus 可以正常 scrape target
- `up` 這個 metric 顯示為 `1`
- Grafana 可以查到 CPU、Memory、Disk、Network
- Dashboard 上看到的數值符合你對主機狀態的理解

確認這些基本資料可信之後，

再開始思考要補哪些應用程式指標，

以及哪些狀況需要進一步變成告警。

### 追蹤

如果系統沒有到一定規模，

通常會建議先把 `Logs` 和 `Metrics` 做好。

`Traces` 除了會增加部署複雜度以外，

也會需要有空間存放 Traces，

或者更直白地說，

你需要存放大量請求路徑資料。

為了要產生這些 Traces，

Application 不僅需要安裝套件，

也可能需要在關鍵流程補上 instrumentation，

最後部署時還需要配置 Exporter 與 Collector，

把資料轉發到後端儲存系統。

#### Application 安裝套件

如果真的要開始導入 Traces，

我會建議先從 `OpenTelemetry` 開始。

原因是它不是綁定單一廠商的格式，

未來不管資料要送到 Jaeger、Tempo、Datadog、New Relic，

或是其他可觀測性平台，

都比較容易保留調整空間。

以 Application 來說，

通常會先安裝對應語言的 OpenTelemetry SDK 或 Agent：

- Python：`opentelemetry-sdk`、`opentelemetry-instrumentation`
- Java：`opentelemetry-javaagent`
- .NET：`OpenTelemetry`、`OpenTelemetry.Extensions.Hosting`

如果是剛開始導入，

不一定要馬上手動在每個 function 裡面加 span。

可以先從自動 instrumentation 開始，

例如 HTTP request、database client、message queue client，

先讓一次請求的主要路徑被串起來。

等到真的需要分析特定商業流程時，

再補上自訂 span，

例如付款、建立訂單、產生報表這類關鍵步驟。

#### Exporter

Application 產生 Trace 之後，

需要透過 Exporter 把資料送出去。

在 OpenTelemetry 裡，

最常見的是使用 `OTLP`，

也就是 OpenTelemetry Protocol。

Application 會把 Trace 送到指定的 endpoint，

例如：

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAME=order-service
```

其中 `OTEL_SERVICE_NAME` 很重要，

它會決定這個服務在 Trace 系統裡顯示的名稱。

如果每個服務都叫 default 或 application，

等到真的要查問題時，

就會很難分辨是哪個服務出了狀況。

#### Collector（轉發）

在 Traces 的架構裡，

通常會放一個 `OpenTelemetry Collector` 作為中繼站。

它的角色有點像 Logs 裡的 Fluent Bit 或 Vector，

負責接收 Application 送來的資料，

再依照設定轉發到後端儲存系統。

這樣做的好處是，

Application 不需要直接知道後端平台是哪一套，

未來要從 Jaeger 換成 Tempo，

或是同時送到兩個平台，

主要調整 Collector 設定就好。

一個簡化後的流程會像這樣：

```text
Application
   ↓
OpenTelemetry Collector
   ↓
Trace Backend
   ↓
Grafana / Jaeger UI
```

#### Server

最後需要有一個地方儲存和查詢 Traces。

常見的選擇包含 `Jaeger`、`Grafana Tempo`，

或是雲端與 SaaS 平台提供的 APM 服務。

如果團隊已經在使用 Grafana，

可以考慮用 Tempo，

因為它可以和 Grafana 的 Dashboard、Logs、Metrics 串在一起看。

如果只是想快速理解 Trace 長什麼樣子，

Jaeger 也很適合作為入門工具。

不過不管選哪一套，

導入 Traces 前都應該先確認幾件事：

- 服務名稱是否清楚
- request id 或 trace id 是否能和 Logs 對上
- 是否真的能看出一次請求經過哪些服務
- 是否能看出哪一段花最多時間
- 是否有設定資料保留天數，避免 Trace 資料無限制成長

Traces 的價值不在於把每一行程式都記錄下來，

而是讓我們在服務之間快速定位：

這次請求到底卡在哪裡。

## 建議導入順序

如果一開始不知道該從哪裡下手，

可以依照下面的順序逐步推進：

1. 先集中 Logs，讓團隊能查到事件
2. 格式化 Logs，讓系統能穩定解析
3. 建立基本 Metrics，觀察 CPU、Memory、Disk、Network
4. 用 Prometheus 和 Grafana 做出第一版 Dashboard
5. 補上少量可信任的告警
6. 當服務開始變多、請求鏈路變長時，再導入 Traces

可觀測性不是一次買齊所有工具，

也不是把所有資料都收進來就結束。

真正重要的是，

當問題發生時，

團隊能不能更快回答三個問題：

- 發生了什麼事？
- 影響範圍有多大？
- 下一步應該往哪裡查？

## 結語

可觀測性的目標不是讓 Dashboard 看起來很漂亮，

也不是讓告警變得很多。

它真正要解決的是：

當系統出問題時，

團隊能不能更早發現、更快定位，

並且用足夠可靠的資料做出判斷。

如果目前還不知道該如何開始，

那就先從 Logs 開始。

當 Logs 能查、Metrics 能看、告警能信任之後，

再逐步補上 Traces。

這樣的導入方式不一定最華麗，

但會比較容易在真實團隊裡持續推進。
