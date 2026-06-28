---
layout: post
title: '別再把連結當按鈕：a、button、input type="button" 到底怎麼選？'
description: 'a、button、input type="button" 外觀都能做成按鈕，但語意、鍵盤操作、表單行為與可容納內容不同。本文用範例說明何時該選哪一個 HTML 元素。'
author: Mark_Mew
categories: [HTML]
tags: [html, button, accessibility]
keywords: [HTML, a, button, input, accessibility, semantic HTML]
date: 2026-06-28
---

身為網頁開發者，對 `a`、`button`、`input` 這三種 HTML 元素應該都不陌生。透過 CSS，它們都能做出相似的按鈕外觀，但外表相同，不代表用途也相同。

它們的差異不只在能不能放圖片，還包括內容來源、預設行為、HTML 語意、CSS 彈性，以及 Accessibility（無障礙）。

先記住最重要的判斷原則：

> **前往另一個位置用 `a`，執行一個動作用 `button`。**

至於 `input type="button"`，它同樣可以執行動作，但內容與樣式彈性較低。大多數新程式若沒有特殊限制，通常優先使用 `button`。

## 快速比較

| 元素 | 主要語意 | 內容來源 | 預設行為 | 可放 HTML 子元素 |
| --- | --- | --- | --- | --- |
| `a` | 前往另一個 URL 或文件位置 | 開始與結束標籤之間的內容 | 導航至 `href` | 可以，但不能包含其他互動元素 |
| `button` | 執行操作 | 開始與結束標籤之間的內容 | 在表單內可能送出表單 | 可以放文字、圖片、SVG、`span` 等 phrasing content |
| `input type="button"` | 執行操作 | `value` 屬性 | 沒有預設動作 | 不行，它是 Void Element |

## 差異一：可以包含的 HTML 內容不同

原本最直覺的差異是：`button` 可以使用 HTML 內容組成按鈕，而 `input type="button"` 只能顯示純文字標籤。

```html
<button type="button">
  <img src="save.svg" alt="">
  <span>儲存</span>
</button>
```

`button` 裡可以放入文字、圖片、`span`、`strong` 或 SVG，因此很適合製作圖示按鈕或包含多種樣式的按鈕。

不過，嚴格來說不能說 `button` 可以包含「任何 HTML」。它的內容主要是 phrasing content，而且不能巢狀放入 `a`、另一個 `button`、`input` 等互動元素。

```html
<!-- 錯誤：button 裡不能再放互動元素 -->
<button type="button">
  儲存
  <a href="/help">說明</a>
</button>
```

`input` 則是 Void Element，不能有結束標籤，也不能包含任何子元素：

```html
<input type="button" value="儲存">
```

下面這種寫法不符合 HTML 規範：

```html
<!-- 錯誤：input 不能包含子元素 -->
<input type="button">
  <img src="save.svg" alt="">
  儲存
</input>
```

容易被忽略的是，`a` 也不只可以放文字。它同樣能包含圖片、`span`、`strong`、SVG，甚至能做成一整張可點擊的卡片：

```html
<a href="/settings" class="link-card">
  <img src="settings.svg" alt="">
  <span>
    <strong>系統設定</strong>
    <small>管理帳號與通知</small>
  </span>
</a>
```

`a` 使用 transparent content model，實際能放哪些內容也取決於它所在的上下文。不過，它不能包含另一個 `a`、`button`、`input` 等互動元素，也不能在子元素上指定 `tabindex`。

## 差異二：顯示內容的來源不同

`a` 與 `button` 顯示的內容，都來自開始標籤與結束標籤之間的 DOM 內容：

```html
<a href="/settings">系統設定</a>
<button type="button">儲存</button>
```

除了純文字，也可以由多個子元素組成：

```html
<button type="button">
  <svg aria-hidden="true"><!-- icon --></svg>
  <span>儲存變更</span>
</button>
```

相較之下，`input type="button"` 的顯示文字來自 `value` 屬性：

```html
<input type="button" value="儲存變更">
```

使用 JavaScript 更新文字時，操作方式也不相同：

```javascript
document.querySelector("button").textContent = "處理中";
document.querySelector('input[type="button"]').value = "處理中";
```

這也是 `button` 比較容易擴充的原因：它的內容是 DOM，可以分別調整圖示、文字、Loading 狀態或其他視覺元素；`input` 則只有一個文字形式的 `value`。

## 差異三：預設行為不同

三種元素被點擊時，瀏覽器提供的預設行為並不相同。

### a 的預設行為是導航

具有 `href` 的 `a` 是超連結，點擊後會前往另一個頁面、網站、檔案或同頁錨點：

```html
<a href="/settings">前往設定頁</a>
<a href="#comments">查看留言</a>
<a href="/report.pdf" download>下載報表</a>
```

### button 在表單內可能送出表單

`button` 在表單裡若沒有指定 `type`，通常會成為 Submit Button。原本只想開啟視窗或預覽內容的按鈕，可能因此意外送出表單。

```html
<form>
  <!-- 一般操作，不送出表單 -->
  <button type="button">預覽</button>

  <!-- 送出表單 -->
  <button type="submit">儲存</button>

  <!-- 重設表單，實務上較少使用 -->
  <button type="reset">重設</button>
</form>
```

即使按鈕目前不在表單裡，明確寫出 `type="button"` 也能避免未來調整 DOM 結構時產生意外。

### input type="button" 沒有預設動作

`input type="button"` 本身不會導航，也不會送出表單，通常需要搭配 JavaScript 才會產生效果。

```html
<input type="button" value="開啟視窗" onclick="openDialog()">
```

不要把它與 `input type="submit"` 混為一談：

```html
<!-- 一般按鈕，沒有預設動作 -->
<input type="button" value="預覽">

<!-- 送出表單 -->
<input type="submit" value="儲存">
```

## 差異四：HTML 語意不同

這三種元素最大的差異不是外觀，而是它們想向瀏覽器表達什麼。

### a 表示「前往某處」

如果點擊後會改變 URL、前往另一頁、跳到文件中的另一個位置或下載檔案，就應該使用帶有 `href` 的 `a`。

連結具有瀏覽器原生的導航能力，例如可以在新分頁開啟、複製連結網址，也能讓搜尋引擎理解頁面之間的關係。

不要使用沒有 `href` 的 `a` 假裝按鈕：

```html
<!-- 不建議 -->
<a onclick="openDialog()">開啟視窗</a>

<!-- 正確語意 -->
<button type="button" onclick="openDialog()">開啟視窗</button>
```

`href="#"` 也不是理想的替代方案，因為它仍代表導航，還可能改變 URL 或讓頁面跳回頂端。

### button 與 input type="button" 表示「執行動作」

開啟對話框、切換選單、加入購物車、儲存資料等行為，都屬於頁面上的操作，應該使用按鈕。

`button` 和 `input type="button"` 在語意上都能代表按鈕，但 `button` 可以容納更豐富的內容，因此在新的程式中通常更實用。`input type="button"` 仍適合既有系統、由工具產生的表單，或只需要純文字控制項的簡單場景。

反過來說，也不建議用 `button` 搭配 JavaScript 模擬頁面導航。這會失去開新分頁、複製連結等原生功能。

一句話總結：

> **Link goes somewhere. Button does something.**

## 差異五：CSS 與版面彈性不同

CSS 可以把三者做成幾乎完全相同的外觀，但它們的瀏覽器預設樣式與可調整內容仍不相同。

`a` 預設通常顯示為行內文字連結；`button` 和 `input` 則帶有作業系統或瀏覽器提供的表單控制項樣式。實務上通常會先統一字型、邊框、背景與間距：

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
<a class="button" href="/settings">前往設定</a>
<button class="button" type="button">儲存</button>
<input class="button" type="button" value="預覽">
```

真正的差異出現在內部排版：`a` 和 `button` 都能為圖示與文字建立子元素，再利用 Flexbox、Grid 或個別 Class 調整；`input` 沒有子元素，只能調整控制項本身，無法直接替內部文字或圖示建立獨立版面。

因此，若設計需要圖示、Loading Spinner、兩行文字或其他複合內容，`button` 通常會比 `input type="button"` 更適合。

## 差異六：Accessibility 不同

正確使用原生 HTML 元素，瀏覽器就會提供相應的角色、焦點與鍵盤操作：

- 帶有 `href` 的 `a` 會被辨識為 Link，通常使用 Enter 啟用。
- `button` 與 `input type="button"` 會被辨識為 Button，通常可使用 Enter 或 Space 啟用。
- `button` 與 `input` 原生支援 `disabled`。
- `a` 沒有 `disabled` 屬性。

```html
<button type="button" disabled>處理中</button>
<input type="button" value="處理中" disabled>
```

即使在 `a` 上加上 `aria-disabled="true"`，也只是在 Accessibility Tree 中表達停用狀態，不會自動阻止導航或 Click Event。如果某個控制項本質上是可以停用的操作，通常代表它更適合使用 `button`。

### 圖示按鈕仍需要可理解的名稱

只有圖示、沒有可見文字的按鈕，應該提供清楚的 Accessible Name：

```html
<button type="button" aria-label="關閉視窗">
  <svg aria-hidden="true"><!-- close icon --></svg>
</button>
```

如果圖示旁已經有能說明用途的文字，裝飾性圖片可以使用空白的 `alt`，避免螢幕閱讀器重複朗讀：

```html
<button type="button">
  <img src="save.svg" alt="">
  儲存
</button>
```

也不要用 `div` 或 `span` 模擬按鈕，否則必須自行補上焦點、鍵盤事件與 ARIA 語意，而且很容易遺漏。

```html
<!-- 不建議 -->
<div class="button" onclick="save()">儲存</div>

<!-- 建議 -->
<button type="button" onclick="save()">儲存</button>
```

能使用原生 HTML 元素時，就不需要重新發明一顆比較難用的按鈕。

## 到底該選哪一個？

最後，可以用下面的流程快速判斷：

1. 點擊後會改變目前 URL、前往另一頁或下載資源嗎？使用 `a href="..."`。
2. 點擊後會執行目前頁面上的操作嗎？使用 `button`。
3. 這個按鈕會送出表單嗎？使用 `button type="submit"`。
4. 只是一般操作，不應送出表單嗎？使用 `button type="button"`。
5. 受限於舊系統或只需要純文字表單控制項嗎？才考慮 `input type="button"`。

先選擇正確的 HTML 語意，再用 CSS 決定外觀。這樣不只程式更容易維護，也能讓鍵盤、輔助科技與搜尋引擎正確理解頁面的功能。

## 參考資料

- [HTML Living Standard：The `a` element](https://html.spec.whatwg.org/multipage/text-level-semantics.html#the-a-element)
- [HTML Living Standard：The `button` element](https://html.spec.whatwg.org/multipage/form-elements.html#the-button-element)
- [HTML Living Standard：The `input` element](https://html.spec.whatwg.org/multipage/input.html#the-input-element)
