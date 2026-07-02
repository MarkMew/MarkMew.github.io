---
layout: post
title: "AWS Cost Optimization in Practice: From Resource Inventory to Savings Plans"
description: "AWS cost optimization is about more than purchasing RIs. This article presents a sustainable FinOps approach covering cost visibility, idle resource cleanup, rightsizing, S3 Lifecycle, Spot, ALB consolidation, and scheduled shutdowns."
author: Mark_Mew
categories: [AWS]
tags: [AWS, Cost Management]
keywords: [AWS, Cost Management, FinOps, Savings Plans, Reserved Instances, Spot Instance]
lang: en
date: 2026-07-03
---

Cloud services have lowered the barrier to building infrastructure. Launching an EC2 instance or creating an RDS database now takes only a few minutes. But because resources are so easy to create, expired test environments, unused disks, and obsolete backups can also remain on the bill for months.

As a system gradually moves to AWS, higher costs do not necessarily mean waste. More users, better availability, and more complete redundancy all cost money. The real questions are whether we can explain the purpose of every expense and whether we are obtaining the performance and reliability we need at a reasonable price.

This article summarizes the approach I have used in cost optimization projects. The essential order is:

1. Make costs visible and attributable.
2. Remove resources that no longer provide value.
3. Right-size resources according to actual usage.
4. Only then use Reserved Instances or Savings Plans for discounts.

The order matters. If we begin by making a long-term commitment, we may lock in usage that is currently overprovisioned. Even if we later shut down those instances, the commitment remains.

## Background: A Higher Bill Does Not Tell You Where the Money Went

Like many companies undergoing digital transformation, we began defining SLAs and SLOs and gradually moved services to the cloud to improve system resilience. As the number of systems grew, our AWS bill increased year after year.

The first problem was not how to save money. It was that no one could immediately answer these questions:

- Which product, department, or environment generated this cost?
- Did the cost increase because traffic grew, or because someone forgot to shut down a resource?
- Is this EC2 instance required capacity, or was it oversized as a precaution?
- After a service was shut down, are its EBS volumes, snapshots, Elastic IP addresses, or logs still incurring charges?

Cost optimization therefore begins not with an architectural change, but with observability.

## Step 1: Establish a Cost Baseline

### Standardize Resource Tags

Resources such as EC2, RDS, S3, and ECR should at least identify their purpose and owner. The exact tag keys can be adapted to the organization. For example:

| Tag key | Example | Purpose |
| --- | --- | --- |
| `Application` | `order-service` | Identifies the product or system |
| `Environment` | `prod`, `staging` | Distinguishes production and non-production environments |
| `Owner` | `platform-team` | Identifies the team responsible for the resource |
| `CostCenter` | `CC-1001` | Maps the resource to an internal cost center |
| `ManagedBy` | `terraform` | Identifies how the resource is created and maintained |

After applying tags, you must activate them as Cost Allocation Tags in Billing and Cost Management before they can be analyzed in Cost Explorer or a Cost and Usage Report. A new tag key can take up to 24 hours to appear on the activation page, and activation itself can take another 24 hours. Tags are therefore not suitable for investigating today's costs in real time.

More importantly, Cost Allocation Tags do not retroactively fill in usage that was previously untagged. If the account already contains many resources, start by manually inventorying the services that account for the largest share of the bill. Then enforce tagging rules in Terraform, CloudFormation, or the resource provisioning pipeline so the problem does not return.

### Identify the Real Cost Drivers

Start in Cost Explorer by reviewing trends from the last three to six months. Group costs by Service, Linked Account, Region, Usage Type, and Tag. Do not stop at “EC2 costs this much.” Expand the bill and examine:

- EC2 running hours and instance types
- EBS capacity, IOPS, and snapshots
- Data processed by NAT Gateway
- Cross-Availability Zone, cross-Region, and internet data transfer
- RDS instances, storage, and backups
- Load Balancer running hours and LCUs
- CloudWatch Logs ingestion and retention

Record the monthly cost, resource count, and key metrics at the time of analysis. Without a baseline, all you can say after the work is complete is that the bill “feels lower”; you cannot demonstrate the effect of the changes.

AWS Budgets and Cost Anomaly Detection are also useful. Budgets help track whether spending exceeds expectations, while Anomaly Detection identifies expenses that differ from historical patterns. Both are alerts rather than substitutes for resource management, but they reduce the time an unnoticed problem remains on the bill.

## Step 2: Remove Resources with No Business Value First

Deleting a completely unnecessary resource is usually more effective than finding a 20% discount for it. I prefer to create a list of candidates, have each owner confirm them, and set an observation period and deletion date. This prevents cost savings from accidentally breaking a service that is still in use.

### Remove Idle EC2 Instances, Not Merely Small Ones

Companies often retain test instances such as `t3.small` and `t3.medium`. Because a single instance appears inexpensive, no one pays much attention to it. But dozens of similar resources running for months still create a steady expense.

A small instance is not automatically safe to delete. At minimum, verify:

- Whether CPU, network, and disk I/O have remained near zero during the last 30 days
- Whether there are recent connections, scheduled jobs, or deployment records
- Whether DNS, a Target Group, or an Auto Scaling Group still points to it
- Whether the owner can explain its purpose and retention period

Once the instance is confirmed as unnecessary, create a snapshot or AMI if required, stop it for an observation period, and finally terminate it. Stopping an EC2 instance only stops its compute charges; attached EBS volumes and some IP resources can continue to incur charges.

Apply the same review to unattached EBS volumes, obsolete snapshots, idle Elastic IP addresses, old AMIs, Load Balancers with no traffic, and RDS databases left behind after testing.

### Remove Old S3 Versions and Configure Lifecycle Rules

CI/CD pipelines often upload JavaScript, CSS, installation packages, and reports to S3. If every build is retained, more projects and more frequent deployments eventually leave a bucket full of objects that will never be read again. Buckets with Versioning enabled also require a review of noncurrent versions. Just because they are not visible in the default view does not mean they consume no storage.

Rather than deleting objects manually at regular intervals, configure S3 Lifecycle rules according to the nature of the data:

- CI artifacts: retain only the latest versions and delete the rest after 30 or 90 days.
- Unknown access patterns: consider moving objects to S3 Intelligent-Tiering.
- Long-term regulatory retention with almost no access: evaluate a Glacier storage class.
- Parts left by incomplete multipart uploads: remove them automatically after a few days.

Moving data to Glacier as early as possible is not always cheaper. Some storage classes have minimum storage durations, retrieval fees, and per-object overhead. A large number of very small files may not be suitable for archival either. Estimate costs based on object size, access frequency, retention period, and recovery time objectives before defining the rules.

## Step 3: Right-Size Instead of Blindly Downsizing

After cleanup, address resources that are still useful but overprovisioned. Based on current configurations and utilization metrics, AWS Compute Optimizer can make recommendations for EC2, Auto Scaling Groups, EBS, ECS on Fargate, and some RDS and Aurora resources.

Do not look only at average CPU utilization. Any of the following may become the bottleneck:

- Average and peak CPU utilization
- Memory usage and swap
- Network packets per second and throughput
- EBS IOPS, throughput, and queue length
- RDS connections, freeable memory, and read/write latency
- CPU Credit Balance for T-family instances

Memory utilization is not a standard metric that EC2 sends to CloudWatch by default. It must be collected through the CloudWatch Agent or an existing monitoring system. If you make a decision based on CPU alone, it is easy to downsize a memory-intensive service too far.

When changing a resource size, retain adequate headroom, validate the change in a non-production environment, and apply it during a low-risk period. In production, also verify startup time, Auto Scaling behavior, fault tolerance, and rollback procedures. The goal of cost optimization is to eliminate waste, not to operate the system without any safety margin.

### Standardize Configurations Without Overconstraining Them

When a team maintains too many EC2 families, operating systems, and database versions at once, monitoring, patching, images, and capacity planning all become more complicated. Converging similar workloads on a small set of validated configurations makes operations and long-term discount planning easier.

However, there is no need to force every service to use only three instance types. Compute-intensive, memory-intensive, and general-purpose workloads naturally have different needs. Excessive restrictions may also prevent teams from benefiting from the price-performance improvements of newer instance generations or Graviton. The purpose of standardization is to remove meaningless variation, not to make every workload wear the same pair of shoes.

## Step 4: Choose the Appropriate Pricing Model

Only after cleanup and rightsizing can you clearly see the stable baseline usage. At that point, decide which workloads should use On-Demand, Reserved Instances, Savings Plans, or Spot.

### Reserved Instances and Savings Plans

With Savings Plans, you commit to a fixed dollar amount of compute usage per hour for one or three years in exchange for prices below On-Demand rates. This is not a prepaid bundle of “usable hours.” If there is insufficient eligible usage in a given hour, you still pay the committed amount for that hour.

In practice, consider the following:

- Long-running, stable services such as RDS, ElastiCache, and OpenSearch: evaluate the relevant Reserved Instance or Reserved Node offering.
- A stable EC2 family and Region where a larger discount is preferred: evaluate EC2 Instance Savings Plans.
- Workloads that may move across families or Regions, or that use Fargate and Lambda: evaluate the more flexible Compute Savings Plans.
- Short-term projects, uncertain demand, or services that may be retired: remain on On-Demand rather than rushing into a commitment.

Cost Explorer recommendations are useful before a purchase, but verify whether the selected lookback period represents future usage. AWS recommendations are calculated from historical usage. They do not predict a product shutdown, an architectural migration, or next month's traffic change.

A more conservative approach is to purchase in stages. Cover only the baseline usage that is certain to remain, observe Coverage and Utilization, and then gradually increase the commitment. Do not pursue 100% Coverage at the cost of low Utilization.

### Spot Instances

Spot is suitable for interruptible, retryable, and horizontally scalable workloads such as batch processing, CI runners, image transcoding, and stateless workers. It is not suitable for replacing an irreplaceable single production server with Spot and simply hoping it will never be reclaimed.

Design the system to handle Spot interruptions:

- Store job state externally rather than on a single instance's local disk.
- Make tasks idempotent so they can be retried safely.
- On receiving an interruption notice, stop accepting new work and drain the instance.
- Configure an Auto Scaling Group with multiple acceptable instance types and Availability Zones.
- Use an allocation strategy such as Capacity Optimized instead of selecting only the cheapest pool with insufficient capacity.
- Retain some On-Demand baseline capacity for critical services.

The [EC2 Spot Instance Advisor](https://aws.amazon.com/ec2/spot/instance-advisor/) provides historical interruption frequencies for instance pools, but no instance family should be considered permanently safe or unsafe. Spot capacity changes by Region, Availability Zone, instance type, and time. Diversifying across instance types is generally more reliable than betting on a single one.

## Step 5: Reduce Fixed Costs Through Architecture

Some costs cannot be improved by choosing a smaller instance. They come from duplicated infrastructure components in the architecture.

### Consolidate ALBs for Low-Traffic Systems

An ALB can route requests to different Target Groups using Host Header or Path Pattern rules. The frontend, backend, order, and membership modules of the same low-traffic system do not necessarily each require their own ALB.

If six low-traffic modules originally have one ALB each, consolidation can reduce the fixed hourly Load Balancer cost. However, the final bill will not necessarily fall to exactly one sixth. ALBs also charge by LCU, and Listener Rules, certificates, WAF, and cross-AZ traffic may affect the total.

More importantly, consolidation increases the blast radius. Separate ALBs remain appropriate when:

- Systems belong to different security boundaries or accounts
- They require different WAF, TLS, or access policies
- Their release and maintenance cycles differ
- One system receives enough traffic to affect the others
- Independent observability, quotas, or failure isolation are required

ALB consolidation is therefore suitable for services with low traffic, similar lifecycles, and common security requirements. It is not a rule that every system should share one ALB.

### Schedule Non-Production Environments to Start and Stop

Development, test, and training environments rarely need to run 24 hours a day, 365 days a year. EventBridge Scheduler can work with Lambda, Systems Manager Automation, or AWS Instance Scheduler to start resources before business hours and stop them afterward.

If an environment is needed for only ten hours on each weekday, excluding holidays, scheduling can significantly reduce EC2 running time. Keep the following in mind:

- Persistent resources such as EBS continue to incur charges after EC2 is stopped.
- A public IPv4 address not associated with an Elastic IP may change after restart.
- Data on Instance Store does not persist across a stop/start cycle.
- RDS storage, Provisioned IOPS, and backups continue to incur charges while the database is stopped.
- A regular RDS DB instance can remain stopped for no more than seven consecutive days before it starts automatically.

Scheduled shutdowns are most suitable for non-production environments that can tolerate startup time. For production environments with predictable peaks and troughs, use Auto Scaling to adjust capacity according to demand rather than switching instances off at a fixed time.

### Do Not Ignore Network and Logging Costs

Once compute costs have been reduced, NAT Gateway, Data Transfer, and CloudWatch Logs often become much more visible.

Areas to investigate include:

- Whether a Private Subnet sends large amounts of S3, DynamoDB, or other AWS service traffic through a NAT Gateway, and whether a VPC Endpoint can be used instead
- Whether cross-AZ calls are required by the architecture or caused by indirect service discovery and traffic routing
- Whether containers continuously emit unusable debug logs
- Whether CloudWatch Log Groups lack a Retention Policy and retain data forever
- Whether ECR images and snapshots have Lifecycle Policies

Understand the traffic path before changing these costs. Sacrificing Multi-AZ availability merely to avoid cross-AZ charges is usually a poor tradeoff.

## Making Cost Optimization Sustainable

A one-time cost project can easily return to its original state within six months. A more effective approach is to make cost part of normal engineering work:

1. Require every resource to have Owner, Application, and Environment tags when created.
2. Have product, finance, and platform teams review cost trends and anomalies together each month.
3. For every improvement, record the original cost, estimated savings, risk, owner, and completion date.
4. Regularly review RI and Savings Plans Coverage and Utilization.
5. Add defaults such as Log Retention, S3 Lifecycle, and non-production scheduling to Terraform or organizational policies.
6. Notify owners automatically about unowned, idle, or expired resources rather than deleting them automatically.

“How much less did we spend this month?” should not be the only cost metric. If a product is growing, a higher total bill may be entirely reasonable. Unit costs such as cost per active user, order, API request, or tenant are often more meaningful.

## Conclusion

AWS cost optimization is not a matter of seeing a large bill at the end of the month and hastily shutting down a few instances. Nor does it end after purchasing Savings Plans. It is a continuous cycle: establish cost visibility, remove idle resources, right-size configurations, select pricing models, and return to monitoring and validation.

If I could begin with only three actions, I would choose these:

1. Give every major cost an owner and a purpose.
2. Remove resources that are confirmed to provide no value, and define retention periods for data.
3. Complete rightsizing before purchasing long-term commitments in stages.

The savings matter, but creating a mechanism that tells the team why the money is being spent matters even more. When cost can be discussed alongside reliability, performance, and product value, FinOps stops being merely about deleting resources and becomes genuine engineering decision-making.

## References

- [AWS Billing: Activating user-defined cost allocation tags](https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/activating-tags.html)
- [AWS Compute Optimizer: Supported resources](https://docs.aws.amazon.com/compute-optimizer/latest/ug/supported-resources.html)
- [AWS Savings Plans: What are Savings Plans?](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html)
- [AWS Savings Plans: Understanding recommendation calculations](https://docs.aws.amazon.com/savingsplans/latest/userguide/sp-rec-calculations.html)
- [Amazon EC2: Spot interruption notices](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-instance-termination-notices.html)
- [Amazon S3: Transitioning objects using Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/lifecycle-transition-general-considerations.html)
- [Elastic Load Balancing: Listeners for Application Load Balancers](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
- [Amazon EC2: How instance stop and start works](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/how-ec2-instance-stop-start-works.html)
- [Amazon RDS: Stopping a DB instance temporarily](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_StopInstance.html)
