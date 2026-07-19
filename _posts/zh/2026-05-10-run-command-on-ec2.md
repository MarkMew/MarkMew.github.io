---
layout: post
title: "按需在 EC2 上執行指令"
description: "本文承接 Systems Manager 的 Session Manager 設定，進一步介紹如何在 EC2 上執行 Command。"
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, SSM]
keywords: [AWS Systems Manager, Run Command, EC2]
lang: zh-TW
date: 2026-05-10
---

上一篇介紹了如何透過 `Systems Manager` 連進 EC2，

如果你已經可以用 Session Manager 開 Shell，

下一步通常就是想問：

能不能不要一台一台登入，

直接從 AWS 對主機下指令？

答案就是 `Run Command`。

它很適合做這幾類事情：

1. 批次檢查服務狀態
2. 發布簡單設定檔
3. 重啟服務或排程工作
4. 臨時修正某個作業系統層級問題

這篇就來看 `Run Command` 的權限設定方式、

Linux 與 Windows 的差異，

以及最後用 Windows 實際示範如何透過 PowerShell 變更本機使用者密碼。

## Run Command 是什麼

`Run Command` 是 AWS Systems Manager 底下的遠端執行功能。

你可以選擇一批 EC2，

然後套用 AWS 提供的 Document，

例如：

1. `AWS-RunShellScript`
2. `AWS-RunPowerShellScript`
3. `AWS-RunPatchBaseline`

本質上，

它是由 Systems Manager 把指令送給節點上的 `SSM Agent`，

再由 Agent 在主機上執行。

也因為如此，

真正要先確認的不是指令內容，

而是權限有沒有設對。

## 使用前需要先準備什麼

和前一篇 Session Manager 一樣，

要讓 EC2 能吃到 Run Command，

至少要確認四件事：

1. EC2 已綁定正確 IAM Role
2. 主機上的 `SSM Agent` 正常運作
3. 主機可連到 Systems Manager 相關端點（TCP 443）
4. 發送指令的人或系統本身也有足夠 IAM 權限

前面三項是「節點可被管理」的前提，

第四項則是「誰可以下命令」的前提。

很多人會漏掉第四項，

結果 EC2 明明 Online，

但操作的人沒有權限送出指令。

## 權限設定

權限可以拆成兩塊看：

1. EC2 Instance Role 的權限
2. 操作者 IAM User / Role 的權限

### EC2 Instance Role

EC2 端最基本還是先綁 `AmazonSSMManagedInstanceCore`。

這份 AWS Managed Policy 已經包含節點向 Systems Manager 註冊、

接收命令、回報執行結果所需的核心權限。

如果你的指令裡還會額外存取其他 AWS 服務，

例如：

1. 從 S3 下載腳本
2. 寫入 CloudWatch Logs
3. 讀取 Secrets Manager

那就要額外把對應權限加在 EC2 的 Instance Role 上。

也就是說，

`AmazonSSMManagedInstanceCore` 只負責讓機器能被管理，

不代表它已經有權限存取你腳本中會用到的所有 AWS 資源。

### 操作者 IAM 權限

除了 EC2 自己要有權限，

送出 Run Command 的人也要有至少以下能力：

1. `ssm:SendCommand`
2. `ssm:GetCommandInvocation`
3. `ssm:ListCommandInvocations`
4. `ssm:ListCommands`

如果你是從 AWS Console 操作，

通常還會一起需要：

1. `ssm:DescribeInstanceInformation`
2. `ssm:ListDocuments`
3. `ssm:DescribeDocument`

下面是一份偏精簡的示意 Policy：

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

如果你要更嚴格控管，

可以把 `Resource` 限制在特定 Document 與特定 EC2 Tag 範圍。

實務上不建議一開始就全部放到 `AdministratorAccess`，

因為 Run Command 本質上就是遠端執行。

一旦開太大，

等於給了很高的主機操作能力。

## Linux 和 Windows 的差異要先講清楚

這一段很重要。

因為你雖然都叫它 Run Command，

但 Linux 和 Windows 在「設定」與「執行」上其實都有明顯差異。

### 1. Document 不同

Linux 通常使用：

`AWS-RunShellScript`

Windows 通常使用：

`AWS-RunPowerShellScript`

也就是說，

Linux 送的是 shell 指令，

Windows 送的是 PowerShell 指令。

### 2. 執行身分不同

Linux 上，`SSM Agent` 預設會以 `root` 執行命令。

Windows 上，`SSM Agent` 預設會以 `NT AUTHORITY\SYSTEM` 執行命令。

這會直接影響兩件事：

1. 你是否還需要 `sudo`
2. 指令能不能碰到某些使用者層級資源

在 Linux，

因為通常已經是 `root`，

多數情境下不需要再加 `sudo`。

在 Windows，

雖然 `SYSTEM` 權限非常高，

但它不是互動式登入的普通使用者，

所以和使用者 Profile、桌面、映射磁碟機、某些憑證內容有關的行為，

不能假設會和你 RDP 登入時完全一樣。

### 3. 權限需求的補充不同

Linux 如果你只是改系統檔、查服務、重啟 daemon，

通常只要節點已被 SSM 管理即可。

Windows 如果你要做的是本機帳號、服務帳號、登錄檔、排程工作等設定，

除了 Run Command 本身可執行外，

還要考慮該操作是否允許 `SYSTEM` 直接處理。

以這篇最後的密碼變更範例來說，

在 Windows 上用 PowerShell 變更本機帳號密碼是可行的，

但如果你改的是網域帳號，

就不是同一套做法。

### 4. 指令格式與跳脫字元不同

Linux 常見是：

```bash
systemctl restart nginx
cat /etc/os-release
```

Windows 常見是：

```powershell
Restart-Service W32Time
Get-ComputerInfo
```

如果你的腳本包含引號、變數或多行內容，

PowerShell 與 Bash 的處理方式也不同。

這就是為什麼我會建議：

不要用同一套文字硬塞 Linux 和 Windows，

而是分開維護兩份指令內容。

## Linux 與 Windows 的設定差異

為了避免混淆，

下面直接分開說。

### Linux 要注意什麼

1. 確認目標主機有支援的 shell 環境
2. 確認檔案路徑、權限模型、服務管理方式是 Linux 版本相容的
3. 若指令依賴外部工具，例如 `jq`、`aws`、`python3`，要先確認已安裝

例如你想查服務狀態，

可以送出：

```bash
systemctl status amazon-ssm-agent --no-pager
```

如果你在 Linux 上執行需要使用者家目錄的指令，

也要注意現在執行者是 `root`，

不是 `ec2-user` 或你平常登入的帳號。

### Windows 要注意什麼

1. 目標主機要有 PowerShell 執行環境
2. 若使用較新 Cmdlet，要確認 Windows Server 版本與 PowerShell 版本支援
3. 如果操作依賴使用者互動桌面，Run Command 通常不適合

例如你想查 SSM Agent 服務狀態，

可以送出：

```powershell
Get-Service AmazonSSMAgent
```

如果你用到本機使用者帳號管理功能，

也要先確認該主機版本有 `Microsoft.PowerShell.LocalAccounts` 模組，

否則可能需要改用 `net user`。

## 怎麼實際送出 Run Command

### 透過 AWS Console

1. 打開 Systems Manager
2. 進入 `Run Command`
3. 點選 `Run command`
4. 選擇 Document
5. 選擇目標 EC2（可以用 Instance ID 或 Tag）
6. 填入指令內容
7. 送出後查看執行結果

### 透過 AWS CLI

Linux 送 shell script 時：

```bash
aws ssm send-command \
	--document-name "AWS-RunShellScript" \
	--targets "Key=instanceids,Values=i-0123456789abcdef0" \
	--parameters 'commands=["uname -a","id","systemctl status amazon-ssm-agent --no-pager"]'
```

Windows 送 PowerShell 時：

```bash
aws ssm send-command \
	--document-name "AWS-RunPowerShellScript" \
	--targets "Key=instanceids,Values=i-0123456789abcdef0" \
	--parameters 'commands=["Get-ComputerInfo | Select-Object WindowsProductName,OsVersion","Get-Service AmazonSSMAgent"]'
```

如果你是從 Windows 本機用 PowerShell 呼叫 AWS CLI，

JSON 和引號跳脫會再麻煩一點，

建議把指令內容先整理成檔案或用變數組起來，

避免在命令列上一路逃脫到看不懂。

## 以 Windows 為例：透過 PowerShell 更換使用者密碼

下面用 Windows Server 本機帳號示範。

先講清楚這個例子的範圍：

1. 這是變更 Windows 本機使用者密碼
2. 不是變更 AD 網域帳號密碼
3. 指令由 Run Command 透過 `AWS-RunPowerShellScript` 執行

### 做法 1：使用 `Set-LocalUser`

如果你的 Windows Server 支援 `LocalAccounts` 模組，

可以用下面的 PowerShell：

```powershell
$userName = "app-user"
$plainPassword = "ChangeMe_2026!"
$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

Set-LocalUser -Name $userName -Password $securePassword
Write-Output "Password changed for local user: $userName"
```

這段可以直接放進 `AWS-RunPowerShellScript` 的 commands 參數。

### 做法 2：使用 `net user`

如果你的環境沒有 `Set-LocalUser`，

可以退回比較傳統的方式：

```powershell
net user app-user "ChangeMe_2026!"
```

這種方式也能改本機帳號密碼，

但因為是直接把密碼字串放進命令列，

閱讀性與後續保護性都比較差。

### 在 Run Command 中送出的範例

```bash
aws ssm send-command \
	--document-name "AWS-RunPowerShellScript" \
	--targets "Key=instanceids,Values=i-0123456789abcdef0" \
	--comment "Rotate local Windows password" \
	--parameters 'commands=["$userName = \"app-user\"","$plainPassword = \"ChangeMe_2026!\"","$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force","Set-LocalUser -Name $userName -Password $securePassword","Write-Output \"Password changed for local user: $userName\""]'
```

## 這個範例要特別注意的風險

這裡故意先用最直觀的方法示範，

但你應該已經注意到一件事：

密碼直接出現在指令內容裡了。

這在正式環境通常不夠安全，

因為它可能出現在：

1. 指令歷程
2. Run Command 執行紀錄
3. 稽核或除錯畫面

所以真正在 Production 做這件事時，

比較合理的做法通常是：

1. 由外部安全來源產生密碼
2. Run Command 執行密碼變更
3. 變更後把密碼安全保存或觸發後續流程

## 如何確認指令有成功執行

你可以到 Systems Manager 的執行紀錄看結果，

也可以用 CLI 查：

```bash
aws ssm list-command-invocations \
	--command-id <command-id> \
	--details
```

如果只想看單一 instance 的結果：

```bash
aws ssm get-command-invocation \
	--command-id <command-id> \
	--instance-id <instance-id>
```

重點要看：

1. `Status`
2. `StandardOutputContent`
3. `StandardErrorContent`

### Linux 和 Windows 的成功判斷也有點不同

Linux 上常見是看 exit code 與 stdout/stderr。

Windows 上除了 exit code，

也要留意 PowerShell 有沒有把錯誤吞掉。

如果你需要更嚴格的失敗判斷，

可以在腳本開頭加上：

```powershell
$ErrorActionPreference = "Stop"
```

這樣一旦 Cmdlet 出錯，

整個 Run Command 會比較容易直接失敗，

不會表面看起來成功，

實際上中途有錯沒被攔到。

## 常見問題

### 1) 為什麼 instance 是 Online，但 Run Command 還是失敗

先檢查：

1. 操作者有沒有 `ssm:SendCommand`
2. Document 有沒有選對（Linux 不要送 PowerShell，Windows 不要送 Shell）
3. 指令中用到的 AWS 資源權限有沒有補齊

### 2) Linux 上明明手動登入可執行，Run Command 卻失敗

常見原因是：

1. 你手動登入用的是 `ec2-user`，但 Run Command 實際上是 `root`
2. 使用者環境變數、PATH、家目錄不同
3. 指令依賴互動式 shell 才會載入的設定檔

### 3) Windows 上指令成功，但效果不如預期

常見原因是：

1. 你以為它會用某個登入者身份跑，但實際上是 `SYSTEM`
2. 需要互動式桌面的程式不適合透過 Run Command 做
3. PowerShell 版本或模組不存在

## 小結

`Run Command` 的價值在於：

你不用登入每一台主機，

就能集中發命令、收結果、保留稽核軌跡。

但它不是單純「遠端開個 shell」而已，

真正的重點在權限模型。

尤其 Linux 和 Windows 在 Document、執行身分、腳本格式上都不同，

如果不先分清楚，

後面很容易踩坑。

## 回家作業

如果你已經可以用 Run Command 幫 Windows 本機帳號換密碼，

下一題就應該是：

換完之後，這個新密碼要怎麼保存？

提示方向可以想兩種：

1. 直接把機密安全地存進 `Secrets Manager`
2. 透過 `SNS` 發出事件，接給後續流程去保存或通知

不過要特別提醒，

`SNS` 比較適合做通知或觸發，

不適合直接存放明文密碼。

所以如果題目是「安全保存密碼本身」，

通常還是會以 `Secrets Manager` 為主。