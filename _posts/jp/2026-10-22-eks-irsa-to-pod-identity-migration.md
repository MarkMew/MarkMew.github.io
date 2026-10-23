---
layout: post
title: "EKS の IRSA から Pod Identity への移行手順と判断ポイント"
description: "EKS の IRSA を Pod Identity に移行すべきかを整理し、Agent の導入、IAM ロールの信頼ポリシー、関連付けの作成、Pod での確認まで説明します。"
author: Mark_Mew
categories: [AWS, EKS]
tags: [AWS, EKS, IAM, Kubernetes]
keywords: [EKS IRSA Pod Identity 移行, EKS Pod Identity, Pod Identity Association, eks-pod-identity-agent, IAM ロール]
lang: ja
date: 2026-10-22
---

**EKS の IRSA を Pod Identity に移行する必要はあるのでしょうか。必須ではありません。** 現在の IRSA が安定しており、クラスターごとの OIDC プロバイダーや IAM ロールの信頼ポリシーの管理が負担になっていなければ、新しい方式という理由だけで切り替える必要はありません。複数クラスターでの設定を簡素化し、ServiceAccount と IAM ロールの対応を EKS 側で管理したい場合には、Pod Identity が選択肢になります。[AWS の Pod Identity 設定ガイド](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html)

IRSA は OIDC identity federation と STS の Web Identity を利用します。仕組みとしては、セルフマネージド Kubernetes やオンプレミス環境で認証を AWS IAM と連携する構成に近いものの、**IRSA 自体は EKS の機能**です。一方、Pod Identity は EKS 専用の AWS による統合で、EKS の関連付け、EKS Auth、ノード上の Agent を使って認証情報を提供します。設定を EKS に集約できる反面、EKS 固有の仕組みへの依存は増えます。[AWS の EKS における IAM ベストプラクティス](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)

移行する場合は、EKS Pod Identity Agent の導入、`pods.eks.amazonaws.com` を信頼する IAM ロールの設定、既存の namespace と ServiceAccount に対する関連付けの作成、IRSA annotation の削除、Pod の再作成という順序で進めます。S3 や Secrets Manager などへのアクセスを許可する既存の IAM 権限ポリシーは、通常そのまま利用できます。

以下では、EKS の EC2 ノードで動く `database-backup/database-backup-sa` を例にします。IRSA の設定については、[既存の記事](/posts/aws-eks-irsa-service-account-iam-role/)も参照してください。

## IRSA と Pod Identity の違い

| 項目 | IRSA | EKS Pod Identity |
|---|---|---|
| IAM ロールの信頼先 | クラスターの IAM OIDC プロバイダー | `pods.eks.amazonaws.com` |
| ServiceAccount の設定 | `eks.amazonaws.com/role-arn` annotation | namespace、ServiceAccount、ロールを結ぶ EKS の関連付け |
| 認証情報の取得 | Web Identity token と STS | Pod Identity Agent と EKS Auth |
| ノード側の構成 | Pod Identity Agent は不要 | 通常の EC2 ノードでは Agent が必要。EKS Auto Mode には組み込み済み |

Pod Identity のロールは特定クラスターの OIDC プロバイダーに紐づかないため、別のクラスターの関連付けでも再利用できます。ただし、**関連付けを作成するだけでは、既存の Pod は IRSA から切り替わりません**。IRSA 用の環境変数が残っていると、AWS SDK のデフォルト認証情報チェーンが IRSA を先に選ぶ場合があります。[AWS SDK の対応状況と認証情報チェーン](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html)

## 移行前に確認すること

クラスター名、リージョン、namespace、ServiceAccount、現在のロール ARN を控えます。また、アプリケーションが [Pod Identity に対応する AWS SDK](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html) とデフォルト認証情報チェーンを使っていることを確認してください。固定のアクセスキーや独自の credential provider は、関連付けだけでは切り替わりません。以下は通常の EKS EC2 ノードを対象とします。Fargate や特殊なノード環境では、事前に [Agent の要件](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)を確認してください。

コマンドは Bash の例です。値を環境に合わせて変更します。

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

## 1. Pod Identity Agent を導入する

まず `aws eks describe-addon --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent --region "$AWS_REGION"` で導入済みか確認します。通常の EC2 ノードで未導入の場合は、次を実行します。

```bash
aws eks create-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name eks-pod-identity-agent \
  --region "$AWS_REGION"

kubectl get daemonset -n kube-system eks-pod-identity-agent
```

ワークロードが稼働するノードで Agent が動いていることを確認してから、切り替えを進めます。Agent はノードの IAM ロールの権限を使用し、Agent 自身の IRSA ロールは使いません。EKS Auto Mode には Pod Identity が組み込まれているため、この add-on の追加は不要です。[Agent の導入ガイド](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-agent-setup.html)、[EKS add-on 一覧](https://docs.aws.amazon.com/eks/latest/userguide/workloads-add-ons-available-eks.html)

## 2. IAM ロールの信頼ポリシーを更新する

IRSA のロールはクラスターの OIDC プロバイダーを信頼し、`sts:AssumeRoleWithWebIdentity` を許可します。Pod Identity を使うには、既存の信頼ポリシーの `Statement` 配列に**次のステートメントを追加**します。

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

移行中は従来の OIDC ステートメントを残し、旧 Pod が IRSA を使えるようにします。S3 や Secrets Manager への権限ポリシーは、認証情報の取得方式を変えるだけなら修正不要です。CLI を使う場合は**信頼ポリシー全体**を取得して編集し、`aws iam update-assume-role-policy --role-name "$ROLE_NAME" --policy-document file://trust-policy.json` で更新します。上のステートメントだけで既存のポリシーを上書きしないでください。[AWS の信頼ポリシー例](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-association.html)

## 3. Pod Identity の関連付けを作成する

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

関連付けは EKS が管理するため、ServiceAccount に新しい annotation を付ける必要はありません。設定の反映には短い遅延が生じる場合があります。関連付けを確認してからワークロードを切り替えてください。[AWS CLI リファレンス](https://docs.aws.amazon.com/cli/latest/reference/eks/create-pod-identity-association.html)

## 4. IRSA annotation を削除し、Pod を再作成する

まず Helm chart、Kustomize、GitOps の ServiceAccount 定義から `eks.amazonaws.com/role-arn` を削除します。そうしないと、次のデプロイで元に戻る可能性があります。続いてクラスター上の ServiceAccount を更新します。

```bash
kubectl annotate serviceaccount "$SERVICE_ACCOUNT" \
  -n "$NAMESPACE" \
  eks.amazonaws.com/role-arn-
```

既存 Pod の環境変数やマウントは ServiceAccount の更新だけでは変わりません。Deployment の場合は Pod を再作成します。

```bash
kubectl rollout restart deployment/database-backup -n "$NAMESPACE"
kubectl rollout status deployment/database-backup -n "$NAMESPACE"
```

CronJob の場合は次の Job を待つか、確認用の Job を作成します。上の Deployment 用コマンドは CronJob には使用しません。

## 5. Pod が実際に使用する IAM ロールを確認する

**新しく作成された** Pod の環境変数を確認します。

```bash
kubectl exec -n "$NAMESPACE" <new-pod-name> -- \
  env | grep -E '^AWS_(CONTAINER_CREDENTIALS_FULL_URI|CONTAINER_AUTHORIZATION_TOKEN_FILE|ROLE_ARN|WEB_IDENTITY_TOKEN_FILE)='
```

`AWS_CONTAINER_CREDENTIALS_FULL_URI` と `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE` が表示され、IRSA 用の `AWS_ROLE_ARN` と `AWS_WEB_IDENTITY_TOKEN_FILE` がないことを確認します。さらに、**同じアプリケーションコンテナ内**で `aws sts get-caller-identity` を実行し、想定した assumed-role ARN が返るか確認します。AWS CLI が入っていない場合は、アプリケーションと同じ AWS SDK から STS を呼び出してください。最後に、必要な S3 や Secrets Manager の操作も試し、権限まで確認します。[Pod Identity の仕組み](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-how-it-works.html)

そのロールを共有するすべてのワークロードの移行が終わってから、古い OIDC の信頼ステートメントを削除します。他の ServiceAccount が IRSA を使っている可能性があり、クラスターの IAM OIDC プロバイダーにも別の用途があるかもしれません。

## よくある質問

### 関連付けを作成したのに、Pod が IRSA を使い続けるのはなぜですか？

annotation の削除、Pod の再作成、アプリケーションで別の認証情報を指定していないかを確認してください。関連付けだけでは、[AWS SDK の認証情報チェーン](https://docs.aws.amazon.com/eks/latest/userguide/pod-id-minimum-sdk.html)で先に見つかった認証情報は上書きされません。

### 既存の IAM ロールは使えますか？

使えます。権限ポリシーは残し、信頼ポリシーに `pods.eks.amazonaws.com` を追加します。複数の ServiceAccount で同じロールを使う場合は、同じ権限を与えてよいか確認してください。[AWS の IAM ベストプラクティス](https://docs.aws.amazon.com/eks/latest/best-practices/identity-and-access-management.html)

### IRSA に戻すにはどうすればよいですか？

古い OIDC の信頼ステートメントを残していれば、デプロイ設定に `eks.amazonaws.com/role-arn` annotation を戻し、Pod を再作成します。`get-caller-identity` と必要な AWS 操作を確認したうえで、関連付けを削除するか判断してください。

`eksctl` で管理しているクラスターでは、`eksctl utils migrate-to-pod-identity --cluster my-cluster` で移行計画を確認し、`--approve` を付けて適用する方法もあります。対象の ServiceAccount、add-on、信頼ポリシーの変更内容を事前に確認してください。[eksctl の移行ガイド](https://docs.aws.amazon.com/eks/latest/eksctl/pod-identity-associations.html)
