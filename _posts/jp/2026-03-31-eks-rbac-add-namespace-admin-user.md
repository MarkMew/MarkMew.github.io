---
layout: post
title: "AWS EKS RBAC 入門：特定 Namespace に Admin ユーザーを追加する方法"
description: "AWS EKS で特定 Namespace に Admin ユーザーを追加する方法を解説します。IAM Policy、Access Entry、Role、RoleBinding、ClusterRole までまとめて確認できます。"
date: 2026-03-31
categories: [K8S]
tags: [EKS, K8S, RBAC, IAM]
keywords: [AWS EKS RBAC, EKS namespace admin, Kubernetes RBAC, EKS Access Entry, IAM User, RoleBinding, ClusterRoleBinding]
---

Kubernetes を管理していると、他のユーザーに共同管理用のアカウントを作成する必要が出てくることがあります。特定 namespace への最大権限を付与する場合、`Role` だけでなく `ClusterRole` も考慮する必要があります。

この記事では `demo` namespace を例に、IAM から RBAC までの設定フローを一通り説明します。

---

## 流れの概要

1. IAM User を作成し、最小権限の Policy をアタッチする
2. EKS Access Entry を作成し、IAM User を K8S の ID にマッピングする
3. Namespace の Role と RoleBinding を作成する
4. ClusterRole と ClusterRoleBinding を作成する（最小限の Cluster 権限）
5. kubeconfig を設定して動作確認する

---

## ステップ 1：IAM Policy を作成する

`eks:DescribeCluster` の呼び出しを許可する IAM Policy を作成します。これは `aws eks update-kubeconfig` を実行するために必要な最低限の権限です：

```json
{
    "Statement": [
        {
            "Action": "eks:DescribeCluster",
            "Effect": "Allow",
            "Resource": [
                "arn:aws:eks:ap-northeast-1:{AWS_ACCOUNT_ID}:cluster/{AWS_EKS_CLUSTER_NAME}"
            ]
        }
    ],
    "Version": "2012-10-17"
}
```

IAM User を作成した後、この Policy をアタッチします。

---

## ステップ 2：EKS Access Entry を作成する

AWS EKS では IAM ID を K8S RBAC にマッピングする方法が 2 種類あります：

- **EKS Access Entry**（新しい方法・推薦）
- **aws-auth ConfigMap**（従来の方法・引き続き対応）

### 方法 1：EKS Access Entry を使う（推薦）

```bash
aws eks create-access-entry \
  --cluster-name {AWS_EKS_CLUSTER_NAME} \
  --principal-arn arn:aws:iam::{AWS_ACCOUNT_ID}:user/demo-admin \
  --username demo-admin \
  --kubernetes-groups demo-admin
```

### 方法 2：aws-auth ConfigMap を編集する（従来の方法）

```bash
kubectl edit configmap aws-auth -n kube-system
```

`mapUsers` フィールドに以下を追加します：

```yaml
mapUsers: |
  - userarn: arn:aws:iam::{AWS_ACCOUNT_ID}:user/demo-admin
    username: demo-admin
    groups:
      - demo-admin
```

---

## ステップ 3：Namespace の Role と RoleBinding を作成する

`demo` namespace に `Role` を作成し、よく使うリソースへのフルアクセス権限を付与します。次に `RoleBinding` で `demo-admin` グループにバインドします：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: demo-admin
  namespace: demo
rules:
  - apiGroups: ["*"]
    resources: ["pods", "pods/log", "pods/exec", "pods/portforward", "secrets", "ingresses", "ingresses/status", "services", "configmaps", "deployments", "replicasets", "statefulsets", "jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]
  - apiGroups: ["*"]
    resources: ["serviceaccounts", "roles", "rolebindings"]
    verbs: ["get", "list", "watch", "create", "patch", "update", "delete"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: demo-admin
  namespace: demo
roleRef:
  kind: Role
  name: demo-admin
  apiGroup: rbac.authorization.k8s.io
subjects:
- kind: Group
  name: demo-admin
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f role.yaml
```

---

## ステップ 4：ClusterRole と ClusterRoleBinding を作成する

Namespace スコープの Role だけでは不十分です。多くの `kubectl` 操作（例：ノードの確認、namespace の一覧取得）には最小限の Cluster レベル権限が必要です。

cluster リソースへの read-only アクセスのみを付与する `ClusterRole` を作成します：

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: list-node-role
rules:
  - apiGroups: [""]
    resources: ["nodes", "persistentvolumes"]
    verbs: ["get", "watch", "list"]
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses"]
    verbs: ["list", "watch"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: list-node-role-binding
subjects:
- kind: User
  name: demo-admin
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: list-node-role
  apiGroup: rbac.authorization.k8s.io
```

```bash
kubectl apply -f cluster-role.yaml
```

---

## ステップ 5：ユーザーの kubeconfig を設定する

対象ユーザーのマシンで以下のコマンドを実行し、クラスターのアクセス認証情報を取得します：

```bash
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name {AWS_EKS_CLUSTER_NAME}
```

---

## 動作確認

現在のユーザーの K8S ID マッピングを確認します：

```bash
kubectl auth whoami
```

`demo` namespace のリソースへのアクセスを確認します：

```bash
kubectl get pods -n demo
```

他の namespace へのアクセスが拒否されることを確認します（`Forbidden` が返ってくるはずです）：

```bash
kubectl get pods -n default
```
