---
layout: post
title: "AWS EKS RBAC 教學：為特定 Namespace 新增 Admin 使用者"
date: 2026-03-31
categories: [K8S]
tags: [EKS, K8S, RBAC, IAM]
---

在管理 Kubernetes 時，偶爾會需要建立帳號給其他使用者共同管理，當我們需要建立一個 namespace 的最大權限時，除了 Role 以外，也需要考慮到 Cluster Role。

本篇以在 `demo` namespace 下建立一個 admin 使用者為例，完整說明從 IAM 到 RBAC 的設定流程。

---

## 流程概覽

1. 建立 IAM User 並附加最小權限 Policy
2. 在 EKS 中建立 Access Entry，將 IAM User 對應至 K8S 身份
3. 建立 Namespace Role 與 RoleBinding
4. 建立 ClusterRole 與 ClusterRoleBinding（提供最小 Cluster 層級權限）
5. 設定 kubeconfig 並驗證

---

## 步驟一：建立 IAM Policy

建立一個 IAM Policy，允許使用者呼叫 `eks:DescribeCluster`，這是執行 `aws eks update-kubeconfig` 時所需的最低權限：

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

建立 IAM User 後，將這個 Policy 附加上去。

---

## 步驟二：在 EKS 中建立 Access Entry

AWS EKS 目前有兩種方式可以將 IAM 身份對應至 K8S RBAC：

- **EKS Access Entry**（新方式，推薦）
- **aws-auth ConfigMap**（舊方式，仍支援）

### 方法一：使用 EKS Access Entry（推薦）

```bash
aws eks create-access-entry \
  --cluster-name {AWS_EKS_CLUSTER_NAME} \
  --principal-arn arn:aws:iam::{AWS_ACCOUNT_ID}:user/demo-admin \
  --username demo-admin \
  --kubernetes-groups demo-admin
```

### 方法二：修改 aws-auth ConfigMap（舊方式）

```bash
kubectl edit configmap aws-auth -n kube-system
```

在 `mapUsers` 欄位新增：

```yaml
mapUsers: |
  - userarn: arn:aws:iam::{AWS_ACCOUNT_ID}:user/demo-admin
    username: demo-admin
    groups:
      - demo-admin
```

---

## 步驟三：建立 Namespace Role 與 RoleBinding

在 `demo` namespace 中建立一個 `Role`，授予對常用資源的完整操作權限，再透過 `RoleBinding` 將其綁定至 `demo-admin` group：

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

## 步驟四：建立 ClusterRole 與 ClusterRoleBinding

只有 Namespace 層級的 Role 還不夠，許多 `kubectl` 操作（例如查看節點、列出 namespace）需要最小的 Cluster 層級權限。

建立一個 `ClusterRole`，僅授予 read-only 的 cluster 資源存取：

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

## 步驟五：設定使用者的 kubeconfig

讓目標使用者在其機器上執行以下指令取得 cluster 存取憑證：

```bash
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name {AWS_EKS_CLUSTER_NAME}
```

---

## 驗證

確認目前使用者的 K8S 身份對應是否正確：

```bash
kubectl auth whoami
```

驗證是否能操作 `demo` namespace 的資源：

```bash
kubectl get pods -n demo
```

確認無法存取其他 namespace（應收到 `Forbidden`）：

```bash
kubectl get pods -n default
```
