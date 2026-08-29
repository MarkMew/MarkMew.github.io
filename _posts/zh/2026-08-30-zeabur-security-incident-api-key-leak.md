---
layout: post
title: "Zeabur 資安事件解析：API 金鑰外洩事件回顧與資安教訓"
image: https://fastly.picsum.photos/id/258/1200/630.jpg?hmac=1tNJdsrdyuIv3qsmBvgDQVZjIs5pTV_JqsWFtqD3Qik
description: "解析 2026 年 8 月 Zeabur 資安事件始末，包含 OpenAI、AWS 等 API 金鑰外洩原因、官方應變措施，以及用戶應立即採取的資安防護行動與教訓。"
author: Mark_Mew
categories: [Security]
tags: [Zeabur, Security, AI, LiteLLM, API Key]
keywords: [Zeabur, 資安事件, API 金鑰外洩, LiteLLM, 資安, Security Incident]
lang: zh-TW
date: 2026-08-30
---

雲端部署平台 Zeabur 在 8/27 發生資安事件，有人未經授權存取了用於檢索專案環境變數記錄的內部服務憑證，攻擊者用這組憑證拿到部分用戶的環境變數。環境變數根據官方接露的部分，除了 OpenAI、Anthropic 相關 AI 工具的 的 API 金鑰以外，亦包含 GitHub PAT、AWS 相關金鑰。實際上能做到甚麼，仍取決於 key 被授予的權限，有人拿著受害用戶的 key 使用服務，帳單算在原主人頭上。

## 發生了什麼
* 8/27：Zeabur 內部一組服務憑證被未授權存取
* 攻擊者利用這組憑證，取得用戶的環境變數
* 外洩的憑證類型：OpenAI / Anthropic / OpenRouter / GitHub PAT / AWS / Cloudflare / Stripe token (詳細可參考官方狀態頁面：![Zeabur Status Page](https://status.zeabur.com/incident/1037896))
* 已確認有用戶的 AI API key 被盜用（帳單異常）

## 調查線索
官方狀態頁接露 Zeabur AI Hub 服務所使用的 LiteLLM 有可疑活動。正在調查 LiteLLM 的可疑活動是否與此事件有關，雖然尚未證實，為預防起見，並防止任何潛在的進一步影響，Zeabur 將在調查期間暫時中止 Zeabur AI Hub 服務。

## 創辦人怎麼處理
林沅霖 8/29 在 Threads 上發布相關說明：
- 在偵測到異常的當天即完成第一時間的控制
- 持續監控是否有進一步異常
- 逐一通知所有可能受影響的使用者並發布公告
- 正在配合上游廠商及執法機關進行進一步調查

**呼籲用戶：立即輪換所有存放在 Zeabur 的 API key 跟密碼、檢查用量跟帳單。如果發現被盜用，保留時間、金額、token 用量、來源 IP 等證據提交客服。**
![Zeabur Founder Annoouncement](/assets/img/zeabur_founder_announcement.png)

## 如果你是 Zeabur 用戶，現在該做的事
1. 立即輪換所有存在 Zeabur 環境變數裡的 key 跟密碼
2. 檢查帳單：所有有在用於 Zeabur 的服務的 API Key 及關連服務
3. 如果有異常用量，截圖保留證據後提交 Zeabur 客服
4. 資料庫密碼、JWT Secret及其他 Credentials 相關資訊皆需要更換

## 教訓：
### 設定上限
不管使用甚麼平台，記得設定 usage limit 或 budget

### 最小權限原則
從雲端興起後，各個平台就很常呼籲儘量以最小權限為原則，當權限限縮後，就不容易讓影響範圍無限制擴張，這點在 AI 工具大量公眾於視野後，其實使用 API 也是一樣的道理。

### 考慮採用 Federated Authentication（聯合身分驗證）
近年來，許多平台開始不採用長效金鑰，改以系統對系統之間的聯合身分驗證（Federated Authentication，例如 OIDC）進行授權，透過短效憑證與細緻的信任關係限制使用範圍，可以有效降低金鑰外洩後被盜用的風險

## 參考資料
- [Zeabur Status Page - Incident Report](https://status.zeabur.com/incident/1037896)
- [動區動趨 BlockTempo - Zeabur 環境變數外洩，OpenAI、Anthropic API 金鑰遭竊](https://www.blocktempo.com/zeabur-environment-variable-leak-openai-anthropic-api-key-stolen-compensation/)
- [Inside 硬塞的網路趨勢觀察 - Zeabur 環境變數外洩，API 金鑰遭竊事件](https://www.inside.com.tw/article/42241-zeabur-environment-variable-leak-api-keys-stolen)
- [geekMickey - Facebook 貼文](https://www.facebook.com/geekMickey/posts/pfbid0Hz2edfN8yAWayebxLy9JbirdiJfSws3QisrGi5cuubvtwhLU2c6X5dDuERaR9wRfl)
- [林沅霖（Zeabur 創辦人）- Threads 貼文](https://www.threads.com/@yuaanlin/post/DcmVCO7kuG6)
- [Threads 分享連結](https://www.threads.com/share/E3cDHLVLV/)