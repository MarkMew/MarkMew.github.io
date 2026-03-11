---
layout: post
title: "Kubernetes Pod Logs 入門：kubectl で複数 Pod のログを素早く確認する方法"
date: 2026-03-12
categories: [K8S]
tags: [EKS, K8S]
---

Kubernetes でデバッグするとき、Pod logs の確認は最もよく行う作業の 1 つです。サービスに複数 Pod（Deployment の replicas など）がある場合、複数 Pod の logs をまとめて確認したいことがあります。

この記事では、`kubectl logs` のよく使う方法を整理します。

---

## 1. 基本的な使い方

### 単一 Pod の Logs を確認する

最も基本的なコマンド：

```bash
kubectl logs -n {namespace} {podname} --tail=100
```

例：

```bash
kubectl logs -n prod api-server-7c8f6d9d8f-abcde --tail=100
```

### Logs を継続的に追跡する

```bash
kubectl logs -n {namespace} {podname} -f
```

### 複数 Container を持つ Pod の Logs を確認する

Pod 内に複数 container がある場合：

```bash
kubectl logs -n {namespace} {podname} -c {container-name}
```

### 直前に Crash した Container の Logs を確認する

Pod が `CrashLoopBackOff` のときに有効です：

```bash
kubectl logs -n {namespace} {podname} --previous
```

## 2. 複数 Pod の Logs を一度に確認する

Deployment に複数 replicas がある場合、`kubectl get pods` と `xargs` または shell loop を組み合わせます。

### 方法1：xargs を使う

```bash
kubectl get pods -n {namespace} -o name \
| xargs -I {} kubectl logs -n {namespace} {} --tail=100
```

- 流れ：
  - まず全 Pod を列挙
  - `kubectl logs` を順番に実行

- 出力例：

```
pod/api-123
pod/api-456
pod/api-789
```

### 方法2：Shell Loop を使う

こちらのほうが読みやすいと感じる人もいます：

```bash
for p in $(kubectl get pods -n {namespace} -o name); do
  kubectl logs -n {namespace} $p --tail=100
done
```

## 3. 特定 Deployment の Pod だけを対象にする

実務では namespace 全体ではなく、特定サービスだけを見ることがほとんどです。

一般的には label selector を使います。

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} kubectl logs -n {namespace} {} --tail=100
```

前提として Deployment に次のような label があること：

```bash
app=my-service
```

## 4. Logs に Pod Name を付ける

複数 Pod の logs が混ざる場合、Pod 名を付けるのがおすすめです：

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} sh -c 'echo "===== {} ====="; kubectl logs -n {namespace} {} --tail=100'
```

出力は次のようになります：

```bash
===== pod/api-7c8f6d9d8f-abcde =====
log line 1
log line 2

===== pod/api-7c8f6d9d8f-fghij =====
log line 1
log line 2
```

これで各ログがどの Pod 由来か明確になります。

## 5. 複数 Pod の Logs をリアルタイム追跡する

リアルタイムで追いたい場合：

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} sh -c 'kubectl logs -n {namespace} -f {} | sed "s/^/[{}] /"'
```

出力例：

```bash
[pod/api-xxx] server started
[pod/api-yyy] connection opened
```

## 6. Deployment が使う Labels を確認する

Deployment の label が不明な場合は、先に確認します：

```bash
kubectl get deploy {deployment-name} -n {namespace} --show-labels
```

または：

```bash
kubectl get pods -n {namespace} --show-labels
```

対応する label selector を確認したら、`kubectl get pods -l` に適用します。

## 7. まとめ

よく使う Kubernetes logs の確認パターン：

- 単一 Pod logs を確認
- `--tail` で出力行数を制限
- `-f` でリアルタイム追跡
- `kubectl get pods + xargs` で複数 Pod を一括確認
- label selector で特定 Deployment に絞る
