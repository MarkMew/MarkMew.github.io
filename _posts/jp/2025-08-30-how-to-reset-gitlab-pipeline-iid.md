---
layout: post
title: GitLab CI_PIPELINE_IID のリセットは可能？現実的な対応方法
author: Mark_Mew
category: [CICD, Gitlab]
tags: [CICD, Gitlab]
date: 2025-8-30
---

公式には推奨されておらず、

`ci_pipeline_iid` をリセットする方法も提供されていません。

この値を本当にリセットしたい場合は、

プロジェクトを削除して再作成する必要があります。

そのときに初めて pipeline IID がリセットされます。

ただし、この破壊的な方法を採用するケースは多くありません。

そのため、ユニークな ID が必要なら

自分でルールを作る必要があります。

`gitlab-ci.yml` の仕組みを使えば、

同等の効果を実現できます。

以下はサンプルコードです。

```yaml
stages:
  - prepare
  - build

variables:
  COUNTER_FILE: counter.txt

# 準備ステージ：カウンターを読み込む or 初期化
prepare_counter:
  stage: prepare
  script:
    - |
      if [ -f $COUNTER_FILE ]; then
        echo "Found counter file."
        COUNTER=$(cat $COUNTER_FILE)
        COUNTER=$((COUNTER + 1))
      else
        echo "No counter file found, start from 1."
        COUNTER=1
      fi
      echo $COUNTER > $COUNTER_FILE
      echo "PIPELINE_COUNTER=$COUNTER" >> variables.env
  artifacts:
    reports:
      dotenv: variables.env
  cache:
    key: project-counter
    paths:
      - $COUNTER_FILE

# build job では PIPELINE_COUNTER を直接利用可能
build_job:
  stage: build
  dependencies:
    - prepare_counter
  script:
    - echo "This is build number: $PIPELINE_COUNTER"

```

GitLab CI では、

`cache` は異なる pipeline/job 間でファイルを共有するために使われます。

cache key を削除・変更しない限り、`counter.txt` は保持され、後続 pipeline でも使われます。

この例では：

```yaml
cache:
  key: project-counter
  paths:
    - $COUNTER_FILE
```

すべての pipeline が同じ cache key（`project-counter`）を使います。

そのため同一プロジェクト内の pipeline は同じ `counter.txt` を共有します。

pipeline 実行後、

GitLab Runner は更新済みの `counter.txt` を cache に保存します。

次の pipeline はそれを再利用します。

> 注意事項：
> 1. cache は永続を保証しません。
>    - runner / ストレージの状況に応じて、GitLab が古い cache を削除することがあります（特に self-hosted runner のディスククリーン時）。
>    - cache が消えた場合、次の pipeline は「counter.txt が見つからない -> 1 から開始」となります。
> 2. pipeline 同時実行時は race condition が起きる可能性があります。
>    - 2 つの pipeline が同時に走ると、同じ古い cache を読み、同じ連番を計算してしまうことがあります。
>    - 要件が「必ず一意で重複なし」であれば、外部ストレージ（DB、Git tag、Artifacts API など）を検討してください。



---

参考資料：
1. [change CI_PIPELINE_IID manually
](https://gitlab.com/gitlab-org/gitlab/-/issues/25283)
2. [Add ability to setup CI_PIPELINE_IID value for next pipelines.
](https://gitlab.com/gitlab-org/gitlab/-/issues/22949)
3. [Using CI_PIPELINE_IID variable, how can I navigate back to the corresponding commit in GitLab CI?](https://stackoverflow.com/questions/76306927/using-ci-pipeline-iid-variable-how-can-i-navigate-back-to-the-corresponding-com)
