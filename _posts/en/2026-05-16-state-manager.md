---
layout: post
title: "Automate EC2 Configuration Management with State Manager"
description: "This article introduces AWS Systems Manager's State Manager feature, demonstrating how to use Associations to continuously maintain the desired state of EC2 and implement automated tasks such as regular password rotation."
author: Mark_Mew
categories: [AWS]
tags: [AWS, EC2, SSM, State Manager]
keywords: [AWS State Manager, Run Command, EC2, Association, Automation]
lang: en
date: 2026-05-16
---

In the previous article, we introduced how to use `Run Command` to execute commands in batches on multiple EC2 instances.

However, if you want certain configurations to be "continuously maintained" or need to "execute tasks periodically," using Run Command alone can be inconvenient.

This is where `State Manager` comes in.

## What is State Manager?

`State Manager` is a feature of AWS Systems Manager that allows you to define the "desired state" of your EC2 instances and automatically execute specified SSM Documents on a schedule or event trigger to maintain that state.

In short, State Manager is a "schedulable, version-controlled Run Command."

## State Manager vs. Run Command

| Feature | Run Command | State Manager |
|---------|-------------|---------------|
| Execution | Manual or scheduled via EventBridge | Automatically via Association |
| Version Control | No built-in versioning | Supports versioned Associations |
| Execution History | Retains execution logs | Retains logs and compliance tracking |
| Target Management | Specify each time | Dynamic selection via Tag or Resource Group |
| Use Case | One-off or ad-hoc tasks | Ongoing, periodic tasks |

## Core Concept: Association

In State Manager, each automation task you create is called an `Association`.

An Association includes:

1. **SSM Document**: The script or command to execute
2. **Targets**: The EC2 instances to apply to
3. **Schedule**: How often to run
4. **Parameters**: Inputs required by the Document

Once created, Systems Manager will execute the Association according to your schedule and track each run's status.

## Example: Regular EC2 Password Rotation

Suppose you need to automatically rotate the local account password on all web servers every month. Using State Manager is easier to manage than EventBridge + Run Command.

### Step 1: Prepare the SSM Document

You can use AWS built-in `AWS-RunShellScript` (Linux) or `AWS-RunPowerShellScript` (Windows), or create a custom document.

For Linux, to update the `webuser` password:

```yaml
schemaVersion: '2.2'
description: Update webuser password
parameters:
  NewPassword:
    type: String
    description: New password for webuser
    noEcho: true
mainSteps:
  - action: aws:runShellScript
    name: updatePassword
    inputs:
      runCommand:
        - |
          echo 'webuser:{{NewPassword}}' | chpasswd
          echo "Password updated successfully"
```

### Step 2: Create the Association

Via AWS Console:

1. Go to **Systems Manager** > **State Manager**
2. Click **Create association**
3. Select your Document (e.g., the custom one above)
4. In **Targets**, choose:
   - Specific Instance IDs
   - Or dynamic selection via Tag (e.g., `Environment=Production` and `Role=WebServer`)
5. Set **Schedule** (e.g., `cron(0 2 1 * ? *)` for 2 AM on the 1st of each month)
6. Fill in **Parameters** (new password or reference from Parameter Store/Secrets Manager)
7. Click **Create association**

Via AWS CLI:

```bash
aws ssm create-association \
  --name "UpdateWebUserPassword" \
  --document-name "Custom-UpdatePassword" \
  --targets "Key=tag:Role,Values=WebServer" \
  --schedule-expression "cron(0 2 1 * ? *)" \
  --parameters "NewPassword=SecurePass123!" \
  --association-name "MonthlyPasswordRotation"
```

### Step 3: Check Execution Status

After creating the Association, you can view:

- **Status**: Success / Failed / Pending
- **Last execution time**
- **Compliance status**: How many instances are compliant

If a run fails, you can view detailed error messages.

## Association Version Management

A major advantage of State Manager is version control. When you change the Association (schedule, parameters, targets), each change creates a new version.

You can:

1. View historical versions
2. Compare differences
3. Roll back to previous versions

This is very useful in large environments for tracking changes.

## Why Not Just Use EventBridge + Run Command?

You might ask:

> Can't I just use EventBridge to schedule Run Command?

Technically yes, but State Manager offers extra benefits:

1. **Unified management interface**: All scheduled tasks are visible in one place
2. **Version control**: Track every change to Association configuration
3. **Compliance tracking**: See how many instances succeeded or failed
4. **Dynamic targets**: New EC2s matching a Tag are automatically included
5. **Built-in retry mechanism**: Failed executions can be retried automatically

For simple tasks, EventBridge is fine. For complex or large-scale management, State Manager is much more organized.

## Common State Manager Use Cases

### 1. Regular Security Patch Installation

```bash
aws ssm create-association \
  --name "AWS-RunPatchBaseline" \
  --targets "Key=tag:Environment,Values=Production" \
  --schedule-expression "cron(0 3 ? * SUN *)"
```

Every Sunday at 3 AM, Patch Manager runs automatically.

### 2. Ensure a Service is Always Running

```yaml
mainSteps:
  - action: aws:runShellScript
    name: ensureServiceRunning
    inputs:
      runCommand:
        - |
          if ! systemctl is-active --quiet nginx; then
            systemctl start nginx
            echo "Nginx was down, restarted"
          else
            echo "Nginx is running"
          fi
```

Check every 30 minutes if Nginx is running; restart if not.

### 3. Regularly Clean Temporary Files

```bash
aws ssm create-association \
  --name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=i-1234567890abcdef0" \
  --schedule-expression "rate(7 days)" \
  --parameters 'commands=["find /tmp -type f -mtime +7 -delete"]'
```

Clean up files older than 7 days in /tmp every week.

## How to View Association Execution History

### Console

1. Go to **Systems Manager** > **State Manager**
2. Select the Association
3. Switch to **Execution history**
4. See execution times, status, and targets

### CLI

```bash
aws ssm describe-association-execution-targets \
  --association-id "<association-id>" \
  --execution-id "<execution-id>"
```

## Troubleshooting

### 1. Association Stuck in Pending

Possible causes:

- SSM Agent not connected
- Insufficient IAM Role permissions
- Schedule not yet reached

### 2. Failed Execution with No Error Message

Check:

1. Document syntax
2. Parameter passing
3. SSM Agent logs on EC2: `/var/log/amazon/ssm/amazon-ssm-agent.log`

### 3. Run Association Immediately

Use `apply-association-now`:

```bash
aws ssm start-associations-once \
  --association-ids "<association-id>"
```

## Integrating with Parameter Store

If your Document needs sensitive parameters (like passwords), store them in Parameter Store or Secrets Manager instead of directly in the Association.

Example:

```bash
# Store password in Parameter Store
aws ssm put-parameter \
  --name "/app/webuser/password" \
  --value "SecurePass123!" \
  --type "SecureString"

# Reference in Association
aws ssm create-association \
  --name "Custom-UpdatePassword" \
  --targets "Key=tag:Role,Values=WebServer" \
  --parameters "NewPassword={{ssm:/app/webuser/password}}"
```

Benefits:

1. Centralized management
2. KMS encryption
3. Fine-grained IAM access control

## Summary

State Manager is a powerful feature in Systems Manager, enabling you to:

1. Define and maintain the desired state of EC2
2. Track changes with version control
3. Dynamically target new instances
4. Centrally monitor all automation tasks

Compared to Run Command or EventBridge alone, State Manager offers more comprehensive management, especially for long-term, periodic tasks.

Start with simple scenarios—like log cleanup or service monitoring—and gradually expand to more complex automation.

---

## References

1. AWS Systems Manager State Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html
2. About State Manager Associations: https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-state-about.html
3. Create Associations (Console): https://docs.aws.amazon.com/systems-manager/latest/userguide/sysman-state-assoc.html
4. SSM Document Syntax: https://docs.aws.amazon.com/systems-manager/latest/userguide/documents-syntax.html
