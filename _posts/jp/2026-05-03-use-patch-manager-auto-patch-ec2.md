---
layout: post
title: "Patch Manager で EC2 パッチを自動適用する"
description: "Session Manager の設定に続いて、Patch Manager を使用して EC2 インスタンスのパッチを自動的に定期スキャン・インストールする方法を解説します。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, EC2, IAM, SSM]
keywords: [AWS Systems Manager, Patch Manager, EC2, Auto Patching]
lang: ja
date: 2026-05-03 09:00:00 +0800
---

Session Manager を設定し、SSM Agent が稼働している状態まで来たら、

次は OS パッチの管理を自動化する番です。

それが `Patch Manager` です。

## Patch Manager とは

`Patch Manager` は AWS Systems Manager の一機能で、

複数の EC2 インスタンスに対して OS やアプリケーションパッチを

一元管理することができます。

主な機能：

1. パッチスキャン：利用可能なパッチを検出
2. パッチインストール：定期的または手動でパッチを適用
3. コンプライアンスレポート：フロート全体のパッチ状況を集約
4. 除外ルール：特定パッチをスキップ可能

手動で各サーバに SSH して更新する、

または自分で cron job を書くのと比べて、

Patch Manager の利点は：

1. ポリシーの一元管理
2. 監査ログとコンプライアンスレポート
3. 柔軟なスケジューリング（メンテナンスウィンドウ）
4. 失敗時の自動ロールバック

## 事前準備

Session Manager と同様に、以下が必要です：

1. EC2 が Session Manager の設定済み（IAM Role、Agent 稼働）
2. EC2 が SSM エンドポイントに到達可能
3. IAM Role が Patch Manager 権限を持つこと

## IAM Policy の設定

`AmazonSSMManagedInstanceCore` を既にアタッチしていれば、

Patch Manager 権限は含まれています。

より細かく制御したい場合は、以下のカスタムポリシーを追加できます：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:DescribeDocumentParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:document/AWS-RunPatchBaseline"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetAutomationExecution",
        "ssm:StartAutomationExecution",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:ListCommands"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:*:*:aws-patch-manager-*"
    }
  ]
}
```

通常 Patch Manager は追加の S3 やサービス権限は不要です。

カスタムパッチソースを使わない限りは。

## Patch Manager の動作モード

2 つの運用モードがあります：

1. **Scan Only**：スキャンのみ、パッチは適用しない
2. **Scan and Install**：スキャンして自動適用

実務では、まず Scan Only で数週間運用してから、

Scan and Install に切り替えるのが安全です。

## パッチスケジューリングの設定

### ステップ 1: Patch Baseline を作成

AWS Console で Systems Manager > Patch Manager > Patch Baselines へ。

新しい Baseline を作成：

1. 名前：例 `linux-standard`
2. OS：Linux または Windows を選択
3. Approval rules：
   - 特定分類のパッチを自動承認
   - 一般的な分類：`Security`、`Bugfix`、`Enhancement`
   - リリース後の承認遅延を設定可（例：7 日後に承認）

スキップしたいパッチがあれば、

Patch exceptions に追加します。

### ステップ 2: メンテナンスウィンドウを作成

Systems Manager から Maintenance Windows へ。

新しいメンテナンスウィンドウを作成：

1. 名前：例 `weekly-patch-sunday`
2. スケジュール：Cron 形式、例えば毎週日曜 2 時
   ```
   cron(0 2 ? * SUN *)
   ```
3. 継続時間：例えば 2 時間（バッファ時間）
4. タイムゾーン：運用タイムゾーンを選択

### ステップ 3: Patch Task を作成

メンテナンスウィンドウ内にタスクを追加：

1. Task type：`Run command`
2. Document：`AWS-RunPatchBaseline`
3. Service role：Patch Manager ロール
4. Targets：EC2 インスタンスを選択
   - タグ利用（例 `Environment: Production`）
   - Instance ID を直接指定
5. Parameters：
   - Operation：`Install`（スキャン + 適用）または `Scan`（スキャンのみ）
   - Baseline Override：複数 Baseline がある場合は指定

### ステップ 4: スケジュール実行を待機

Patch Manager は指定したメンテナンスウィンドウで実行します。

Patch Manager > Compliance でステータスを確認。

各 EC2 は以下のいずれかを表示：

- Compliant：全パッチ適用済み
- Non-compliant：未適用パッチあり
- Failed：実行失敗

## ベストプラクティス

### 1. Scan Only で始める

いきなり `Install` しないでください。

数週間 `Scan` で実行して、パッチリストが妥当かを検証してから

`Install` に切り替えましょう。

### 2. 環境ごとに Baseline を分ける

Dev、Staging、Prod で異なる Baseline を作成。

Production はより保守的なルール（2-4 週間遅延）、

Dev は積極的に。

### 3. Patch Group を使用

EC2 に `Patch Group` タグをつけて

異なる戦略を適用可能です。

### 4. 通知を設定

SNS や EventBridge と連携して

パッチ完了通知と監査ログを得ましょう。

基本的に EventBridge は Scan または Install 後の EC2 のステータス変化を捕捉し、

イベントを下流に送信します。

EventBridge + SNS の組み合わせで基本的な通知を配信できます。

ただし、パッチリスト、失敗原因などの詳細情報を含めたい場合は、

Lambda を追加して通知を加工・充実させてから SNS で送信するのが効果的です。

## トラブルシューティング

### 1) メンテナンスウィンドウ後、パッチが実行されない

確認事項：

1. EC2 の IAM Role に Patch 権限があるか
2. EC2 が Online か（`aws ssm describe-instance-information` で確認）
3. メンテナンスウィンドウの Target に該当 EC2 が含まれているか

### 2) パッチ実行が失敗した場合

よくある原因：

1. パッチが再起動を必要とするが、自動再起動が off
2. パッチがシステムと非互換
3. ディスク空き容量不足

Compliance の詳細ログを確認。

### 3) パッチ適用後、システムが不安定になった

Staging 環境で先にテストして

互換性問題を事前に検出しましょう。

### 4) 今回のパッチ実行をスキップしたい

メンテナンスウィンドウを一時停止するか、

該当 EC2 を Target から削除。

## まとめ

Patch Manager の核となる価値は：

各サーバに SSH して手動更新する必要がなく、

一元的なスケジューリング、レポート、監査ログが得られることです。

推奨ロールアウト：

1. Scan で現状把握
2. 非本番環境で Install をテスト
3. 段階的ポリシー設定（Dev / Staging / Prod）
4. Compliance レポートの継続監視

これにより堅牢な自動パッチガバナンスが実現します。

---

## 参考資料

1. AWS Patch Manager: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/patch-manager.html
2. AWS-RunPatchBaseline Document: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/documents-ssm-docs-run-command.html
3. Patch Baselines: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/patch-baselines.html
4. Maintenance Windows: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/maintenance-windows.html
