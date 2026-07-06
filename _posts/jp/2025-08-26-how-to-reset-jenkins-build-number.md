---
layout: post
title: "Jenkinsのビルド番号をリセットする方法：Build Historyの削除とNext Build Numberの設定"
description: "Jenkins Script Consoleから対象JobのBuild Historyを削除し、次のビルド番号をリセットする方法と、実行前に確認すべきリスクや制約を説明します。"
author: Mark_Mew
category: [CICD, Jenkins]
tags: [CICD, Jenkins]
date: 2025-8-26
lang: ja
---

Jenkins Pipelineでは、ビルド番号をアプリケーションのバージョン文字列に含めることがあります。たとえば、次のような形式です。

```text
0.0.${BUILD_NUMBER}
```

最後の部分にはJenkinsの `BUILD_NUMBER` をそのまま使用します。major versionやminor versionを上げた後、patch numberを再び1から始めたい場合に、Jenkinsのビルド番号をリセットする必要が生じます。

ただし、Jenkinsのビルド番号は本来、単調に増加する識別子です。リセットは通常のリリース操作ではありません。次の番号を1へ戻すには、そのJobに残っている既存のビルド履歴を先に削除する必要があります。これは破壊的な管理操作であり、単なる表示上の整理として実行すべきではありません。

## 実行前に確認すること

この記事では、Jenkins Script ConsoleからGroovyスクリプトを実行します。Script ConsoleはJenkins controllerを完全に操作できる強い権限を持ち、`Overall/Administer` 権限を持つ管理者だけが利用できます。

実行前に、以下を確認してください。

- Jobに実行中またはキューで待機中のビルドがないこと。
- 必要なConsole Log、Artifact、テストレポート、監査記録をバックアップしていること。
- 外部システムが既存のJenkins Build URLやBuild Numberを参照し続けていないこと。
- 特にFolderやMultibranch Pipeline内のJobでは、完全なJob名を確認していること。
- 可能であれば非本番環境でスクリプトを試し、Jenkinsの設定をバックアップしていること。

Build Historyを削除すると、以前のビルドページ、記録、Buildディレクトリ内のArtifactは復元できない可能性があります。古い記録を整理するだけであれば、番号をリセットするのではなく、Build Discarderの設定を優先してください。

## Script Consoleから番号をリセットする

管理者権限を持つアカウントでJenkinsへログインし、次の画面を開きます。

```text
Manage Jenkins → Script Console
```

以下は、私が当時実際に実行したGroovyスクリプトです。実行前に `your-job-name-here` を対象Pipelineの名前へ置き換えてください。

```groovy
item = Jenkins.instance.getItemByFullName("your-job-name-here")
// THIS WILL REMOVE ALL BUILD HISTORY
item.builds.each() { build ->
  build.delete()
}
item.updateNextBuildNumber(1)
```

このスクリプトは指定したPipelineを取得し、すべてのBuild Historyを順に削除して、次のビルド番号を1に設定します。Job名が正しいかどうかを追加で検証せず、削除前の確認も求めないため、実行者自身が対象とバックアップ状況を確認する必要があります。

## 実行結果を確認する

実行後にJobページへ戻り、以前のBuild Historyが消えていることを確認します。Pipelineを再度実行すると、新しいビルド番号は `#1` から始まります。Pipelineが `${BUILD_NUMBER}` を使ってバージョン文字列を作成している場合は、既存のArtifact、Container Image、公開済みパッケージと同じバージョンにならないことも確認してください。

## 本当にリセットが必要か

外部システムがビルド番号を一意な識別子として使用している場合、`#1` を再利用すると追跡や監査が曖昧になる可能性があります。より安定した設計は、Jenkins Build Numberを増加させ続け、アプリケーションのバージョンとビルド識別子を分けることです。

```text
Application version: 2.0.0
Build metadata:      Jenkins #183
```

履歴を安全に削除でき、外部システムが以前の番号に依存していない場合に限り、リセットを検討してください。次の番号を大きくしたいだけなら、Next Build Number Pluginも選択肢になります。Jenkinsでは、大きな番号のビルド履歴を残したまま次の番号を小さくすることはできません。

---

## 参考資料

- [Jenkins Script Console](https://www.jenkins.io/doc/book/managing/script-console/)
- [Jenkins Job API：updateNextBuildNumber](https://javadoc.jenkins.io/hudson/model/Job.html)
- [How to reset build number in Jenkins?](https://stackoverflow.com/questions/20901791/how-to-reset-build-number-in-jenkins)
