---
layout: post
title: How to prevent cronjob execution failure on EKS from causing Worker Node auto-extension failure
author: Mark_Mew
category: K8S
tags: [EKS, K8S]
date: 2026-3-8
---

Recently when servicing EKS

Something happened

Because a lot of cronjob execution fails

Causes Worker Node to automatically scale without creating new deployments

There are multiple levels of possibility of this problem

1. Resolve Worker Node Auto Expansion Strategies
2. Cronjob execution failure results in massive Pod reboots impacting performance of API Server and kube-scheduler

Here is a cronjob for writing a problem
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

Back up the database in less than 10 seconds

Whether the program can run

Accumulate an Error Pod in 10 Seconds

Expect EKS Cluster to be hung by a wrong Pod for less than an hour

Maybe there's a way to solve Worker Node's auto-expansion strategy

But Unlimited Growth Worker Node

It also causes a Cronjob to be misconfigured

Significantly increase your overall maintenance costs

The above error settings should add two settings compensation

1. Add ConcurrencyPolicy settings
 Wrong Pod Continues to Accumulate
 Parallel is also allowed
 Pods that will constantly accumulate errors
```yaml
Spec:
 ConcurrencyPolicy: Forbid
```

2. Enhance Retry Policy Settings
 If there is a problem with the program
 Once it's wrong, it just keeps getting it wrong
 Until the program is fixed
 Here you should add a number of retries and timeout settings
```yaml
Spec:
 BackoffLimit: 2 # Give up twice if you fail, don't try all the time there
 ActiveDeadlineSeconds: 600 # Kill it for more than ten minutes regardless of success
```

3. Increase the number of success and error history settings
 This setting is not mandatory
 However, in the end Log will be forwarded to Log Server
 Therefore, you only need to keep a few newer records on the server
```yaml
Spec:
 FailedJobHistoryLimit: 1
 SuccessfulJob HistoryLimit: 3
```

All plus and then are roughly as follows

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
      activeDeadlineSeconds: 600 # Kill it for more than ten minutes regardless of success
      backoffLimit: 2 # Give up twice if you fail, don't try all the time there
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

> Adding `apk add --no-cache aws-cli` to Container execution is not a good idea,
> At least one would like to put the InitContainer block,
> At the preparation stage, pack the required package,
> Of course, the best way is to pack a container yourself.
{: .prompt-warning}

This example and the direction of improvement is not the best practice

The source still wants to fix a program that has errors

The direction of improvement is not the only one

But that's not the topic of discussion this time.

In the future, we will write another description in the following way.

* Syntax and Schema Validation
``bash
cubeconform -summary -strict my-cronjob.yaml
```
* Check with SAST tools such as kube-score or Kube-Linter
* Simulate running `Dry Run`
```
kubectl apply -f my-cronjob.yaml --dry-run=server
```