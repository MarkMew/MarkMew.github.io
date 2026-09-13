---
layout: post
title: "K8S Secret 與 ConfigMap 差異：Base64 不是加密，為何憑證仍要用 Secret？"
image: https://fastly.picsum.photos/id/523/1200/630.jpg?hmac=eqnaeTHYrg6DamyKUBWUMQWNjCykDblhXWO7my-QSz4
description: "Kubernetes Secret 的 Base64 並非加密，為何憑證仍要用 Secret？從獨立 RBAC 管理、Encryption at Rest 與安全工具整合三個重點，理解 K8S Secret 和 ConfigMap 的差異。"
author: Mark_Mew
categories: [K8S]
tags: [K8S, Kubernetes, Secret, ConfigMap, RBAC]
keywords: [K8S Secret ConfigMap 差異, Kubernetes Secrets, Base64 不是加密, Credentials 管理, etcd 靜態加密, RBAC]
lang: zh-TW
date: 2026-09-13
---

最近看到一則關於 K8S 的謎因，有人將密碼使用 configmap 儲存。

![Store password in configmap](/assets/img/k8s_password_in_configmap_meme.png)

對於已經有 K8S 維護經驗的應該不陌生，但是對於 K8S 新手，也許不一定能理解。

Configmap 裡面儲存的是明碼，Secrets 裡面雖然不是明碼，不過也只是 Base64 轉換過的值。

其實實質上也沒有達到加密的作用，那為什麼 K8S 在設計得時候，我們非得將密碼使用 Secrets 來儲存，而不是 Configmap 呢？

我覺得這是個很有趣的問題，因此決定寫一篇來討論這問題。

## K8S Secret 只是 Base64，為什麼憑證不放 ConfigMap？

**因為 Secret 可以把密碼和一般設定分開做 RBAC 管理，也能搭配 Encryption at Rest，以及 K8S 生態系統的安全工具。** 只是這些都需要設定，並不是建立 Secret 之後，密碼就自動受到加密保護。[Kubernetes Secret 官方文件](https://kubernetes.io/docs/concepts/configuration/secret/)

所以只看 YAML 裡面的 Base64，確實看不出使用 Secret 有什麼好處。我們還得往下看：密碼放進去之後，誰能讀取？存進 etcd 時有沒有加密？又能透過哪些工具來管理？

## Secret 與 ConfigMap 的差異

先把兩者放在一起比較。ConfigMap 用來放一般設定，Secret 則用來放密碼、Token 這類敏感資料。不過它們有些功能是重疊的，像 RBAC 和靜態加密，兩者都能設定。[ConfigMap 官方文件](https://kubernetes.io/docs/concepts/configuration/configmap/)

| 比較項目 | ConfigMap | Secret |
| --- | --- | --- |
| 用途 | 一般設定 | 密碼、Token、Key、Certificate |
| API 資料形式 | `data` 為明文 string；`binaryData` 使用 Base64 | `data` 使用 Base64；`stringData` 可輸入明文 |
| 預設 etcd 加密 | Kubernetes 預設未啟用 API 層靜態加密，依叢集設定而定 | Kubernetes 預設未啟用 API 層靜態加密，依叢集設定而定 |
| 可搭配 Encryption at Rest | ✅ 可以設定 | ✅ 可以設定，官方建議啟用 |
| Kubernetes／tooling 是否以敏感資料處理 | 定位為一般設定，不應期待工具隱藏內容 | 定位為敏感資料，相關工具可採取額外保護，但不保證所有工具都會遮蔽 |
| RBAC 可獨立限制 | ✅ 可獨立授權 | ✅ 可與 ConfigMap 分開授權；較嚴格的權限需實際設定 |
| Secret Store／Vault／KMS 整合 | 非憑證管理整合的主要用途；仍可搭配 KMS 靜態加密 | ✅ 常作為外部憑證整合資源，也可搭配 KMS 靜態加密 |
| `kubectl describe` 等工具的敏感資料處理 | `kubectl describe configmap` 會顯示資料內容 | `kubectl describe secret` 通常顯示 key 與大小；`kubectl get secret -o yaml` 仍可取得 Base64 內容 |

這樣看下來，可能還是會覺得：「ConfigMap 也能限制權限、也能加密，那為什麼要分開？」拿資料庫設定來想，就比較容易理解了。

## 第一，Secret 可以被單獨做 RBAC 管理

假設有人要排查資料庫連線問題，他可能需要知道 `DB_HOST`，但不一定需要知道 `DB_PASSWORD`。

如果兩個都放在 ConfigMap，開放讀取設定的同時，密碼也一起開放了。把 `DB_PASSWORD` 另外放在 Secret，就可以只讓他讀 ConfigMap。以 ServiceAccount 的授權來說，Role 裡可以有這樣的規則：

```yaml
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
```

這段沒有包含 `secrets`，所以不會授予讀取 Secret 的權限。原本只是為了檢查設定而取得權限的使用者、Controller 或工作負載，就不需要連密碼也拿到。

不過這裡有個容易漏掉的地方：RBAC 權限會累加。如果其他 RoleBinding 或 ClusterRoleBinding 已經給了讀取 Secret 的權限，這段規則並不會把它收回。

另外，也要留意建立 Pod 的權限，因為能建立 Pod 的人，可能透過掛載讀到 Secret。`list`、`watch` Secret 也可能取得內容，不能只擋 `get`。[Secret 存取控制建議](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 第二，Secret 可以搭配 Kubernetes Encryption at Rest

權限管好了，接著就是資料存在哪裡、怎麼存的問題。

Secret 的 `data` 雖然只是 Base64，但 Kubernetes API Server 可以另外設定 encryption provider，讓資料在寫入 etcd 前先加密：

```text
Kubernetes API Server
    ↓ Encryption Provider
加密後的 Secret 資料
    ↓
etcd
```

**這裡的 Encryption at Rest，才是真正需要金鑰才能還原的加密。** 它和 YAML 裡看到的 Base64 是兩回事。

Kubernetes 預設沒有替 Secret 啟用 API 層的 etcd 靜態加密。如果用的是託管叢集，要再確認服務的設定。ConfigMap 也能納入加密範圍，所以不能只憑 `kind: Secret` 就判斷資料有沒有加密。[靜態加密官方文件](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

那加密後，別人是不是就讀不到密碼了？還是要看他從哪裡讀。

如果是 etcd 的儲存檔或快照外洩，在金鑰沒有一起外洩的前提下，加密就能提供保護。但如果對方本來就有權限執行 `kubectl get secret -o yaml`，API Server 還是會回傳可解碼的內容。這也是為什麼加密和 RBAC 都要做。

實際啟用時還要記得，既有資料需要重新寫入才會套用加密，舊備份也不會跟著自動加密。[既有資料加密說明](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

## 第三，很多 K8S 生態系統的安全工具都以 Secret 為整合介面

除了自己設定權限和加密，我們也不一定要手動維護每一份 Secret YAML。

像 External Secrets Operator、HashiCorp Vault、AWS Secrets Manager、GCP Secret Manager、Azure Key Vault、Secrets Store CSI Driver、Sealed Secrets，都是這個話題裡常見的工具或服務，只是各自負責的事情不同。

例如，密碼可以放在 Vault 或雲端 Secret Manager，再由 External Secrets Operator 讀取，建立成 Kubernetes Secret，供 Pod 使用。[External Secrets Operator 官方文件](https://external-secrets.io/latest/)

```text
Vault / AWS Secrets Manager / GCP Secret Manager / Azure Key Vault
    ↓
External Secrets Operator
    ↓
Kubernetes Secret
    ↓
Pod
```

這樣就不需要把真正的密碼寫在 Git 裡，Git 可以只保存要從哪裡取得憑證的設定。不過同步進叢集後，那份 Secret 還是需要前面提到的權限與加密保護。

另一種方式是用 Secrets Store CSI Driver，把外部憑證直接掛載成 Pod 裡的檔案：

```text
Vault / Cloud Secret Manager
    ↓
Secrets Store CSI Driver + provider
    ↓
Pod filesystem
```

這種方式不一定會建立 Kubernetes Secret。如果應用需要 Secret，再另外開啟同步功能，而且要有 Pod 掛載對應的 CSI volume，才會觸發同步。[CSI 同步官方文件](https://secrets-store-csi-driver.sigs.k8s.io/topics/sync-as-kubernetes-secret)

Sealed Secrets 則是先把資料加密成 `SealedSecret`，讓它可以放進 Git，再由叢集裡的 Controller 解密，建立一般的 Kubernetes Secret。[Sealed Secrets 官方文件](https://github.com/bitnami/sealed-secrets)

所以這些工具並不是全部都靠 Kubernetes Secret 儲存資料，但 Secret 是它們接到 K8S 時常用的資源。把憑證放在 Secret，也就比較容易沿用這些工具。

至於常一起出現的 KMS，在 Kubernetes 靜態加密整合裡負責的是加密金鑰，和用來保存密碼、Token 的 Secret Manager 用途不同。

## 使用 Secret，不代表憑證已經安全

講到這裡，再回頭看這份 YAML。以下只是示範密碼：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: demo-credentials
type: Opaque
data:
  password: cGFzc3dvcmQ=
```

只要有支援 `base64` 指令的 shell，就能把密碼解出來：

```bash
printf '%s' 'cGFzc3dvcmQ=' | base64 -d
# 輸出：password
```

所以如果把含有真實憑證的 Secret YAML 直接 commit 到 Git，看得到檔案的人一樣能拿到密碼。改用 `stringData` 也沒有差別，它只是方便我們直接輸入明文的欄位。[Secret 官方文件](https://kubernetes.io/docs/concepts/configuration/secret/)

正式環境裡，還是得限制誰能讀取 Secret、設定靜態加密，並安排憑證輪替與存取稽核。使用 GitOps 的話，可以像前面那樣只保存外部憑證的參照，或使用適當加密後的資源。[Secret 安全實務](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 結論

回頭看這張謎因，我覺得容易搞混的地方，就是把「使用 Secret」和「密碼已經加密」當成同一件事。Secret 讓我們能把密碼和一般設定分開管理，也方便接上加密與外部憑證工具，但這些都需要實際設定。

所以密碼還是應該放在 Secret，只是不能做到這裡就覺得安全了。把密碼轉成 Base64 再丟進 Git，該洩漏的還是會洩漏。

如果想接著看外部憑證怎麼掛載與同步，可以參考我另一篇 [EKS Secrets Store CSI 同步問題與解法](/posts/eks-secrets-store-csi-sync-secret/)。

## 參考資料

- [Kubernetes 官方文件：Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Kubernetes 官方文件：ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes 官方文件：Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Kubernetes 官方文件：Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [External Secrets Operator 官方文件](https://external-secrets.io/latest/)
- [Secrets Store CSI Driver：Sync as Kubernetes Secret](https://secrets-store-csi-driver.sigs.k8s.io/topics/sync-as-kubernetes-secret)
- [Sealed Secrets 官方 GitHub 專案](https://github.com/bitnami/sealed-secrets)
- [本站文章：EKS Secrets Store CSI 同步問題與解法](/posts/eks-secrets-store-csi-sync-secret/)
