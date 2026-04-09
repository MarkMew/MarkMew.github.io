---
layout: post
title: "AWS EKS IRSA Tutorial: How Pods Assume IAM Roles via Service Accounts"
description: "Learn how to configure IRSA in AWS EKS so Pods can assume IAM Roles through Kubernetes Service Accounts and securely access S3 and Secrets Manager without long-lived AWS credentials."
author: Mark_Mew
categories: [K8S]
tags: [EKS, K8S, IAM]
keywords: [AWS EKS IRSA, EKS IRSA guide, EKS Service Account IAM Role, EKS Pod AWS permissions, EKS Pod access S3, EKS Secrets Manager, IAM Roles for Service Accounts, Kubernetes Service Account IAM Role]
date: 2026-4-10
---

If you manage AWS infrastructure, setting up a CronJob to back up a database is a pretty normal requirement.

Now imagine that this backup job runs on AWS EKS. It needs to read database credentials from Secrets Manager and then upload the backup file to S3. At that point, the real question becomes obvious: how should the Pod get AWS permissions securely?

The most natural starting point is usually the CronJob itself, for example:

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

If you are running EKS, you will often combine this with the Secrets Store CSI Driver or a similar integration so that values from Secrets Manager can be mounted into the Pod.

The database credentials themselves can be managed through rotation mechanisms, such as RDS plus scheduled rotation. But if this backup job also depends on a dedicated IAM User access key just to upload to S3, the setup usually becomes harder to maintain over time.

The cleaner approach is to let the Pod use a Kubernetes Service Account that maps to an IAM Role. That way, the Pod can obtain temporary AWS credentials at runtime and perform actions such as uploading to S3, without storing long-lived credentials inside the application.

## What you need

At a minimum, you need these two pieces:

1. An IAM Role for the Service Account
2. An IAM Policy and the matching trust relationship

## IAM Policy

Start by creating an IAM Role and noting down its ARN. That ARN needs to match the annotation in the YAML above:

`eks.amazonaws.com/role-arn: <service_account>`

Then attach a policy that allows access to Secrets Manager and S3.

If your Secrets Manager values are encrypted with a KMS key, make sure the role also has the required KMS permissions.

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

The most important part is the trust relationship.

When you create an Amazon EKS cluster, you usually also set up an OIDC identity provider. This is what allows a Kubernetes Service Account to establish trust with an AWS IAM Role, which is exactly what IRSA stands for: IAM Roles for Service Accounts.

The trust relationship will reference the OIDC provider that belongs to your EKS cluster.

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

There are two key checks here:

1. `sub` must match the exact Kubernetes Service Account
2. `aud` must be `sts.amazonaws.com`

Once both conditions are satisfied, the Pod can use that Service Account identity to obtain temporary credentials from AWS STS through OIDC.

## What happens in the end

After all of this is in place, the CronJob can run using `database-backup-sa`, authenticate through the EKS OIDC provider, and receive temporary permissions from the IAM Role.

In practice, that means the Pod no longer needs a long-lived IAM User access key in order to:

1. Read database credentials from Secrets Manager
2. Connect to the database and generate a backup file
3. Upload the backup file to S3

This is generally the recommended way to let workloads on EKS access AWS resources. Compared with handing out long-lived credentials manually, IRSA is both safer and easier to manage.