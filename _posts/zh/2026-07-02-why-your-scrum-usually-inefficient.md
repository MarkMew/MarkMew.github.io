---
layout: post
title: "為什麼你的 Scrum 總是跑得這麼沒效率"
description: "Scrum 沒有效率，通常不是會議不夠多，而是權責、團隊組成與交付方式出了問題。從 Scrum 的基本結構出發，整理幾個企業最常見的反模式。"
author: Mark_Mew
categories: [Agile]
tags: [Scrum, Agile]
keywords: [Scrum, Agile, Scrum Master, Sprint, MVP]
lang: zh-TW
date: 2026-07-02
---

Scrum 是一套用來處理複雜問題的輕量級框架。

它採用迭代與增量的方式，讓團隊在有限時間內完成可檢視的成果，再根據實際結果調整下一步。

Scrum 的概念在 1990 年代逐漸成形，第一版 Scrum Guide 則於 2010 年發布。

後來隨著課程、顧問與證照制度普及，Scrum 幾乎成為許多軟體團隊導入 Agile 時的預設選項。

但很多公司導入的其實只有 Scrum 的外觀：

- 每天站著報告進度
- 每隔一兩週切一次 Sprint
- 在 Jira 上搬動 Ticket
- 讓 Scrum Master 主持固定會議

所有儀式都做了，交付速度卻沒有變快，會議反而更多。

問題通常不是團隊「不夠 Agile」，而是公司只換了流程名稱，沒有改變原本的權責、決策與交付方式。

## Scrum 的組成

依照 2020 Scrum Guide，Scrum Team 由 3 種職責組成，並在 Sprint 之中進行 4 個正式事件，產出 3 項 Scrum 產出物（Artifacts）。

### 3 種職責

#### Product Owner

Product Owner 對產品價值負責，管理 Product Backlog、排序優先順序，並確保團隊理解 Product Goal。

Product Owner 不是把需求轉貼給工程師的窗口，也不是由一群利害關係人共同投票產生的委員會。

如果任何人都能臨時插單、改優先順序，Product Owner 就只有職稱，沒有真正的決策權。

#### Scrum Master

Scrum Master 對 Scrum Team 的有效性負責，協助團隊與組織理解 Scrum、排除阻礙，並讓每個事件維持其目的。

他不是專案經理、會議記錄員，也不是負責追殺 Ticket 的流程警察。

#### Developers

Developers 負責規劃 Sprint、維持品質，並在每個 Sprint 建立符合 Definition of Done 的 Increment。

這裡的 Developers 不只代表程式設計師，而是所有實際參與產出 Increment 的成員。

### Sprint 與 4 個 Meeting

Sprint 是 Scrum 的容器，長度不超過一個月。Sprint Planning、Daily Scrum、Sprint Review 與 Sprint Retrospective 都在其中發生。

#### Sprint Planning Meeting

團隊決定這個 Sprint 為什麼值得做、能完成什麼，以及預計如何完成，並形成 Sprint Goal 與 Sprint Backlog。

#### Daily Scrum Meeting

Daily Scrum 是 Developers 檢視 Sprint Goal 進度、調整當日計畫的事件，不是輪流向主管報告昨天做了什麼。

#### Sprint Review Meeting

團隊與利害關係人一起檢視成果與環境變化，討論下一步。它不是只有投影片和掌聲的成果發表會。

#### Sprint Retrospective Meeting

團隊檢視合作方式、流程、工具與品質，找出下一個 Sprint 可以實際採取的改善。

### 3 項 Scrum 產出物

Scrum 的 3 項產出物分別是 Product Backlog、Sprint Backlog 與 Increment，對應的承諾則是 Product Goal、Sprint Goal 與 Definition of Done。

- **Product Backlog**：為了改善產品而需要進行工作的排序清單
- **Sprint Backlog**：Sprint Goal、選入的 Product Backlog Items，以及交付它們的計畫
- **Increment**：已完成、可使用，並符合 Definition of Done 的產品增量

這些元素不是拿來增加文件，而是讓工作透明，讓團隊能根據真實結果進行檢視與調整。

## 為什麼你的 Scrum 跑得不好

### Scrum Master 同時握有考核權

Scrum Guide 沒有規定主管絕對不能擔任 Scrum Master，真正的問題在於權力如何被使用。

當 Scrum Master 同時決定成員的績效、升遷或去留，團隊就很難在 Retrospective 坦白討論失敗，也很難在 Sprint Planning 對不合理的承諾說不。

原本應該用來檢視與調整的事件，最後會圍繞主管的偏好重新安排。團隊表面上自主管理，實際上仍在等待指令。

如果主管無法放下分派工作與評價個人的習慣，就不適合同時擔任 Scrum Master。

> The Great ScrumMaster 這本書裡面有提到為什麼主管不適合做 Scrum Master
{: .prompt-info}

### 主管把 Daily Scrum 當成點名

Scrum Team 內沒有傳統式的職級階層。

Product Owner 說明目標與排序，Scrum Master 改善團隊有效性，Developers 自主管理如何完成工作。

但主管一進到 Daily Scrum，就站在看板前逐一審問：

- 這張 Ticket 為什麼還沒做完？
- 你昨天到底做了什麼？
- 今天下班前能不能上線？

Daily Scrum 於是從 Developers 的協作事件，變成每天 15 分鐘的績效面談。

成員開始修飾進度、隱藏問題，甚至把工作拆成容易呈現的 Ticket。看板看起來很忙，真正的風險卻更晚才被發現。

### Product Owner 沒有排序權

另一個常見問題是，每一位主管都是 Product Owner。

業務說客戶最重要，營運說事故最重要，老闆則在 Sprint 中途丟進一個「應該很簡單」的新需求。

真正的 Product Owner 只能幫大家建立 Ticket，卻不能拒絕插單，也不能決定先做什麼。

在這種情況下，Sprint Goal 沒有任何約束力。團隊每天都在處理當下聲量最大的人，而不是交付最有價值的成果。

Scrum 需要一位對 Product Backlog 排序負責，而且其決策會被組織尊重的 Product Owner。

### MVP 只拿來 Demo，卻從不上線

過往執行經驗中，最常見的問題之一，是團隊做出了可以 Demo 的 MVP，**但是不上線**。

很多新系統在 Sprint 結束後，成果只存在於工程師的本機或會議室裡。Demo 完便繼續累積功能，等到幾個月後再一次整批發布。

這不是增量交付，只是把小型瀑布切成數個 Sprint。

Increment 不代表每個 Sprint 都必須正式發布給所有使用者，但它至少要符合 Definition of Done、處於可使用狀態，而且不需要等下一個 Sprint 補完測試或整合才能發布。

如果永遠無法讓真實使用者接觸成果，團隊就拿不到真正的回饋，只能用 Demo 現場的意見猜測產品方向。

### 團隊技能無法共同完成 Increment

假設團隊中只有一位 DBA、一位 DevOps、一位網管、一位前端、一位後端，再加上一位行銷人員。

成員雖然都在同一個看板，工作卻彼此沒有關聯，也無法共同完成一項產品增量。

當行銷同仁接到 Apply 防火牆設定的 Task，前端同仁要替 Kubernetes 建立 Prometheus Operator，而 DBA 被分配去調整 GTM，問題不是大家不願意跨領域，而是團隊邊界從一開始就畫錯了。

跨職能不等於每個人什麼都要會，而是整個 Scrum Team 具備完成 Increment 所需的能力，並共同對一個 Product Goal 負責。

如果成員只是在同一個部門裡接收互不相關的工單，Kanban 或一般的工作管理方式可能更適合，沒有必要硬套 Scrum。

> 這樣的團隊組成，
> 我甚至會懷疑公司是不是故意用這方式資遣員工。
{: .prompt-info}

### Sprint 短到只剩會議

曾經遇過一個專案，六週後必須上線，因此把 Sprint 縮成一週。

結果每週都要進行 Planning、Review、Retrospective，還要處理跨團隊協調與發布流程。工程師剛把問題理解清楚，下一輪 Planning 又開始了。

短 Sprint 可以更快取得回饋，但前提是團隊有能力在這個週期內完成可用的 Increment。

如果工作本身需要大量外部審核、跨部門等待或手動部署，單純縮短 Sprint 只會提高會議占比，不會讓交付變快。

這時應該先處理等待時間與依賴關係，再決定適合的 Sprint 長度。

### Scrum Master 不懂，也不願意碰軟體開發

「有 PMP 證照不代表你是厲害的 PM，但它可能幫你找到 PM 的工作。」

Scrum Master 也是一樣。擁有證照、上過課或接受過 Coach，不代表就能帶領團隊改善。

我認為，在軟體開發團隊中，Scrum Master 可以不是技術最強的人，也可以不承擔主要的開發產能，但完全不懂軟體開發，甚至因為「不想寫程式」才選擇成為 Scrum Master，是完全不行的。

因為團隊遇到的阻礙往往就在開發過程裡：需求是否能被實作、技術債為什麼拖慢交付、測試與部署卡在哪裡、跨服務依賴如何影響 Sprint Goal。若 Scrum Master 聽不懂這些問題，也不願意理解，就無法分辨團隊是真的遇到阻礙，還是工作方式需要改善。

這不代表 Scrum Master 必須搶走 Developers 的工作，而是至少要有實際參與軟體開發的經驗，理解一項功能從需求、設計、實作、測試到部署的完整過程。即使現在不負責主要開發，也不能把「我不碰技術」當成這個角色的定位。

如果只會照表主持會議、計算 Velocity，再催促大家更新 Ticket，最後就只是在技術團隊外面增加一層不懂技術的管理者，無法真正協助團隊提升有效性。

好的 Scrum Master 不會替團隊做所有決定，而是讓問題透明、協助移除組織障礙，並讓團隊逐步具備自行解決問題的能力。

### 把 Velocity 當成 KPI

Velocity 只能協助同一個團隊理解自己的交付能力，不能用來比較不同團隊，更不適合成為績效指標。

一旦主管要求 Velocity 每個 Sprint 都要提高，最容易改變的不是生產力，而是 Story Point 的估算方式。

原本 3 點的工作改估成 5 點，報表立刻成長，產品卻沒有更早交付。

真正值得觀察的是：團隊是否更穩定地達成 Sprint Goal、Increment 是否真的可用、從想法到取得使用者回饋需要多久，以及同樣的問題是否反覆發生。

## 先確認你是否真的需要 Scrum

Scrum 適合面對需求與解法都需要透過實作逐步探索的複雜工作。

如果工作主要是處理大量零散請求、優先順序頻繁改變，而且每項工作彼此獨立，Kanban 可能更自然。

如果需求、技術與交付方式都十分明確，也不一定需要為了「Agile」而增加固定事件。

在導入 Scrum 前，可以先回答以下問題：

1. 團隊是否共同負責同一個 Product Goal？
2. Product Owner 是否真的能決定 Product Backlog 的排序？
3. 團隊是否具備在一個 Sprint 內完成 Increment 的能力？
4. Definition of Done 是否包含測試、整合與必要的發布準備？
5. Sprint Review 是否能取得利害關係人的有效回饋？
6. Retrospective 提出的改善是否真的有人執行？
7. 團隊是否能在不受懲罰的情況下揭露問題？

如果多數答案是否定的，先增加更多 Scrum 儀式通常沒有幫助。

## 結論

Scrum 不會自動讓團隊變快。

它真正做的，是透過透明、檢視與調整，讓組織原本存在的問題更快浮現。

Product Owner 沒有決策權、主管習慣微管理、團隊無法獨立交付、發布流程耗時，這些問題不會因為建立 Sprint 和看板就消失。

如果公司看見問題後願意改變權責、團隊邊界與交付流程，Scrum 才可能發揮作用。

如果只是把週會改名為 Daily Scrum，把需求清單改名為 Product Backlog，再用 Velocity 追蹤績效，那麼 Scrum 帶來的通常不會是敏捷，而是更多會議。

同樣地，採用瀑布式開發也不代表團隊比較落後。

當需求明確、變動有限，各階段的責任與驗收標準都能事先定義時，瀑布式開發反而能讓規劃、預算與交付時間更加清楚。對需要嚴格審核、法規文件或硬體整合的專案而言，它甚至可能比 Scrum 更適合。

開發方法本身沒有高下之分。Scrum、Kanban 或瀑布式開發都只是協助團隊完成工作的工具，而不是必須信奉的教條。

只要一套方法能讓團隊穩定、可預測地交付有價值的成果，它就是好的開發方式。反過來說，當一套方法增加了等待、會議與溝通成本，甚至開始阻礙專案進展，就應該重新調整，必要時直接停止採用。

團隊真正需要追求的從來不是「我們有沒有正確地跑 Scrum」，而是「我們能不能持續把有價值的產品交付出去」。

## 參考資料

- [The 2020 Scrum Guide](https://scrumguides.org/scrum-guide.html)
- [Scrum Guide Revision History](https://scrumguides.org/revisions.html)
- [Common Myths about Scrum Masters](https://www.scrum.org/resources/common-myths-about-scrum-masters)
