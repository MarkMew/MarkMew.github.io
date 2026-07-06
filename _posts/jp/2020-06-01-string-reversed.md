---
layout: post
title: "文字列反転の三つの境地：ジュニアは for、初級者は reverse、達人は \\u202E？"
description: "JavaScriptで文字列を反転する三つの方法を比較します。forループ、reverse、そしてUnicode \\u202Eを使った表示上の裏技です。"
author: Mark_Mew
category: 小技
date: 2020-6-1
lang: ja
---

先週、フロントエンドのコミュニティで、文字列の反転についての面白い[投稿](https://www.facebook.com/groups/f2e.tw/permalink/2913375802033099/)を見かけました。

話題になっていた投稿は次の画像のとおりです。

![Alt 文字列の反転](/assets/img/100869303_112730000452747_3790033580424429568_n.jpg)

同じ要件でも、書き方によって三つのまったく異なる境地が見えてきます。

## ジュニア：forループを自分で書く

プログラミングを学び始めたときに最も思いつきやすいのは、文字列の末尾から `for` ループで逆向きにたどり、一文字ずつ新しい文字列へ追加する方法です。

```javascript
const text = "Hello";
let reversed = "";

for (let i = text.length - 1; i >= 0; i--) {
  reversed += text[i];
}

console.log(reversed); // olleH
```

処理の流れが分かりやすく、インデックスやループの練習にもなります。一方でコードが少し長く、開始位置や終了条件を間違えやすいのが欠点です。

## 初級者：reverseを使う

JavaScriptの組み込みメソッドに慣れたら、文字列を配列へ展開し、`reverse()` を呼び出してから `join()` で文字列へ戻せます。

```javascript
const text = "Hello";
const reversed = [...text].reverse().join("");

console.log(reversed); // olleH
```

コードが短く、意図も明確です。ただし、複数のUnicodeコードポイントで構成される絵文字や結合文字を正確に扱うには、grapheme clusterを認識できる実装が必要です。

## 達人：`\u202E` 一つで解決？

投稿で紹介されていた方法はまったく異なります。Unicodeの方向制御文字 `\u202E` を先頭に加えると、後続の文字を右から左へ表示できます。

```javascript
const text = "Hello";
const reversed = "\u202E" + text + "\u202C";

console.log(reversed);
```

`\u202E` はRight-to-Left Override（RLO）、`\u202C` は方向制御を終了するための文字です。画面上では反転したように見えますが、保存されている文字の順序はまったく変わっていません。

もちろん、これを「達人の解法」と呼ぶのは冗談です。面白いUnicodeの黒魔術ではありますが、本当の文字列反転ではありません。方向制御文字は、読み取り、検索、コピー＆ペースト、さらにはセキュリティ上の混乱を招く可能性があるため、実際の機能で `for` や `reverse()` の代わりに使うべきではありません。

一般的な文字列なら、読みやすい `reverse()` の方法で十分です。複雑なUnicode文字を扱う場合は、文字境界を正しく認識する実装を選びましょう。`\u202E` は、面接のネタや黒魔術のデモだけに残しておくほうが安全です。
