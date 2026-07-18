---
layout: post
title: "AWS SQL Server Setup Tutorial: A Complete Walkthrough from Creation to Connection"
image: https://fastly.picsum.photos/id/210/1200/630.jpg?hmac=U8wtlsOPi38zUOhUIWdeBtlklDDrIKanqey3u6CXoco
description: "Walk through creating RDS for SQL Server on AWS, including subnet groups, parameter groups, option groups, storage, connectivity, backups, and Terraform."
author: Mark_Mew
categories: [AWS, RDS]
tags: [Database, RDS, SQL Server]
keywords: [Database, AWS, RDS, SQL Server]
lang: en
date: 2026-07-18
---

SQL Server is a common relational database choice in enterprise systems. In on-premises environments or virtual machines, a DBA or system administrator usually installs SQL Server, tunes the operating system, plans backups, configures monitoring, and then hands the database over to applications.

On AWS, you do not necessarily need to carry all of that yourself. If you do not need special OS-level access, unsupported SQL Server features, or a custom licensing model, Amazon RDS for SQL Server is often easier to operate. RDS helps manage the underlying host, storage, backups, maintenance windows, monitoring integrations, and high availability capabilities, so the team can spend more time on data modeling, query performance, access control, and restore drills.

This article walks through creating an RDS for SQL Server DB instance in two ways:

- Creating it with the AWS Management Console.
- Creating the basic resources with Terraform.

The examples are aimed at development or test environments. For production, you still need to adjust the design based on data volume, RPO, RTO, security requirements, and availability requirements.

> Supported RDS for SQL Server versions change over time with AWS and Microsoft support policies. During implementation, use the AWS Management Console in your Region or `aws rds describe-db-engine-versions` as the source of truth.
{: .prompt-info}

## Things to Confirm Before You Start

Before creating RDS, confirm the following items first:

| Item | What to confirm |
| --- | --- |
| VPC and subnets | Which VPC the DB should use, and whether it should only be placed in private subnets |
| Security Group | Which sources can connect to SQL Server port `1433` |
| SQL Server version | Which SQL Server major/minor version the application supports |
| Edition | Feature and licensing differences among Express, Web, Standard, and Enterprise |
| Storage capacity | Initial capacity, maximum capacity, IOPS, throughput, and growth rate |
| Backups | Automated backup retention period, and whether PITR or AWS Backup is required |
| Maintenance window | When maintenance or version updates can be applied |
| Parameters and options | Whether a custom DB parameter group or option group is required |

These may look like small prerequisites, but database incidents often start with something decided too casually: the wrong network placement, the wrong version, a backup strategy that does not meet requirements, or a security group that is too open.

## Method 1: Create It with the AWS Management Console

Open the RDS page in the AWS Management Console.

![Amazon and RDS dashboard page](/assets/img/rds/rds_home_page.png)

The RDS creation flow itself is not difficult, but several group concepts are easy to mix up at first:

- DB subnet group: decides which subnets RDS can use.
- DB parameter group: manages database engine parameters.
- Option group: enables engine-specific features, such as SQL Server native backup and restore.
- Security Group: controls who can connect to the DB.

The following sections create these resources in order.

### Create a DB Subnet Group

If this is your first RDS setup, you usually start by planning a DB subnet group.

Even if a VPC already has multiple subnets, not every subnet is suitable for a database. In general, a database should not be placed directly in a public subnet and should not be directly reachable from the internet. A common approach is to place RDS in private subnets across multiple Availability Zones, then allow connections only from the application Security Group or internal network ranges.

If this is a new environment, the subnet group list might be empty. Choose the create button to start.

![RDS Subnet Group list page](/assets/img/rds/rds_subnet_group_list_page.png)

On the creation page, choose the VPC first. After selecting the VPC, you can select Availability Zones and subnets under that VPC.

![RDS Subnet Group create page](/assets/img/rds/rds_subnet_group_create_page.png)

I recommend choosing private subnets in at least two different Availability Zones. This better matches RDS high availability design if you enable Multi-AZ later, or when maintenance and failover scenarios occur.

![Subnet Group create sample](/assets/img/rds/rds_subnet_group_create_sample_page.png)

After it is created, the subnet group appears in the list.

![Subnet Group create result](/assets/img/rds/rds_subnet_group_create_result.png)

### Create a DB Parameter Group

Every database engine has parameters that can be tuned. With a self-managed SQL Server, you might adjust these through SQL Server Management Studio, T-SQL, or host-level configuration. In RDS, you cannot log in to the underlying OS, and you do not get full `sysadmin` privileges. Instead, you manage the parameters that RDS allows through a DB parameter group.

If you do not have any custom parameter groups yet, the list will be empty.

![RDS Parameter Group list page](/assets/img/rds/rds_parameter_group_list_page.png)

Choose Create to open the parameter group creation page.

![RDS Parameter Group create page](/assets/img/rds/rds_parameter_group_create_page.png)

A parameter group is tied to the database engine and major version. In other words, SQL Server 2019 and SQL Server 2022 require compatible parameter group families. When creating one, choose the family that matches the RDS version you plan to create.

![RDS Parameter Group create sample](/assets/img/rds/rds_parameter_group_create_sample_page.png)

After it is created, it appears in the parameter group list.

![RDS Parameter Group create result](/assets/img/rds/rds_parameter_group_create_result.png)

> Some parameter changes can be applied immediately, while others require a DB reboot. For production, test changes in a non-production environment first and confirm the maintenance window.
{: .prompt-warning}

### Create an Option Group

An option group is one of the easier RDS settings to overlook. It is not a general database parameter. It is used to enable additional features for specific database engines.

For SQL Server, if you want to use native backup and restore to back up `.bak` files to S3 or restore from S3, you need to add the `SQLSERVER_BACKUP_RESTORE` option to the option group and let RDS use an IAM role with S3 permissions.

![RDS Option Group list page](/assets/img/rds/rds_option_group_list_page.png)

When creating an option group, choose the SQL Server engine and the matching version.

![RDS Option Group create page](/assets/img/rds/rds_option_group_create_page.png)

For a basic demo, you can first create an empty option group. If you need native backup and restore later, add `SQLSERVER_BACKUP_RESTORE`.

![RDS Option Group create sample](/assets/img/rds/rds_option_group_create_sample_page.png)

After it is created, the option group appears in the list.

![RDS Option Group create result](/assets/img/rds/rds_option_group_create_result.png)

> If you only use RDS automated backups and PITR, you do not necessarily need SQL Server native backup and restore. You need this option mainly when importing or exporting `.bak` files, or when integrating with an existing SQL Server backup workflow.
{: .prompt-info}

### Configure the SQL Server Option Group

If this RDS for SQL Server DB instance needs native backup and restore later, meaning you want to put SQL Server `.bak` files in S3 and restore them to RDS, or back up `.bak` files from RDS to S3, an empty option group is not enough.

This feature requires three components to work together:

| Component | Purpose |
| --- | --- |
| S3 bucket | Stores SQL Server `.bak` backup files |
| IAM role and policy | Allows RDS to read from and write to the specified S3 bucket |
| Option group | Adds `SQLSERVER_BACKUP_RESTORE` and specifies the IAM role ARN |

The setup order can look like this:

1. Create an S3 bucket dedicated to SQL Server backup files.
2. Create an IAM role whose trust relationship allows `rds.amazonaws.com` to assume the role.
3. Attach an S3 permissions policy to the IAM role.
4. Add `SQLSERVER_BACKUP_RESTORE` to the SQL Server option group.
5. Set the IAM role ARN in the option setting `IAM_ROLE_ARN`.
6. Create or modify the RDS DB instance and attach this option group to SQL Server.

The S3 bucket should be in the same Region as the RDS DB instance, because RDS for SQL Server native backup and restore does not support an S3 bucket in a different Region. If the backup file comes from another Region, copy it to the Region where RDS is located first, for example with S3 Replication or another transfer process.

The IAM role trust relationship can follow this pattern:

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

The S3 permissions policy must at least allow RDS to list the bucket, get the bucket location, and read and write backup objects:

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

If the backup files need KMS encryption, add `kms:DescribeKey`, `kms:GenerateDataKey`, `kms:Encrypt`, and `kms:Decrypt` for the KMS key to the IAM role, and make sure the KMS key policy allows this IAM role to use the key.

> Use a dedicated bucket, or at least a dedicated prefix such as `sqlserver-native-backup/`. If you leave the prefix empty, RDS might scan unrelated files in the bucket during multifile restore, which makes troubleshooting unnecessarily painful.
{: .prompt-info}

### Create the Database

After the subnet group, parameter group, and option group are ready, you can create the RDS DB instance.

![RDS Database list page](/assets/img/rds/rds_database_list_page.png)

Choose Create database. The console shows many settings. I recommend choosing the full configuration flow instead of an overly simplified default path, because the database network, security, backups, and maintenance window should all be explicit.

![RDS Database create page](/assets/img/rds/rds_database_create_page.png)

Example settings:

```plaintext
Engine options
> SQL Server

Templates
> Dev/Test

Settings
> Database management type
>> Amazon RDS

> Edition
>> SQL Server Express Edition

> Engine version
>> Choose a version currently supported by the console, such as SQL Server 2022

> DB instance identifier
>> sql-server-express-demo

Credentials settings
> Master username
>> admin

> Credentials management
>> Self managed, or Secrets Manager depending on your company standard

> Master password
>> Use a strong password
```

This example uses Express Edition for demonstration and testing. For production, choose the proper edition based on feature requirements, licensing, database size, and performance requirements.

For the instance class, a development or test environment can start with a smaller t class, for example:

```plaintext
DB instance class
> Burstable classes
>> db.t3.small
```

For production, do not look only at CPU and memory. SQL Server workloads are often affected by IOPS, throughput, connection count, TempDB usage, query patterns, and locking behavior. Use monitoring data from the existing environment to estimate the required specifications.

#### Configure Storage

Storage settings require special attention. Besides the initial capacity, consider whether to enable storage autoscaling and whether you need to specify IOPS or throughput.

![RDS Database create page storage spec](/assets/img/rds/rds_database_create_page_storage_spec.png)

At minimum, confirm:

- Whether the initial capacity is enough for current data and short-term growth.
- Whether the maximum storage threshold matches budget and risk control.
- Whether gp3 needs specified IOPS or throughput.
- Whether a CloudWatch alarm should be created for `FreeStorageSpace`.

Storage autoscaling can reduce the risk of running out of database space, but it is not a replacement for capacity planning. RDS storage cannot be directly reduced after it is expanded. If growth is uncontrolled, it will still become a cost and governance issue.

#### Configure Connectivity and Security Groups

In the connectivity settings, choose the DB subnet group created earlier.

![RDS Database create page connection](/assets/img/rds/rds_database_create_page_connection.png)

Do not open the Security Group to `0.0.0.0/0`. SQL Server uses port `1433` by default. Allow only necessary sources, such as:

- The Security Group of the application servers.
- The Security Group of a bastion host or VPN.
- Internal company network ranges, only with stricter network controls.

For development or testing, you might temporarily allow `1433` from the VPC CIDR. For production, Security Group referencing is usually better because the rule follows the application resources instead of opening an entire network range.

#### Configure Monitoring, Backups, and Maintenance

For monitoring, you can start with the default CloudWatch metrics. If you need more detailed OS-level metrics, enable Enhanced Monitoring. If you need to inspect DB load, wait events, and SQL-level bottlenecks, enable Performance Insights or CloudWatch Database Insights.

![RDS Database create page addition config](/assets/img/rds/rds_database_create_page_addition_config.png)

Also confirm the following settings:

- Whether the parameter group created earlier is selected.
- Whether the option group created earlier is selected.
- Whether the backup retention period meets requirements.
- Whether the backup window avoids peak traffic.
- Whether the maintenance window matches the operations schedule.
- Whether deletion protection should be enabled.
- Whether time zone and collation match the application requirements.

> Time zone and collation are not always easy to change after creation. Collation especially affects sorting, comparisons, and case sensitivity. For production, align it with the application, reporting system, and existing database settings first.
{: .prompt-warning}

After confirming the settings, create the DB instance and wait until its status becomes Available. Then get the endpoint and test the connection with SQL Server Management Studio, Azure Data Studio, DBeaver, or the application.

The connection information usually looks like this:

```plaintext
Server / Host: <rds-endpoint>
Port: 1433
User: admin
Password: The password configured during creation
Database: Specify one if needed, or connect to the default database first
```

If you cannot connect, check these items first:

1. Whether RDS is Available.
2. Whether the client is in an allowed network location.
3. Whether the Security Group inbound rule allows the source to connect to `1433`.
4. Whether the route table, NACL, VPN, or bastion host is configured correctly.
5. Whether the SQL Server username and password are correct.
6. Whether DNS can resolve the RDS endpoint.

## Method 2: Create It with Terraform

If your production infrastructure is already managed by Terraform, I recommend managing RDS in Terraform as well to avoid configuration drift from console changes.

The following simplified example shows the relationship among the subnet group, parameter group, Security Group, S3 bucket, IAM role, option group, and RDS DB instance. In a real environment, connect VPC, subnets, KMS, passwords, tags, and naming rules to your existing modules.

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

This Terraform is only a demonstration. For production, adjust at least the following:

- Do not hard-code the password in `.tf` files. Use Secrets Manager, SSM Parameter Store, or CI/CD secrets.
- Enable `deletion_protection` for production.
- Avoid `skip_final_snapshot = true` for production.
- If the database is critical, evaluate `multi_az`.
- Confirm `family`, `engine_version`, and `major_engine_version` against the actual supported versions.
- Supported CloudWatch log exports vary by engine and version. Confirm them for your version.
- The S3 bucket must be in the same Region as the RDS DB instance.
- S3 bucket names are globally unique, so replace `backup_bucket_name` with your own name.
- If you want to encrypt `.bak` files with KMS, both the IAM policy and KMS key policy must allow this role to use the key.
- The trust policy example limits permissions to RDS DB and option group ARN patterns in the same account and Region. For production, you can restrict it further to explicit DB instance and option group ARNs.
- `backup_prefix` must match the S3 object path used during actual backup and restore operations.

## Backup and Restore Strategy

RDS for SQL Server commonly uses three backup approaches:

| Approach | Purpose |
| --- | --- |
| Automated Backup | RDS automated backups, supporting PITR within the retention period |
| Manual Snapshot | A manual DB snapshot at a specific point in time |
| Native backup and restore | Import or export SQL Server databases through `.bak` files and S3 |

Automated Backup is the most basic backup feature and should usually be enabled. It supports Point-in-Time Recovery within the configured backup retention period. If data is accidentally deleted, a deployment writes bad data, or a batch job corrupts records, you can restore to a specified point in time.

RDS PITR does not overwrite the original DB. It creates a new DB instance. This is usually safer because you can validate the data first, then decide whether to switch the application connection, copy data back to the original database, or keep it only for incident analysis.

Manual Snapshot is useful before major changes, such as upgrades, parameter adjustments, or large batch updates. It does not replace Automated Backup, but it gives you an explicit recovery point before a change.

Native backup and restore is better suited for integrating with existing SQL Server workflows. For example, you can back up an on-premises SQL Server database to a `.bak` file in S3 and restore it to RDS, or back up an RDS database to S3 for another environment. This requires `SQLSERVER_BACKUP_RESTORE` in the option group and an IAM role with S3 permissions.

A production backup strategy should answer at least three questions:

| Question | Meaning |
| --- | --- |
| What is the RPO? | The maximum amount of data loss you can accept |
| What is the RTO? | The maximum time you can accept before service is restored |
| How often do you run restore drills? | Confirm that backups are really usable, not just successful in status |

Having backups does not mean you can restore. I recommend regularly running restore drills in a non-production environment and recording restore time, cutover steps, permission differences, parameter groups, option groups, Security Groups, and application connection settings.

## Advantages of Using RDS for SQL Server

### Monitoring Is Easier to Put in Place

For a self-managed SQL Server on EC2 or on premises, you usually need to install agents, collect logs, and integrate a monitoring platform before the database becomes truly observable.

RDS provides many CloudWatch metrics by default, such as CPU, connections, storage, IOPS, and latency. If you need more detail, you can enable Enhanced Monitoring, Performance Insights, or CloudWatch Database Insights.

At minimum, I recommend setting alarms for:

| Metric | What to watch |
| --- | --- |
| `CPUUtilization` | Whether CPU stays above the normal baseline for a long time |
| `FreeableMemory` | Whether memory is insufficient |
| `FreeStorageSpace` | Whether storage is close to full |
| `DatabaseConnections` | Whether connections increase abnormally |
| `ReadLatency` / `WriteLatency` | Whether storage latency is getting worse |
| `ReadIOPS` / `WriteIOPS` | Whether I/O is approaching a bottleneck |

### Storage Expansion Is Simpler

On-premises or self-managed EC2 databases sometimes run into insufficient disk space. This is especially common when an application or batch job accidentally writes large logs, temporary data, or history data into the database.

RDS can use storage autoscaling to automatically increase storage when free space approaches a threshold. You still need capacity planning and cost control, but it reduces the pressure of manually expanding disks, file systems, and mount points in the middle of the night.

### Backups and Maintenance Are More Manageable

RDS provides Automated Backup, Manual Snapshot, PITR, and a maintenance window. These features do not mean DBAs or engineers can ignore the database. They turn many lower-level operational tasks into configurable, traceable, and testable processes.

If your organization already uses AWS Backup, you can include RDS in a centralized backup plan to manage retention periods, cross-account or cross-Region copies, and audit requirements.

### High Availability Is Easier to Standardize

If the database is a critical production component, evaluate Multi-AZ. RDS Multi-AZ improves availability and durability across Availability Zones and reduces impact during some maintenance or failure scenarios.

Multi-AZ is not a read-scaling feature. If you need to distribute read traffic, evaluate Read Replica or application-level read/write routing separately.

> For high availability, confirm both the SQL Server edition and engine version.
> RDS for SQL Server Multi-AZ mainly supports Standard and Enterprise. SQL Server 2022 Web Edition requires 16.00.4215.2 or later for block level replication. Express Edition does not support Multi-AZ.
{: .prompt-info}

## Limitations of RDS for SQL Server

### No Full `sa` or OS-Level Access

In RDS for SQL Server, the master user specified during creation is not the same as the `sa` account commonly used in self-managed SQL Server, and it does not have full `sysadmin` privileges. It is the highest-privilege user that AWS allows you to use.

This means some operations that require OS access, instance-level access, or `sysadmin` privileges cannot be performed. Before adopting RDS, confirm whether existing systems, operational scripts, backup workflows, or DBA habits depend on these permissions.

### Some SQL Server Features Are Not Supported

RDS for SQL Server is a managed service, so it cannot expose every feature available in a self-managed SQL Server. Common limitations include no server-level triggers, no features that require certain OS access, and no arbitrary changes to the underlying file system.

If an existing system depends heavily on SQL Server Agent jobs, linked servers, CLR, SSIS, SSRS, special backup workflows, or other advanced features, compare each requirement with the RDS support status before adoption.

### Version, Edition, and Resource Class Affect Features

SQL Server features depend on edition, version, and the RDS support scope. Express Edition is suitable for demos or small tests, but production systems are usually constrained by capacity, resources, and features. Web, Standard, and Enterprise editions also differ in cost and available features.

Do not move a test configuration directly into production just because it runs. For production, confirm:

- Whether the database size exceeds edition limits.
- Whether the application features are supported.
- Whether the RDS instance class supports the engine and edition.
- Whether licensing cost fits the budget.

## Checklist After Creation

After RDS is created, do not stop after one successful connection test. At minimum, confirm:

- RDS is not publicly accessible and is placed in the correct private subnets.
- The Security Group allows only necessary sources to connect to `1433`.
- The application or administration tools can connect successfully.
- Automated Backup is enabled and the retention period meets requirements.
- The maintenance window and backup window avoid peak traffic.
- The parameter group and option group use the correct versions.
- CloudWatch alarms are configured, at least for storage space and connections.
- Whether Enhanced Monitoring or Performance Insights should be enabled.
- Whether deletion protection matches the environment requirements.
- A restore test has been completed, proving the backup is more than a checkbox.

## Conclusion

Creating RDS for SQL Server is not just replacing an EC2 database with a managed service. The real point is to break database operations into clearly managed areas: network, security, versioning, parameters, storage, backups, monitoring, maintenance, and restore.

For development or testing, a small SQL Server Express RDS instance can be created quickly. For production, however, success is not just whether the instance was created. You need to confirm that it can be operated, monitored, backed up, and restored over the long term.

RDS does not remove all database responsibilities, but it does reduce a lot of low-level platform work. When database platform operations are not where your company wants to differentiate, handing that work to a managed service is usually more practical than building and operating the platform yourself.

## References

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
