---
layout: post
title: "AWS SQL Server 建置教學延伸：稽核設定與密碼輪替"
image: https://fastly.picsum.photos/id/844/1200/630.jpg?hmac=xWnHR7ImvXCXUaOdMpl3LvSW6QGm3mx6DlbjtClUiIo
description: "延續 RDS for SQL Server 的基礎建置，補上 SQL Server Audit、S3 稽核紀錄保存、IAM Role 權限設計，以及使用 AWS Secrets Manager 管理與輪替 master user password 的注意事項。"
author: Mark_Mew
categories: [AWS, RDS]
tags: [Database, RDS, SQL Server]
keywords: [Database, AWS, RDS, SQL Server, SQL Server Audit, Secrets Manager, Password Rotation]
lang: zh-TW
date: 2026-07-20
---

前一篇 [AWS SQL Server 建置教學：從建立到連線的一次完整實作](/posts/how-to-set-up-rds-sql-server/) 已經把 RDS for SQL Server 的基礎建置流程跑過一次，包含 Subnet Group、Parameter Group、Option Group、S3、IAM、備份還原與連線測試。

但如果要把資料庫放到比較接近正式環境的位置，只做到「可以連線、可以備份、可以監控」通常還不夠。

正式環境還會在意兩件事：

- 誰在什麼時間做了哪些資料庫操作，是否能留下可追蹤的稽核紀錄。
- 資料庫密碼是否仍然靠人工保存、人工更新，或已經納入可管理的輪替流程。

這篇就延續上一篇的 SQL Server RDS，補上兩個常見的進階設定：SQL Server Audit 與 master user password rotation。

## 稽核設定

RDS for SQL Server 可以搭配 SQL Server Audit，把稽核檔案輸出到指定的 S3 bucket。概念上會分成兩層：

| 層級 | 要做的事 |
| --- | --- |
| AWS RDS 層 | 在 Option Group 加入 `SQLSERVER_AUDIT`，設定 IAM Role、S3 bucket、壓縮與保存時間 |
| SQL Server 層 | 在資料庫內建立 Server Audit、Server Audit Specification 或 Database Audit Specification |

也就是說，Option Group 只是讓 RDS for SQL Server 具備把 audit file 交給 S3 的能力；真正要稽核哪些事件，仍然要回到 SQL Server 裡建立 audit specification。

### 建立 S3 Bucket

前一篇建立的 S3 Bucket `markmew-rds-sql-server-backup-restore` 是用來存放備份還原使用的 `.bak` 檔案。雖然技術上可以共用 bucket，但正式環境通常會建議把備份檔和稽核紀錄分開。

原因很簡單：備份與稽核的生命週期、權限邊界、保存週期與存取對象通常不同。備份檔可能會被 DBA 或還原流程使用；稽核紀錄則比較接近資安、稽核或合規資料，應該有更嚴格的讀取權限與保留政策。

![建立 S3 稽核 Bucket](/assets/img/rds/rds_s3_audit_bucket.png)

這裡示範使用另一個 bucket：

```plaintext
markmew-rds-sql-server-audit
```

如果同一個 bucket 裡會存放多種 RDS 稽核資料，至少也建議用 prefix 區分，例如：

```plaintext
sqlserver-audit/
```

### 建立 IAM Policy

在建立 IAM Role 前，先建立一份 IAM Policy。這樣等一下建立 role 時，可以直接搜尋並附加，不需要之後再回頭補權限。

![IAM Policy](/assets/img/rds/rds_iam_policy2.png)

SQL Server Audit 的 S3 權限至少需要讓 RDS 可以確認 bucket、取得 bucket 資訊，並把 audit file 寫入指定位置。以下是示範用 policy：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketACL",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-audit"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-audit/*"
    }
  ]
}
```

![IAM Policy review and create](/assets/img/rds/rds_iam_policy_review_and_create2.png)

> 如果正式環境已經決定好 prefix，建議把 object 權限收斂到該 prefix，例如 `arn:aws:s3:::markmew-rds-sql-server-audit/sqlserver-audit/*`。稽核紀錄通常不需要讓 RDS 寫到整個 bucket。
{: .prompt-info}

### 建立 IAM Role

接著建立一個讓 RDS 可以 assume 的 IAM Role。這個 role 會提供 SQL Server Audit 寫入 S3 所需的權限，因此 Trust relationship 至少要允許 `rds.amazonaws.com` 使用它。

![IAM Role](/assets/img/rds/rds_iam_role.png)

剛剛如果已經建立好 policy，現在就可以搜尋並關聯。

![IAM Role attached policy](/assets/img/rds/rds_iam_role_attached_policy2.png)

信任關係可以先使用 `rds.amazonaws.com` 作為 trusted entity。

![IAM Role review and create](/assets/img/rds/rds_iam_role_review_and_create2.png)

示範環境可以先使用下面這種比較單純的 trust policy：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

正式環境若要更嚴謹，建議再加上 `aws:SourceAccount` 與 `aws:SourceArn`，限制只有指定帳號、DB instance 和 Option Group 可以使用這個 role。這個寫法在上一篇文章的 native backup/restore IAM Role 段落已經示範過，稽核用途也可以採用同樣概念。

### 在 Option Group 加入 SQLSERVER_AUDIT

接下來回到 SQL Server 使用的 Option Group。這一步和上一篇加入 `SQLSERVER_BACKUP_RESTORE` 類似，只是這次要加入的是 `SQLSERVER_AUDIT`。

加入 option 時，通常會設定幾個欄位：

| 設定 | 說明 |
| --- | --- |
| `IAM_ROLE_ARN` | 讓 RDS 寫入 S3 的 IAM Role ARN |
| `S3_BUCKET_ARN` | 稽核紀錄要送到的 S3 bucket 或 prefix ARN |
| `ENABLE_COMPRESSION` | 是否壓縮 audit file，預設會啟用 |
| `RETENTION_TIME` | audit file 在 DB instance 上保留多久，單位是小時，最大 840 小時 |

![RDS 稽核選項群組](/assets/img/rds/rds_option_group_audit.png)

設定完成後，可以在 Option Group 看到 `SQLSERVER_BACKUP_RESTORE` 與 `SQLSERVER_AUDIT` 兩個 option。

![RDS 選項群組 - 兩個選項](/assets/img/rds/rds_option_group_options.png)

> 加入 `SQLSERVER_AUDIT` 後，不需要重新啟動 DB instance。只要 Option Group 狀態生效，就可以在 SQL Server 裡建立 audits，並讓 RDS 把完成的 audit logs 上傳到 S3。
{: .prompt-info}

### 在 SQL Server 中建立 Audit

Option Group 生效後，還需要登入 SQL Server 建立 audit 與 audit specification。RDS for SQL Server 使用 SQL Server 原生 Audit 機制，只是檔案輸出位置有 RDS 的限制。

建立 Server Audit 時要注意幾件事：

- `FILEPATH` 要使用 `D:\rdsdbdata\SQLAudit`。
- `MAXSIZE` 需要設定在 2 MB 到 50 MB 之間。
- audit、server audit specification、database audit specification 名稱不要使用 `RDS_` 開頭。
- 不要設定 `MAX_ROLLOVER_FILES` 或 `MAX_FILES`。
- 不要設定寫入 audit record 失敗時關閉 DB instance。

下面是一個簡化示範，用來記錄失敗登入事件：

```sql
USE master;
GO

CREATE SERVER AUDIT [audit_failed_login]
TO FILE (
  FILEPATH = N'D:\rdsdbdata\SQLAudit',
  MAXSIZE = 10 MB
)
WITH (
  QUEUE_DELAY = 1000,
  ON_FAILURE = CONTINUE
);
GO

CREATE SERVER AUDIT SPECIFICATION [audit_failed_login_spec]
FOR SERVER AUDIT [audit_failed_login]
ADD (FAILED_LOGIN_GROUP)
WITH (STATE = ON);
GO

ALTER SERVER AUDIT [audit_failed_login]
WITH (STATE = ON);
GO
```

這段只是示範，正式環境要稽核哪些 action group，應該依照公司資安規範、資料敏感度與系統風險設計。不要為了「有開稽核」就把所有事件都打開，否則後面會遇到儲存量、查詢與告警雜訊的問題。

### Multi-AZ 的注意事項

如果 RDS for SQL Server 使用 Multi-AZ，要特別注意 SQL Server Audit 在不同物件上的行為。

Database audit specification 會複寫到所有節點，但 server audit 與 server audit specification 不會自動複寫到 secondary node。若需要在 failover 後也持續捕捉 server-level audit，必須在 failover 到 secondary 後，以相同名稱與 GUID 建立對應的 server audit 或 server audit specification。

這也是為什麼稽核設定不能只看「Option Group 有沒有開」。正式環境最好把 failover 後的 audit 狀態也納入演練清單。

## 密碼輪替

資料庫密碼常見的壞味道，是大家都知道它很重要，但實際上卻被放在文件、環境變數、CI/CD 設定或某個人手上的密碼管理器裡。時間久了，沒有人敢改，因為一改就不知道哪個服務會斷線。

在 RDS 上，至少可以先把 master user password 納入 AWS Secrets Manager 管理。建立或修改 DB instance 時，可以選擇讓 RDS 管理 master credentials。啟用後，RDS 會產生密碼、存到 Secrets Manager，並在輪替時同步更新資料庫端的 master user password。

在資料庫中按下編輯，選擇 `以 AWS Secrets Manager` 管理，然後就可以自動托管。

![RDS Secrets Rotate](/assets/img/rds/rds_secrets_manager_autorotate.png)

我們去查看 `Secrets Manager`，就可以發現已經自動建立一組 Credentials，並且設定 Rotate。

![Secrets Manager autorotate credentials](/assets/img/rds/secrets_manager_autorotate.png)

### 自行管理密碼時的注意事項

如果目前還沒有使用 RDS 管理 master credentials，而是自行管理 master password，也可以透過修改 DB instance 來變更密碼。不過這種做法比較仰賴人工流程，常見問題是：

- 密碼更新後，應用程式設定沒有同步更新。
- CI/CD、排程工作、維運工具仍然使用舊密碼。
- 沒有確認連線池或長連線在密碼變更後的行為。
- 密碼雖然改了，但沒有留下完整變更紀錄與審核流程。

另外，RDS for SQL Server 建立或修改 master user password 時，不一定會依照 SQL Server 內部 password policy 幫你擋下弱密碼。因此就算操作本身成功，也仍然應該使用高強度密碼，並搭配稽核與事件通知確認風險。

## 結語

RDS for SQL Server 的基礎建置，只是把資料庫平台立起來。要讓它更接近正式環境，還需要補上「可追蹤」與「可輪替」這兩件事。

SQL Server Audit 解決的是事後追蹤與合規證據：誰做了什麼、哪些事件需要被記錄、稽核檔案要保存在哪裡、誰可以讀取。Secrets Manager 與 password rotation 解決的是憑證治理：密碼不再散落在文件與人工流程裡，而是變成可以被權限控管、記錄與輪替的資源。

這些設定看起來沒有建立資料庫那麼有成就感，但它們才是資料庫能不能放心進正式環境的關鍵。會連線是第一步；能被稽核、能被輪替、能被演練，才是真的能維運。

## 參考資料

- [Amazon RDS for SQL Server：SQL Server Audit](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.html)
- [Amazon RDS for SQL Server：Adding SQL Server Audit to the DB instance options](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.Adding.html)
- [Amazon RDS for SQL Server：Using SQL Server Audit](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.CreateAuditsAndSpecifications.html)
- [Amazon RDS for SQL Server：Viewing audit logs](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.Viewing.html)
- [Amazon RDS for SQL Server：Manually creating an IAM role for SQL Server Audit](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.Audit.IAM.html)
- [Amazon RDS：Password management with Amazon RDS and AWS Secrets Manager](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-secrets-manager.html)
- [Amazon RDS for SQL Server：Password considerations for the master login](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.PasswordPolicy.MasterLogin.html)
- [AWS Secrets Manager：Rotate AWS Secrets Manager secrets](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets.html)
