---
layout: post
title: "GitHub Pages から Google Search Console にサイトマップを送信してハマった話"
description: "GitHub Pages で Google Search Console に sitemap を送信した際の「取得できませんでした」問題を、カスタムドメイン、CloudFlare DNS、GitHub Pages 設定で解決した記録です。"
author: Mark_Mew
categories: [GitHub]
tags: [GitHub, GitHub Pages, Google Search Console, SEO]
keywords: [GitHub, GitHub Pages, Google Search Console, SEO]
lang: ja
date: 2026-06-14
---

先に結論から言うと、

カスタムドメインがない場合、

Google Search Console にどれだけサイトマップを送信しても、

採用されない可能性があります。

静的サイトをできるだけ早く Google にインデックスさせたいなら、

ドメインを購入して GitHub Pages に紐づけるのが一番確実な解決策でした。

## ハマった経緯

### 背景

だいたい 2 月か 3 月ごろ、

GitHub Pages をちゃんと運用してみようと思いました。

まずこのサイトのテーマを新しいものに差し替え、

Google Analytics と Google Search Console も紐づけて管理を始めました。

Google Analytics のトラッキングコードはすぐに認証できました。

Google Search Console も Google Analytics と直接連携できたので、

こちらもすぐに認証できました。

ところが、Google Search Console で何度も Sitemap を送信したあと、

![sitemap](/assets/img/google-search-console-create-sitemap-failed.png)

本当に何も言えなくなりました。

設定を直せなかっただけでなく、

AI ツールとやり取りしながら、意味のない修正に時間と Token をかなり使ってしまいました。

### 役に立たなかった修正ループ

#### AI から出てきた役に立たない提案

- `site.url` が間違っている
- `Sitemap URL` と `GSC property` が一致していない
- `<lastmod>` の形式に問題があるかもしれない
- plugin が対応していないので、別の plugin で sitemap を生成すべき
- `robots.txt` がブロックしている
- sitemap に「無効な URL」（js や css などのリソース）が含まれている
- URL が実際には存在しない
- とにかく最小構成の sitemap を使う

私の sitemap は AI ツールを使って作成したもの、

または AI の補助を受けて開発したものでした。

最終的にはオンラインツールでも検証し、

正しい XML であり、正しい sitemap.xml であることも確認しました。

それでも Google Search Console で sitemap を追加すると、

ステータスはずっと `取得できませんでした` のままでした。

AI ツールの提案が悪いと言いたいわけではありません。

Apache2 上に置いた純粋な静的ページや、

自分で管理しているサーバーであれば、

チェックリストとして一つずつ確認する価値はあると思います。

ただ今回は静的サイトのホスティングサービスを使っていて、

OS レベルで触れない部分も多くあります。

そのため、あまり参考にならない確認項目もありました。

#### 最小構成の sitemap.xml

凝った sitemap には、採用されない要素が入る可能性があります。

そのため、ほぼ最小構成の sitemap.xml も試しました。

サイト本体と posts だけを含め、

更新頻度のヒントも入れていません。

それでも最終的に GSC には採用されませんでした。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">

  <url>
    <loc>https://markmew.github.io/</loc>
  </url>

  {% for post in site.posts %}
  <url>
    <loc>{{ site.url }}{{ post.url }}</loc>
    <lastmod>{{ post.date | date_to_xmlschema }}</lastmod>
  </url>
  {% endfor %}

</urlset>
```

#### `GitHub Pages` の信頼度

👉 Google から見た GitHub Pages:
- crawl 頻度が低い
- trust が比較的低い
- 上にスパムサイトも多い

👉 結果：同じ sitemap でも、GitHub Pages のサイトは delay / fail しやすい可能性がある。

AI とやり取りしている中で、

AI ツールが少し面白い観点を出してきました。

カスタムドメインを使っていない場合、

ドメインはすべて `GitHub名`.github.io になります。

つまり、すべて github.io で終わるわけです。

このドメインの信頼度や優先度が本当に高いのかは、少し疑問が残ります。

#### `GitHub Pages` の安定性問題

💥 重要：GitHub Pages + Googlebot の昔からある問題

GitHub Pages には次のような特徴があります：
- CDN（Fastly）
- cache layer
- 分散された edge node

👉 手元で curl したときに当たるのは：

X-Served-By: cache-nrt-xxxx（日本ノード）

👉 しかし Googlebot は：

アメリカやヨーロッパから取得するかもしれません。

別のノードに当たる可能性もあります。

ドメインの信頼度以外にも、

CDN の安定性や国をまたいだ取得の安定性が原因になる可能性もあります（個人的にはあまり信じていませんが）。

ただ、生成方法から上位レイヤーまで一通り確認したあと、

私に残された解決策は本当に一つだけでした。

ドメインを購入して紐づけることです。

## 解決までの流れ

### ドメインを購入する

以前は GoDaddy でドメインを購入していました。

ただ、CloudFlare には以前から面白い機能がいくつかあります。

今回はその機能を試したいこともあり、

CloudFlare でドメインを購入することにしました。

#### DNS サービス

よく知られているように、Google DNS は `8.8.8.8` です。

CloudFlare も DNS サービス `1.1.1.1` を提供しています。

ここでドメインを購入して設定すれば、

DNS の反映も少し速いのではないか、という期待もありました。

#### 内蔵 CDN

CloudFlare は無料プランでも CDN を内蔵しています。

CloudFlare に向けて設定すれば、

コンテンツサイト中心の GitHub Pages であれば、

別途 CDN サービスを購入したり検討したりしなくてもよさそうです。

### CloudFlare の設定

CloudFlare を GitHub Pages に向けるには、4 つの A Record と 1 つの CNAME Record を設定します。

| Type | Name | Value |
| --- | --- | --- |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.108.153 |
| CNAME | www | markmew.github.io |

### カスタムドメイン

左側の `Pages` タブを開き、

一番下にある `Custom domain` からカスタムドメインを設定できます。

DNS の検証には少し時間がかかる場合があります。

しかもページを更新するたびに、

DNS の状態確認が再実行されます。

ドメインを追加したら、あとは辛抱強く待ち、`更新しない` ことです。

`DNS check successful` と表示されるまで待ちます。

このタイミングで Enforce HTTPS を有効にすることをおすすめします。

![GitHub Pages custom domain](/assets/img/github-pages-customized-domain.png)

### サイトマップを送信する

次に Google Search Console に戻ります。

GSC は GA と違い、既存プロパティの URL を直接変更できません。

そのため、新しいプロパティを追加する必要があります。

そして、その新しいプロパティから sitemap を送信します。

送信後、Google はすぐに成功と表示しました。

![Google Search Console create sitemap success](/assets/img/google-search-console-create-sitemap-success.png)

### 追加の収穫

Sitemap の送信に成功したあと、

翌日に CloudFlare の機能をいくつか見ていました。

すると、AI クローラー向けの指標が提供されていることに気づきました。

自分のサイトが AI クローラーにクロールされたかどうか、

さらには AI Agent に取り込まれているかどうかまで確認できます。

![CloudFlare AI agent metrics](/assets/img/cloudflare-ai-agent-metrics.png)

## まとめ

今回の流れを振り返ると、sitemap、robots.txt、各種設定の確認にかなり時間を使いました。

しかし一番重要だったのは、とても単純な一手でした。

カスタムドメインを購入して紐づけることです。

GitHub Pages のような無料サービスでは、

Google Search Console が `github.io` で終わるドメインを比較的低く信頼している可能性があります。

そのため、どれだけ sitemap が完璧でも採用されにくいことがあります。

ポイントは、**カスタムドメイン = sitemap を送信できる = 早くインデックスされる** ということです。

同じ問題に遭遇した場合は、直接ドメインを購入するのが一番手早い解決策です。

節約できる時間と労力を考えると、ドメイン代以上の価値があります。
