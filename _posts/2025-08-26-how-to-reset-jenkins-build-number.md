---
layout: post
title: 如何重置 Jenkins 建置編號
author: Mark_Mew
category: Jenkins | CICD
date: 2025-8-26
---

以往在做 Pipeline 建置時

都會特別將建置編號分為三碼 0.0.{buildNumber}

最後一碼則是使用建置編號當作最末碼

不過當中間號或是大版號提升後

最末碼的小版號就顯得有點尷尬

Jenkins 提供一個方式可以重置建置編號

首先需要登入 Jenkins

並在設定中找到 script console 的頁面

輸入以下程式碼並執行

記得要將 `your-job-name-here` 替換成流水線的名稱

```java
item = Jenkins.instance.getItemByFullName("your-job-name-here")
//THIS WILL REMOVE ALL BUILD HISTORY
item.builds.each() { build ->
  build.delete()
}
item.updateNextBuildNumber(1)
```

執行完成後會發現 pipeline 就跟新的一樣

當你提升版本號因此想要重置 build number 時

~~或是覺得新的流水線滿滿的錯誤很討厭，想要欲蓋彌彰時~~

都是一個簡單好用程式碼



---

參考資料

[How to reset build number in jenkins?](https://stackoverflow.com/questions/20901791/how-to-reset-build-number-in-jenkins)