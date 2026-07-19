---
layout: post
title: "State Manager で EC2 設定を自動化管理"
description: "本記事では AWS Systems Manager の State Manager 機能を紹介し、Association を使って EC2 の望ましい状態を継続的に維持し、定期的なパスワード更新などの自動化タスクを実現する方法を解説します。"
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, SSM, State Manager]
keywords: [AWS State Manager, Run Command, EC2, Association, 自動化]
lang: ja
date: 2026-05-16
---

前回の記事では、`Run Command` を使って複数の EC2 に一括でコマンドを実行する方法を紹介しました。

しかし、特定の設定を「継続的に維持」したい場合や、「定期的にタスクを実行」したい場合、Run Command だけでは不便です。

そんな時に役立つのが `State Manager` です。

## State Manager とは

`State Manager` は AWS Systems Manager の機能の一つで、EC2 の「望ましい状態」を定義し、スケジュールやイベントトリガーで指定した SSM Document を自動実行して、その状態を維持できます。

簡単に言えば、State Manager は「スケジュール可能でバージョン管理できる Run Command」です。

## State Manager と Run Command の違い

| 特徴 | Run Command | State Manager |
|------|-------------|---------------|
| 実行方法 | 手動または EventBridge でスケジュール | Association 作成後に自動実行 |
| バージョン管理 | 標準では不可 | Association のバージョン管理が可能 |
| 実行履歴 | 実行ログを保持 | ログとコンプライアンス追跡を保持 |
| 対象管理 | 毎回指定が必要 | タグやリソースグループで動的選択 |
| 利用シーン | 単発・臨時タスク | 継続的・定期的タスク |

## State Manager のコア概念：Association

State Manager で作成する各自動化タスクは `Association`（関連付け）と呼ばれます。

Association には以下が含まれます：

1. **SSM Document**：実行するスクリプトやコマンド
2. **対象（Targets）**：適用する EC2 インスタンス
3. **スケジュール（Schedule）**：実行頻度
4. **パラメータ（Parameters）**：Document に必要な入力値

Association を作成すると、Systems Manager がスケジュールに従って自動実行し、各実行の状態を追跡します。

## 実例：EC2 パスワードの定期更新

例えば、毎月 Web サーバーのローカルアカウントのパスワードを自動で更新したい場合、State Manager を使うと EventBridge + Run Command より管理が簡単です。

### ステップ 1：SSM Document の準備

AWS 標準の `AWS-RunShellScript`（Linux）や `AWS-RunPowerShellScript`（Windows）を使うか、カスタム Document を作成します。

Linux で `webuser` のパスワードを更新する例：

```yaml
schemaVersion: '2.2'
description: Update webuser password
parameters:
  NewPassword:
    type: String
    description: New password for webuser
    noEcho: true
mainSteps:
  - action: aws:runShellScript
    name: updatePassword
    inputs:
      runCommand:
        - |
          echo 'webuser:{{NewPassword}}' | chpasswd
          echo "Password updated successfully"
```

### ステップ 2：Association の作成

AWS コンソールの場合：

1. **Systems Manager** > **State Manager** を開く
2. **Create association** をクリック
3. 上記のカスタム Document を選択
4. **Targets** で対象を選択：
   - 特定の Instance ID
   - またはタグで動的選択（例：`Environment=Production` かつ `Role=WebServer`）
5. **Schedule** を設定（例：`cron(0 2 1 * ? *)` は毎月1日午前2時）
6. **Parameters** に新しいパスワードを入力（Parameter Store/Secrets Manager 参照も可）
7. **Create association** をクリック

AWS CLI の場合：

```bash
aws ssm create-association \
  --name "UpdateWebUserPassword" \
  --document-name "Custom-UpdatePassword" \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "cron(0 2 1 * ? *)" \
  --parameters "NewPassword=SecurePass123!" \
  --association-name "MonthlyPasswordRotation"
```

### ステップ 3：実行状況の確認

Association 作成後、以下が確認できます：

- **Status**：Success / Failed / Pending
- **Last execution time**：最終実行時刻
- **Compliance status**：準拠しているインスタンス数

失敗時は詳細なエラーメッセージも確認可能です。

## Association のバージョン管理

State Manager の大きな利点はバージョン管理です。Association の設定（スケジュール・パラメータ・対象）を変更するたびに新しいバージョンが作成されます。

1. 過去バージョンの確認
2. 差分の比較
3. 以前のバージョンへのロールバック

大規模環境での変更追跡に非常に便利です。

## EventBridge + Run Command だけではダメ？

> EventBridge で Run Command を定期実行すれば十分では？

技術的には可能ですが、State Manager には以下の利点があります：

1. **統一管理画面**：すべてのスケジュールタスクを一箇所で確認可能
2. **バージョン管理**：Association 設定の変更履歴を追跡
3. **コンプライアンス追跡**：成功・失敗したインスタンス数を確認
4. **動的ターゲット**：タグに一致する新規 EC2 が自動的に対象に含まれる
5. **自動リトライ機能**：失敗した実行を自動的に再試行

単純なタスクなら EventBridge でも問題ありませんが、複雑・大規模な管理には State Manager の方が整理しやすいです。

## State Manager の主な利用例

### 1. セキュリティパッチの定期適用

```bash
aws ssm create-association \
  --name "AWS-RunPatchBaseline" \
  --targets "Key=tag:Environment,Values=Production" \
  --schedule-expression "cron(0 3 ? * SUN *)"
```

毎週日曜午前3時に Patch Manager を自動実行。

### 2. サービスの常時稼働監視

```yaml
mainSteps:
  - action: aws:runShellScript
    name: ensureServiceRunning
    inputs:
      runCommand:
        - |
          if ! systemctl is-active --quiet nginx; then
            systemctl start nginx
            echo "Nginx was down, restarted"
          else
            echo "Nginx is running"
          fi
```

30分ごとに Nginx の稼働を確認し、停止していれば自動起動。

### 3. 一時ファイルの定期削除

```bash
aws ssm create-association \
  --name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=i-1234567890abcdef0" \
  --schedule-expression "rate(7 days)" \
  --parameters 'commands=["find /tmp -type f -mtime +7 -delete"]'
```

/tmp 配下の7日以上前のファイルを毎週削除。

## Association 実行履歴の確認方法

### コンソール

1. **Systems Manager** > **State Manager** を開く
2. 対象 Association を選択
3. **Execution history** タブに切り替え
4. 実行時刻・状態・対象数を確認

### CLI

```bash
aws ssm describe-association-execution-targets \
  --association-id "<association-id>" \
  --execution-id "<execution-id>"
```

## トラブルシューティング

### 1. Association が Pending のまま

- SSM Agent が未接続
- IAM Role 権限不足
- スケジュール未到達

### 2. エラーが出ないのに失敗

- Document の構文確認
- パラメータの渡し方確認
- EC2 上の SSM Agent ログ確認：`/var/log/amazon/ssm/amazon-ssm-agent.log`

### 3. 今すぐ Association を実行したい

`apply-association-now` を利用：

```bash
aws ssm start-associations-once \
  --association-ids "<association-id>"
```

## Parameter Store との連携

Document でパスワード等の機密パラメータが必要な場合、Association に直接書かず、Parameter Store や Secrets Manager に保存しましょう。

例：

```bash
# まずパスワードを Parameter Store に保存
aws ssm put-parameter \
  --name "/app/webuser/password" \
  --value "SecurePass123!" \
  --type "SecureString"

# Association 作成時に参照
aws ssm create-association \
  --name "Custom-UpdatePassword" \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "NewPassword={{ssm:/app/webuser/password}}"
```

メリット：

1. 機密情報の一元管理
2. KMS で暗号化
3. IAM で細かくアクセス制御

## まとめ

State Manager は Systems Manager の強力な機能で、

1. EC2 の望ましい状態を定義・維持
2. バージョン管理で変更履歴を追跡
3. 動的ターゲットで新規インスタンスにも自動適用
4. 自動化タスクの状態を一元監視

Run Command や EventBridge 単体よりも、長期・定期タスクの管理に最適です。

まずはログ削除やサービス監視など簡単なシナリオから始め、徐々に複雑な自動化へ発展させましょう。

---

## 参考資料

1. AWS Systems Manager State Manager: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/systems-manager-state.html
2. State Manager の Association について: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/sysman-state-about.html
3. Association の作成（コンソール）: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/sysman-state-assoc.html
4. SSM Document 構文: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/documents-syntax.html
