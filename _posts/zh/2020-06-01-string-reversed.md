---
layout: post
title: "字串反轉的三種境界：Junior 寫 for、初階用 reverse、專家用 \\u202E？"
description: "比較 JavaScript 字串反轉的三種做法：自己寫 for 迴圈、使用 reverse，以及利用 Unicode \\u202E 改變文字方向的黑魔法。"
author: Mark_Mew
category: 黑魔法
date: 2020-6-1
---

上週在前端社群看到一篇很有趣的[貼文](https://www.facebook.com/groups/f2e.tw/permalink/2913375802033099/)，討論如何把一段字串反轉。

引起討論的貼文如下圖所示

![Alt 字串反轉](/assets/img/100869303_112730000452747_3790033580424429568_n.jpg)

同一個需求，隨著寫法不同，竟然可以看出三種截然不同的境界。

## Junior：自己寫 for 迴圈

剛開始學程式時，最直覺的方式是從字串的最後一個字元開始，利用 `for` 迴圈倒著走，再把每個字元依序組成新的字串。

```javascript
const text = "Hello";
let reversed = "";

for (let i = text.length - 1; i >= 0; i--) {
  reversed += text[i];
}

console.log(reversed); // olleH
```

這種寫法很好理解，也能幫助我們練習索引與迴圈。缺點是程式碼稍長，而且一不小心就可能把起始位置或終止條件寫錯。

## 初階：使用 reverse

熟悉 JavaScript 內建方法後，可以先把字串展開成陣列，呼叫 `reverse()`，最後再用 `join()` 組回字串。

```javascript
const text = "Hello";
const reversed = [...text].reverse().join("");

console.log(reversed); // olleH
```

程式碼短了不少，意圖也很清楚。不過，遇到由多個 Unicode 碼位組成的 Emoji 或組合字元時，真正嚴謹的實作仍需要使用能辨識 grapheme cluster 的方式處理。

## 專家：一個 `\u202E` 解決？

貼文裡的做法完全不同。只要在文字前方加入 Unicode 方向控制字元 `\u202E`，就能讓後續文字由右向左顯示：

```javascript
const text = "Hello";
const reversed = "\u202E" + text + "\u202C";

console.log(reversed);
```

`\u202E` 稱為 Right-to-Left Override（RLO），而 `\u202C` 用來結束這段方向控制。畫面上看起來像是字串反轉了，實際儲存的字元順序卻完全沒有改變。

所以把它叫做「專家解法」其實是一個玩笑。它是很有趣的 Unicode 黑魔法，卻不是真正的字串反轉，也可能造成閱讀、搜尋、複製貼上甚至安全上的混淆，不適合在正式功能中取代 `for` 或 `reverse()`。

如果只是一般字串，選擇可讀性較高的 `reverse()` 就夠了；需要處理複雜 Unicode 字元時，則應使用真正理解文字邊界的實作。至於 `\u202E`，留在面試梗圖和黑魔法展示裡會比較安全。

