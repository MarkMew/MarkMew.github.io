---
layout: post
title: "使用 Systems Manager 管理 AWS 上的 EC2"
description: "本文介紹 AWS Systems Manager 的核心功能與設定方式，示範如何讓 EC2 不開 SSH 也能安全遠端管理。"
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, IAM, SSM]
keywords: [AWS Systems Manager, Session Manager, EC2]
date: 2026-5-2
---

在做地端虛擬化管理的時候，

很常使用的兩套解決方式是 `VMWare` 和 `Hyper-V`，

透過 `vCenter Server` 或 `System Center Virtual Machine Manager` 就可以對虛擬化機器做資源的配置，

不過到了雲端，

是否還有這樣的管理方式呢？

答案是有，

但和地端管理的思維不太一樣。

在 AWS 上，這個服務就是 `Systems Manager`。

雲端環境雖然可以動態調整硬碟空間和虛擬機器規格，

這部分主要還是回到 EC2 本身，

但如果你要對政策、指令、系統狀況有更高能見度，

`Systems Manager` 會是非常實用的管理工具。

## 甚麼是 Systems Manager

`AWS Systems Manager` 可以協助你集中檢視、管理與大規模操作 AWS、內部部署與多雲環境的節點。

它不是單一功能，

而是一組管理工具的集合。

服務本身大多數功能沒有額外費用，

主要透過在機器上安裝 `SSM Agent` 與 AWS 互動。

實際成本通常來自於你搭配的其他服務，

例如 CloudWatch Logs、VPC Endpoint、KMS 等。

## Systems Manager 可以協助甚麼管理

Systems Manager 為一個 AWS 功能的泛稱，

大致可分為四個類別：

1. 營運管理
2. 應用程式管理
3. 變更管理
4. 節點管理

若以日常維運最常用的場景來看，

通常會先從下面三個功能開始：

1. Session Manager：不用開 SSH / RDP Port，就能進主機操作
2. Run Command：批次對多台主機下指令
3. Patch Manager：統一做修補程式盤點與安裝

## 使用前需要先準備什麼

要讓 EC2 進入可管理狀態，

至少需要滿足三件事：

1. EC2 綁定正確的 IAM Role（Instance Profile）
2. 主機可連到 Systems Manager 相關端點（TCP 443）
3. 主機上有正常執行的 `SSM Agent`

## 設定 IAM Role

### Trust Relationship

每台要被管理的 EC2 都需要綁定 IAM Role。

Trust Relationship 可使用以下內容：

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

IAM Policy 建議先直接套用 AWS Managed Policy：

`AmazonSSMManagedInstanceCore`

這是讓 EC2 能被 Systems Manager 管理的基本權限。

## 安裝與確認 Agent

### Linux

如果是使用 Amazon Linux 2 或 Amazon Linux 2023，通常已經預設安裝好 `SSM Agent`。

Ubuntu 通常也可安裝，

但剛釋出的新版 LTS 可能有短暫支援落差，

建議先看官方支援清單：[支援的作業系統和機器類型](https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/operating-systems-and-machine-types.html)

你可以先確認服務狀態：

```bash
sudo systemctl status amazon-ssm-agent
```

如果尚未啟用，可執行：

```bash
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
```

### Windows Server

Windows Server 的步驟相對單純：

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

另外 outbound 記得開啟 TCP 443，

這樣無論 EC2 走 Internet Gateway 或 NAT Gateway，

都能與 AWS 服務正常溝通。

## 隔離網段的 EC2 該如何設定

如果 EC2 在私有子網且無法連到外網（沒有 NAT / IGW），

你需要建立 Interface VPC Endpoint。

至少要有以下三個服務：

```
com.amazonaws.<region>.ssm
com.amazonaws.<region>.ssmmessages
com.amazonaws.<region>.ec2messages
```

另外記得：

1. Endpoint 的 Security Group 要允許來自 EC2 子網的 443
2. EC2 本身的 Security Group / NACL 也要允許到 Endpoint 的 443

## 怎麼實際使用 Session Manager 連線

### 透過 AWS Console

1. 打開 EC2 頁面
2. 選擇目標 Instance
3. 點選 `Connect`
4. 切到 `Session Manager` 分頁
5. 點 `Connect`

### 透過 AWS CLI

```bash
aws ssm start-session --target <instance-id>
```

如果透過 CLI 連線，

本機也要先安裝 Session Manager plugin。

### Session Manager 可以直接 scp 上傳嗎？

這點很重要：

單純使用 `aws ssm start-session` 只會開啟互動式 Shell，

本身不提供像 `scp` / `sftp` 這種檔案傳輸能力。

如果你原本是用 PEM Key `scp -i` 上傳檔案，

改成 Session Manager 後，建議用以下方式：

1. 最推薦：先上傳到 S3，再由 EC2 拉下來

```bash
# local -> S3
aws s3 cp ./app.tar.gz s3://<bucket>/transfer/app.tar.gz

# EC2 端再從 S3 下載
aws s3 cp s3://<bucket>/transfer/app.tar.gz /tmp/app.tar.gz
```

2. 需要保留 scp 習慣時：先做 SSM Port Forwarding，再透過本機 localhost 執行 scp

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["22"],"localPortNumber":["10022"]}'
```

接著在另一個 terminal：

```bash
scp -P 10022 ./app.tar.gz ec2-user@127.0.0.1:/tmp/
```

> 如果你是像這裡一樣，透過 Session Manager 轉送到「同一台 EC2 的 22 Port」，通常不需要在 EC2 Security Group 額外開放 inbound 22 給外部來源。
> 因為連線是先進 SSM 通道，再由節點上的 Agent 轉送到本機服務。
> 但要確認目標主機有啟動 SSH Server，且主機內部防火牆（例如 iptables / firewalld）沒有擋掉本機連線。
> 若你改成轉送到「其他主機」的服務，才需要檢查對方 Security Group / NACL inbound 是否允許。
{: .prompt-info}

第二種做法代表主機仍需有 SSH Server，

只是不用對外開 22 Port；

如果你的目標是完全不依賴 SSH，

那就優先用 S3 中轉會更單純。

## 如何確認主機已被 SSM 管理

你可以用下面指令確認節點是否 Online：

```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName,AgentVersion:AgentVersion}" \
  --output table
```

只要看到 `PingStatus` 是 `Online`，

基本上就代表 Agent、IAM、網路設定都已經正常。

## 常見錯誤與排查

### 1) TargetNotConnected

通常是下列問題之一：

1. IAM Role 沒有 `AmazonSSMManagedInstanceCore`
2. Agent 沒啟動或版本太舊
3. 網路不通（443 無法到 SSM 端點）

### 2) Console 看不到 Session Manager 頁籤

先確認你登入 Console 的身份本身有權限操作 `ssm:StartSession`。

### 3) 私網明明有 Endpoint 還是連不上

大多是 Endpoint Security Group 或 Network ACL 漏開 443，

另外也要確認 Route 與 DNS 設定正常。

## 小結

Systems Manager 最有價值的地方是：

你可以在不暴露 SSH / RDP Port 的前提下，

仍然對 EC2 做安全、可稽核、可批次的維運。

建議先把 Session Manager 導入日常流程，

接著再逐步擴展到 Run Command 與 Patch Manager。

---

## 參考資料

1. 什麼是 AWS Systems Manager？: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/what-is-systems-manager.html
2. Session Manager: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/session-manager.html
3. 管理型政策 AmazonSSMManagedInstanceCore: https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html
4. 建立 Systems Manager 的 VPC Endpoint: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/setup-create-vpc.html
5. 支援的作業系統和機器類型: https://docs.aws.amazon.com/zh_tw/systems-manager/latest/userguide/operating-systems-and-machine-types.html
