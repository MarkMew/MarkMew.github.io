---
layout: post
title: "AWS にログインした後に Switch Role を使う"
description: "本記事では、AWS Console の Switch Role（クロスアカウントでのロール切替）を解説し、Trust Relationship と Policy の設定方法を紹介します。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Role]
keywords: [IAM Role, Switch Role]
date: 2026-4-30
---

AWS Cloud Console へのログイン方法はいくつかあります。

root アカウントでログインする方法（非推奨）、

IAM User の認証情報でログインする方法、

SAML（例: Azure AD）連携でログインする方法、

AWS SSO でログインする方法です。

その中でも特に実務でよく使われる方法が 1 つあります。

まず 1 つの AWS アカウントにログインし、

その後 Switch Role を使って

別の AWS アカウントに切り替える方法です。

この記事では、この方式の考え方と

設定手順を紹介します。

## 図で見るログイン方式の違い

代表的な流れを簡略化すると、次のようになります。

```text
[Root / IAM User / SSO でログイン]
                 |
                 v
      [ソースアカウントの Console に入る]
                 |
            (Switch Role)
                 |
                 v
      [ターゲットアカウントの Role に切替]
                 |
                 v
         [ターゲット資源を操作]
```

結果だけを見ると、どの方式も「Console に入る」点は同じです。

ただし、権限設計の観点では意味が大きく異なります。

| 方式 | 利用する主体 | 長期利用の推奨 | 典型的な利用シーン |
| --- | --- | --- | --- |
| Root アカウント | Account Root User | いいえ | 初期設定、まれな緊急対応 |
| IAM User | 固定のユーザー資格情報 | 組織方針による | 小規模チーム、SSO 未導入 |
| SAML/SSO | 企業アイデンティティ基盤 | はい | 中〜大規模組織、集中管理 |
| Switch Role | ソースにログイン後ロール切替 | はい | クロスアカウント運用、本番分離 |

## なぜ必要なのか

多くのチームでは、本番環境を専用アカウントとして分離します。

普段は一般作業用アカウントで業務を行い、

本番対応が必要なときだけ Switch Role で入ります。

考え方としては、本番前の踏み台に近いです。

この構成には少なくとも 3 つの利点があります。

1. 高権限が長期間露出するリスクを下げられる
2. 日常利用の主体と本番責務を明確に分離できる
3. CloudTrail 監査で「誰がいつどのロールに切替えたか」を追いやすい

> 実務では、Switch 可能な Role を明確な境界として扱えます。
> 先に本人確認、次にロール許可、その後に機密資源へアクセス、という流れです。
{: .prompt-info}

## 設定手順

ここでは最も一般的なクロスアカウント構成を例にします。

1. ユーザーがソースアカウント（A）にログイン
2. ターゲットアカウント（B）で、A から Assume 可能な Role を作成
3. Console で Switch Role を使って B に切替

### 手順 1: ターゲット側で IAM Role を作成

ターゲットアカウント（B）で Role を作る際、

先に Permission Policy を定義します。

例として、CloudWatch Logs の参照と EC2 の参照のみ許可する Policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

### 手順 2: Trust Relationship を設定

次に、ターゲット側 Role の信頼ポリシーで、

ソースアカウント（A）の特定 IAM User/Role を許可します。

よくある例（ソース側 `ops-admin` Role を許可）:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<source_account_id>:role/ops-admin"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

より厳格にする場合は、MFA などの条件を追加できます。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<source_account_id>:role/ops-admin"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
```

### 手順 3: ソース側にも AssumeRole 権限を付与

ソースアカウント（A）のユーザー/ロールには、

ターゲット Role に対する `sts:AssumeRole` 権限が必要です。

これがないと切替できません。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<target_account_id>:role/<target_role_name>"
    }
  ]
}
```

### 手順 4: Console で Switch Role を実行

右上のアカウントメニューから `Switch role` を選び、

次を入力します。

1. Account ID（ターゲットアカウント）
2. Role name（ターゲットロール名）
3. Display name（識別しやすい表示名）

成功すると Console 右上の主体表示が切り替わり、

同じブラウザセッション内で別ロール権限を使っている状態になります。

## よくあるエラーと確認ポイント

### 1) AccessDenied: not authorized to perform sts:AssumeRole

多くは、ソース側に `sts:AssumeRole` 権限がない、

またはターゲット側 Trust Relationship の Principal が誤っているケースです。

### 2) Role は見えるのに切替できない

Account ID と Role name を再確認してください。

また、ターゲット側の Role なのか（ソース側同名 Role ではないか）も確認します。

### 3) 切替成功後に資源が見えない

ターゲット Role の Permission Policy が不足している、

あるいは参照 Region が違うことが多いです。

## ログイン方式の使い分け

簡易的な判断基準は次の通りです。

1. 学習用途や一時操作: IAM User（短期なら可）
2. チームの本番運用: SSO + Switch Role
3. 高機密アカウント（本番など）: 常時権限なし、必要時のみ Switch Role

実務で安定しやすい構成は、

SSO で本人認証を行い、

その後 Switch Role でアカウントと責務ごとに切替える形です。

## まとめ

Switch Role の価値は、単なるクロスアカウントの利便性だけではありません。

本質は、主体と権限を分離できる点にあります。

これにより、高リスク環境へのアクセスをより制御しやすくなります。

一言でまとめると:

普段は低権限で作業し、必要な時だけ対象ロールへ短時間切替える。

これが AWS マルチアカウント運用で非常に重要な実践です。

## 参考資料

1. AWS IAM User Guide - Switching to a role (console): https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-console.html
2. AWS IAM User Guide - Tutorial: Delegate access across AWS accounts using IAM roles: https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html
3. AWS IAM JSON policy elements reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html
