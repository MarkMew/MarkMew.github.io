---
layout: post
title: "AWS Systems Manager で EC2 を管理する"
description: "AWS Systems Manager の基本機能と設定手順を解説し、SSH ポートを開放せずに EC2 を安全にリモート管理する方法を紹介します。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, EC2, IAM, SSM]
keywords: [AWS Systems Manager, Session Manager, EC2]
date: 2026-5-2
lang: ja
---

オンプレ環境で仮想化基盤を管理する場合、

よく使われるのは `VMWare` や `Hyper-V` です。

`vCenter Server` や `System Center Virtual Machine Manager` を使えば、

仮想マシンのリソースを集中管理できます。

ではクラウドではどうでしょうか。

同じように集約管理は可能ですが、

オンプレとは少し運用の考え方が変わります。

AWS でその役割を担うのが `Systems Manager` です。

クラウドでは EC2 自体でスペック変更やストレージ拡張がしやすい一方、

運用ポリシー、実行コマンド、システム状態をまとめて可視化・統制したい場合は、

`Systems Manager` が非常に有効です。

## Systems Manager とは

`AWS Systems Manager` は、AWS 環境だけでなくオンプレやマルチクラウドを含むノードを、

一元的に可視化・管理・大規模運用するためのサービスです。

単一機能ではなく、

複数の管理機能をまとめたスイートです。

主要機能そのものに追加料金がかからないケースが多く、

各ノード上の `SSM Agent` を通じて AWS と連携します。

実際のコストは、

CloudWatch Logs、VPC Endpoint、KMS など周辺サービス側で発生することが多いです。

## Systems Manager で何ができるか

Systems Manager は大きく次の 4 分野に整理できます。

1. 運用管理
2. アプリケーション管理
3. 変更管理
4. ノード管理

日常運用でまず使われることが多いのは次の 3 つです。

1. Session Manager: SSH / RDP ポートを開放せずにサーバへ接続
2. Run Command: 複数台へコマンドを一括実行
3. Patch Manager: パッチ適用状況の把握と適用の統制

## 利用前に準備するもの

EC2 を Systems Manager 管理下に置くには、

最低でも次の 3 点を満たす必要があります。

1. EC2 に適切な IAM Role（Instance Profile）がアタッチされている
2. インスタンスが Systems Manager 関連エンドポイントへ TCP 443 で到達できる
3. インスタンス上で `SSM Agent` が正常に稼働している

## IAM Role の設定

### Trust Relationship

管理対象にする EC2 には IAM Role のアタッチが必要です。

Trust Relationship は次のように設定できます。

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### IAM Policy

IAM Policy はまず AWS 管理ポリシーを適用するのが安全です。

`AmazonSSMManagedInstanceCore`

これは EC2 を Systems Manager で管理するための基本権限です。

## Agent のインストールと確認

### Linux

Amazon Linux 2 / Amazon Linux 2023 では、`SSM Agent` は通常プリインストールされています。

Ubuntu でも基本的に利用可能ですが、

リリース直後の新しい LTS では一時的にサポートが追いつかないことがあるため、

事前に公式の対応一覧を確認してください: [サポートされている OS とマシンタイプ](https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/operating-systems-and-machine-types.html)

まずはサービス状態を確認します。

```bash
sudo systemctl status amazon-ssm-agent
```

必要なら有効化して起動します。

```bash
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
```

### Windows Server

Windows Server の手順は比較的シンプルです。

```powershell
[System.Net.ServicePointManager]::SecurityProtocol = 'TLS12'
$progressPreference = 'silentlyContinue'
Invoke-WebRequest `
    https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe `
    -OutFile $env:USERPROFILE\Desktop\SSMAgent_latest.exe
```

```powershell
Start-Process `
    -FilePath $env:USERPROFILE\Desktop\SSMAgent_latest.exe `
    -ArgumentList "/S"
```

```powershell
rm -Force $env:USERPROFILE\Desktop\SSMAgent_latest.exe
```

あわせて outbound の TCP 443 を許可してください。

EC2 が Internet Gateway 経由でも NAT Gateway 経由でも、

AWS サービスへ通信できる必要があります。

## 分離ネットワーク（プライベートサブネット）の場合

EC2 がプライベートサブネットにあり、外向き経路がない場合（NAT / IGW なし）は、

Interface VPC Endpoint の作成が必要です。

最低限必要なのは次の 3 つです。

```
com.amazonaws.<region>.ssm
com.amazonaws.<region>.ssmmessages
com.amazonaws.<region>.ec2messages
```

あわせて次を確認します。

1. Endpoint 側 Security Group で EC2 サブネットからの 443 を許可
2. EC2 側 Security Group / NACL でも Endpoint 宛て 443 を許可

## Session Manager での接続方法

### AWS Console から接続

1. EC2 画面を開く
2. 対象インスタンスを選択
3. `Connect` をクリック
4. `Session Manager` タブへ切り替え
5. `Connect` をクリック

### AWS CLI から接続

```bash
aws ssm start-session --target <instance-id>
```

CLI 接続する場合は、

ローカル端末に Session Manager plugin のインストールも必要です。

### Session Manager で scp アップロードは直接できる？

ここは誤解しやすいポイントです。

`aws ssm start-session` が提供するのは対話シェルであり、

`scp` / `sftp` のようなファイル転送機能は標準では持っていません。

従来 PEM Key の `scp -i` を使っていた場合は、

Session Manager へ移行後、次の方法が実務的です。

1. 推奨: いったん S3 にアップロードし、EC2 側で取得する

```bash
# local -> S3
aws s3 cp ./app.tar.gz s3://<bucket>/transfer/app.tar.gz

# EC2 側で S3 から取得
aws s3 cp s3://<bucket>/transfer/app.tar.gz /tmp/app.tar.gz
```

2. scp の運用を維持したい場合: SSM Port Forwarding を張って localhost 宛てに scp する

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["22"],"localPortNumber":["10022"]}'
```

続けて別ターミナルで実行します。

```bash
scp -P 10022 ./app.tar.gz ec2-user@127.0.0.1:/tmp/
```

> この例のように同一 EC2 の 22 番ポートへ転送する場合、通常は EC2 の Security Group で外部からの inbound 22 を追加で許可する必要はありません。
> 通信はまず SSM チャネルに入り、その後 Agent がノード内のローカルサービスへ転送します。
> ただし対象 EC2 で SSH Server が起動していること、またホスト内ファイアウォール（iptables / firewalld など）でブロックされていないことは確認が必要です。
> 別ホスト上のサービスへ転送する場合は、転送先ホスト側の Security Group / NACL inbound 設定を確認してください。
{: .prompt-info}

2 つ目の方法は、

ポート 22 を外部公開しないだけで、SSH Server 自体は必要です。

SSH 依存をなくしたい場合は、

S3 経由の転送を優先するほうが運用はシンプルです。

## SSM 管理状態の確認方法

次のコマンドで対象ノードが Online か確認できます。

```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName,AgentVersion:AgentVersion}" \
  --output table
```

`PingStatus` が `Online` なら、

Agent / IAM / ネットワークの基本設定は概ね正常です。

## よくあるエラーと切り分け

### 1) TargetNotConnected

主な原因は次のいずれかです。

1. IAM Role に `AmazonSSMManagedInstanceCore` が付与されていない
2. Agent が停止中、またはバージョンが古い
3. ネットワーク経路に問題があり 443 で SSM エンドポイントへ到達できない

### 2) Console に Session Manager タブが出ない

Console ログイン中のユーザー/ロールに `ssm:StartSession` 権限があるか確認してください。

### 3) Endpoint を作ってもプライベート EC2 が接続できない

Endpoint 側 Security Group または NACL で 443 が不足しているケースが多く、

あわせて Route / DNS の設定不備も確認対象です。

## まとめ

Systems Manager の大きな利点は、

SSH / RDP ポートを公開せずに、

EC2 を安全に・監査可能に・スケーラブルに運用できることです。

まずは Session Manager から導入し、

その後 Run Command、Patch Manager へ拡張していくのが現実的です。

---

## 参考資料

1. AWS Systems Manager とは: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/what-is-systems-manager.html
2. Session Manager: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/session-manager.html
3. AmazonSSMManagedInstanceCore 管理ポリシー: https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html
4. Systems Manager 用 VPC Endpoint の作成: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/setup-create-vpc.html
5. サポートされている OS とマシンタイプ: https://docs.aws.amazon.com/ja_jp/systems-manager/latest/userguide/operating-systems-and-machine-types.html
