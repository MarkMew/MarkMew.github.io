---
layout: post
title: "AWS EKS IRSA 解説: Pod が Service Account 経由で IAM Role を使う方法"
description: "AWS EKS で IRSA（IAM Roles for Service Accounts）を設定し、Pod が Kubernetes Service Account 経由で IAM Role を利用して、S3 や Secrets Manager に安全にアクセスする方法を解説します。"
author: Mark_Mew
categories: [K8S]
tags: [EKS, K8S, IAM]
keywords: [AWS EKS IRSA, EKS IRSA 入門, EKS Service Account IAM Role, EKS Pod AWS 権限, EKS Pod S3 アクセス, EKS Secrets Manager, IAM Roles for Service Accounts, Kubernetes Service Account IAM Role]
date: 2026-4-10
---

AWS の運用をしていると、データベースのバックアップを定期実行する CronJob を用意したい場面はよくあります。

たとえば AWS EKS 上で動くバックアップジョブが、Secrets Manager からデータベースの認証情報を取得し、その後バックアップファイルを S3 にアップロードするケースを考えてみます。このとき必ず出てくるのが、「Pod に AWS 権限をどう安全に持たせるか」という問題です。

まずは、よくある CronJob の定義例から見ていきます。

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

EKS を使っている場合、Secrets Store CSI Driver などを組み合わせて、Secrets Manager の値を Pod にマウントする構成はよくあります。

データベースの認証情報そのものはローテーションで管理できますが、S3 にアップロードするためだけに IAM User の Access Key を別途発行して使い続ける構成は、長期的には扱いづらくなりがちです。

そこで有力なのが、Kubernetes Service Account を IAM Role にひも付ける方法です。これなら Pod は実行時に一時的な AWS 権限を取得できるため、長期的な認証情報をアプリケーション内に持たせずに済みます。

## 準備するもの

必要になるのは、主に次の 2 つです。

1. Service Account 用の IAM Role
2. その Role に紐づく IAM Policy と信頼関係

## IAM Policy

まず IAM Role を作成し、その ARN を控えておきます。この ARN は、上の YAML で指定している `ServiceAccount` の annotation に対応します。

`eks.amazonaws.com/role-arn: <service_account>`

次に、Secrets Manager へのアクセスと S3 へのアップロードを許可する IAM Policy をアタッチします。

Secrets Manager の値が KMS Key で暗号化されている場合は、KMS の権限も忘れずに追加してください。

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

一番重要なのは、Trust Relationship です。

Amazon EKS クラスターを作成するときは、通常 OIDC（OpenID Connect）Identity Provider も合わせて構成します。これによって、Kubernetes Service Account と AWS IAM Role の間に信頼関係を作れるようになります。これが IRSA の仕組みです。

ここでは、その EKS クラスターに紐づく OIDC Provider を使います。

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

この設定で特に重要なのは、次の 2 点です。

1. `sub` が対象の Kubernetes Service Account と正確に一致していること
2. `aud` が `sts.amazonaws.com` になっていること

この条件が満たされていれば、Pod はその Service Account の身份を使って、OIDC 経由で AWS STS から一時的な認証情報を取得できます。

## 最終的にどうなるか

ここまでの設定が完了すると、CronJob は `database-backup-sa` という Service Account を使って EKS の OIDC Provider に対して認証を行い、対応する IAM Role の一時権限を受け取れるようになります。

つまり、この Pod は IAM User の Access Key を保持しなくても、次の処理を実行できます。

1. Secrets Manager からデータベース認証情報を取得する
2. データベースに接続してバックアップファイルを生成する
3. 生成したバックアップファイルを S3 にアップロードする

EKS 上のワークロードから AWS リソースを使う場合、この方法はかなりおすすめです。長期的な認証情報を配る構成と比べると、IRSA のほうが安全で、運用もしやすくなります。