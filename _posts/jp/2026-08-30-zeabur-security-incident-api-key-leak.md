---
layout: post
title: "Zeabur セキュリティインシデント解説：APIキー漏洩事件の振り返りと教訓"
image: https://fastly.picsum.photos/id/258/1200/630.jpg?hmac=1tNJdsrdyuIv3qsmBvgDQVZjIs5pTV_JqsWFtqD3Qik
description: "2026年8月に発生したZeaburのセキュリティインシデントを解説。OpenAIやAWSなどのAPIキー漏洩の原因、公式の対応、そしてユーザーが今すぐ取るべき対策と教訓をまとめる。"
author: Mark_Mew
categories: [Security]
tags: [Zeabur, Security, AI, LiteLLM, API Key]
keywords: [Zeabur, セキュリティインシデント, APIキー漏洩, LiteLLM, セキュリティ]
lang: ja
date: 2026-08-30
---

クラウドデプロイプラットフォームのZeaburで8月27日、セキュリティインシデントが発生した。プロジェクトの環境変数記録を取得するための内部サービス認証情報が不正アクセスを受け、攻撃者はこの認証情報を使って一部ユーザーの環境変数を取得した。Zeaburが公表した内容によると、漏洩した環境変数にはOpenAIやAnthropicなどAIツール関連のAPIキーのほか、GitHub PATやAWS関連の認証情報も含まれていた。実際に何ができるかは付与されていた権限次第だが、被害を受けたユーザーのキーが攻撃者に使われ、請求は元の所有者に発生している。

## 何が起きたか
* 8月27日：Zeabur内部のサービス認証情報が不正アクセスを受けた
* 攻撃者はこの認証情報を利用し、ユーザーの環境変数を取得した
* 漏洩した認証情報の種類：OpenAI / Anthropic / OpenRouter / GitHub PAT / AWS / Cloudflare / Stripe トークン（詳細は公式ステータスページを参照：![Zeabur Status Page](https://status.zeabur.com/incident/1037896)）
* 一部ユーザーのAI APIキーが不正利用されたことが確認されている（請求異常）

## 調査の手がかり
公式ステータスページでは、Zeabur AI Hubが利用するLiteLLMに不審な活動があったことが明らかにされた。この不審な活動が今回の事件と関係しているかどうかは調査中でまだ確認されていないが、予防措置として、また潜在的な影響拡大を防ぐため、ZeaburはAI Hubサービスを調査期間中一時停止するとしている。

## 創業者の対応
創業者のLin Yuan-Lin氏は8月29日にThreadsで以下のように説明した：
- 異常を検知した当日中に初動対応を完了
- さらなる異常がないか継続的に監視
- 影響を受けた可能性のあるユーザーへ個別に通知し、告知を発表
- 上流ベンダーおよび捜査機関と協力しさらなる調査を実施中

**ユーザーへの呼びかけ：Zeaburに保存しているAPIキーとパスワードを直ちにローテーションし、利用量と請求を確認すること。不正利用が発見された場合は、時刻・金額・トークン利用量・送信元IPなどの証拠を保存の上サポートへ提出してください。**
![Zeabur Founder Announcement](/assets/img/zeabur_founder_announcement.png)

## Zeaburユーザーが今すぐすべきこと
1. Zeaburの環境変数に保存されているキーとパスワードを直ちにローテーションする
2. Zeaburで利用しているすべてのサービスと関連APIキーの請求を確認する
3. 異常な利用があればスクリーンショットで証拠を保存し、Zeaburサポートへ提出する
4. データベースのパスワード、JWTシークレット、その他の認証情報もすべて更新する

## 教訓
### 上限の設定
どのプラットフォームを使う場合でも、利用上限（usage limit）や予算（budget）を設定しておくこと。

### 最小権限の原則
クラウドの普及以降、各プラットフォームは最小権限の原則に従うよう呼びかけてきた。権限を絞ることで影響範囲が無制限に拡大するのを防げる。AIツールが広く使われるようになった今、APIの利用についても同じ考え方が当てはまる。

### Federated Authentication（フェデレーション認証）の採用を検討する
近年、多くのプラットフォームは長期間有効なキーの代わりに、システム間のフェデレーション認証（Federated Authentication、例えばOIDC）を採用し始めている。短命な認証情報ときめ細かな信頼関係によって利用範囲を制限することで、認証情報漏洩後の不正利用リスクを大幅に下げることができる。

## 参考資料
- [Zeabur Status Page - Incident Report](https://status.zeabur.com/incident/1037896)
- [BlockTempo - Zeabur環境変数漏洩、OpenAI・Anthropic APIキーが盗まれる](https://www.blocktempo.com/zeabur-environment-variable-leak-openai-anthropic-api-key-stolen-compensation/)
- [Inside - Zeabur環境変数漏洩、APIキー盗難事件](https://www.inside.com.tw/article/42241-zeabur-environment-variable-leak-api-keys-stolen)
- [geekMickey - Facebook投稿](https://www.facebook.com/geekMickey/posts/pfbid0Hz2edfN8yAWayebxLy9JbirdiJfSws3QisrGi5cuubvtwhLU2c6X5dDuERaR9wRfl)
- [Lin Yuan-Lin（Zeabur創業者）- Threads投稿](https://www.threads.com/@yuaanlin/post/DcmVCO7kuG6)
- [Threads共有リンク](https://www.threads.com/share/E3cDHLVLV/)
