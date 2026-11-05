---
layout: post
title: EKS での cronjob 実行エラーによってワーカーノードの自動拡張が失敗するのを防ぐ方法
description: "EKS のバックアップ CronJob が失敗し、ノードのスケールアウトも遅れた事例。Job の失敗原因、Pending Pod のイベント、オートスケーラーのログを切り分ける。"
author: Mark_Mew
category: K8S
tags: [EKS, K8S]
date: 2026-3-8
last_modified_at: 2026-11-05
lang: ja
---

EKS の運用中、バックアップ用 CronJob の失敗が続き、同時期に Pod が Pending のまま残り、ノードのスケールアウトも遅れました。ただし、CronJob の失敗だけでオートスケーラーへの影響を断定することはできません。Job のエラー、Pending Pod のイベント、オートスケーラーのログを分けて確認します。

以下は当時のバックアップ Job を簡略化した例です。実行時のパッケージ導入や Job の再試行設定を確認する必要がありますが、このマニフェストだけでスケールアウト失敗の原因は特定できません。
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

> 毎回 `apk add --no-cache aws-cli` を実行すると、パッケージ取得の失敗や起動時間の増加につながります。必要なツールは事前にコンテナイメージへ組み込んでください。
{: .prompt-warning}

## 切り分けの手順

1. `kubectl describe cronjob database-backup -n operating` と `kubectl get jobs,pods -n operating` で最近の Job を確認します。
2. 失敗した Pod のイベントとログを確認し、コンテナの起動、`pg_dump`、S3 へのアップロードのどこで失敗したかを調べます。
3. Pending Pod は別に `kubectl describe pod <pod-name> -n operating` で確認します。リソース不足と、起動後のコンテナエラーは異なる問題です。
4. オートスケーラーのログとノードグループの上限を確認してから、スケールアウト失敗の原因を判断します。

必要に応じて CronJob の `concurrencyPolicy`、`startingDeadlineSeconds`、Job の再試行設定を見直します。これらは実行タイミングと再試行を制御するもので、バックアップ処理そのもののエラーは修正できません。

```bash
kubectl apply --dry-run=server -f my-cronjob.yaml
```

各設定の動作は [Kubernetes の CronJob ドキュメント](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)を参照してください。
