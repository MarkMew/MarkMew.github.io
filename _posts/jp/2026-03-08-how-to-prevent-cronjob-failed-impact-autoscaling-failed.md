---
layout: post
title: EKS での cronjob 実行エラーによってワーカーノードの自動拡張が失敗するのを防ぐ方法
description: "EKS での cronjob 実行エラーによってワーカーノードの自動拡張が失敗するのを防ぐ方法. Practical notes and implementation steps."
author: Mark_Mew
category: K8S
tags: [EKS, K8S]
date: 2026-3-8
lang: ja
---

最近、EKSにサービスを提供しているとき

何かが起こりました。

cronjob の実行の多くが失敗するからです。

Worker Node を新しいデプロイメントを作成せずに自動的にスケーリングするようにします。

この問題の可能性には複数のレベルがあります。

1.ワーカーノード自動拡張戦略の解決
2.Cronjob の実行に失敗すると、ポッドが大量に再起動し、API Server と kube-scheduler のパフォーマンスに影響が及びます。

以下は問題を書くための cronjob です。
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup
  namespace: operating
spec:
  schedule: "*/10 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: database-backup-sa
          containers:
            - name: database-backup
              image: postgres:17-alpine
              imagePullPolicy: IfNotPresent
              command:
              - /bin/sh
              - -c
              - |
                export HOST=$(cat /mnt/secrets-store/db-host)
                export PORT=$(cat /mnt/secrets-store/db-port)
                export USERNAME=$(cat /mnt/secrets-store/db-user)
                export PASSWORD=$(cat /mnt/secrets-store/db-password)
                DATABASE="dummy-biz"
                apk add --no-cache aws-cli
                BACKUP_FILE="/tmp/database-backup_$(date +%Y%m%d_%H%M%S).sql"
                PGPASSWORD=$PASSWORD pg_dump -h $HOST -p $PORT -U $USERNAME -d $DATABASE -f $BACKUP_FILE
                aws s3 cp $BACKUP_FILE s3://database-backup/staging/
              resources:
                limits:
                  cpu: "100m"
                  memory: "512Mi"
                requests:
                  cpu: "50m"
                  memory: "64Mi"
              volumeMounts:
              - name: secrets-store
                mountPath: /mnt/secrets-store
                readOnly: true
          volumes:
          - name: secrets-store
            csi:
              driver: secrets-store.csi.k8s.io
              readOnly: true
              volumeAttributes:
                secretProviderClass: database-secret
          restartPolicy: OnFailure
```

10 秒未満でデータベースをバックアップできます

プログラムが実行できるかどうか

10 秒でエラーポッドを蓄積する

EKS Cluster が間違ったポッドによって 1 時間以内にハングアップすることが予想されます

ワーカーノードの自動拡張戦略を解決する方法があるかもしれません

しかし無制限成長ワーカーノード

また、Cronjob の設定が誤る原因にもなります。

全体的なメンテナンスコストが大幅に増加する

上記のエラー設定により、2 つの設定補正が追加されるはずです。

1.同時実行ポリシー設定の追加
 間違ったポッドが蓄積され続ける
 パラレルも可能です。
 常にエラーが蓄積されるポッド
```yaml
spec:
  concurrencyPolicy: Forbid
```

2。リトライポリシー設定の強化
 プログラムに問題があった場合
 一度間違えると、間違え続けるだけです。
 プログラムが修正されるまで
 ここで、再試行回数とタイムアウト設定を追加する必要があります。
```yaml
spec:
  backoffLimit: 2 # 失敗したら二度あきらめて、そこでずっと試してはいけない
  activeDeadlineSeconds: 600 # 成功にかかわらず 10 分以上強制終了する
```

3。成功履歴とエラー履歴の設定数を増やす
 この設定は必須ではありません。
 ただし、最終的にログはログサーバーに転送されます。
 そのため、サーバーには新しいレコードをいくつか保存するだけで済みます。
```yaml
spec:
  failedJobsHistoryLimit: 1 # 失敗したジョブ履歴の上限
  successfulJobsHistoryLimit: 3 # ジョブ成功履歴の上限
```

すべてプラスとその次はおおまかに次のようになります

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: database-backup
  namespace: operating
spec:
  schedule: "*/10 * * * *"
  concurrencyPolicy: Forbid
  failedJobsHistoryLimit: 1
  successfulJobsHistoryLimit: 3
  jobTemplate:
    spec:
      activeDeadlineSeconds: 600 # 成功に関わらず 10 分以上強制終了する
      backoffLimit: 2 # 失敗したら二度あきらめて、そこでずっと試してはいけない
      template:
        spec:
          serviceAccountName: database-backup-sa
          containers:
            - name: database-backup
              image: postgres:17-alpine
              imagePullPolicy: IfNotPresent
              command:
              - /bin/sh
              - -c
              - |
                export HOST=$(cat /mnt/secrets-store/db-host)
                export PORT=$(cat /mnt/secrets-store/db-port)
                export USERNAME=$(cat /mnt/secrets-store/db-user)
                export PASSWORD=$(cat /mnt/secrets-store/db-password)
                DATABASE="dummy-biz"
                apk add --no-cache aws-cli
                BACKUP_FILE="/tmp/database-backup_$(date +%Y%m%d_%H%M%S).sql"
                PGPASSWORD=$PASSWORD pg_dump -h $HOST -p $PORT -U $USERNAME -d $DATABASE -f $BACKUP_FILE
                aws s3 cp $BACKUP_FILE s3://database-backup/staging/
              resources:
                limits:
                  cpu: "100m"
                  memory: "512Mi"
                requests:
                  cpu: "50m"
                  memory: "64Mi"
              volumeMounts:
              - name: secrets-store
                mountPath: /mnt/secrets-store
                readOnly: true
          volumes:
          - name: secrets-store
            csi:
              driver: secrets-store.csi.k8s.io
              readOnly: true
              volumeAttributes:
                secretProviderClass: database-secret
          restartPolicy: OnFailure
```

> コンテナの実行に `apk add--no-cache aws-cli` を追加するのは良い考えではありませんが、
> 少なくとも 1 人は InitContainer ブロックを入れたいと思っています。
> 準備段階で、必要なパッケージを梱包し、
> もちろん、一番いい方法は自分で容器を詰めることです。
{: .prompt-warning}

この例と改善の方向性はベストプラクティスではありません

ソースはまだエラーのあるプログラムの修正を望んでいます。

改善の方向性だけではない。

しかし、今回はそこが議論のテーマではありません。

今後、次の方法で別の説明を書く予定です。

* 構文とスキーマの検証
``bash
kubeconform -summary -strict my-cronjob.yaml
```
* キューブスコアやキューブリンターなどの SAST ツールで確認する
*「ドライラン」の実行をシミュレート
```
kubectl apply -f my-cronjob.yaml --dry-run=server
```