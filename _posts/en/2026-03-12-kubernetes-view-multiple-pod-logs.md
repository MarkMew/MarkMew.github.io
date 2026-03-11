---
layout: post
title: "Kubernetes Pod Logs Guide: Quickly View Logs from Multiple Pods with kubectl"
date: 2026-03-12
categories: [K8S]
tags: [EKS, K8S]
---

When debugging in Kubernetes, checking pod logs is one of the most common tasks. If a service has multiple pods (for example, replicas created by a Deployment), you may need to view logs from multiple pods at once.

This post summarizes several practical ways to use `kubectl logs`.

---

## 1. Basic Usage

### View Logs from a Single Pod

The most basic command:

```bash
kubectl logs -n {namespace} {podname} --tail=100
```

Example:

```bash
kubectl logs -n prod api-server-7c8f6d9d8f-abcde --tail=100
```

### Stream Logs Continuously

```bash
kubectl logs -n {namespace} {podname} -f
```

### View Logs from Multi-Container Pods

If a pod contains multiple containers:

```bash
kubectl logs -n {namespace} {podname} -c {container-name}
```

### View Logs from the Previous Crashed Container

Very useful when a pod is in `CrashLoopBackOff`:

```bash
kubectl logs -n {namespace} {podname} --previous
```

## 2. View Logs from Multiple Pods at Once

If a Deployment has multiple replicas, you can combine `kubectl get pods` with `xargs` or a shell loop.

### Method 1: Use xargs

```bash
kubectl get pods -n {namespace} -o name \
| xargs -I {} kubectl logs -n {namespace} {} --tail=100
```

- Flow:
  - List all pods first
  - Run `kubectl logs` one by one

- Example output:

```
pod/api-123
pod/api-456
pod/api-789
```

### Method 2: Use a Shell Loop

Some people find this easier to read:

```bash
for p in $(kubectl get pods -n {namespace} -o name); do
  kubectl logs -n {namespace} $p --tail=100
done
```

## 3. Filter Pods by a Specific Deployment

In practice, you usually inspect one service instead of the entire namespace.

The most common way is using a label selector.

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} kubectl logs -n {namespace} {} --tail=100
```

This assumes your Deployment uses labels like:

```bash
app=my-service
```

## 4. Prefix Logs with Pod Names

When logs from multiple pods are mixed together, add pod-name markers:

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} sh -c 'echo "===== {} ====="; kubectl logs -n {namespace} {} --tail=100'
```

Output becomes:

```bash
===== pod/api-7c8f6d9d8f-abcde =====
log line 1
log line 2

===== pod/api-7c8f6d9d8f-fghij =====
log line 1
log line 2
```

This makes it clear which pod each log block comes from.

## 5. Follow Logs from Multiple Pods in Real Time

If you need real-time streaming:

```bash
kubectl get pods -n {namespace} -l app={deployment-name} -o name \
| xargs -I {} sh -c 'kubectl logs -n {namespace} -f {} | sed "s/^/[{}] /"'
```

Output will look like:

```bash
[pod/api-xxx] server started
[pod/api-yyy] connection opened
```

## 6. Check Deployment Labels

If you are not sure which labels are used by the Deployment, check first:

```bash
kubectl get deploy {deployment-name} -n {namespace} --show-labels
```

Or:

```bash
kubectl get pods -n {namespace} --show-labels
```

After identifying the correct label selector, apply it to `kubectl get pods -l`.

## 7. Summary

Common Kubernetes log inspection patterns:

- View logs from a single pod
- Use `--tail` to limit output lines
- Use `-f` to stream logs in real time
- Use `kubectl get pods + xargs` to inspect multiple pods at once
- Use label selectors to scope logs to one Deployment
