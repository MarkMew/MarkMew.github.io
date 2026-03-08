---
layout: post
title: 如果避免 EKS 上 的 cronjob 執行失敗導致 Worker Node 自動擴展失敗
author: Mark_Mew
category: K8S
tags: [EKS, K8S]
date: 2026-3-8
---

最近在維運 EKS 時

發生一件事情

因為大量的 cronjob 執行失敗

導致 Worker Node 無法自動擴展而無法建立新的佈署

這個問題有多個層面的可能性

1. 解決 Worker Node 自動擴展策略
2. Cronjob 執行失敗導致大量 Pod 重啟影響到 API Server 和 kube-scheduler 的效能

以下是撰寫有問題的 cronjob
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

先不論 10 秒鐘備份一次資料庫

程式是否可以執行的完

不過 10 秒鐘累積一個錯誤的 Pod

預計不到一小時 EKS Cluster 就有可能被一個錯誤的 Pod 打掛

解決 Worker Node 自動擴展策略也許是個方法

不過無限制的增長 Worker Node

也會讓一個 Cronjob 的錯誤設定

就讓整個維運支出大幅增加

以上的錯誤設定應該增加兩項設定彌補

1. 新增 concurrencyPolicy 設定
   錯誤的 Pod 持續累積
   又允許並行的話
   將持續累積錯誤的 Pod
```yaml
spec:
  concurrencyPolicy: Forbid
```

2. 強化重試政策的設定
   如果是程式上的問題
   一旦出錯就只會繼續錯下去
   直到程式修正為止
   於此應該加個重試次數和超時設定
```yaml
spec:
  backoffLimit: 2 # 失敗兩次就放棄，別在那邊一直試
  activeDeadlineSeconds: 600 # 不管成功失敗，超過十分鐘就把它殺掉
```

3. 增加成功和錯誤歷史紀錄次數設定
   這設定不是強制
   不過最終 Log 會轉發到 Log Server
   因此 Server 上只需要保留較新的幾筆紀錄即可
```yaml
spec:
  failedJobsHistoryLimit: 1
  successfulJobsHistoryLimit: 3
```

全部加上去後大致如下

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
      activeDeadlineSeconds: 600 # 不管成功失敗，超過十分鐘就把它殺掉
      backoffLimit: 2 # 失敗兩次就放棄，別在那邊一直試
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

> Container 執行中加入 `apk add --no-cache aws-cli` 不是個好想法，
> 至少會希望放到 initContainer 區塊，
> 在準備階段的時候就將需要的 Package 裝好，
> 當然最好的方式還是自己打包製作一份 Container 存起來
{: .prompt-warning}

這份範例和改善方向不是最好的做法

最源頭還是希望修正有錯誤的程式

至於改善方向也非唯一

不過這不在這次的討論範疇

也羅列以下方式，未來會再寫一篇描述

* 語法與 Schema 驗證
```bash
kubeconform -summary -strict my-cronjob.yaml
```
* 使用 SAST 工具檢查，如：kube-score 或 Kube-Linter
* 模擬執行 `Dry Run`
```
kubectl apply -f my-cronjob.yaml --dry-run=server
```