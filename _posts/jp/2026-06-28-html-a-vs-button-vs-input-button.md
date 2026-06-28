---
layout: post
title: 'リンクをボタン代わりにしない：a・button・input type="button" の正しい使い分け'
description: 'a、button、input type="button" は同じようなボタンの見た目にできますが、セマンティクス、キーボード操作、フォームの挙動、スタイルの自由度、アクセシビリティが異なります。各 HTML 要素の正しい使い分けをサンプルコード付きで解説します。'
author: Mark_Mew
categories: [HTML]
tags: [html, button, accessibility]
keywords: [HTML, a, button, input, accessibility, semantic HTML]
lang: ja
date: 2026-06-28
---

Web 開発者であれば、`a`、`button`、`input` という 3 つの HTML 要素にはなじみがあるはずです。CSS を使えば、どれも同じようなボタンの見た目にできます。しかし、見た目が同じだからといって、役割まで同じとは限りません。

違いは画像を入れられるかどうかだけではありません。表示内容の取得元、デフォルトの挙動、HTML セマンティクス、CSS の柔軟性、Accessibility（アクセシビリティ）にも違いがあります。

まず、最も重要な判断基準を覚えておきます。

> **別の場所へ移動するなら `a`、何らかの操作を実行するなら `button` を使う。**

`input type="button"` も操作を実行できますが、内容やスタイルの自由度は低くなります。特別な制約がない新しいコードでは、通常は `button` を優先するほうが扱いやすいでしょう。

## 早見表

| 要素 | 主なセマンティクス | 内容の取得元 | デフォルトの挙動 | HTML 子要素を含められるか |
| --- | --- | --- | --- | --- |
| `a` | 別の URL や文書内の位置へ移動する | 開始タグと終了タグの間の内容 | `href` へ移動する | 可能。ただし、ほかのインタラクティブ要素は含められない |
| `button` | 操作を実行する | 開始タグと終了タグの間の内容 | フォーム内では送信する場合がある | テキスト、画像、SVG、`span` などの phrasing content を含められる |
| `input type="button"` | 操作を実行する | `value` 属性 | デフォルトの動作はない | 不可。Void Element であるため |

## 違い 1：含められる HTML コンテンツ

最も分かりやすい違いは、`button` では HTML コンテンツを使ってボタンを構成できるのに対し、`input type="button"` ではプレーンテキストのラベルしか表示できないことです。

```html
<button type="button">
  <img src="save.svg" alt="">
  <span>保存</span>
</button>
```

`button` には、テキスト、画像、`span`、`strong`、SVG などを入れられます。そのため、アイコン付きボタンや複数のスタイルを組み合わせたボタンに向いています。

ただし、厳密には `button` に「どんな HTML でも」入れられるわけではありません。主に phrasing content を含められますが、`a`、別の `button`、`input` などのインタラクティブ要素をネストすることはできません。

```html
<!-- 誤り：button の中にインタラクティブ要素を入れない -->
<button type="button">
  保存
  <a href="/help">ヘルプ</a>
</button>
```

一方、`input` は Void Element です。終了タグを持たず、子要素を含めることもできません。

```html
<input type="button" value="保存">
```

次のマークアップは HTML 仕様に準拠していません。

```html
<!-- 誤り：input は子要素を持てない -->
<input type="button">
  <img src="save.svg" alt="">
  保存
</input>
```

見落とされがちですが、`a` もテキストだけに限定されているわけではありません。画像、`span`、`strong`、SVG を含めたり、カード全体をクリックできる構造にしたりできます。

```html
<a href="/settings" class="link-card">
  <img src="settings.svg" alt="">
  <span>
    <strong>システム設定</strong>
    <small>アカウントと通知を管理する</small>
  </span>
</a>
```

`a` は transparent content model を使用しているため、実際に含められる内容は周囲のコンテキストにも依存します。ただし、別の `a` や、`button`、`input` などのインタラクティブ要素を含めることはできません。また、子孫要素に `tabindex` を指定することもできません。

## 違い 2：表示内容の取得元

`a` と `button` の表示内容は、開始タグと終了タグの間にある DOM の内容から取得されます。

```html
<a href="/settings">システム設定</a>
<button type="button">保存</button>
```

複数の子要素を組み合わせてラベルを作ることもできます。

```html
<button type="button">
  <svg aria-hidden="true"><!-- icon --></svg>
  <span>変更を保存</span>
</button>
```

これに対して、`input type="button"` に表示される文字列は `value` 属性から取得されます。

```html
<input type="button" value="変更を保存">
```

JavaScript でラベルを書き換える方法も異なります。

```javascript
document.querySelector("button").textContent = "処理中";
document.querySelector('input[type="button"]').value = "処理中";
```

これが `button` を拡張しやすい理由の 1 つです。ラベルが DOM で構成されているため、アイコン、テキスト、Loading 状態などの見た目を個別に変更できます。`input` が持てるのは、テキスト形式の `value` だけです。

## 違い 3：デフォルトの挙動

これらの要素が操作されたとき、ブラウザが提供するデフォルトの挙動はそれぞれ異なります。

### a のデフォルト動作はページ移動

`href` を持つ `a` はハイパーリンクです。操作すると、別のページ、Web サイト、ファイル、または同じ文書内の別の位置へ移動します。

```html
<a href="/settings">設定ページへ移動</a>
<a href="#comments">コメントを見る</a>
<a href="/report.pdf" download>レポートをダウンロード</a>
```

### button はフォームを送信する場合がある

フォーム内にある `button` で `type` を省略すると、通常は Submit Button になります。ダイアログを開く、またはプレビューを表示するだけのつもりだったボタンが、意図せずフォームを送信する可能性があります。

```html
<form>
  <!-- 通常の操作。フォームは送信しない -->
  <button type="button">プレビュー</button>

  <!-- フォームを送信する -->
  <button type="submit">保存</button>

  <!-- フォームをリセットする。実務ではあまり使わない -->
  <button type="reset">リセット</button>
</form>
```

現在はフォームの外にあるボタンでも、`type="button"` を明示しておけば、将来 DOM 構造が変わったときの意図しない動作を防げます。

### input type="button" にはデフォルトの動作がない

`input type="button"` は、それだけではページ移動もフォーム送信も行いません。通常は JavaScript と組み合わせて動作させます。

```html
<input type="button" value="ダイアログを開く" onclick="openDialog()">
```

`input type="submit"` と混同しないように注意します。

```html
<!-- 通常のボタン。デフォルトの動作はない -->
<input type="button" value="プレビュー">

<!-- フォームを送信する -->
<input type="submit" value="保存">
```

## 違い 4：HTML セマンティクス

これら 3 つの要素で最も重要な違いは、見た目ではなく、ブラウザに何を伝えるかです。

### a は「別の場所へ移動する」ことを表す

操作した結果として URL が変わる、別のページを開く、文書内の別の位置へ移動する、またはファイルをダウンロードする場合は、`href` を持つ `a` を使います。

リンクには、別のタブで開く、URL をコピーするといったブラウザ本来の機能があります。また、検索エンジンもページ同士の関係を理解できます。

`href` のない `a` をボタン代わりに使わないようにします。

```html
<!-- 非推奨 -->
<a onclick="openDialog()">ダイアログを開く</a>

<!-- 正しいセマンティクス -->
<button type="button" onclick="openDialog()">ダイアログを開く</button>
```

`href="#"` も適切な代替手段ではありません。これは依然としてページ移動を表し、URL が変わったり、ページ上部へ移動したりする可能性があります。

### button と input type="button" は「操作を実行する」ことを表す

ダイアログを開く、メニューを切り替える、商品をカートへ追加する、データを保存するといった処理は、現在のページ上で行う操作です。そのため、ボタンを使用します。

`button` と `input type="button"` は、どちらもセマンティクス上はボタンを表せます。ただし、`button` のほうが豊富な内容を持てるため、新しいコードでは通常こちらが実用的です。`input type="button"` は、既存システム、ツールが生成するフォーム、純粋なテキストラベルだけで十分な単純な場面では引き続き利用できます。

逆に、`button` と JavaScript を使ってページ移動を再現する方法も推奨できません。別タブで開く、URL をコピーするといったリンク本来の機能が失われるためです。

一言でまとめると、次のとおりです。

> **Link goes somewhere. Button does something.**

## 違い 5：CSS とレイアウトの柔軟性

CSS を使えば 3 つの要素をほぼ同じ見た目にできますが、ブラウザのデフォルトスタイルと内部レイアウトの柔軟性は異なります。

`a` は通常、インラインのテキストリンクとして表示されます。`button` と `input` には、ブラウザや OS が提供するフォームコントロールのスタイルが適用されます。実務では、まずフォント、枠線、背景、余白などを共通スタイルでそろえることがよくあります。

```css
.button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: 0.5rem;
  padding: 0.5rem 1rem;
  border: 1px solid transparent;
  border-radius: 0.375rem;
  font: inherit;
  color: inherit;
  text-decoration: none;
  cursor: pointer;
}
```

```html
<a class="button" href="/settings">設定ページへ移動</a>
<button class="button" type="button">保存</button>
<input class="button" type="button" value="プレビュー">
```

本当の違いは内部レイアウトに現れます。`a` と `button` では、アイコンとテキストを別々の子要素として配置し、Flexbox、Grid、個別の Class で調整できます。`input` には子要素がないため、コントロール自体しかスタイルできず、内部のテキストやアイコンを個別にレイアウトすることはできません。

アイコン、Loading Spinner、2 行のテキストなど、複数の要素を組み合わせたデザインでは、通常 `input type="button"` より `button` のほうが適しています。

## 違い 6：Accessibility

ネイティブ HTML 要素を正しく使用すれば、ブラウザが適切な Role、フォーカス、キーボード操作を提供します。

- `href` を持つ `a` は Link として認識され、通常は Enter で操作できます。
- `button` と `input type="button"` は Button として認識され、通常は Enter または Space で操作できます。
- `button` と `input` は、ネイティブの `disabled` 属性に対応しています。
- `a` には `disabled` 属性がありません。

```html
<button type="button" disabled>処理中</button>
<input type="button" value="処理中" disabled>
```

`a` に `aria-disabled="true"` を追加しても、Accessibility Tree に無効状態を伝えるだけです。ページ移動や Click Event が自動的に無効になるわけではありません。コントロールの本質が「無効にできる操作」であれば、最初から `button` を使うほうが適切な場合が多いでしょう。

### アイコンボタンにも分かりやすい名前が必要

表示テキストのないアイコンだけのボタンには、明確な Accessible Name を付けます。

```html
<button type="button" aria-label="ダイアログを閉じる">
  <svg aria-hidden="true"><!-- close icon --></svg>
</button>
```

アイコンの隣に用途を説明するテキストがすでにある場合、装飾用の画像には空の `alt` を設定できます。これにより、スクリーンリーダーが同じ情報を重複して読み上げることを防げます。

```html
<button type="button">
  <img src="save.svg" alt="">
  保存
</button>
```

`div` や `span` でボタンを再現することも避けます。その場合、フォーカス、キーボードイベント、ARIA セマンティクスをすべて自分で実装しなければならず、必要な挙動を見落としやすいためです。

```html
<!-- 非推奨 -->
<div class="button" onclick="save()">保存</div>

<!-- 推奨 -->
<button type="button" onclick="save()">保存</button>
```

ネイティブ HTML 要素で解決できるなら、わざわざ使いにくいボタンを作り直す必要はありません。

## どれを選べばよいのか？

最後に、次の手順で判断できます。

1. 操作後に現在の URL が変わる、別のページへ移動する、またはリソースをダウンロードするか？ `a href="..."` を使用します。
2. 現在のページ上で何らかの操作を実行するか？ `button` を使用します。
3. フォームを送信するボタンか？ `button type="submit"` を使用します。
4. フォームを送信しない通常の操作か？ `button type="button"` を使用します。
5. 既存システムの制約がある、またはプレーンテキストのフォームコントロールだけで十分か？ その場合にのみ `input type="button"` を検討します。

まず正しい HTML セマンティクスを選び、その後 CSS で見た目を整えます。そうすることでコードを保守しやすくなり、キーボード、支援技術、検索エンジンもページの機能を正しく理解できるようになります。

## 参考資料

- [HTML Living Standard：The `a` element](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-a-element)
- [HTML Living Standard：The `button` element](https://html.spec.whatwg.org/multipage/form-elements.html#the-button-element)
- [HTML Living Standard：The `input` element](https://html.spec.whatwg.org/multipage/input.html#the-input-element)
