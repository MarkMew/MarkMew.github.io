---
layout: post
title: "Using Patch Manager to Auto-Patch EC2 Instances"
description: "Following the Systems Manager Session Manager setup, this guide covers Patch Manager to automatically scan and install OS patches on EC2 instances on a schedule."
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, IAM, SSM]
keywords: [AWS Systems Manager, Patch Manager, EC2, Auto Patching]
lang: en
date: 2026-05-03
---

Once you have Session Manager set up and SSM Agent running,

the next step is to automate patch management itself.

This is where Patch Manager comes in.

## What is Patch Manager?

`Patch Manager` is a feature within AWS Systems Manager

that lets you centrally manage OS and application patches across multiple EC2 instances.

Core capabilities:

1. Patch scanning: detect which patches are available
2. Patch installation: apply patches on schedule or manually
3. Compliance reporting: aggregate patch status across fleet
4. Exclusion rules: skip certain patches if needed

Compared to manual updates or homegrown cron jobs,

Patch Manager offers:

1. Centralized policy management
2. Audit trails and compliance reports
3. Flexible scheduling with maintenance windows
4. Automatic rollback on failure

## Prerequisites

Similar to Session Manager, you need:

1. EC2 already configured for Session Manager (IAM Role, Agent running)
2. EC2 can reach SSM endpoints (already set up)
3. IAM Role has Patch Manager permissions

## Configure IAM Policy

If you already have `AmazonSSMManagedInstanceCore` attached,

Patch Manager permissions are included.

For finer control, you can add this custom policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeDocument",
        "ssm:GetDocument",
        "ssm:DescribeDocumentParameters"
      ],
      "Resource": "arn:aws:ssm:*:*:document/AWS-RunPatchBaseline"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetAutomationExecution",
        "ssm:StartAutomationExecution",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:ListCommands"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:*:*:aws-patch-manager-*"
    }
  ]
}
```

Patch Manager typically doesn't require extra S3 or service permissions

unless you have custom patch sources.

## How Patch Manager Works

There are two operational modes:

1. **Scan Only**: check what patches are available, don't install
2. **Scan and Install**: scan and apply patches automatically

In practice, start with Scan Only for a few weeks,

then switch to Scan and Install once you're confident.

## Setting Up Patch Scheduling

### Step 1: Create a Patch Baseline

In AWS Console, go to Systems Manager > Patch Manager > Patch Baselines.

Create a new baseline:

1. Name: e.g. `linux-standard`
2. OS: choose Linux or Windows
3. Approval rules:
   - Enable auto-approval for patches matching certain classifications
   - Common choices: `Security`, `Bugfix`, `Enhancement`
   - Can also set approval delay (e.g. approve 7 days after release)

For patches you want to skip,

add them to Patch exceptions.

### Step 2: Create a Maintenance Window

In Systems Manager, go to Maintenance Windows.

Create a new maintenance window:

1. Name: e.g. `weekly-patch-sunday`
2. Schedule: Cron format, e.g. every Sunday at 2 AM
   ```
   cron(0 2 ? * SUN *)
   ```
3. Duration: e.g. 2 hours (buffer time)
4. Timezone: your ops timezone

### Step 3: Create a Patch Task

Add a task within that maintenance window:

1. Task type: `Run command`
2. Document: `AWS-RunPatchBaseline`
3. Service role: your Patch Manager role
4. Targets: select EC2 instances
   - Use tags (e.g. `Environment: Production`)
   - Or specify Instance IDs directly
5. Parameters:
   - Operation: `Install` (scan + install) or `Scan` (scan only)
   - Baseline Override: if multiple baselines exist, specify which one

### Step 4: Wait for Scheduled Execution

Patch Manager will run at your specified maintenance window.

Check compliance in Patch Manager > Compliance.

Each EC2 will show one of:

- Compliant: all patches installed
- Non-compliant: some patches pending
- Failed: execution failed

## Common Practices

### 1. Start with Scan Only

Don't jump straight to `Install`.

Run `Scan` for a few weeks to validate patch lists

before switching to `Install`.

### 2. Separate by Environment

Create different baselines for Dev, Staging, Prod.

Production can use conservative approval rules (delay 2-4 weeks),

while Dev is more aggressive.

### 3. Use Patch Groups

Tag EC2s with `Patch Group` to apply different strategies.

Reference these groups in your baselines.

### 4. Enable Notifications

Integrate with SNS or EventBridge

to get patch completion notifications and audit logs.

Essentially, EventBridge captures state changes from EC2 after Scan or Install,

then sends events downstream.

A simple EventBridge + SNS setup can deliver basic notifications.

For more detailed content—such as patch lists, failure reasons, and other specifics—

add a Lambda function to process and enrich the notification before sending via SNS.

## Troubleshooting

### 1) Maintenance Window passed but patches didn't run

Check:

1. EC2 IAM Role has Patch permissions
2. EC2 is Online (verify with `aws ssm describe-instance-information`)
3. Maintenance Window targets include this EC2

### 2) Patch execution failed

Common causes:

1. Patch install requires reboot but auto-reboot is off
2. Patch is incompatible with the system
3. Insufficient disk space

Review the detailed logs in Compliance.

### 3) System degrades after patching

Test patches in Staging first

to catch compatibility issues before Production.

### 4) Need to skip one patch run

Temporarily disable the Maintenance Window

or remove the EC2 from targets.

## Summary

Patch Manager's core value is:

no more manual SSH into each server,

unified scheduling, reporting, and auditing.

Recommended rollout:

1. Use Scan to understand current state
2. Test Install in non-critical environments
3. Set up tiered policies (Dev / Staging / Prod)
4. Monitor Compliance reports continuously

This establishes a robust automated patch governance process.

---

## References

1. AWS Patch Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-manager.html
2. AWS-RunPatchBaseline Document: https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-ssm-docs-run-command.html
3. Patch Baselines: https://docs.aws.amazon.com/systems-manager/latest/userguide/patch-baselines.html
4. Maintenance Windows: https://docs.aws.amazon.com/systems-manager/latest/userguide/maintenance-windows.html
