---
layout: post
title: "Kubernetes Pod Logs 教學：快速查看多個 Pod Logs（kubectl 實戰）"
date: 2026-03-12
categories: [K8S]
tags: [EKS, K8S]
---

在 Kubernetes 除錯時，查看 Pod logs 是最常做的事情之一。如果服務有多個 Pod（例如 Deployment 產生的 replicas），有時會需要一次查看多個 Pod 的 logs。

這篇整理幾個常用的 `kubectl logs` 使用方式。

---

## 1. 基本用法

### 查看單一 Pod 的 Logs

最基本的指令：

```bash
kubectl logs -n {namespace} {podname} --tail=100
```

例如：

```bash
kubectl logs -n prod api-server-7c8f6d9d8f-abcde --tail=100
```

### 持續追蹤 Logs

```bash
kubectl logs -n {namespace} {podname} -f
```

### 查看多 Container Pod

如果 Pod 裡有多個 container：

```bash
kubectl logs -n {namespace} {podname} -c {container-name}
```

### 查看上一個 Crash 的 Container

當 Pod 出現 CrashLoopBackOff 時很有用：

```bash
kubectl logs -n {namespace} {podname} --previous
```

## 2. 一次查看多個 Pod Logs

如果 Deployment 有多個 replicas，可以透過 kubectl get pods 搭配 xargs 或 shell loop。

### 方法一：使用 xargs

```bash
kubectl get pods -n {namespace} -o name \
| xargs -I {} kubectl logs -n {namespace} {} --tail=100
```

- 流程：
  - 先列出所有 Pod
  - 逐一執行 `kubectl logs`

- 輸出類似：

```
pod/api-123
pod/api-456
pod/api-789
```

### 方法二：使用 Shell Loop

有些人會覺得這種方式比較好閱讀：

```bash
for p in $(kubectl get pods -n {namespace} -o name); do
  kubectl logs -n {namespace} $p --tail=100
done
```

## 3. 只抓某個 Deployment 的 Pods

實務上通常只會看某個服務，而不是整個 namespace。

最常見的方法是使用 label selector。

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} kubectl logs -n {namespace} {} --tail=100
```

前提是 Deployment 使用類似以下 label：

```bash
app=my-service
```

## 4. 在 Logs 中標示 Pod Name

當多個 Pod logs 混在一起時，建議加上 Pod 標示：

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} sh -c 'echo "===== {} ====="; kubectl logs -n {namespace} {} --tail=100'
```

輸出會變成：

```bash
===== pod/api-7c8f6d9d8f-abcde =====
log line 1
log line 2

===== pod/api-7c8f6d9d8f-fghij =====
log line 1
log line 2
```

這樣可以清楚知道每段 log 來自哪個 Pod。

## 5. 同時追蹤多個 Pod Logs

如果需要即時追蹤：

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} sh -c 'kubectl logs -n {namespace} -f {} | sed "s/^/[{}] /"'
```

輸出會像：

```bash
[pod/api-xxx] server started
[pod/api-yyy] connection opened
```

## 6. 查看 Deployment 使用的 Labels

如果不確定 Deployment 的 label，可以先查：

```bash
kubectl get deploy {deployment-name} -n {namespace} --show-labels
```

或：

```bash
kubectl get pods -n {namespace} --show-labels
```

找到對應的 label selector 後，再套用到 `kubectl get pods -l`。

## 7. 小結

常見的 Kubernetes logs 使用方式：

- 查看單一 Pod logs
- 使用 `--tail` 限制輸出行數
- 使用 `-f` 即時追蹤 logs
- 透過 `kubectl get pods + xargs` 一次查看多個 Pods
- 使用 label selector 限縮到某個 Deployment