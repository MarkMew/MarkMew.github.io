---
layout: post
title: Jenkins のビルド番号をリセットする方法
author: Mark_Mew
category: [CICD, Jenkins]
tags: [CICD, Jenkins]
date: 2025-8-26
---

これまで Pipeline のビルドを運用するとき、

バージョン番号を `0.0.{buildNumber}` のような 3 桁構成にすることがよくありました。

最後の桁には Jenkins の build number を使います。

ただし、

中間バージョンやメジャーバージョンを上げると、

末尾の小さい番号が少し扱いづらくなります。

Jenkins には build number をリセットする方法があります。

まず Jenkins にログインし、

設定から Script Console ページを開きます。

以下のコードを入力して実行してください。

`your-job-name-here` は対象の Pipeline 名に置き換えてください。

```java
item = Jenkins.instance.getItemByFullName("your-job-name-here")
//THIS WILL REMOVE ALL BUILD HISTORY
item.builds.each() { build ->
  build.delete()
}
item.updateNextBuildNumber(1)
```

実行後、pipeline は新規作成直後のような状態になります。

バージョンを上げるタイミングで build number をリセットしたいとき、

~~あるいは新しい pipeline がエラーだらけで、都合よく隠したくなったとき~~

このコードはシンプルで使いやすいです。



---

参考資料

[How to reset build number in jenkins?](https://stackoverflow.com/questions/20901791/how-to-reset-build-number-in-jenkins)
