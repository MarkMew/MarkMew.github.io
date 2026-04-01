---
layout: post
title: "AWS EKS RBAC Guide: Add a Namespace Admin User"
description: "Learn how to add an admin user for a specific namespace in AWS EKS, including IAM Policy, EKS Access Entry, Role, RoleBinding, ClusterRole, and ClusterRoleBinding setup."
date: 2026-03-31
categories: [K8S]
tags: [EKS, K8S, RBAC, IAM]
keywords: [AWS EKS RBAC, EKS namespace admin, Kubernetes RBAC, EKS Access Entry, IAM User, RoleBinding, ClusterRoleBinding]
---

When managing Kubernetes, you may occasionally need to create accounts for other users to co-manage the cluster. When you need to grant full admin access within a specific namespace, you need to configure not only a `Role` but also a `ClusterRole` for minimum cluster-level permissions.

This post uses the `demo` namespace as an example and walks through the full setup from IAM to RBAC.

---

## Overview

1. Create an IAM User and attach a minimal permission Policy
2. Create an EKS Access Entry to map the IAM User to a K8S identity
3. Create a Namespace Role and RoleBinding
4. Create a ClusterRole and ClusterRoleBinding (minimum cluster-level permissions)
5. Configure kubeconfig and verify

---

## Step 1: Create an IAM Policy

Create an IAM Policy that allows the user to call `eks:DescribeCluster`. This is the minimum permission required to run `aws eks update-kubeconfig`:

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

After creating the IAM User, attach this Policy to it.

---

## Step 2: Create an EKS Access Entry

AWS EKS currently supports two ways to map IAM identities to K8S RBAC:

- **EKS Access Entry** (new approach, recommended)
- **aws-auth ConfigMap** (legacy approach, still supported)

### Option 1: Using EKS Access Entry (Recommended)

```bash
aws eks create-access-entry \
  --cluster-name {AWS_EKS_CLUSTER_NAME} \
  --principal-arn arn:aws:iam::{AWS_ACCOUNT_ID}:user/demo-admin \
  --username demo-admin \
  --kubernetes-groups demo-admin
```

### Option 2: Editing the aws-auth ConfigMap (Legacy)

```bash
kubectl edit configmap aws-auth -n kube-system
```

Add the following under `mapUsers`:

```yaml
mapUsers: |
  - userarn: arn:aws:iam::{AWS_ACCOUNT_ID}:user/demo-admin
    username: demo-admin
    groups:
      - demo-admin
```

---

## Step 3: Create a Namespace Role and RoleBinding

Create a `Role` in the `demo` namespace granting full access to common resources, then bind it to the `demo-admin` group via a `RoleBinding`:

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

## Step 4: Create a ClusterRole and ClusterRoleBinding

A Namespace-scoped Role alone is not enough. Many `kubectl` operations (e.g., listing nodes, listing namespaces) require minimum cluster-level permissions.

Create a `ClusterRole` that grants read-only access to cluster resources:

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

## Step 5: Configure kubeconfig for the User

Have the target user run the following command on their machine to obtain cluster access credentials:

```bash
aws eks update-kubeconfig \
  --region ap-northeast-1 \
  --name {AWS_EKS_CLUSTER_NAME}
```

---

## Verification

Confirm the current user's K8S identity mapping:

```bash
kubectl auth whoami
```

Verify access to resources in the `demo` namespace:

```bash
kubectl get pods -n demo
```

Confirm that access to other namespaces is denied (should receive `Forbidden`):

```bash
kubectl get pods -n default
```
