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

### 建立選項群組

Option Group 是 RDS 中比較容易被忽略的設定。它不是一般資料庫參數，而是用來啟用特定資料庫引擎的額外功能。

以 SQL Server 來說，如果希望使用 native backup/restore，將 `.bak` 檔案備份到 S3 或從 S3 還原，就需要在 Option Group 加入 `SQLSERVER_BACKUP_RESTORE` 選項，並讓 RDS 使用有 S3 權限的 IAM Role。

![RDS Option Group list page](/assets/img/rds/rds_option_group_list_page.png)

建立 Option Group 時，同樣要選擇 SQL Server 引擎與對應版本。

![RDS Option Group create page](/assets/img/rds/rds_option_group_create_page.png)

範例中可以先建立一個空的 Option Group，後續若要啟用 native backup/restore，再加入 `SQLSERVER_BACKUP_RESTORE`。

![RDS Option Group create sample](/assets/img/rds/rds_option_group_create_sample_page.png)

建立完成後，Option Group 會出現在列表中。

![RDS Option Group create result](/assets/img/rds/rds_option_group_create_result.png)

> 如果只是使用 RDS Automated Backup 與 PITR，不一定需要設定 SQL Server native backup/restore。只有在要匯入或匯出 `.bak` 檔、與既有 SQL Server 備份流程銜接時，才需要特別處理這個 Option Group。
{: .prompt-info}

### 設定 SQL Server 的 Option Group

如果這台 RDS for SQL Server 之後需要使用 native backup/restore，也就是把 SQL Server 的 `.bak` 檔放到 S3，再從 S3 還原到 RDS，或是從 RDS 備份 `.bak` 到 S3，那就不能只建立空的 Option Group。

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
6. 建立或修改 RDS DB Instance，將這個 Option Group attach 到 SQL Server。

S3 bucket 建議和 RDS DB Instance 放在同一個 Region，因為 RDS for SQL Server native backup/restore 不支援跨 Region 的 S3 bucket。若備份檔來自其他 Region，可以先透過 S3 Replication 或其他方式複製到 RDS 所在 Region。

IAM role 的 Trust relationship 可以參考下面的概念：

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
      "Resource": "arn:aws:s3:::<bucket-name>"
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
      "Resource": "arn:aws:s3:::<bucket-name>/<prefix>/*"
    }
  ]
}
```

如果備份檔需要 KMS 加密，IAM role 還要補上對應 KMS key 的 `kms:DescribeKey`、`kms:GenerateDataKey`、`kms:Encrypt`、`kms:Decrypt`，而且 KMS key policy 也要允許這個 IAM role 使用該 key。

> 建議使用專用 bucket 或至少使用專用 prefix，例如 `sqlserver-native-backup/`。如果 prefix 留空，RDS 在多檔還原時可能會掃到 bucket 中其他不相關檔案，排查起來會很麻煩。
{: .prompt-info}

### 建立資料庫

前面的 Subnet Group、Parameter Group 和 Option Group 建好後，就可以開始建立 RDS DB Instance。

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
- 是否選擇剛剛建立的 Option Group。
- Backup retention period 是否符合需求。
- Backup window 是否避開流量高峰。
- Maintenance window 是否符合維運時段。
- Deletion protection 是否需要啟用。
- Time zone、Collation 是否符合應用程式需求。

> Time zone 與 Collation 建立後不一定能輕易修改。尤其 Collation 會影響排序、比較與大小寫敏感行為，正式環境務必先和應用程式、報表與既有資料庫設定對齊。
{: .prompt-warning}

確認設定後按下建立，等待 RDS 狀態變成 Available。建立完成後，就可以取得 endpoint，使用 SQL Server Management Studio、Azure Data Studio、DBeaver 或應用程式連線測試。

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

## 方法二：使用 Terraform 建立

如果正式環境已經使用 Terraform 管理基礎設施，RDS 也建議放進 Terraform，避免 Console 設定漂移。

下面是一個簡化範例，展示 Subnet Group、Parameter Group、Security Group、S3 bucket、IAM role、Option Group 與 RDS Instance 的關係。實際環境請把 VPC、Subnet、KMS、密碼、Tag 與命名規則接到既有模組。

```hcl
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

resource "aws_db_subnet_group" "sqlserver" {
  name       = "sqlserver-demo-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = {
    Name = "sqlserver-demo-subnet-group"
  }
}

resource "aws_security_group" "sqlserver" {
  name        = "sqlserver-demo-sg"
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

resource "aws_db_parameter_group" "sqlserver" {
  name   = "sqlserver-demo-parameter-group"
  family = "sqlserver-ex-16.0"

  tags = {
    Name = "sqlserver-demo-parameter-group"
  }
}

resource "aws_db_option_group" "sqlserver" {
  name                     = "sqlserver-demo-option-group"
  option_group_description = "Option group for SQL Server demo"
  engine_name              = "sqlserver-ex"
  major_engine_version     = "16.00"

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
  engine_version = "16.00"
  license_model  = "license-included"

  instance_class        = "db.t3.small"
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  username = "admin"
  password = var.db_password
  port     = 1433

  db_subnet_group_name   = aws_db_subnet_group.sqlserver.name
  vpc_security_group_ids = [aws_security_group.sqlserver.id]
  parameter_group_name   = aws_db_parameter_group.sqlserver.name
  option_group_name      = aws_db_option_group.sqlserver.name

  backup_retention_period = 7
  backup_window           = "18:00-19:00"
  maintenance_window      = "sun:19:00-sun:20:00"

  multi_az            = false
  publicly_accessible = false
  deletion_protection = false
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = ["error", "agent"]

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
- [Unsupported and limited-support features](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/SQLServer.Concepts.General.FeatureNonSupport.html)
- [Terraform Registry: aws_db_option_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_option_group)
