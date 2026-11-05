---
layout: post
title: "Investigating CronJob Failures and Delayed EKS Node Scaling"

description: "A failed EKS backup CronJob coincided with delayed node scaling. Review Job failures, pending Pod events, autoscaler logs, and the CronJob manifest before deciding where to fix the problem."
author: Mark_Mew
category: K8S
tags: [EKS, K8S]
date: 2026-3-8
last_modified_at: 2026-11-05
lang: en
---

During EKS operations, repeated backup CronJob failures coincided with Pods waiting for capacity and delayed node scaling. These symptoms appeared together, but a failed CronJob alone does not prove that it prevented the cluster autoscaler from adding nodes. Check the Job failures, Pending Pod events, and autoscaler logs before assigning a cause.

The manifest below is a simplified version of the backup Job. It installs a package at runtime and has no explicit limits on Job retries or concurrent schedules. Those choices deserve review, but the manifest alone does not establish why scaling failed.
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

## How to investigate

1. Inspect the CronJob and its recent Jobs: `kubectl describe cronjob database-backup -n operating` and `kubectl get jobs,pods -n operating`.
2. Read the failed Pod's events and logs with `kubectl describe pod <pod-name> -n operating` and `kubectl logs <pod-name> -n operating`. Check whether the container started, whether `pg_dump` failed, and whether the S3 upload failed.
3. For a Pod stuck in `Pending`, inspect its events separately. A scheduling failure due to insufficient resources is different from a container that started and then exited with an error.
4. Inspect the autoscaler's logs and node group limits before claiming a scaling failure. A Pod may also be unschedulable for reasons that adding a node cannot fix.

Review `.spec.concurrencyPolicy`, `.spec.startingDeadlineSeconds`, and Job retry settings for the intended backup behavior. These controls manage scheduling and retries; they are not a substitute for fixing the backup command. Build a container image with the required tools instead of installing `aws-cli` on every run.

Validate changes before deployment:

```bash
kubectl apply --dry-run=server -f my-cronjob.yaml
```

See the [Kubernetes CronJob documentation](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/) for the exact behavior of these fields.
