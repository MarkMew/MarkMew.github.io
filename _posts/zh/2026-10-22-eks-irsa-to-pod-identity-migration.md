---
layout: post
title: "EKS IRSA 如何轉換成 Pod Identity？遷移步驟與驗證方式"
description: "EKS IRSA 一定要轉 Pod Identity 嗎？比較 OIDC identity federation 與 EKS 原生整合的取捨，並示範 Agent、IAM Role、association 與 Pod 驗證的遷移步驟。"
author: Mark_Mew
categories: [AWS, EKS]
tags: [AWS, EKS, IAM, Kubernetes]
keywords: [EKS IRSA 轉 Pod Identity, EKS Pod Identity 遷移, IRSA migration, Pod Identity Association, eks-pod-identity-agent]
lang: zh-TW
date: 2026-10-22
---

**EKS 的 IRSA 一定要轉成 Pod Identity 嗎？不一定。** 若現有 IRSA 運作穩定，沒有管理大量叢集 OIDC 信任關係的困擾，也不需要為了「比較新」而遷移。若你想用 EKS 管理 ServiceAccount 與 IAM Role 的關聯、減少每個叢集各自設定 OIDC provider 和 trust policy 的工作，Pod Identity 才比較值得採用。[AWS Pod Identity 設定文件](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html)

IRSA 使用 OIDC identity federation 與 STS Web Identity，概念上比較接近自行管理 Kubernetes 身分與 AWS IAM 的整合；這種做法也較容易讓人聯想到自建或地端 Kubernetes 的架構，但 **IRSA 本身仍是 EKS 的功能**，不能直接把它等同於地端方案。Pod Identity 則是 AWS 為 EKS 提供的整合方式：由 EKS association、EKS Auth 與節點上的 Agent 配合提供憑證。它讓 EKS 上的設定更集中，代價是更依賴 AWS 的 EKS 專屬機制。[AWS 身分管理最佳實務](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)

如果決定轉換，做法是安裝 EKS Pod Identity Agent、讓 IAM Role 信任 `pods.eks.amazonaws.com`、為原本的 namespace 與 ServiceAccount 建立 association，最後移除 IRSA annotation 並重建 Pod。原本授予 S3、Secrets Manager 等服務存取權的 IAM policy 通常可以沿用；改變的是 Pod 取得臨時憑證的方式。

本文以 EKS EC2 節點上的 `database-backup/database-backup-sa` 為例。若想先了解原本的機制，可以閱讀[IRSA 設定範例](/posts/aws-eks-irsa-service-account-iam-role/)。

## IRSA 與 Pod Identity 的差異

| 項目 | IRSA | EKS Pod Identity |
|---|---|---|
| IAM Role 信任對象 | 叢集的 IAM OIDC provider | `pods.eks.amazonaws.com` |
| ServiceAccount 設定 | `eks.amazonaws.com/role-arn` annotation | EKS 裡的 namespace、ServiceAccount、Role association |
| 憑證來源 | Web Identity token 與 STS | Pod Identity Agent 與 EKS Auth |
| 節點元件 | 不需要 Pod Identity Agent | 一般 EC2 節點需安裝 Agent；EKS Auto Mode 已整合 |

Pod Identity 的 Role 不再綁定單一叢集的 OIDC provider，因此能供不同叢集的 association 使用。不過，建立 association **不會自動讓舊 Pod 停用 IRSA**。若 Pod 仍帶有 IRSA 環境變數，AWS SDK 的預設憑證鏈可能先選用 IRSA。[AWS SDK 憑證鏈說明](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html)

## 遷移前確認

先記下叢集、Region、namespace、ServiceAccount 與原本的 Role ARN，並確認應用程式使用[支援 Pod Identity 的 AWS SDK 版本](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html)和預設憑證鏈。硬編碼的 access key 或自訂 credential provider 不會因 association 自動改變。以下示例針對一般 EKS EC2 節點；若工作負載跑在 Fargate 或特殊節點環境，先核對[官方限制與 Agent 安裝條件](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)。

以下命令使用 Bash，請替換成自己的值：

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

## 1. 安裝 Pod Identity Agent

先用 `aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent --region "$AWS_REGION"` 檢查是否已安裝。一般 EC2 節點尚未安裝時，執行：

```bash
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name eks-pod-identity-agent \
  --region "$AWS_REGION"

kubectl get daemonset -n kube-system eks-pod-identity-agent
```

確認 Agent 在承載工作負載的節點上正常運作，再繼續切換。Agent 使用節點 IAM Role 的權限，並非靠自己的 IRSA Role。EKS Auto Mode 已整合 Pod Identity，無須額外安裝此 add-on。[AWS Agent 安裝文件](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)、[AWS add-on 清單](https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html)

## 2. 更新 IAM Role 的信任關係

IRSA 原本信任叢集 OIDC provider，並允許 `sts:AssumeRoleWithWebIdentity`。Pod Identity 需要把以下聲明**加入現有 trust policy 的 `Statement` 陣列**：

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

切換期間先保留原本的 OIDC 聲明，讓舊 Pod 仍可使用 IRSA。這裡改的是 Role 的信任關係；Role 原有的 S3、Secrets Manager 等權限政策不必因憑證機制更換而重寫。若使用 CLI，可先匯出並編輯**完整**的 trust policy，再執行 `aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document file://trust-policy.json`。不要用上面的單一聲明覆蓋整份文件。[AWS trust policy 範例](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html)

## 3. 建立 Pod Identity association

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

Association 由 EKS 管理，ServiceAccount 不需要新的 annotation。建立後可能有短暫的最終一致性延遲；先確認查得到 association，再切換工作負載。[AWS CLI 指令文件](https://docs.aws.amazon.com/cli/latest/reference/eks/create-pod-identity-association.html)

## 4. 移除 IRSA annotation 並重建 Pod

先從 Helm chart、Kustomize 或 GitOps 中的 ServiceAccount 宣告移除 `eks.amazonaws.com/role-arn`，避免下一次部署又加回來，再更新叢集：

```bash
kubectl annotate serviceaccount "$SERVICE_ACCOUNT" \
  -n "$NAMESPACE" \
  eks.amazonaws.com/role-arn-
```

既有 Pod 的環境變數與掛載不會因 ServiceAccount 更新而消失。若工作負載是 Deployment，重建 Pod：

```bash
kubectl rollout restart deployment/database-backup -n "$NAMESPACE"
kubectl rollout status deployment/database-backup -n "$NAMESPACE"
```

若是 CronJob，讓下一個 Job 建立新 Pod，或建立測試 Job 驗證；不要對 CronJob 執行上述 Deployment 命令。

## 5. 驗證實際使用的 AWS 身分

選一個**新建立**的 Pod，檢查環境變數：

```bash
kubectl exec -n "$NAMESPACE" <new-pod-name> -- \
  env | grep -E '^AWS_(CONTAINER_CREDENTIALS_FULL_URI|CONTAINER_AUTHORIZATION_TOKEN_FILE|ROLE_ARN|WEB_IDENTITY_TOKEN_FILE)='
```

預期看到 `AWS_CONTAINER_CREDENTIALS_FULL_URI` 與 `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`，而非 IRSA 的 `AWS_ROLE_ARN`、`AWS_WEB_IDENTITY_TOKEN_FILE`。再於**同一個應用程式容器**執行 `aws sts get-caller-identity`，確認回傳預期的 assumed-role ARN；若映像檔沒有 AWS CLI，就用程式所用的 AWS SDK 呼叫 STS。最後實測原本需要的 S3 或 Secrets Manager 操作，確認權限也正確。[AWS Pod Identity 運作說明](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-how-it-works.html)

確認所有共用 Role 的工作負載都已切換後，才從 trust policy 移除舊 OIDC 聲明。若其他 ServiceAccount 仍使用 IRSA，不能刪除它們依賴的信任關係；叢集的 IAM OIDC provider 也可能仍供其他用途。

## 常見問題

### 建立 association 後，為何 Pod 還是使用 IRSA？

檢查 annotation 是否移除、Pod 是否重建，以及應用程式有沒有指定其他憑證來源。AWS SDK 的憑證鏈會優先選用較前面的來源，association 存在不代表程式一定使用 Pod Identity。[AWS SDK 憑證鏈](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html)

### 原本的 IAM Role 可以沿用嗎？

可以。保留原本的權限政策，並在 trust policy 加上 `pods.eks.amazonaws.com` 的聲明。若多個 ServiceAccount 共用 Role，應確認它們需要相同權限。[AWS IAM 最佳實務](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)

### 如何回復 IRSA？

若保留了舊 OIDC 信任聲明，可在部署設定恢復 `eks.amazonaws.com/role-arn` annotation、重新建立 Pod，並以 `get-caller-identity` 和實際 AWS 操作驗證。查明問題後再決定是否刪除暫時建立的 association。

若叢集由 `eksctl` 管理，官方也提供 `eksctl utils migrate-to-pod-identity --cluster my-cluster` 預覽遷移計畫，再加 `--approve` 執行。執行前先檢查計畫涵蓋的 ServiceAccount、add-on 與 trust policy 變更。[eksctl 遷移文件](https://docs.aws.amazon.com/eks/latest/eksctl/pod-identity-associations.html)
