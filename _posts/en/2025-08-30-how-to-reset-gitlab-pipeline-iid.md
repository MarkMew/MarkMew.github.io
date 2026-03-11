---
layout: post
title: "GitLab CI_PIPELINE_IID Reset: What You Can (and Can’t) Do"
author: Mark_Mew
category: [CICD, Gitlab]
tags: [CICD, Gitlab]
date: 2025-8-30
---

GitLab does not recommend this,

and it also does not provide a direct way to reset `ci_pipeline_iid`.

If you really need to reset it,

you have to delete and recreate the project.

Only then will the pipeline IID be reset.

However, this destructive approach is not practical for most teams.

So if you need a unique incremental ID,

you usually need to define your own rule.

Using some mechanisms in `gitlab-ci.yml`,

we can achieve a similar effect.

Here is an example:

```yaml
stages:
  - prepare
  - build

variables:
  COUNTER_FILE: counter.txt

# Preparation stage: read or initialize the counter
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

# Your build job can directly use PIPELINE_COUNTER
build_job:
  stage: build
  dependencies:
    - prepare_counter
  script:
    - echo "This is build number: $PIPELINE_COUNTER"

```

In GitLab CI,

`cache` is used to share files across different pipelines/jobs.

As long as you do not clear or change the cache key, `counter.txt` will remain and be reused by subsequent pipelines.

In the example:

```yaml
cache:
  key: project-counter
  paths:
    - $COUNTER_FILE
```

All pipelines use the same cache key (`project-counter`).

So pipelines in the same project share the same `counter.txt`.

After a pipeline finishes,

GitLab Runner stores the updated `counter.txt` back into cache.

The next pipeline then reads it again.

> Notes:
> 1. Cache is not guaranteed to exist forever.
>    - GitLab may clean old cache depending on runner/storage conditions (especially during disk cleanup on self-hosted runners).
>    - If cache is removed, the next pipeline will "not find counter.txt -> start from 1".
> 2. Concurrent pipelines may cause race conditions.
>    - If two pipelines run at the same time, they may read the same old cache and compute the same counter value.
>    - If your requirement is strictly "unique and non-duplicated," consider external storage (such as a database, Git tags, or the Artifacts API).



---

References:
1. [change CI_PIPELINE_IID manually
](https://gitlab.com/gitlab-org/gitlab/-/issues/25283)
2. [Add ability to setup CI_PIPELINE_IID value for next pipelines.
](https://gitlab.com/gitlab-org/gitlab/-/issues/22949)
3. [Using CI_PIPELINE_IID variable, how can I navigate back to the corresponding commit in GitLab CI?](https://stackoverflow.com/questions/76306927/using-ci-pipeline-iid-variable-how-can-i-navigate-back-to-the-corresponding-com)
