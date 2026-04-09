---
layout: post
title: "AWS EKS IRSA 教學：讓 Pod 透過 Service Account 取得 IAM Role 權限"
description: "本文示範如何在 AWS EKS 中使用 IRSA（IAM Roles for Service Accounts），讓 Pod 透過 Kubernetes Service Account 安全取得 IAM Role 權限，並存取 S3 與 Secrets Manager。"
author: Mark_Mew
categories: [K8S]
tags: [EKS, K8S, IAM]
keywords: [AWS EKS IRSA, EKS IRSA 教學, EKS Service Account IAM Role, EKS Pod AWS 權限, EKS Pod 存取 S3, EKS Secrets Manager, IAM Roles for Service Accounts, Kubernetes Service Account IAM Role]
date: 2026-4-10
---

身為 AWS 管理者或基礎設施維護者，替資料庫安排一個定期備份的 CronJob，其實是很合理的需求。

假設你現在在 AWS EKS 上執行一個備份工作，需要從 Secrets Manager 取得資料庫帳號密碼，接著把備份檔上傳到 S3，那麼問題很快就會出現：這個 Pod 到底要怎麼安全地取得 AWS 權限？

最直覺的做法，通常會先從建立一個 CronJob 開始，例如下面這份設定：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: database-backup

---
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  namespace: database-backup
  name: example
spec:
  provider: aws
  secretObjects:
    - secretName: example-db-secret
      type: Opaque
      data:
        - key: db-user
          objectName: db-user
        - key: db-password
          objectName: db-password
        - key: db-host
          objectName: db-host
        - key: db-port
          objectName: db-port
  parameters:
    objects:  |
      - objectName: "<database_arn>"
        objectType: secretsmanager
        jmesPath:
          - path: username
            objectAlias: db-user
          - path: password
            objectAlias: db-password
          - path: host
            objectAlias: db-host
          - path: "port | to_string(@)"
            objectAlias: db-port
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: database-backup-sa
  namespace: database-backup
  annotations:
    eks.amazonaws.com/role-arn: <service_account>
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: bpm-backup
  namespace: database-backup
spec:
  schedule: "13 */2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: database-backup-sa
          containers:
            - name: example-backup
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
                DATABASE="example-backup"
                apk add --no-cache aws-cli
                BACKUP_FILE="/tmp/example_backup_$(date +%Y%m%d_%H%M%S).sql"
                PGPASSWORD=$PASSWORD pg_dump -h $HOST -p $PORT -U $USERNAME -d $DATABASE -f $BACKUP_FILE
                aws s3 cp $BACKUP_FILE s3://<bucket_name>/example-backup/
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
                secretProviderClass: example
          restartPolicy: OnFailure
```

如果你使用的是 EKS，通常也會搭配 Secrets Store CSI Driver 或相關整合，把 Secrets Manager 裡的資料掛載進 Pod。

資料庫憑證本身可以透過 RDS 加上輪替機制來管理，但如果這個備份工作還要再建立一組固定的 IAM User Access Key 來上傳到 S3，後續維護通常會變得很麻煩。

比較合理的做法，是直接讓這個 Pod 透過 Kubernetes Service Account 對應到 IAM Role。這樣一來，Pod 在執行時就能取得暫時性的 AWS 權限，完成像是上傳 S3 這類操作，而不需要在應用程式裡額外保存長期憑證。

## 需要準備什麼

要完成這件事，至少需要準備下面兩個部分：

1. 一個給 Service Account 使用的 IAM Role
2. 對應的 IAM Policy 與信任關係（Trust Relationship）

## IAM Policy

先建立 IAM Role，並記下它的 ARN。這個 ARN 需要對應到上面 YAML 中 `ServiceAccount` 的 annotation，也就是：

`eks.amazonaws.com/role-arn: <service_account>`

接著替這個 IAM Role 綁定一份可以存取 Secrets Manager 與上傳 S3 的 Policy。

如果你的 Secrets Manager 內容有搭配 KMS Key 進行加解密，記得也要把對應的 KMS 權限一併加上。

```json
{
    "Statement": [
        {
            "Action": [
                "kms:Decrypt",
                "kms:Encrypt"
            ],
            "Effect": "Allow",
            "Resource": [
                "<kms_key_arn>"
            ]
        },
        {
            "Action": [
                "secretsmanager:GetResourcePolicy",
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:ListSecretVersionIds"
            ],
            "Effect": "Allow",
            "Resource": [
                "<secrets_manager_arn>"
            ]
        },
        {
            "Action": [
                "secretsmanager:ListSecrets"
            ],
            "Effect": "Allow",
            "Resource": "*"
        },
        {
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Effect": "Allow",
            "Resource": "arn:aws:s3:::<bucket_name>/*"
        }
    ],
    "Version": "2012-10-17"
}
```

## Trust Relationship

真正的關鍵其實是信任關係，也就是 `trust relationship`。

在建立 Amazon EKS 叢集時，通常也會一起建立 OIDC（OpenID Connect）Identity Provider。它的用途，就是讓 Kubernetes Service Account 可以和 AWS IAM Role 建立信任關係，也就是常聽到的 IRSA（IAM Roles for Service Accounts）。

這裡會用到的，就是當初建立 EKS 時所對應的那組 OIDC Provider。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::<aws_account_id>:oidc-provider/oidc.eks.ap-northeast-1.amazonaws.com/id/<identity_provider_id>"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.ap-northeast-1.amazonaws.com/id/<identity_provider_id>:sub": "system:serviceaccount:<namespace>:database-backup-sa",
                    "oidc.eks.ap-northeast-1.amazonaws.com/id/<identity_provider_id>:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
```

這份信任關係的重點在於兩個條件：

1. `sub` 必須精準對應到指定的 Kubernetes Service Account
2. `aud` 必須是 `sts.amazonaws.com`

只要這兩個條件成立，Pod 就能以該 Service Account 的身分，透過 OIDC 向 AWS STS 取得暫時性憑證。

## 最後會發生什麼事

當這些設定都完成之後，CronJob 在執行時就可以透過 `database-backup-sa` 這個 Service Account 向 AWS 的 OIDC Provider 完成驗證，接著取得對應 IAM Role 的暫時性權限。

也就是說，這個 Pod 不需要保存 IAM User 的 Access Key，就能夠：

1. 讀取 Secrets Manager 中的資料庫憑證
2. 連線資料庫並產生備份檔
3. 將備份檔上傳到 S3

這也是在 EKS 上操作 AWS 資源時，比較推薦的做法。因為相較於手動發放長期憑證，IRSA 會更安全，也更容易管理。