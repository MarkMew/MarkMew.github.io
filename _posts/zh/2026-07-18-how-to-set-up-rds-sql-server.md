---
layout: post
title: "AWS SQL Server 建置教學：從建立到連線的一次完整實作"
image: https://fastly.picsum.photos/id/210/1200/630.jpg?hmac=U8wtlsOPi38zUOhUIWdeBtlklDDrIKanqey3u6CXoco
description: "本文示範如何在 AWS 建立 RDS for SQL Server，包含子網路群組、參數群組、選項群組、儲存、連線、安全群組、備份與 Terraform 範例。"
author: Mark_Mew
categories: [AWS, RDS]
tags: [Database, RDS, SQL Server]
keywords: [Database, AWS, RDS, SQL Server]
lang: zh-TW
date: 2026-07-18
---

SQL Server 是企業系統中很常見的關聯式資料庫。過去如果在地端機房或 VM 上維運，通常會由 DBA 或系統管理員安裝 SQL Server、調整作業系統、規劃備份、設定監控，再交給應用程式使用。

到了 AWS 上，這些工作不一定都要自己接住。若沒有特殊的 OS 權限、SQL Server 功能或授權需求，Amazon RDS for SQL Server 會是比較容易維運的選擇。RDS 會幫忙處理底層主機、儲存、備份、維護窗口、監控整合與高可用能力，團隊可以把心力放在資料模型、查詢效能、權限控管與還原演練。

這篇文章會示範如何建立一台 RDS for SQL Server，流程分成兩種方式：

- 使用 AWS Console GUI 建立。
- 使用 Terraform 建立基本資源。

範例會以開發或測試環境為主，正式環境還需要再依照資料量、RPO、RTO、資安規範與可用性需求調整。

> RDS for SQL Server 支援的版本會隨 AWS 與 Microsoft 支援政策變動。實作時請以所在 Region 的 AWS Console 或 `aws rds describe-db-engine-versions` 查到的結果為準。
{: .prompt-info}

## 建置前先確認幾件事

開始建立 RDS 前，建議先把下面幾件事確認清楚：

| 項目 | 建議先確認的內容 |
| --- | --- |
| VPC 與 Subnet | DB 要放在哪個 VPC，是否只放在 Private Subnet |
| Security Group | 哪些來源可以連到 SQL Server 的 `1433` port |
| SQL Server 版本 | 應用程式支援哪個 SQL Server major/minor version |
| Edition | Express、Web、Standard、Enterprise 的功能與授權差異 |
| 儲存容量 | 初始容量、最大容量、IOPS、Throughput 與成長速度 |
| 備份 | Automated Backup 保存天數、是否需要 PITR 或 AWS Backup |
| 維護窗口 | 何時可以套用維護或版本更新 |
| 參數與選項 | 是否需要自訂 Parameter Group 或 Option Group |

這些看起來像是前置雜事，但資料庫最怕的是建好後才發現網路放錯、版本選錯、備份策略不符合需求，或安全群組開得太大。

## 方法一：使用 AWS Console GUI 建立

進入 AWS Console 後，打開 RDS 頁面。

![Amazon and RDS dashboard page](/assets/img/rds/rds_home_page.png)

RDS 建立流程本身不難，但幾個群組概念一開始容易混在一起：

- DB Subnet Group：決定 RDS 可以被放到哪些 Subnet。
- DB Parameter Group：管理資料庫引擎參數。
- Option Group：啟用特定引擎的額外功能，例如 SQL Server native backup/restore。
- Security Group：控制誰可以連進 DB。

下面會依照建置順序逐一建立。

### 建立子網路群組

如果是第一次建立 RDS，通常會先規劃 DB Subnet Group。

雖然 VPC 內已經有多個 Subnet，但不代表每個 Subnet 都適合放資料庫。一般來說，資料庫不應該直接放在 Public Subnet，也不應該直接對 Internet 開放。比較常見的做法是讓 RDS 放在跨 Availability Zone 的 Private Subnet，然後只允許應用程式所在的 Security Group 或內部網段連線。

第一次進入 Subnet Group 頁面時，列表可能會是空的。直接按下建立按鈕即可。

![RDS Subnet Group list page](/assets/img/rds/rds_subnet_group_list_page.png)

建立頁面中需要先選擇 VPC。選完 VPC 之後，才會出現該 VPC 底下可選的 Availability Zone 與 Subnet。

![RDS Subnet Group create page](/assets/img/rds/rds_subnet_group_create_page.png)

建議選擇至少兩個不同 Availability Zone 的 Private Subnet。這樣未來如果要啟用 Multi-AZ，或遇到維護與故障切換情境，會比較符合 RDS 的高可用設計。

![Subnet Group create sample](/assets/img/rds/rds_subnet_group_create_sample_page.png)

建立完成後，就可以在列表中看到剛剛建立的 Subnet Group。

![Subnet Group create result](/assets/img/rds/rds_subnet_group_create_result.png)

### 建立參數群組

每個資料庫引擎都有一些可以調整的參數。自建 SQL Server 時，可能會透過 SQL Server Management Studio、T-SQL 或主機層級設定來調整；但 RDS 不能直接登入底層 OS，也不能取得完整的 `sysadmin` 權限，因此需要透過 DB Parameter Group 管理 RDS 允許調整的參數。

如果目前還沒有自訂參數群組，列表頁會是空的。

![RDS Parameter Group list page](/assets/img/rds/rds_parameter_group_list_page.png)

點擊建立後，進入 Parameter Group 建立頁面。

![RDS Parameter Group create page](/assets/img/rds/rds_parameter_group_create_page.png)

Parameter Group 會綁定資料庫引擎與 major version。也就是說，SQL Server 2019 和 SQL Server 2022 需要使用各自相容的 Parameter Group family。建立時要選擇與預計建立的 RDS 版本一致的 family。

![RDS Parameter Group create sample](/assets/img/rds/rds_parameter_group_create_sample_page.png)

建立完成後，會出現在 Parameter Group 列表中。

![RDS Parameter Group create result](/assets/img/rds/rds_parameter_group_create_result.png)

> 有些參數變更可以立即套用，有些需要重啟 DB 才會生效。正式環境調整前，建議先在非正式環境測試並確認維護窗口。
{: .prompt-warning}

### 建立資料庫

前面的 Subnet Group 和 Parameter Group 建好後，就可以開始建立 RDS DB Instance。如果這台資料庫還需要 native backup/restore，再另外準備後面會提到的 Option Group、S3 與 IAM 設定即可。

![RDS Database list page](/assets/img/rds/rds_database_list_page.png)

按下建立資料庫後，Console 會列出很多設定。這邊建議選擇完整組態，不要使用過度簡化的預設流程，因為資料庫的網路、安全、備份與維護窗口都值得明確設定。

![RDS Database create page](/assets/img/rds/rds_database_create_page.png)

範例設定如下：

```plaintext
引擎選項
> SQL Server

範本
> 開發/測試

設定
> 資料庫管理類型
>> Amazon RDS

> 版本
>> SQL Server Express Edition

> 引擎版本
>> 依照 Console 目前支援版本選擇，例如 SQL Server 2022

> 資料庫執行個體識別符
>> sql-server-express-demo

認證設定
> 主要使用者名稱
>> admin

> 憑證管理
>> 自我管理，或依公司規範使用 Secrets Manager

> 主要密碼
>> 請設定高強度密碼
```

這裡使用 Express Edition 是為了示範與測試。正式環境要依照功能需求、授權、資料庫大小與效能需求選擇合適的 Edition。

Instance class 的部分，開發測試可以從較小的 t 類型開始，例如：

```plaintext
執行個體組態
> 爆量類別
>> db.t3.small
```

但正式環境不要只看 CPU 和 Memory。SQL Server workload 很容易受到 IOPS、Throughput、連線數、TempDB 使用量、查詢型態與鎖定行為影響。建議先用既有環境的監控資料估算，再選擇合適規格。

#### 設定儲存

儲存設定需要特別留意。除了初始容量外，也要考慮是否啟用 Storage Autoscaling，以及是否需要指定 IOPS 或 Throughput。

![RDS Database create page storage spec](/assets/img/rds/rds_database_create_page_storage_spec.png)

建議至少確認：

- 初始容量是否足夠放目前資料與短期成長。
- 最大儲存容量是否符合預算與風險控管。
- 是否需要 gp3 指定 IOPS / Throughput。
- 是否需要針對 `FreeStorageSpace` 建立 CloudWatch Alarm。

Storage Autoscaling 可以降低資料庫空間不足的風險，但它不是容量規劃的替代品。RDS 儲存擴大後不能直接縮小，如果成長失控，最後還是會反映在成本與治理問題上。

#### 設定連線與安全群組

連線設定中，記得選擇前面建立的 `資料庫子網路群組`。

![RDS Database create page connection](/assets/img/rds/rds_database_create_page_connection.png)

Security Group 的規則請不要直接開 `0.0.0.0/0`。SQL Server 預設連線 port 是 `1433`，建議只允許必要來源，例如：

- 應用程式伺服器的 Security Group。
- Bastion Host 或 VPN 所在的 Security Group。
- 公司內部網段，且必須搭配更嚴格的網路控管。

如果只是開發測試，也可以先限制在 VPC CIDR 內的 `1433`，但正式環境更建議使用 Security Group referencing，讓規則跟著應用程式資源走，而不是開整段網段。

#### 設定監控、備份與維護

監控的部分可以先使用 CloudWatch 預設指標。如果需要更細的 OS 層級指標，可以啟用 Enhanced Monitoring；如果要觀察 DB load、等待事件與 SQL 層級瓶頸，則可以啟用 Performance Insights 或 CloudWatch Database Insights。

![RDS Database create page addition config](/assets/img/rds/rds_database_create_page_addition_config.png)

其他組態中也要確認：

- 是否選擇剛剛建立的 Parameter Group。
- 如果有要使用 native backup/restore，是否選擇對應的 Option Group。
- Backup retention period 是否符合需求。
- Backup window 是否避開流量高峰。
- Maintenance window 是否符合維運時段。
- Deletion protection 是否需要啟用。
- Time zone、Collation 是否符合應用程式需求。

> Time zone 與 Collation 建立後不一定能輕易修改。尤其 Collation 會影響排序、比較與大小寫敏感行為，正式環境務必先和應用程式、報表與既有資料庫設定對齊。
{: .prompt-warning}

確認設定後按下建立，等待 RDS 狀態變成 Available。建立時間會依照 DB instance class、儲存設定與當下服務狀態而不同，測試環境常見是數分鐘到十多分鐘不等。

建立完成後，就可以取得 endpoint，使用 SQL Server Management Studio、Azure Data Studio、DBeaver 或應用程式連線測試。如果有啟用 Automated Backup，RDS 也會依照設定建立自動備份，不需要另外手動觸發。

連線資訊大致如下：

```plaintext
Server / Host: <rds-endpoint>
Port: 1433
User: admin
Password: 建立時設定的密碼
Database: 視情況指定，或先連到預設資料庫
```

如果連不上，通常先檢查這幾個地方：

1. RDS 是否已經 Available。
2. Client 是否在允許連線的網路位置。
3. Security Group inbound 是否允許來源連到 `1433`。
4. Route table、NACL、VPN 或 Bastion 是否正確。
5. SQL Server 使用者名稱與密碼是否正確。
6. DNS 是否能解析 RDS endpoint。

### 設定備份還原（Optional）

如果這台 RDS for SQL Server 之後需要使用 native backup/restore，也就是把 SQL Server 的 `.bak` 檔放到 S3，再從 S3 還原到 RDS，或是從 RDS 備份 `.bak` 到 S3，就需要額外設定 S3、IAM role 和 Option Group。

這個功能需要把三個元件接起來：

| 元件 | 用途 |
| --- | --- |
| S3 bucket | 存放 SQL Server `.bak` 備份檔 |
| IAM role 與 policy | 讓 RDS 可以讀寫指定的 S3 bucket |
| Option Group | 加入 `SQLSERVER_BACKUP_RESTORE`，並指定 IAM role ARN |

順序可以這樣做：

1. 建立一個專門放 SQL Server 備份檔的 S3 bucket。
2. 建立 IAM role，Trust relationship 允許 `rds.amazonaws.com` assume role。
3. 在 IAM role 上掛載 S3 權限 policy。
4. 在 SQL Server Option Group 中加入 `SQLSERVER_BACKUP_RESTORE`。
5. 將 IAM role ARN 填到 Option 的 `IAM_ROLE_ARN` 設定。
6. 建立或修改 RDS DB Instance，將這個 Option Group 套用到 SQL Server。

S3 bucket 建議和 RDS DB Instance 放在同一個 Region，因為 RDS for SQL Server native backup/restore 不支援跨 Region 的 S3 bucket。若備份檔來自其他 Region，可以先透過 S3 Replication 或其他方式複製到 RDS 所在 Region。

> `SQLSERVER_BACKUP_RESTORE` 和 `S3_INTEGRATION` 容易混在一起。前者是 `.bak` native backup/restore 使用的 Option Group option；後者是把檔案在 RDS host 的 `D:\S3\` 與 S3 之間傳輸的功能。本文主要示範 native backup/restore，因此核心設定是 Option Group 的 `SQLSERVER_BACKUP_RESTORE`。
{: .prompt-info}

#### 建立選項群組

Option Group 是 RDS 中比較容易被忽略的設定。它不是一般資料庫參數，而是用來啟用特定資料庫引擎的額外功能。

以 SQL Server 來說，如果希望使用 native backup/restore，將 `.bak` 檔案備份到 S3 或從 S3 還原，就需要在 Option Group 加入 `SQLSERVER_BACKUP_RESTORE` 選項，並讓 RDS 使用有 S3 權限的 IAM Role。

![RDS Option Group list page](/assets/img/rds/rds_option_group_list_page.png)

建立 Option Group 時，同樣要選擇 SQL Server 引擎與對應版本。

![RDS Option Group create page](/assets/img/rds/rds_option_group_create_page.png)

如果一開始還沒有 IAM role，可以先建立空的 Option Group。等 S3 bucket、IAM policy 和 IAM role 準備好後，再回來加入 `SQLSERVER_BACKUP_RESTORE`，並在 option setting 中填入 `IAM_ROLE_ARN`。

![RDS Option Group create sample](/assets/img/rds/rds_option_group_create_sample_page.png)

建立完成後，Option Group 會出現在列表中。

![RDS Option Group create result](/assets/img/rds/rds_option_group_create_result.png)

> 如果只是使用 RDS Automated Backup 與 PITR，不一定需要設定 SQL Server native backup/restore。只有在要匯入或匯出 `.bak` 檔、與既有 SQL Server 備份流程銜接時，才需要特別處理這個 Option Group。
{: .prompt-info}

#### 建立 S3 Bucket

先建立一個專門存放 SQL Server `.bak` 檔案的 S3 bucket。建議這個 bucket 和 RDS DB Instance 放在同一個 Region，因為 RDS for SQL Server native backup/restore 不支援跨 Region 的 S3 bucket。

如果備份檔原本在其他 Region，通常會先用 S3 Replication 或其他同步方式複製到 RDS 所在 Region，再交給 RDS 匯入或還原。

![建立 S3 備份還原 Bucket](/assets/img/rds/rds_s3_backup_restore_bucket.png)

#### 建立 IAM Policy 以存取 S3 Bucket

在建立 IAM role 前，建議先建立 IAM policy。這樣建立 role 時就可以直接搜尋並附加，不需要之後再回頭補權限。

![IAM Policy](/assets/img/rds/rds_iam_policy.png)

S3 權限 policy 則至少需要讓 RDS 可以列出 bucket、確認 bucket 位置，以及讀寫備份物件：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-backup-restore"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObjectAttributes",
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListMultipartUploadParts",
        "s3:AbortMultipartUpload"
      ],
      "Resource": "arn:aws:s3:::markmew-rds-sql-server-backup-restore/*"
    }
  ]
}
```

![IAM Policy review and create](/assets/img/rds/rds_iam_policy_review_and_create.png)

> 建議使用專用 bucket，或至少使用專用 prefix，例如 `sqlserver-native-backup/`。如果 prefix 留空，RDS 在多檔還原時可能會掃到 bucket 中其他不相關檔案，排查起來會很麻煩。
{: .prompt-info}

如果備份檔需要 KMS 加密，IAM role 還要補上對應 KMS key 的 `kms:DescribeKey`、`kms:GenerateDataKey`、`kms:Encrypt`、`kms:Decrypt`，而且 KMS key policy 也要允許這個 IAM role 使用該 key。

#### 建立 IAM Role

接著建立一個讓 RDS 可以 assume 的 IAM role。這個 role 會提供 native backup/restore 存取 S3 所需的權限，因此 Trust relationship 至少要允許 `rds.amazonaws.com` 使用它。

![IAM Role](/assets/img/rds/rds_iam_role.png)

剛剛如果有建立好 policy，現在就可以搜尋並關聯。

![IAM Role attached policy](/assets/img/rds/rds_iam_role_attached_policy.png)

信任關係可以先使用 `rds.amazonaws.com` 作為 trusted entity。

![IAM Role review and create](/assets/img/rds/rds_iam_role_review_and_create.png)

正式環境若要更嚴謹，可以再加上 `aws:SourceAccount` 與 `aws:SourceArn`，限制只有指定帳號、DB instance 和 Option Group 可以使用這個 role：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "aws:SourceAccount": "<account-id>"
        },
        "ArnLike": {
          "aws:SourceArn": [
            "arn:aws:rds:<region>:<account-id>:db:<db-instance-id>",
            "arn:aws:rds:<region>:<account-id>:og:<option-group-name>"
          ]
        }
      }
    }
  ]
}
```

#### 將 IAM Role 接到 Option Group

S3 bucket、IAM policy 和 IAM role 都準備好後，回到 SQL Server 的 Option Group，加入 `SQLSERVER_BACKUP_RESTORE` option，並在 `IAM_ROLE_ARN` 填入剛剛建立的 IAM role ARN。

如果 DB instance 已經建立完成，修改 Option Group 後，記得確認 DB instance 是否已經套用這個 Option Group。某些 Option Group 變更會需要重新啟動 DB instance 才會生效，正式環境請放在維護窗口內操作。

#### 補充：啟用 S3 Integration

如果除了 native backup/restore 以外，也需要使用 RDS for SQL Server 的 S3 integration，例如把 S3 檔案下載到 DB instance host 的 `D:\S3\` 目錄，再用 SQL Server 功能處理檔案，就需要到 DB instance 的 `Connectivity & security` 頁籤設定 IAM role。

往下捲到 `Manage IAM roles` 區塊後，可以看到管理 IAM role 的設定。

![RDS 管理 IAM 角色](/assets/img/rds/rds_manage_iam_role.png)

只要剛剛建立的 IAM role 信任關係正確，就可以在下拉式選單中找到。功能欄位選擇 `S3_INTEGRATION`。

![RDS 設定 IAM 角色](/assets/img/rds/rds_manage_iam_role_settings.png)

等待幾分鐘後，狀態會顯示為作用中。這代表 S3 integration 已經啟用。

> 如果只是要執行 `rds_backup_database` 或 `rds_restore_database`，重點仍然是 Option Group 的 `SQLSERVER_BACKUP_RESTORE`。`S3_INTEGRATION` 是另一個檔案傳輸功能，不要把兩者當成同一個設定。
{: .prompt-warning}

#### 製作 `.bak` 備份檔並輸出到 S3

找一台可以連到 SQL Server 的機器，使用 SQL Server Management Studio、Azure Data Studio 或其他 SQL client 連上 RDS。

以下範例會把 `my_app` 資料庫完整備份成 `.bak` 檔並輸出到 S3：

```sql
exec msdb.dbo.rds_backup_database
  @source_db_name='my_app',
  @s3_arn_to_backup_to='arn:aws:s3:::markmew-rds-sql-server-backup-restore/my_app_full.bak',
  @overwrite_s3_backup_file=1,
  @type='FULL';
```

查詢備份狀態可以使用 `rds_task_status`：

```sql
exec msdb.dbo.rds_task_status @db_name='my_app';
```

如果想看目前 DB instance 上所有 native backup/restore task，也可以不帶參數：

```sql
exec msdb.dbo.rds_task_status;
```

和地端直接操作備份檔不同，RDS for SQL Server 的 native backup/restore 會建立 task。task 建立後會從 `CREATED` 進到 `IN_PROGRESS`，完成後會變成 `SUCCESS`；如果失敗則會顯示 `ERROR`，並在 `task_info` 裡提供錯誤訊息。

如果要從 S3 還原 `.bak` 檔，可以使用 `rds_restore_database`。還原時不能覆蓋已存在的同名資料庫，因此通常會先還原成新的資料庫名稱：

```sql
exec msdb.dbo.rds_restore_database
  @restore_db_name='my_app_restore',
  @s3_arn_to_restore_from='arn:aws:s3:::markmew-rds-sql-server-backup-restore/my_app_full.bak';
```

##### RDS for SQL Server 的 `rds_*` 預存程序與 Task

使用 RDS for SQL Server 時，會發現很多在自建 SQL Server 上習慣用 GUI、OS 權限、`sysadmin` 權限或檔案系統處理的工作，在 RDS 上會改成透過 Amazon RDS 提供的 `msdb.dbo.rds_*` stored procedures / functions 執行。

這不是 SQL Server 原生語法被取代，而是因為 RDS 是 Managed Service。AWS 不提供 DB instance 的 shell access，也會限制某些需要高權限的系統程序和系統資料表。因此 AWS 把常見 DBA 工作包成 RDS-specific procedures / functions，讓你在不碰底層主機的情況下完成管理動作。

官方文件有一頁專門整理這些函數和預存程序，常見類型如下：

| 類型 | 常見 procedures / functions | 用途 |
| --- | --- | --- |
| 管理任務 | `rds_drop_database`、`rds_modify_db_name`、`rds_read_error_log`、`rds_set_configuration` | 刪除或重新命名資料庫、讀取錯誤日誌、調整 RDS-specific 設定 |
| CDC | `rds_cdc_enable_db`、`rds_cdc_disable_db` | 在 RDS for SQL Server 上啟用或停用 change data capture |
| Native backup/restore | `rds_backup_database`、`rds_restore_database`、`rds_restore_log`、`rds_finish_restore`、`rds_cancel_task` | 以 task 方式處理 `.bak` 備份、還原、取消任務 |
| Task 狀態 | `rds_task_status` | 查詢 native backup/restore task 的狀態 |
| S3 檔案傳輸 | `rds_download_from_s3`、`rds_upload_to_s3`、`rds_gather_file_details`、`rds_delete_from_filesystem` | 搭配 S3 integration 在 S3 與 DB instance host 的 `D:\S3\` 之間傳輸或管理檔案 |
| TDE | `rds_backup_tde_certificate`、`rds_restore_tde_certificate`、`rds_drop_tde_certificate`、`rds_fn_list_user_tde_certificates` | 管理 Transparent Data Encryption 憑證 |
| SQL Server Agent / system database sync | `rds_set_system_database_sync_objects`、`rds_fn_get_system_database_sync_objects`、`rds_fn_server_object_last_sync_time` | 在特定情境同步 SQL Server Agent job 等系統資料庫物件 |
| MSBI | `rds_msbi_task`、`rds_fn_task_status` | 管理或查詢 SSAS、SSIS、SSRS 相關任務 |
| Resource Governor | `rds_create_resource_pool`、`rds_alter_resource_pool`、`rds_drop_resource_pool`、`rds_create_workload_group` | 管理 Resource Governor 相關物件 |

這裡有兩個容易混淆的狀態查詢：

- `rds_task_status`：用來查 native backup/restore task，例如 `rds_backup_database`、`rds_restore_database`。
- `rds_fn_task_status`：用來查 MSBI 相關 task，例如 SSAS、SSIS、SSRS 部署或管理任務。

所以如果你在 RDS for SQL Server 上找不到熟悉的主機層操作，先不要急著判斷「RDS 不支援」。比較好的做法是先查官方的函數和預存程序清單，確認 AWS 是否已經提供對應的 `rds_*` procedure 或 function。

## 方法二：使用 Terraform 建立

如果正式環境已經使用 Terraform 管理基礎設施，RDS 也建議放進 Terraform，避免 Console 設定漂移。

下面是一個簡化範例，展示 Subnet Group、Parameter Group、Security Group、S3 bucket、IAM role、Option Group 與 RDS Instance 的關係。實際環境請把 VPC、Subnet、KMS、密碼、Tag 與命名規則接到既有模組。

```terraform
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "app_security_group_id" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "backup_bucket_name" {
  type = string
}

variable "backup_prefix" {
  type    = string
  default = "sqlserver-native-backup"
}

resource "aws_db_subnet_group" "database" {
  name       = "rds-database-subenet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "rds-database-subenet-group"
  }
}

resource "aws_security_group" "sqlserver" {
  name        = "sqlserver"
  description = "Allow application access to RDS SQL Server"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SQL Server from application"
    from_port       = 1433
    to_port         = 1433
    protocol        = "tcp"
    security_groups = [var.app_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_s3_bucket" "sqlserver_backup" {
  bucket = var.backup_bucket_name

  tags = {
    Name = var.backup_bucket_name
  }
}

resource "aws_s3_bucket_public_access_block" "sqlserver_backup" {
  bucket = aws_s3_bucket.sqlserver_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "sqlserver_backup_restore" {
  name = "rds-sqlserver-backup-restore"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
          ArnLike = {
            "aws:SourceArn" = [
              "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:db:*",
              "arn:aws:rds:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:og:*"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_iam_policy" "sqlserver_backup_restore" {
  name = "rds-sqlserver-backup-restore-s3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.sqlserver_backup.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObjectAttributes",
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.sqlserver_backup.arn}/${var.backup_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sqlserver_backup_restore" {
  role       = aws_iam_role.sqlserver_backup_restore.name
  policy_arn = aws_iam_policy.sqlserver_backup_restore.arn
}

resource "aws_db_parameter_group" "mssql_ex_17_parameter_group" {
  name        = "sqlserver-ex-17-parameter-group"
  family      = "sqlserver-ex-17.0"
  description = "sqlserver express 2025 parametergroup"
}

resource "aws_db_option_group" "mssql_ex_17" {
  name                     = "sqlserver-demo-option-group"
  option_group_description = "Option group for SQL Server demo"
  engine_name              = "sqlserver-ex"
  major_engine_version     = "17.00"

  option {
    option_name = "SQLSERVER_BACKUP_RESTORE"

    option_settings {
      name  = "IAM_ROLE_ARN"
      value = aws_iam_role.sqlserver_backup_restore.arn
    }
  }

  tags = {
    Name = "sqlserver-demo-option-group"
  }

  depends_on = [
    aws_iam_role_policy_attachment.sqlserver_backup_restore
  ]
}

resource "aws_db_instance" "sqlserver" {
  identifier = "sqlserver-express-demo"

  engine         = "sqlserver-ex"
  engine_version = "17.00.4045.5.v1"
  license_model  = "license-included"

  instance_class        = "db.t3.small"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  username = "admin"
  password = var.db_password
  port     = 1433

  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.sqlserver.id]
  parameter_group_name   = aws_db_parameter_group.mssql_ex_17_parameter_group.name
  option_group_name      = aws_db_option_group.mssql_ex_17.name

  timezone                = "Taipei Standard Time"
  backup_retention_period = 7
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:00-sun:20:00"

  multi_az            = false
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "sqlserver-express-demo"
  }
}
```

這段 Terraform 是展示用，正式環境至少要再調整：

- 不要把密碼寫死在 `.tf` 檔案中，建議使用 Secrets Manager、SSM Parameter Store 或 CI/CD secret。
- 正式環境建議啟用 `deletion_protection`。
- 正式環境通常不應該使用 `skip_final_snapshot = true`。
- 如果資料庫是關鍵服務，應評估啟用 `multi_az`。
- `family`、`engine_version` 和 `major_engine_version` 要依照實際支援版本確認。
- CloudWatch log exports 支援項目會依引擎與版本不同而有差異，請以實際版本為準。
- S3 bucket 必須和 RDS DB Instance 位於同一個 Region。
- S3 bucket 名稱是全域唯一，範例中的 `backup_bucket_name` 需要換成自己的命名。
- 如果要用 KMS 加密 `.bak` 檔案，IAM policy 和 KMS key policy 都要允許這個 role 使用該 key。
- Trust policy 範例用同帳號同 Region 的 RDS DB 與 Option Group ARN pattern 收斂權限；正式環境可以再改成明確的 DB instance ARN 與 Option Group ARN。
- `backup_prefix` 要和實際備份/還原時使用的 S3 object path 對齊。

## 備份與還原策略

RDS for SQL Server 常見有三種備份方式：

| 方式 | 用途 |
| --- | --- |
| Automated Backup | RDS 自動備份，支援在保存期間內做 PITR |
| Manual Snapshot | 手動建立某個時間點的 DB snapshot |
| Native backup/restore | 透過 `.bak` 檔與 S3 匯入或匯出 SQL Server 資料庫 |

Automated Backup 是最基本也最應該打開的備份方式。它可以在設定的 backup retention period 內支援 Point-in-Time Recovery。發生誤刪資料、錯誤部署或批次作業寫壞資料時，可以還原到指定時間點。

要注意的是，RDS 的 PITR 還原不是直接覆蓋原本 DB，而是建立一台新的 DB Instance。這通常比較安全，因為你可以先驗證資料，再決定要切換應用程式連線、抽資料回原庫，或保留作為事故分析用。

Manual Snapshot 適合用在重大變更前，例如升級、調整參數、資料庫大批次修改前。它不取代 Automated Backup，但可以作為明確的變更前回復點。

Native backup/restore 則比較適合和既有 SQL Server 流程銜接。例如從地端 SQL Server 備份 `.bak` 到 S3，再還原到 RDS；或把 RDS 的資料庫備份到 S3，提供給其他環境使用。這需要 Option Group 中加入 `SQLSERVER_BACKUP_RESTORE`，並搭配有 S3 權限的 IAM Role。

正式環境的備份策略至少要回答三個問題：

| 問題 | 代表意義 |
| --- | --- |
| RPO 是多少？ | 最多能接受遺失多久的資料 |
| RTO 是多少？ | 最久能接受多久恢復服務 |
| 還原演練多久做一次？ | 確認備份真的可用，而不是只看備份狀態成功 |

有備份不代表能還原。建議至少在非正式環境定期做一次還原演練，記錄還原時間、切換流程、權限差異、Parameter Group、Option Group、Security Group 與應用程式連線設定是否完整。

## 採用 RDS for SQL Server 的優點

### 監控比較容易落地

如果是在 EC2 或地端自建 SQL Server，通常要自己安裝 Agent、設定 log 收集、串接監控平台，才能建立可用的資料庫監控。

RDS 預設會提供多種 CloudWatch 指標，例如 CPU、連線數、儲存空間、IOPS 與 Latency。需要更細緻時，也可以啟用 Enhanced Monitoring、Performance Insights 或 CloudWatch Database Insights。

至少建議建立這些基本告警：

| 指標 | 觀察目的 |
| --- | --- |
| `CPUUtilization` | 是否長期高於平常基準 |
| `FreeableMemory` | 記憶體是否不足 |
| `FreeStorageSpace` | 儲存空間是否快滿 |
| `DatabaseConnections` | 連線數是否異常增加 |
| `ReadLatency` / `WriteLatency` | 儲存延遲是否惡化 |
| `ReadIOPS` / `WriteIOPS` | I/O 是否接近瓶頸 |

### 儲存擴展比較單純

地端或 EC2 自建資料庫偶爾會遇到硬碟空間不足。尤其開發或批次程式如果不小心把大量 log、暫存資料或歷史資料寫進資料庫，很容易讓資料庫空間突然被塞滿。

RDS 可以設定 Storage Autoscaling，讓儲存空間在接近不足時自動增加。雖然仍然要做容量規劃與成本控管，但至少可以降低半夜手動擴磁碟、擴檔案系統、確認 mount point 的壓力。

### 備份與維護比較可控

RDS 提供 Automated Backup、Manual Snapshot、PITR 與 Maintenance Window。這些功能不代表 DBA 或工程師完全不用管資料庫，而是讓很多底層維運變成可設定、可追蹤、可演練的流程。

如果組織已經使用 AWS Backup，也可以把 RDS 納入統一的備份計畫，集中管理保存週期、跨帳號或跨區複製，以及稽核需求。

### 高可用能力比較容易標準化

正式環境如果資料庫是關鍵元件，應該評估 Multi-AZ。RDS Multi-AZ 可以讓資料庫跨 Availability Zone 具備更好的可用性與耐久性，並在部分維護或故障情境下降低中斷影響。

Multi-AZ 不是讀寫分離工具。如果要分擔讀取流量，需要另外評估 Read Replica 或應用程式層級的讀寫路由。

> 高可用要同時確認 SQL Server Edition 與 engine version。
> RDS for SQL Server 的 Multi-AZ 主要支援 Standard / Enterprise；SQL Server 2022 Web Edition 需 16.00.4215.2 以上才支援 block-level replication，Express Edition 不支援。
{: .prompt-info}

## 採用 RDS for SQL Server 的限制

### 沒有完整的 `sa` 或 OS 權限

在 RDS for SQL Server 中，建立時指定的 master user 不是地端自建 SQL Server 常見的 `sa`，也不具備完整 `sysadmin` 權限。它是 AWS 允許你使用的最高權限帳號。

這代表有些需要 OS 權限、Instance 層級或 `sysadmin` 權限的操作不能做。導入前要確認既有系統、維運腳本、備份流程與 DBA 操作習慣是否依賴這些權限。

### 部分 SQL Server 功能不支援

RDS for SQL Server 是 Managed Service，所以不可能開放所有自建 SQL Server 的功能。常見限制包含不能使用伺服器層級觸發器、不能使用某些需要 OS 存取權的功能，也不能任意修改底層檔案系統。

如果既有系統大量依賴 SQL Server Agent Job、Linked Server、CLR、SSIS、SSRS、特殊備份流程或其他進階功能，導入前一定要逐項比對 RDS 支援狀態。

### 版本、Edition 與資源規格會影響功能

SQL Server 的功能會受到 Edition、版本與 RDS 支援範圍影響。Express Edition 適合示範或小型測試，但正式環境通常會受限於容量、資源與功能。Web、Standard、Enterprise Edition 的成本與可用功能也不同。

不要只因為測試環境能跑，就直接照搬到正式環境。正式環境要先確認：

- 資料庫大小是否超過 Edition 限制。
- 應用程式需要的功能是否支援。
- RDS Instance class 是否支援該引擎與 Edition。
- 授權成本是否符合預算。

## 建立完成後的檢查清單

RDS 建好後，不要只測一次連線就結束。建議至少確認：

- RDS 不可公開存取，且位於正確的 Private Subnet。
- Security Group 只允許必要來源連到 `1433`。
- 應用程式或管理工具可以正常連線。
- Automated Backup 已啟用，保存天數符合需求。
- Maintenance Window 與 Backup Window 避開流量高峰。
- Parameter Group 與 Option Group 使用正確版本。
- CloudWatch Alarm 已設定，至少包含儲存空間與連線數。
- Enhanced Monitoring 或 Performance Insights 是否需要啟用。
- Deletion Protection 是否符合環境需求。
- 已做過一次還原測試，確認備份不是只存在帳面上。

## 結語

建立 RDS for SQL Server 並不只是把資料庫從 EC2 換到 Managed Service。真正的重點是把資料庫維運拆成幾個可以被明確管理的面向：網路、安全、版本、參數、儲存、備份、監控、維護與還原。

如果只是開發測試，一台小型 SQL Server Express RDS 很快就能建立起來。但如果要進正式環境，就不能只看建立流程是否成功，而要確認它是否能被長期維運、監控、備份與還原。

RDS 不能消除所有資料庫責任，但它能讓團隊少處理很多底層平台工作。當資料庫不是公司想投入維運差異化的核心能力時，把這些工作交給 Managed Service，通常會比自建一套資料庫平台更實際。

## 參考資料

- [Amazon RDS for Microsoft SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_SQLServer.html)
- [Microsoft SQL Server versions on Amazon RDS](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.VersionSupport.html)
- [Version policy for Amazon RDS for Microsoft SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.VersionPolicy.html)
- [Support for native backup and restore in SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.BackupRestore.html)
- [Setting up for native backup and restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.Native.Enabling.html)
- [Importing and exporting SQL Server databases using native backup and restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.html)
- [Using native backup and restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.Native.Using.html)
- [Troubleshooting native backup and restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Procedural.Importing.Native.Troubleshooting.html)
- [Integrating an Amazon RDS for SQL Server DB instance with Amazon S3](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/User.SQLServer.Options.S3-integration.html)
- [Enabling RDS for SQL Server integration with S3](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.Options.S3-integration.enabling.html)
- [Functions and stored procedures for Amazon RDS for Microsoft SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.StoredProcedures.html)
- [Common DBA tasks for Amazon RDS for Microsoft SQL Server](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.SQLServer.CommonDBATasks.html)
- [Unsupported and limited-support features](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.FeatureNonSupport.html)
- [Terraform Registry: aws_db_option_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_option_group)
