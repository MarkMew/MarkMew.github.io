---
layout: post
title: "Kubernetes Secret と ConfigMap の違い：Base64 は暗号化ではないのに、なぜ Secret を使う？"
image: https://fastly.picsum.photos/id/523/1200/630.jpg?hmac=eqnaeTHYrg6DamyKUBWUMQWNjCykDblhXWO7my-QSz4
description: "Kubernetes Secret は Base64 なのに、なぜパスワードを ConfigMap に入れてはいけないのか。RBAC、保存時の暗号化、外部のシークレット管理ツールとの連携から考えます。"
author: Mark_Mew
categories: [K8S]
tags: [K8S, Kubernetes, Secret, ConfigMap, RBAC]
keywords: [Kubernetes Secret ConfigMap 違い, Kubernetes Secrets, Base64 暗号化 違い, 認証情報 管理, etcd 保存時の暗号化, RBAC]
lang: ja
date: 2026-09-13
---

最近、パスワードを ConfigMap に保存している人をネタにした、K8S のミームを見かけました。

![パスワードを ConfigMap に保存することをネタにした Kubernetes のミーム](/assets/img/k8s_password_in_configmap_meme.png)

K8S の運用経験がある方なら、何を言いたいのかすぐにわかると思います。ただ、使い始めたばかりだと、どこが問題なのかピンとこないかもしれません。

ConfigMap に入れたパスワードは平文です。一方、Secret の `data` に入れると見た目は変わりますが、実際には Base64 に変換しただけです。

これでは暗号化したことにはなりません。それなのに、なぜパスワードは ConfigMap ではなく Secret に入れるのでしょうか。

考えてみると面白い疑問なので、今回はこの話を書いてみようと思います。

## Secret も Base64 なら、ConfigMap に入れてもよいのでは？

**Secret を使うと、パスワードと通常の設定を分けて RBAC で管理でき、保存時の暗号化や K8S のシークレット管理ツールとも組み合わせられます。** ただし、どれも設定が必要です。Secret を作っただけで、パスワードが自動的に暗号化されるわけではありません。[Kubernetes Secret の公式ドキュメント](https://kubernetes.io/docs/concepts/configuration/secret/)

YAML の Base64 だけを見ても、Secret を使うメリットはわかりにくいと思います。もう少し先の「誰が読めるのか」「etcd に保存するときに暗号化されるのか」「どんなツールで管理できるのか」まで見ていく必要があります。

## Secret と ConfigMap の違い

まずは両者を並べてみます。ConfigMap は通常の設定、Secret はパスワードやトークンなどの機密情報を入れるためのリソースです。ただ、機能には重なる部分もあり、RBAC や保存時の暗号化はどちらにも設定できます。[ConfigMap の公式ドキュメント](https://kubernetes.io/docs/concepts/configuration/configmap/)

| 比較項目 | ConfigMap | Secret |
| --- | --- | --- |
| 用途 | 通常の設定 | パスワード、トークン、鍵、証明書 |
| API 上のデータ形式 | `data` は平文の文字列、`binaryData` は Base64 | `data` は Base64、`stringData` では平文を入力可能 |
| etcd のデフォルトの暗号化 | Kubernetes では API 層の保存時暗号化はデフォルトで無効。クラスタの設定を確認する必要がある | Kubernetes では API 層の保存時暗号化はデフォルトで無効。クラスタの設定を確認する必要がある |
| Encryption at Rest | ✅ 設定可能 | ✅ 設定可能。公式でも有効化を推奨 |
| Kubernetes／ツールによる機密情報の扱い | 通常の設定として扱われるため、内容の非表示は期待できない | 機密情報向けのリソースとして追加の保護が行われる場合がある。ただし、すべてのツールが内容を隠すわけではない |
| RBAC による個別の制限 | ✅ 個別に権限を設定可能 | ✅ ConfigMap と分けて権限を設定可能。厳しい制限は別途設定が必要 |
| Secret Store／Vault／KMS との連携 | 認証情報の連携では主な対象ではない。KMS を使った保存時の暗号化は可能 | ✅ 外部の認証情報との連携でよく使われる。KMS を使った保存時の暗号化も可能 |
| `kubectl describe` などでの表示 | `kubectl describe configmap` はデータの内容を表示する | `kubectl describe secret` は通常、キーとサイズを表示する。ただし `kubectl get secret -o yaml` では Base64 の値を取得できる |

ここまで読んでも、「ConfigMap でも権限を制限できて、暗号化もできるなら、なぜ分けるの？」と思うかもしれません。データベースの設定を例にすると、少しわかりやすくなります。

## 1. Secret は RBAC で個別に管理できる

データベースへの接続トラブルを調べる人がいるとします。`DB_HOST` は確認したくても、`DB_PASSWORD` まで知る必要があるとは限りません。

両方を ConfigMap に入れていると、設定を読む権限を渡した時点でパスワードも見えてしまいます。`DB_PASSWORD` を Secret に分けておけば、ConfigMap だけを読めるようにできます。ServiceAccount に権限を付与する場合、Role のルールはたとえば次のようになります。

```yaml
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
```

ここには `secrets` が含まれていないので、このルールから Secret の読み取り権限は付与されません。設定の確認だけが必要なユーザーや Controller、ワークロードに、パスワードまで渡さずに済みます。

ただし、見落としやすい点があります。RBAC の権限は加算されます。別の RoleBinding や ClusterRoleBinding ですでに Secret を読む権限が付いていれば、このルールでその権限が取り消されるわけではありません。

Pod を作成できる権限にも注意が必要です。Pod を作れる人は、Secret をマウントして内容を読める可能性があります。また、Secret の `list` や `watch` でも内容を取得できるため、`get` だけを制限すればよいわけではありません。[Secret のアクセス制御に関する公式ガイド](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## 2. Secret は Kubernetes の Encryption at Rest と組み合わせられる

読み取り権限を設定したら、次はデータをどこに、どう保存するかという話です。

Secret の `data` は Base64 ですが、Kubernetes API Server に encryption provider を設定すれば、etcd に書き込む前にデータを暗号化できます。

```text
Kubernetes API Server
    ↓ Encryption Provider
暗号化された Secret のデータ
    ↓
etcd
```

**この Encryption at Rest（保存時の暗号化）は、元に戻すために鍵が必要な暗号化です。** YAML に表示される Base64 とは別の話です。

Kubernetes では、Secret に対する API 層の etcd 保存時暗号化はデフォルトでは有効になっていません。マネージドクラスタを使っている場合は、そのサービスの設定を確認してください。ConfigMap も暗号化の対象にできるので、`kind: Secret` だけを見て暗号化の有無を判断することはできません。[保存時の暗号化の公式ドキュメント](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

暗号化すれば誰にもパスワードを読まれなくなるかというと、どこから読むかによって変わります。

etcd の保存ファイルやスナップショットが流出した場合、鍵まで一緒に流出していなければ、暗号化が保護になります。一方、もともと `kubectl get secret -o yaml` を実行する権限がある人には、API Server はデコード可能な値を返します。暗号化と RBAC の両方が必要なのは、このためです。

実際に有効化するときは、既存データを再度書き込まないと暗号化が適用されない点も忘れずに。古いバックアップも自動的に暗号化されるわけではありません。[既存データの暗号化について](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)

## 3. K8S の多くのセキュリティツールが Secret と連携している

権限や暗号化を設定するだけでなく、Secret の YAML を一つひとつ手作業で管理する手間も減らせます。

External Secrets Operator、HashiCorp Vault、AWS Secrets Manager、GCP Secret Manager、Azure Key Vault、Secrets Store CSI Driver、Sealed Secrets などは、この話でよく出てくるツールやサービスです。ただし、それぞれ担当することは違います。

たとえば、パスワードは Vault やクラウドの Secret Manager に保存しておきます。External Secrets Operator がそこから取得し、Pod で使うための Kubernetes Secret を作る構成にできます。[External Secrets Operator の公式ドキュメント](https://external-secrets.io/latest/)

```text
Vault / AWS Secrets Manager / GCP Secret Manager / Azure Key Vault
    ↓
External Secrets Operator
    ↓
Kubernetes Secret
    ↓
Pod
```

これなら Git に本物のパスワードを書かず、取得先の設定だけを置けます。ただし、クラスタ内に同期された Secret には、先ほどの権限制限や暗号化が引き続き必要です。

もう一つの方法が Secrets Store CSI Driver です。外部の認証情報を、Pod 内のファイルとして直接マウントできます。

```text
Vault / Cloud Secret Manager
    ↓
Secrets Store CSI Driver + provider
    ↓
Pod 内のファイルシステム
```

この方法では、必ずしも Kubernetes Secret を作る必要はありません。アプリケーションが Secret を必要とするなら、別途同期を有効にします。その同期は、Pod が対応する CSI volume をマウントして初めて実行されます。[CSI の Secret 同期に関する公式ドキュメント](https://secrets-store-csi-driver.sigs.k8s.io/topics/sync-as-kubernetes-secret)

Sealed Secrets は、先にデータを暗号化して `SealedSecret` にし、Git に置けるようにする仕組みです。クラスタ内の Controller が復号して、通常の Kubernetes Secret を作成します。[Sealed Secrets の公式ドキュメント](https://github.com/bitnami/sealed-secrets)

つまり、これらのツールがすべて Kubernetes Secret にデータを保存するわけではありませんが、K8S と連携する際によく使われるリソースが Secret です。認証情報を Secret で扱うことで、こうしたツールも利用しやすくなります。

なお、同じ話題でよく出てくる KMS は、Kubernetes の保存時暗号化との連携では暗号鍵を管理します。パスワードやトークンを保存する Secret Manager とは役割が違います。

## Secret に入れただけで安心はできない

ここまでの話を踏まえて、もう一度この YAML を見てみます。以下のパスワードは説明用の例です。

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: demo-credentials
type: Opaque
data:
  password: cGFzc3dvcmQ=
```

`base64` コマンドが使えるシェルなら、次のように元のパスワードを取り出せます。

```bash
printf '%s' 'cGFzc3dvcmQ=' | base64 -d
# 出力：password
```

本物の認証情報を含む Secret YAML をそのまま Git にコミットすれば、ファイルを読める人はパスワードも取得できます。`stringData` に変えても同じです。これは平文で入力できるようにするためのフィールドにすぎません。[Secret の公式ドキュメント](https://kubernetes.io/docs/concepts/configuration/secret/)

本番環境では、Secret を読める人を制限し、保存時の暗号化を設定して、認証情報のローテーションやアクセスの監査も行う必要があります。GitOps であれば、先ほどのように外部の認証情報への参照だけを保存するか、適切に暗号化したリソースを使えます。[Secret のセキュリティに関する公式ガイド](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)

## おわりに

最初のミームに戻ると、混同しやすいのは「Secret を使うこと」と「パスワードが暗号化されていること」だと思います。Secret を使えば、パスワードを通常の設定と分けて管理でき、暗号化や外部の認証情報管理ツールとも連携できます。ただ、どれも実際に設定してこその話です。

なので、パスワードはやはり Secret に入れるべきですが、そこで安心して終わりにはできません。Base64 に変換して Git に置いただけなら、パスワードが漏れることに変わりはありません。

外部の認証情報をマウント・同期する具体例は、別の記事 [EKS Secrets Store CSI の同期問題と解決方法](/ja/posts/eks-secrets-store-csi-sync-secret/)で紹介しています。

## 参考資料

- [Kubernetes 公式ドキュメント：Secrets](https://kubernetes.io/docs/concepts/configuration/secret/)
- [Kubernetes 公式ドキュメント：ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
- [Kubernetes 公式ドキュメント：Good practices for Kubernetes Secrets](https://kubernetes.io/docs/concepts/security/secrets-good-practices/)
- [Kubernetes 公式ドキュメント：Encrypting Confidential Data at Rest](https://kubernetes.io/docs/tasks/administer-cluster/encrypt-data/)
- [External Secrets Operator 公式ドキュメント](https://external-secrets.io/latest/)
- [Secrets Store CSI Driver：Sync as Kubernetes Secret](https://secrets-store-csi-driver.sigs.k8s.io/topics/sync-as-kubernetes-secret)
- [Sealed Secrets 公式 GitHub リポジトリ](https://github.com/bitnami/sealed-secrets)
- [このブログの記事：EKS Secrets Store CSI の同期問題と解決方法](/ja/posts/eks-secrets-store-csi-sync-secret/)
