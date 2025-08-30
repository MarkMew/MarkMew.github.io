---
layout: post
title: 如何重置 Gitlab CI_PIPELINE_IID
author: Mark_Mew
category: Jenkins | CICD
date: 2025-8-27
---

官方並不建議

同時也沒有提供可以 reset ci_pipeline_iid 的方法

去 reset 這個值

如果真的需要 reset

是需要砍掉 project 再重建

此時 pipeline iid 才會重置

不過這種破壞式方式估計大部分的人不採用

因此如果需要有一個唯一的 id 值就需要自己建立規則

使用 gitlab-ci.yml 的一些機制

我們可以達到此效果

以下為範例程式碼


```yaml
stages:
  - prepare
  - build

variables:
  COUNTER_FILE: counter.txt

# 準備階段：讀取或建立流水號
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

# 你的 build job 可以直接用 PIPELINE_COUNTER
build_job:
  stage: build
  dependencies:
    - prepare_counter
  script:
    - echo "This is build number: $PIPELINE_COUNTER"

```

在 GitLab CI 裡

cache 是用來在不同 pipeline/job 之間共享檔案。

只要你不清除或變更 cache key，counter.txt 就會一直保留並被後續 pipeline 繼續使用。

在範例裡面

```yaml
cache:
  key: project-counter
  paths:
    - $COUNTER_FILE
```

所有 pipeline 都會用同一個 cache key (project-counter)。

所以同一個專案的 pipeline 會共享同一份 counter.txt

pipeline 跑完後

GitLab Runner 會把更新後的 counter.txt 存回 cache

下次 pipeline 再取出來

> 注意事項：
> 1. cache 不是保證永遠存在
>    - GitLab 會視 runner / 儲存狀況，有可能清掉舊 cache（尤其 self-hosted runner 的磁碟清理時）。
>    - 如果 cache 被清掉，下次 pipeline 會「找不到 counter.txt → 從 1 開始」。
> 2. 多個 pipeline 併發時可能有 race condition
>    - 假設你同時跑兩個 pipeline，它們可能同時拿到同一份舊 cache，結果算出一樣的流水號。
>    - 如果你的需求一定要「唯一且不重複」，可能需要改用 外部儲存（像資料庫、Git tag、Artifacts API）。
---
參考文件：
1. [change CI_PIPELINE_IID manually
](https://gitlab.com/gitlab-org/gitlab/-/issues/25283)
2. [Add ability to setup CI_PIPELINE_IID value for next pipelines.
](https://gitlab.com/gitlab-org/gitlab/-/issues/22949)
3. [Using CI_PIPELINE_IID variable, how can I navigate back to the corresponding commit in GitLab CI?](https://stackoverflow.com/questions/76306927/using-ci-pipeline-iid-variable-how-can-i-navigate-back-to-the-corresponding-com)