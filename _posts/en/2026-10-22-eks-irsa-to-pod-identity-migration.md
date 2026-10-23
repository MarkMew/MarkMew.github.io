---
layout: post
title: "Migrate from EKS IRSA to Pod Identity: When and How"
description: "Do you need to replace IRSA with EKS Pod Identity? Compare the tradeoffs, then migrate the IAM role, association, service account, and Pods safely."
author: Mark_Mew
categories: [AWS, EKS]
tags: [AWS, EKS, IAM, Kubernetes]
keywords: [EKS IRSA to Pod Identity, EKS Pod Identity migration, Pod Identity association, eks-pod-identity-agent]
lang: en
date: 2026-10-22
---

**Do you need to migrate from IRSA to EKS Pod Identity? No.** If IRSA works well and maintaining an OIDC provider and role trust policy for each cluster is manageable, there is no reason to migrate just because Pod Identity is newer. Pod Identity is worth considering when you want EKS to manage the mapping between a Kubernetes service account and an IAM role, particularly across multiple clusters. See the [AWS Pod Identity guide](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html).

IRSA uses OIDC identity federation and STS web identity. Its model resembles an integration you might build for a self-managed or on-premises Kubernetes cluster, although **IRSA itself is an EKS feature**. Pod Identity is an AWS-specific integration for EKS: EKS associations, EKS Auth, and an agent on each supported node provide credentials. It centralizes configuration in EKS while increasing reliance on EKS-specific components. See the [AWS IAM best practices for EKS](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html).

If you choose to migrate, install the EKS Pod Identity Agent, update the IAM role to trust `pods.eks.amazonaws.com`, create an association for the existing namespace and service account, remove the IRSA annotation, and replace the Pods. The IAM permissions granting access to S3, Secrets Manager, and other services can generally stay as they are.

This walkthrough uses `database-backup/database-backup-sa` on EKS EC2 nodes. For background, see the [IRSA setup example](/posts/aws-eks-irsa-service-account-iam-role/).

## IRSA versus Pod Identity

| | IRSA | EKS Pod Identity |
|---|---|---|
| IAM role trusts | The cluster's IAM OIDC provider | `pods.eks.amazonaws.com` |
| Service account configuration | `eks.amazonaws.com/role-arn` annotation | An EKS association linking the namespace, service account, and role |
| Credential path | Web identity token and STS | Pod Identity Agent and EKS Auth |
| Node component | No Pod Identity Agent | Agent on ordinary EC2 nodes; integrated with EKS Auto Mode |

A Pod Identity role does not refer to one cluster's OIDC provider, so it can be reused across associations in different clusters. However, **creating an association does not switch existing Pods away from IRSA**. If a Pod still has IRSA environment variables, the AWS SDK default credential chain may choose IRSA first. See [AWS SDK support and credential resolution](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html).

## Before you start

Record the cluster, Region, namespace, service account, and current role ARN. Check that the application uses an [AWS SDK version that supports Pod Identity](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html) and its default credential chain. Hard-coded access keys and custom credential providers will not switch automatically. These steps target ordinary EKS EC2 nodes; check the [agent requirements](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html) before applying them to Fargate or another node environment.

The commands below use Bash. Replace the example values:

```bash
CLUSTER_NAME=my-cluster
AWS_REGION=ap-northeast-1
NAMESPACE=database-backup
SERVICE_ACCOUNT=database-backup-sa
ROLE_NAME=DatabaseBackupRole
ACCOUNT_ID=111122223333
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

kubectl get serviceaccount "$SERVICE_ACCOUNT" -n "$NAMESPACE" -o yaml
aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument'
```

## 1. Install the Pod Identity Agent

First check whether the add-on is already installed with `aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent --region "$AWS_REGION"`. If it is missing on an ordinary EC2-backed cluster, install it:

```bash
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name eks-pod-identity-agent \
  --region "$AWS_REGION"

kubectl get daemonset -n kube-system eks-pod-identity-agent
```

Verify that the agent runs on the nodes hosting your workload before moving on. The agent uses permissions from the node IAM role rather than its own IRSA role. EKS Auto Mode already integrates Pod Identity and does not require this add-on. See the [agent setup guide](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html) and [EKS add-on list](https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html).

## 2. Update the IAM role trust policy

With IRSA, the role trusts the cluster's OIDC provider and allows `sts:AssumeRoleWithWebIdentity`. For Pod Identity, **add** this statement to the existing trust policy's `Statement` array:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "pods.eks.amazonaws.com"
  },
  "Action": [
    "sts:AssumeRole",
    "sts:TagSession"
  ]
}
```

Keep the OIDC statement during the transition so old Pods can still use IRSA. The role's S3 or Secrets Manager permission policies do not need to change solely because the credential mechanism changes. If you use the CLI, export and edit the **complete** trust policy, then run `aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document file://trust-policy.json`. Do not overwrite the whole policy with the single statement above. See the [AWS trust policy example](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html).

## 3. Create a Pod Identity association

```bash
aws eks create-pod-identity-association \
  --cluster-name "$CLUSTER_NAME" \
  --namespace "$NAMESPACE" \
  --service-account "$SERVICE_ACCOUNT" \
  --role-arn "$ROLE_ARN" \
  --region "$AWS_REGION"

aws eks list-pod-identity-associations \
  --cluster-name "$CLUSTER_NAME" \
  --namespace "$NAMESPACE" \
  --service-account "$SERVICE_ACCOUNT" \
  --region "$AWS_REGION"
```

EKS manages the association; you do not add a new annotation to the service account. Association changes can take a short time to propagate, so confirm that it appears before switching the workload. See the [AWS CLI reference](https://docs.aws.amazon.com/cli/latest/reference/eks/create-pod-identity-association.html).

## 4. Remove the IRSA annotation and replace the Pods

Remove `eks.amazonaws.com/role-arn` from the service account definition in Helm, Kustomize, or GitOps first, so a later deployment does not restore it. Then update the cluster:

```bash
kubectl annotate serviceaccount "$SERVICE_ACCOUNT" \
  -n "$NAMESPACE" \
  eks.amazonaws.com/role-arn-
```

Existing Pods retain their environment variables and mounts. For a Deployment, create new Pods:

```bash
kubectl rollout restart deployment/database-backup -n "$NAMESPACE"
kubectl rollout status deployment/database-backup -n "$NAMESPACE"
```

For a CronJob, wait for the next Job or create a test Job. Do not run the Deployment commands against a CronJob.

## 5. Verify which AWS identity the Pod actually uses

Choose a **newly created** Pod and inspect its environment:

```bash
kubectl exec -n "$NAMESPACE" <new-pod-name> -- \
  env | grep -E '^AWS_(CONTAINER_CREDENTIALS_FULL_URI|CONTAINER_AUTHORIZATION_TOKEN_FILE|ROLE_ARN|WEB_IDENTITY_TOKEN_FILE)='
```

You should see `AWS_CONTAINER_CREDENTIALS_FULL_URI` and `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`, rather than IRSA's `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE`. Run `aws sts get-caller-identity` in the **same application container** and confirm the expected assumed-role ARN. If the image lacks the AWS CLI, call STS with the same AWS SDK the application uses. Finally, exercise the required S3 or Secrets Manager operation to confirm permissions as well as identity. See [how Pod Identity works](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-how-it-works.html).

Remove the old OIDC trust statement only after every workload sharing that role has migrated. Other service accounts may still rely on IRSA, and the cluster's IAM OIDC provider may have other users.

## Common questions

### Why does the Pod still use IRSA after I create the association?

Check that the annotation is gone, the Pod was replaced, and the application does not specify another credential source. An association alone does not override providers earlier in the [AWS SDK default credential chain](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html).

### Can I keep the existing IAM role?

Yes. Keep its permission policies and add `pods.eks.amazonaws.com` to its trust policy. If several service accounts share the role, confirm that they should have the same permissions. See [AWS IAM best practices](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html).

### How do I roll back to IRSA?

If you kept the OIDC trust statement, restore the `eks.amazonaws.com/role-arn` annotation in your deployment configuration, replace the Pods, and verify `get-caller-identity` and the required AWS operations. Investigate the failure before deciding whether to delete the temporary association.

If `eksctl` manages the cluster, `eksctl utils migrate-to-pod-identity --cluster my-cluster` can preview a migration plan; add `--approve` to apply it. Review the affected service accounts, add-ons, and trust-policy changes first. See the [eksctl migration guide](https://docs.aws.amazon.com/eks/latest/eksctl/pod-identity-associations.html).
