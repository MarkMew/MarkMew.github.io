---
layout: post
title: "Why You Should Consider Using RDS Instead of Continuing to Self-Host a Database on EC2"
image: https://fastly.picsum.photos/id/388/1200/630.jpg?hmac=3X4hBgiMUuCq4LWzGXpRr8aLv-ruGrEdVjJ5GJ_NBWc
description: "Running a database on EC2 may look flexible, but in practice you must handle capacity, backups, recovery, connections, monitoring, and patching yourself. This article explains why most teams should consider Amazon RDS first, and what limitations to keep in mind when adopting it."
author: Mark_Mew
categories: [AWS, EC2]
tags: [RDS, Database, AWS]
keywords: [RDS, Database, EC2, Self-hosted Database, PITR, RDS Proxy, CloudWatch, AWS Backup]
lang: en
date: 2026-07-15
---

When many teams first start using AWS, it feels natural to install the database on EC2.

The reason is straightforward: this is how they used to do it in an IDC or on virtual machines. Installing MySQL, PostgreSQL, or SQL Server by themselves seems more flexible, and it is easier to reuse existing operational habits. Launch an EC2 instance, attach EBS, configure a Security Group, install the database, and the service can start connecting.

But the hard part of running a database is usually not "installation."

The hard part is continuous operation:

- When the disk is almost full, can you expand capacity before an incident happens?
- Are backups succeeding every day? Have you actually restored from them?
- If data is accidentally deleted, can you recover to a specific point in time?
- When connections suddenly surge, will the application fail first, or will the database?
- Who schedules, validates, and rolls back OS, database version, and security patches?
- Does monitoring only look at CPU, or can it detect abnormal IOPS, latency, connections, and `FreeStorageSpace`?

If you have to handle all of these things yourself, a database on EC2 is no longer just a cheap VM. It becomes a database platform that requires long-term operational effort.

This article is not saying that "all databases must be moved to RDS." Rather, it aims to explain why, in most common web, internal system, and enterprise application scenarios, you should consider RDS first instead of continuing to operate a database as if it were just an ordinary EC2 instance.

## The Biggest Cost of a Self-Hosted Database Is Not the EC2 Bill

A common mistake when self-hosting databases is to compare only the instance price on the bill.

For example:

- An EC2 instance plus EBS looks cheaper than an RDS instance with similar specifications.
- Installing the database yourself avoids being constrained by RDS limitations.
- Existing backup scripts can still be reused, so there is no need to learn anything new.

These points are not necessarily wrong, but they only look at resource cost. They do not include operational cost.

When the database runs on EC2, you must at least take responsibility for the following:

| Operational item | Self-hosted EC2 Database | Amazon RDS |
| --- | --- | --- |
| OS maintenance | Update, reboot, and schedule by yourself | RDS manages underlying OS maintenance |
| Database installation | Install and configure by yourself | Choose the engine and version when creating the instance |
| Storage expansion | Expand EBS, the file system, and database settings yourself | Storage Autoscaling is available |
| Backup | Schedule, retain, clean up, and alert by yourself | Automated Backup, Manual Snapshot, AWS Backup |
| PITR | Manage Binlog, WAL, or Archive Log yourself | Restore to a point in time within the backup retention period |
| High availability | Build Standby, Replication, and Failover yourself | Multi-AZ deployment is available |
| Monitoring | Install agents and integrate tools yourself | CloudWatch, Enhanced Monitoring, Performance Insights |
| Patch | Track CVEs, test, and apply patches yourself | RDS provides Maintenance Window and Pending Maintenance |

Of course, RDS does not handle everything for free. You still need to decide instance specifications, backup retention, maintenance windows, parameter settings, monitoring alarms, and access control. But RDS turns many low-level tasks from "you must design and execute them yourself" into "you must configure the strategy and validate the result."

The difference between these two things is huge.

## Disk Capacity: Do Not Wait Until Storage Is Full

One of the worst situations for a database is running out of disk space.

With a self-hosted database on EC2, you can also expand EBS, but the actual process is usually more than clicking one button:

1. Notice that the disk is almost full.
2. Expand the EBS volume.
3. Extend the partition or file system.
4. Confirm that the directory used by the database can see the new capacity.
5. Observe whether IOPS, throughput, and latency can keep up.

These steps are not difficult, but when an alarm rings at midnight and the disk has only 2% left, every manual step becomes a risk.

RDS provides Storage Autoscaling. After it is enabled, when RDS detects that available space is insufficient, it automatically increases storage capacity according to configured conditions. It is not a silver bullet, because RDS storage cannot be directly reduced after expansion, and large data imports may still push the database into a storage-full state for a short period. You still need to set a reasonable initial capacity, maximum capacity, and alarms for `FreeStorageSpace`.

But it at least reduces the common risk of "forgetting to expand capacity."

> Storage Autoscaling is a protection mechanism, not a replacement for capacity planning. If the database keeps growing quickly, you still need to regularly review growth rate, retention policy, index bloat, and archiving strategy.
{: .prompt-warning}

## Backup and PITR: Having Backups Does Not Mean You Can Restore

Many systems have backups, but when an incident actually happens, teams discover that:

- Backups have been failing for several days.
- Backup files exist, but nobody knows the restore procedure.
- Restore takes too long and exceeds the system's acceptable RTO.
- The system can only be restored to yesterday morning, not five minutes before an accidental deletion.
- Backups and production data are in the same permission boundary, so they disappear together after a mistaken deletion or compromise.

A self-hosted database can certainly be done well. MySQL can use mysqldump, XtraBackup, and Binary Log; PostgreSQL can use pg_dump, pg_basebackup, and WAL archive; SQL Server also supports full backups, differential backups, and transaction log backups.

The problem is that the team must design, implement, monitor, rehearse, and hand over all of these processes by itself.

RDS Automated Backup creates snapshots during the backup window and retains transaction logs, allowing you to perform Point-in-Time Recovery within the backup retention period. For a standard RDS DB instance, the backup retention period can be set from 0 to 35 days. Setting it to 0 disables automated backups.

The most important idea here is that PITR restore does not overwrite the original DB. It creates a new DB instance. This is actually a good thing, because you can validate the data first, then decide whether to switch the application to the new database, extract data back into the original database, or use it only to inspect the state before the incident.

If your organization already uses AWS Backup, you can also include RDS in a unified Backup Plan. AWS Backup can centrally manage backup policies, retention periods, cross-account or cross-Region copy, and governance requirements such as Vault Lock. For companies with audit, compliance, or multi-account management needs, this is easier to govern than letting each team configure backups separately.

### A Backup Strategy Should Answer at Least Three Questions

Whether you use native RDS backups or AWS Backup, you should define these first:

| Question | What it means |
| --- | --- |
| What is the RPO? | The maximum amount of data loss you can accept |
| What is the RTO? | The maximum time you can accept before service is restored |
| How often do you run restore drills? | Confirm that backups are really usable, instead of only checking that their status is successful |

Many teams configure daily backups but never run restore drills. That only proves that "backups were generated." It does not prove that "the system can recover during an incident."

I recommend doing a restore drill regularly in a non-production environment and recording:

1. How long it takes to restore a DB to a specified point in time.
2. How long it takes for the application to switch the connection string.
3. Whether permissions, Parameter Group, Option Group, and Security Group settings are missing anything.
4. Whether the restored data matches expectations.

These results are far more valuable than simply saying, "We enabled backups."

## RDS Proxy: Do Not Let Connections Become the First Bottleneck

Database connections are not free resources.

Each connection consumes memory and CPU on the database side. When applications scale horizontally, the number of containers increases, or Lambda functions start in large numbers within a short time, connection storms can happen easily. The result is not that queries are truly too heavy, but that the database is busy creating, authenticating, and maintaining large numbers of connections.

On a self-hosted database, you might use PgBouncer, ProxySQL, HAProxy, or an application-level connection pool. These tools are good, but you also need to deploy, monitor, and maintain them yourself.

RDS Proxy is a managed proxy provided by AWS. It can maintain a connection pool between the application and RDS, reuse existing connections, and reduce the cost of frequently opening new ones. When used with Multi-AZ or failover, RDS Proxy can also help applications reconnect more reliably to an available DB.

RDS Proxy is especially suitable for:

- Lambda or short-lived workloads.
- API services where connection counts can surge.
- Environments where application-side connection pool settings are inconsistent.
- Systems that want to manage database credentials with Secrets Manager.

But it is not a query performance optimization tool. If the SQL itself is slow, indexes are poorly designed, or transactions are held for too long, RDS Proxy will not magically make queries faster. Its main purpose is connection management and stability during failover.

## CloudWatch and Enhanced Monitoring: Watch the Right Database Metrics

A common monitoring approach for self-hosted databases is to start with EC2 CPU, memory, and disk usage. These are important, but they are not enough for a database.

Database problems often appear in:

- Connection count keeps rising.
- `FreeStorageSpace` drops quickly.
- `ReadLatency` or `WriteLatency` increases.
- `ReadIOPS`, `WriteIOPS`, or throughput hits storage limits.
- CPU credits are exhausted.
- Replica lag grows.
- Locks or slow queries increase.

RDS sends many metrics to CloudWatch by default and can be paired with CloudWatch Alarms. When you need more detailed OS-level information, you can enable Enhanced Monitoring. When you need to analyze DB load, wait events, and SQL-level bottlenecks, you can use Performance Insights or CloudWatch Database Insights.

The point is not that "more tools are always better." The point is to establish a baseline first.

For example, 70% CPU may be healthy for some systems because they are naturally CPU-bound. But for another system that normally runs at only 15%, suddenly rising to 70% may indicate a query plan change or abnormal traffic. Without a baseline, alarm thresholds easily become guesswork.

I usually start with these basic alarms for production databases:

| Metric | What to observe |
| --- | --- |
| `CPUUtilization` | Whether it stays above the normal baseline for a long time |
| `FreeableMemory` | Whether memory is insufficient or under pressure |
| `FreeStorageSpace` | Whether storage is close to the alarm threshold |
| `DatabaseConnections` | Whether connections increase abnormally |
| `ReadLatency` / `WriteLatency` | Whether storage latency is getting worse |
| `ReadIOPS` / `WriteIOPS` | Whether I/O is approaching a bottleneck |
| `ReplicaLag` | Whether the read replica is falling behind the primary |

If I could only configure one alarm, I would choose `FreeStorageSpace` first. When a database disk becomes full, recovery pressure is usually the greatest, and it may affect writes, backups, and later maintenance.

## Patch and Maintenance Window: Maintenance Cannot Depend on Memory

A database requires not only database engine maintenance, but also underlying OS, hardware, and certificate maintenance.

When self-hosting a database on EC2, these tasks usually fall on the team:

- Track OS security updates.
- Decide whether a database minor version needs to be upgraded.
- Schedule downtime or rolling updates.
- Prepare a rollback plan.
- Verify application compatibility after the update.

If the team has mature SRE or DBA processes, these can be done well. But if the database is only a resource that an application team maintains "by the way," it can easily become infrastructure that nobody dares to touch for a long time.

RDS provides a Maintenance Window, allowing you to control when maintenance events start. Some updates can be applied immediately or scheduled for the next maintenance window. Required security or reliability updates cannot be delayed indefinitely. For Multi-AZ deployments, in some maintenance scenarios RDS can handle the standby first and then perform failover to reduce impact.

This does not mean RDS patching has no risk. You should still:

1. Set the Maintenance Window during the lowest-traffic period.
2. Enable event notifications so you know when there is Pending Maintenance.
3. Test engine upgrades in a non-production environment first.
4. Confirm that the application driver and ORM are compatible.
5. Keep snapshots and a rollback process for production.

The value of RDS is that it makes maintenance manageable, not that it lets you ignore maintenance entirely.

## Multi-AZ: High Availability Is Not Finished by Building One Standby

High availability for a self-hosted database usually involves:

- Synchronous or asynchronous replication between primary and standby.
- Failover decision logic.
- DNS or connection endpoint switching.
- Split-brain protection.
- Deciding which instance should run backups.
- Avoiding long outages during maintenance.

These are all specialized tasks. The most dangerous situation is when it "looks like there is a standby," but failover has never been rehearsed. When the primary fails, the team may discover that the standby is too far behind, permissions are incomplete, the application does not reconnect automatically, or DNS TTL makes the switchover exceed expectations.

RDS Multi-AZ can improve database availability and durability across different Availability Zones. It is not a feature for distributing read traffic. If you need read/write separation, you usually need to use Read Replica separately. The main value of Multi-AZ is to reduce the impact of single points of failure during infrastructure failures, maintenance, or some update scenarios.

If the database is a critical component in production, I would treat Multi-AZ as the default choice, not something to add later only if there is budget left.

## When Is Self-Hosting Still Suitable?

RDS fits most scenarios, but not all of them.

Self-hosting may still be necessary in the following cases:

- You need a database engine, version, or extension that RDS does not support.
- You need OS-level privileges or a special kernel, file system, or agent.
- You need highly customized backup, replication, or topology.
- Your licensing model or commercial contract does not fit RDS.
- Latency, performance, or hardware requirements exceed what RDS can provide.
- The team already has mature DBA/SRE capabilities, and self-hosting brings clear benefits.

These are all real reasons. But if the reason is only "we have always done it this way" or "RDS looks more expensive," then human effort, incident risk, maintenance maturity, and recovery capability should be included in the calculation again.

## Things to Confirm Before Adopting RDS

If you want to move from a self-hosted database on EC2 to RDS, I recommend preparing a checklist first.

### Specification and Capacity

- Current database size and growth rate over the past 3 to 6 months.
- CPU, memory, IOPS, throughput, and connection baselines.
- Whether Provisioned IOPS or specified IOPS / throughput on gp3 is needed.
- Initial capacity and maximum capacity for Storage Autoscaling.

### Availability and Recovery

- Whether Multi-AZ is enabled.
- Automated Backup retention days.
- Whether AWS Backup is needed for cross-account, cross-Region, or long-term retention.
- Whether RPO and RTO are documented.
- Whether a restore drill has been completed.

### Application Compatibility

- Whether the driver, ORM, and database version are compatible.
- Whether unsupported permissions, plugins, extensions, or system table operations are used.
- Whether connection strings, DNS, TLS, or certificates need adjustment.
- Whether RDS Proxy is needed.

### Operations and Security

- How Parameter Group and Option Group are managed.
- Whether Maintenance Window and Backup Window avoid peak hours.
- Whether CloudWatch Alarms, Event Notifications, and Log Export are configured.
- Whether IAM, Security Group, KMS, and Secrets Manager comply with company standards.

The migration itself can be done in many ways, such as Dump/Restore, Snapshot Restore, native replication, or AWS Database Migration Service. The first thing to clarify is not the tool, but downtime, data consistency, and the rollback plan.

## Conclusion

Running a database on EC2 is not wrong. The mistake is underestimating the weight of database operations.

A database is not an ordinary application server. It involves data correctness, backup and recovery, capacity growth, performance bottlenecks, security patches, and incident recovery. When the team does not have enough time to continuously handle these things, a self-hosted database may appear to save RDS cost, but in practice it may only hide the cost in future incidents and human effort.

The value of RDS is not only that "AWS installs the database for you." What it really provides is a managed operational foundation for databases:

1. Storage Autoscaling reduces the risk of insufficient capacity.
2. Automated Backup and PITR make recovery strategies easier to implement.
3. AWS Backup can centrally govern backup and retention policies.
4. RDS Proxy improves connection management and failover resilience.
5. CloudWatch, Enhanced Monitoring, and Performance Insights provide observability.
6. Maintenance Window makes patches and maintenance more controllable.

If your team already has mature DBA capability, self-hosting may still have value. But for most product teams, spending time on data modeling, query performance, data lifecycle, and application stability is usually more worthwhile than maintaining the underlying database platform yourself.

Foundational work that can be managed should be handed to Managed Services. Keep engineering energy for the places that truly require you to understand the business and system context.

## References

- [Amazon RDS: Managing capacity automatically with Amazon RDS storage autoscaling](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIOPS.Autoscaling.html)
- [Amazon RDS: Introduction to backups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html)
- [Amazon RDS: Backup retention period](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.BackupRetention.html)
- [Amazon RDS: Restoring a DB instance to a specified time](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_PIT.html)
- [AWS Backup: Amazon Relational Database Service backups](https://docs.aws.amazon.com/aws-backup/latest/devguide/rds-backup.html)
- [AWS Backup: Continuous backups and point-in-time recovery](https://docs.aws.amazon.com/aws-backup/latest/devguide/point-in-time-recovery.html)
- [Amazon RDS: Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [Amazon RDS: Monitoring Amazon RDS metrics with Amazon CloudWatch](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/monitoring-cloudwatch.html)
- [Amazon RDS: Monitoring OS metrics with Enhanced Monitoring](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_Monitoring.OS.html)
- [Amazon RDS: Maintaining a DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_UpgradeDBInstance.Maintenance.html)
