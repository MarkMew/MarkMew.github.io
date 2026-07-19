---
layout: post
title: "EC2 でコマンドをオンデマンド実行する"
description: "Systems Manager の Session Manager 設定に続いて、Run Command を使って EC2 インスタンス上でコマンドを実行する方法を解説します。"
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, SSM]
keywords: [AWS Systems Manager, Run Command, EC2]
lang: ja
date: 2026-05-10
---

前回の記事では `Systems Manager` を使って EC2 に接続する方法を紹介しました。

Session Manager でシェルを開けるようになったら、

次に気になることといえば：

1台ずつログインしなくても、

AWS から直接コマンドを送れないのか、

というところではないでしょうか。

それを実現するのが `Run Command` です。

特に以下のような作業に向いています：

1. フリート全体のサービス状態を一括確認
2. 簡単な設定ファイルの配布
3. サービスやスケジュールジョブの再起動
4. OS レベルの問題を素早く修正

この記事では `Run Command` の権限設定、

Linux と Windows の違い、

そして最後に Windows で PowerShell を使ってローカルユーザーのパスワードを変更する実践例を紹介します。

## Run Command とは

`Run Command` は AWS Systems Manager のリモート実行機能です。

対象の EC2 インスタンスを選んで、

AWS が提供する Document を適用します。

代表的なものは以下の通りです：

1. `AWS-RunShellScript`
2. `AWS-RunPowerShellScript`
3. `AWS-RunPatchBaseline`

仕組みとしては、

Systems Manager が各ノードの `SSM Agent` にコマンドを届け、

Agent がホスト上で実行する流れです。

そのため、

最初に確認すべきはコマンドの内容ではなく、

権限が正しく設定されているかどうかです。

## 使用前の準備

Session Manager と同様に、

EC2 で Run Command を使うには少なくとも 4 つの条件を満たす必要があります：

1. EC2 に正しい IAM ロールが割り当てられている
2. ホスト上で `SSM Agent` が正常に動作している
3. ホストが Systems Manager 関連エンドポイントに TCP 443 で接続できる
4. コマンドを送る人またはシステム自体にも十分な IAM 権限がある

最初の 3 つは「ノードを管理可能にする」前提条件です。

4 番目は「誰がコマンドを発行できるか」という前提です。

4 番目は見落としがちで、

EC2 は Online なのにコマンドが失敗する、

という場合はたいていここが原因です。

## 権限設定

権限は 2 つの観点で考えます：

1. EC2 インスタンスロールの権限
2. 操作者の IAM ユーザー / ロールの権限

### EC2 インスタンスロール

まずは `AmazonSSMManagedInstanceCore` を EC2 に割り当てます。

この AWS マネージドポリシーには、ノードが Systems Manager に登録し、

コマンドを受け取り、実行結果を返すために必要な基本権限が含まれています。

スクリプトが他の AWS サービスにアクセスする場合、たとえば：

1. S3 からスクリプトをダウンロードする
2. CloudWatch Logs に書き込む
3. Secrets Manager からシークレットを取得する

これらの権限は EC2 インスタンスロールに別途追加する必要があります。

`AmazonSSMManagedInstanceCore` はあくまでノードを管理可能にするだけで、

スクリプト内で使用するすべての AWS リソースへのアクセス権限を付与するわけではありません。

### 操作者の IAM 権限

コマンドを送る人またはシステムには、最低限以下の権限が必要です：

1. `ssm:SendCommand`
2. `ssm:GetCommandInvocation`
3. `ssm:ListCommandInvocations`
4. `ssm:ListCommands`

AWS コンソールから操作する場合は、通常これらも必要になります：

1. `ssm:DescribeInstanceInformation`
2. `ssm:ListDocuments`
3. `ssm:DescribeDocument`

以下はシンプルなポリシーの例です：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:ListCommands",
        "ssm:DescribeInstanceInformation",
        "ssm:ListDocuments",
        "ssm:DescribeDocument"
      ],
      "Resource": "*"
    }
  ]
}
```

より厳密に制御したい場合は、

`Resource` を特定の Document や EC2 タグの範囲に絞り込めます。

Run Command はリモート実行そのものなので、

最初から `AdministratorAccess` を与えることは避けてください。

権限が広すぎると、ホストに対して非常に強い操作能力を与えることになります。

## Linux と Windows の違いを先に整理する

ここは重要なポイントです。

同じ「Run Command」という名前でも、

Linux と Windows では「設定」と「実行」の面で明確な違いがあります。

### 1. Document が異なる

Linux では通常：

`AWS-RunShellScript`

Windows では通常：

`AWS-RunPowerShellScript`

Linux にはシェルコマンドを送り、

Windows には PowerShell コマンドを送ります。

### 2. 実行ユーザーが異なる

Linux では、`SSM Agent` はデフォルトで `root` としてコマンドを実行します。

Windows では、`SSM Agent` はデフォルトで `NT AUTHORITY\SYSTEM` としてコマンドを実行します。

これが直接影響するのは 2 点です：

1. `sudo` が必要かどうか
2. ユーザースコープのリソースにアクセスできるかどうか

Linux では通常すでに `root` なので、

ほとんどのケースで `sudo` は不要です。

Windows では `SYSTEM` は非常に高い権限を持ちますが、

対話型ログインのユーザーではないため、

ユーザープロファイル、デスクトップセッション、マップドドライブ、

一部の証明書ストアに関連する操作は、

RDP でログインしたときと同じように動作するとは限りません。

### 3. 追加権限の補い方が異なる

Linux でシステムファイルの変更、サービスの確認、デーモンの再起動だけなら、

ノードが SSM に管理されていれば通常は十分です。

Windows でローカルアカウント、サービスアカウント、レジストリ、

スケジュールタスクを操作する場合は、

Run Command で実行できること自体に加えて、

その操作が `SYSTEM` による直接処理を許可しているかどうかも確認が必要です。

この記事の最後にあるパスワード変更の例で言えば、

PowerShell でローカルアカウントのパスワードを変更することは可能ですが、

ドメインアカウントのパスワード変更は別の方法が必要です。

### 4. スクリプトの形式とエスケープ処理が異なる

Linux では一般的に：

```bash
systemctl restart nginx
cat /etc/os-release
```

Windows では一般的に：

```powershell
Restart-Service W32Time
Get-ComputerInfo
```

引用符、変数、複数行のスクリプトの扱いも PowerShell と Bash では異なります。

そのため、Linux と Windows で同じスクリプトを使い回そうとせず、

それぞれ別のスクリプトを管理することを推奨します。

## プラットフォーム別の注意点

### Linux で気をつけること

1. 対象ホストにサポートされたシェル環境があることを確認する
2. ファイルパス、権限モデル、サービス管理がそのディストリビューションと互換性があることを確認する
3. スクリプトが `jq`、`aws`、`python3` などの外部ツールに依存している場合は事前にインストールされていることを確認する

たとえばサービス状態を確認するには：

```bash
systemctl status amazon-ssm-agent --no-pager
```

ホームディレクトリを必要とするコマンドを実行する場合は、

実行者が `ec2-user` や普段ログインするアカウントではなく `root` であることに注意してください。

### Windows で気をつけること

1. 対象ホストに PowerShell 実行環境があること
2. 新しい Cmdlet を使う場合は Windows Server バージョンと PowerShell バージョンの互換性を確認する
3. 対話型デスクトップセッションが必要な操作は Run Command には向いていない

たとえば SSM Agent のサービス状態を確認するには：

```powershell
Get-Service AmazonSSMAgent
```

ローカルユーザーアカウントの管理機能を使う場合は、

`Microsoft.PowerShell.LocalAccounts` モジュールが利用できるか確認してください。

使えない場合は `net user` にフォールバックする必要があります。

## Run Command の実際の送り方

### AWS コンソールから

1. Systems Manager を開く
2. `Run Command` に移動する
3. `Run command` をクリックする
4. Document を選択する
5. 対象の EC2 を選ぶ（Instance ID またはタグで指定）
6. コマンド内容を入力する
7. 送信後、実行結果を確認する

### AWS CLI から

Linux にシェルスクリプトを送る場合：

```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=i-0123456789abcdef0" \
  --parameters 'commands=["uname -a","id","systemctl status amazon-ssm-agent --no-pager"]'
```

Windows に PowerShell を送る場合：

```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets "Key=instanceids,Values=i-0123456789abcdef0" \
  --parameters 'commands=["Get-ComputerInfo | Select-Object WindowsProductName,OsVersion","Get-Service AmazonSSMAgent"]'
```

Windows の PowerShell から AWS CLI を呼び出す場合は、

クォートとエスケープがより複雑になります。

コマンド内容は変数にまとめるかファイルから読み込むようにして、

コマンドライン上でエスケープが連鎖するのを避けることをお勧めします。

## Windows 編：PowerShell でユーザーパスワードを変更する

以下は Windows Server のローカルアカウントを使った例です。

この例のスコープを先に明確にしておきます：

1. Windows ローカルユーザーのパスワードを変更する
2. AD ドメインアカウントのパスワード変更ではない
3. コマンドは Run Command の `AWS-RunPowerShellScript` 経由で実行される

### 方法 1：`Set-LocalUser` を使う

Windows Server で `LocalAccounts` モジュールが使える場合：

```powershell
$userName = "app-user"
$plainPassword = "ChangeMe_2026!"
$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

Set-LocalUser -Name $userName -Password $securePassword
Write-Output "Password changed for local user: $userName"
```

このスニペットは `AWS-RunPowerShellScript` の `commands` パラメーターにそのまま渡せます。

### 方法 2：`net user` を使う

`Set-LocalUser` が使えない環境では従来の方法にフォールバックできます：

```powershell
net user app-user "ChangeMe_2026!"
```

ローカルアカウントのパスワード変更は可能ですが、

パスワード文字列がコマンドライン上にそのまま現れるため、

可読性とその後の保護の面では劣ります。

### Run Command で送る完全な例

```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets "Key=instanceids,Values=i-0123456789abcdef0" \
  --comment "Rotate local Windows password" \
  --parameters 'commands=["$userName = \"app-user\"","$plainPassword = \"ChangeMe_2026!\"","$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force","Set-LocalUser -Name $userName -Password $securePassword","Write-Output \"Password changed for local user: $userName\""]'
```

## この例で注意すべきリスク

ここでは意図的に最もわかりやすい方法で示しましたが、

すでに気づいていることがあるはずです：

パスワードがコマンドの内容に直接含まれています。

本番環境ではこれは通常十分に安全ではありません。

以下の場所にパスワードが残る可能性があるためです：

1. コマンド履歴
2. Run Command の実行ログ
3. 監査やデバッグ用の画面

本番でこの操作を行う場合の適切なフローは：

1. 安全な外部ソースから新しいパスワードを生成する
2. Run Command でパスワード変更を実行する
3. 変更後にパスワードを安全に保存するか後続プロセスをトリガーする

## コマンドの実行確認

Systems Manager の実行履歴で結果を確認できますが、

CLI からも確認できます：

```bash
aws ssm list-command-invocations \
  --command-id <command-id> \
  --details
```

特定のインスタンスの結果だけを確認する場合：

```bash
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instance-id>
```

確認すべき主なフィールド：

1. `Status`
2. `StandardOutputContent`
3. `StandardErrorContent`

### 成功の判断もプラットフォームによって少し異なる

Linux では通常、終了コードと stdout/stderr を確認します。

Windows では終了コードに加えて、

PowerShell がエラーを握りつぶしていないかにも注意が必要です。

より厳格なエラー検出が必要な場合は、スクリプトの先頭に以下を追加してください：

```powershell
$ErrorActionPreference = "Stop"
```

これにより、Cmdlet がエラーになると Run Command 全体が失敗状態になるため、

途中でエラーが発生しているのに表面上は成功しているように見える、

という状況を防げます。

## よくある問題

### 1) インスタンスは Online なのに Run Command が失敗する

確認事項：

1. 操作者に `ssm:SendCommand` があるか
2. Document が正しく選ばれているか（Linux に PowerShell、Windows にシェルを送っていないか）
3. スクリプト内で使用する AWS リソースへの権限が補われているか

### 2) Linux で手動ログインなら実行できるのに Run Command では失敗する

よくある原因：

1. 手動では `ec2-user` でログインしているが、Run Command は `root` で実行される
2. ユーザー固有の環境変数、PATH、ホームディレクトリが異なる
3. 対話型シェルセッションでのみ読み込まれる設定ファイルに依存している

### 3) Windows でコマンドは成功しているが期待通りの結果にならない

よくある原因：

1. 特定のログインユーザーとして実行されると思っていたが、実際は `SYSTEM` で実行されている
2. 対話型デスクトップセッションが必要な操作は Run Command には適さない
3. 必要な PowerShell バージョンやモジュールが存在しない

## まとめ

`Run Command` の価値は、

各ホストに個別にログインしなくても、

コマンドを一元的に発行し、結果を収集し、監査ログを残せることです。

ただし、単なるリモートシェルのラッパーではなく、

本質は権限モデルにあります。

Linux と Windows では Document、実行ユーザー、スクリプト形式が異なり、

これを事前に理解していないと必ずつまずきます。

## 宿題

Run Command で Windows ローカルアカウントのパスワードを変更できるようになったら、

次の問いを考えてみてください：

変更した後、新しいパスワードをどこに安全に保存するか？

考え方のヒントは 2 つあります：

1. シークレットを `Secrets Manager` に安全に書き込む
2. `SNS` でイベントを発行して後続プロセスに保存や通知を委ねる

ただし重要な点として、

`SNS` は通知やワークフローのトリガーに向いており、

平文パスワードをそのまま保存するためのものではありません。

「パスワード自体を安全に保存する」という目的であれば、

通常は `Secrets Manager` が適切な選択肢です。
