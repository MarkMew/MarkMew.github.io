---
layout: post
title: "Running Commands on EC2 On Demand"
description: "Building on the Systems Manager Session Manager setup, this guide covers how to run commands on EC2 instances using Run Command."
author: Mark_Mew
categories: [AWS]
tags: [AWS, EC2, SSM]
keywords: [AWS Systems Manager, Run Command, EC2]
lang: en
date: 2026-05-10
---

The previous post walked through connecting to EC2 via `Systems Manager`.

Once you can open a shell with Session Manager,

the next natural question is:

can I skip logging in one by one,

and just send commands directly from AWS?

That is exactly what `Run Command` is for.

It is a good fit for tasks like these:

1. Checking service status across a fleet
2. Pushing a simple configuration file
3. Restarting services or scheduled jobs
4. Applying a quick OS-level fix

This post covers `Run Command` permission setup,

the key differences between Linux and Windows,

and a hands-on Windows example of changing a local user password via PowerShell.

## What is Run Command?

`Run Command` is the remote execution feature inside AWS Systems Manager.

You pick a set of EC2 instances,

choose an AWS-provided Document such as:

1. `AWS-RunShellScript`
2. `AWS-RunPowerShellScript`
3. `AWS-RunPatchBaseline`

and Systems Manager delivers the commands to the `SSM Agent` on each node,

which then executes them locally.

Because of this,

the first thing to verify is not the command itself —

it is whether permissions are set correctly.

## Prerequisites

Just like Session Manager,

getting Run Command to work on an EC2 instance requires four things:

1. EC2 is attached to the correct IAM Role
2. `SSM Agent` is installed and running on the host
3. The host can reach Systems Manager endpoints over TCP 443
4. The caller (person or system sending commands) also has sufficient IAM permissions

The first three are about making the node manageable.

The fourth is about who is allowed to issue commands.

The fourth one is easy to miss —

the instance can show as Online,

yet the command fails because the operator lacks `ssm:SendCommand`.

## Permission Setup

Permissions split into two parts:

1. The EC2 Instance Role
2. The caller's IAM User or Role

### EC2 Instance Role

Start by attaching `AmazonSSMManagedInstanceCore` to the instance.

This AWS Managed Policy covers the baseline permissions the node needs to register with Systems Manager,

receive commands, and report results.

If your script also accesses other AWS services, such as:

1. Downloading a script from S3
2. Writing logs to CloudWatch Logs
3. Reading a secret from Secrets Manager

those permissions must be added to the EC2 Instance Role separately.

`AmazonSSMManagedInstanceCore` only makes the node manageable —

it does not grant access to every AWS resource your script might touch.

### Caller IAM Permissions

The person or system sending the command needs at minimum:

1. `ssm:SendCommand`
2. `ssm:GetCommandInvocation`
3. `ssm:ListCommandInvocations`
4. `ssm:ListCommands`

If you are operating through the AWS Console, you will also typically need:

1. `ssm:DescribeInstanceInformation`
2. `ssm:ListDocuments`
3. `ssm:DescribeDocument`

Here is a minimal example policy:

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

For tighter control, narrow down `Resource` to specific Documents and EC2 Tag conditions.

Avoid defaulting to `AdministratorAccess` —

Run Command is essentially remote execution,

and overly broad permissions translate directly into a high level of host control.

## Linux vs Windows: The Differences That Matter

This section is important.

Even though both platforms use "Run Command",

Linux and Windows differ significantly in how you configure and execute commands.

### 1. Different Documents

Linux typically uses:

`AWS-RunShellScript`

Windows typically uses:

`AWS-RunPowerShellScript`

Linux receives shell commands.

Windows receives PowerShell commands.

### 2. Different Execution Identity

On Linux, `SSM Agent` runs commands as `root` by default.

On Windows, `SSM Agent` runs commands as `NT AUTHORITY\SYSTEM` by default.

This directly affects two things:

1. Whether you still need `sudo`
2. Whether the command can access certain user-scoped resources

On Linux, since you are already `root`,

you generally do not need to prefix commands with `sudo`.

On Windows, `SYSTEM` has very high privileges,

but it is not an interactive logon user,

so behaviors tied to user profiles, desktop sessions, mapped drives, or certain certificate stores

should not be assumed to work the same way as when you RDP in.

### 3. Different Permission Supplementation

On Linux, if you only need to modify system files, query services, or restart a daemon,

the node being managed by SSM is usually enough.

On Windows, if you are touching local accounts, service accounts, the registry, or scheduled tasks,

you need to consider whether `SYSTEM` is allowed to perform that specific operation.

In the password change example at the end of this post,

changing a local Windows account password is achievable through Run Command —

but changing a domain account is an entirely different story.

### 4. Different Script Format and Escaping

Linux typically looks like:

```bash
systemctl restart nginx
cat /etc/os-release
```

Windows typically looks like:

```powershell
Restart-Service W32Time
Get-ComputerInfo
```

PowerShell and Bash also handle quotes, variables, and multiline scripts differently.

That is why I recommend maintaining separate scripts for Linux and Windows

rather than trying to shoehorn a single script into both.

## Platform-Specific Things to Watch

### Linux

1. Confirm the target has a supported shell environment
2. Check that file paths, permission model, and service management match your Linux distribution
3. If your script relies on external tools like `jq`, `aws`, or `python3`, make sure they are pre-installed

For example, to check service status:

```bash
systemctl status amazon-ssm-agent --no-pager
```

If your command relies on a home directory,

remember the executor is `root`, not `ec2-user` or whatever account you normally log in as.

### Windows

1. The target must have a PowerShell execution environment
2. For newer Cmdlets, verify Windows Server version and PowerShell version compatibility
3. Operations that depend on an interactive desktop session are generally not suitable for Run Command

For example, to check SSM Agent service status:

```powershell
Get-Service AmazonSSMAgent
```

If you need to manage local user accounts,

confirm the `Microsoft.PowerShell.LocalAccounts` module is available on that host version,

otherwise fall back to `net user`.

## How to Send a Run Command

### Via AWS Console

1. Open Systems Manager
2. Navigate to `Run Command`
3. Click `Run command`
4. Select a Document
5. Choose target EC2 instances (by Instance ID or Tag)
6. Enter your command content
7. Submit and check the execution output

### Via AWS CLI

Sending a shell script to Linux:

```bash
aws ssm send-command \
  --document-name "AWS-RunShellScript" \
  --targets "Key=instanceids,Values=i-0123456789abcdef0" \
  --parameters 'commands=["uname -a","id","systemctl status amazon-ssm-agent --no-pager"]'
```

Sending PowerShell to Windows:

```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets "Key=instanceids,Values=i-0123456789abcdef0" \
  --parameters 'commands=["Get-ComputerInfo | Select-Object WindowsProductName,OsVersion","Get-Service AmazonSSMAgent"]'
```

If you are calling the AWS CLI from a Windows machine using PowerShell,

quoting and escaping get considerably more complex.

It helps to build the parameters as a variable or load them from a file

instead of constructing everything inline on the command line.

## Windows Example: Changing a Local User Password via PowerShell

The following example targets a Windows Server local account.

Scope clarification upfront:

1. This changes a Windows local user password
2. It does not change an AD domain account password
3. The command is sent via Run Command using `AWS-RunPowerShellScript`

### Option 1: Using `Set-LocalUser`

If the Windows Server has the `LocalAccounts` module available:

```powershell
$userName = "app-user"
$plainPassword = "ChangeMe_2026!"
$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force

Set-LocalUser -Name $userName -Password $securePassword
Write-Output "Password changed for local user: $userName"
```

This snippet can be placed directly into the `commands` parameter of `AWS-RunPowerShellScript`.

### Option 2: Using `net user`

If `Set-LocalUser` is not available:

```powershell
net user app-user "ChangeMe_2026!"
```

This works for local accounts,

but the password appears directly in the command string,

which is less readable and harder to protect down the line.

### Full CLI Example with Run Command

```bash
aws ssm send-command \
  --document-name "AWS-RunPowerShellScript" \
  --targets "Key=instanceids,Values=i-0123456789abcdef0" \
  --comment "Rotate local Windows password" \
  --parameters 'commands=["$userName = \"app-user\"","$plainPassword = \"ChangeMe_2026!\"","$securePassword = ConvertTo-SecureString $plainPassword -AsPlainText -Force","Set-LocalUser -Name $userName -Password $securePassword","Write-Output \"Password changed for local user: $userName\""]'
```

## Security Risk to Be Aware Of

The example above uses the most straightforward approach on purpose,

but you should have already noticed one issue:

the password appears in plain text inside the command.

In a production environment, this is usually not acceptable,

because the password can show up in:

1. Command history
2. Run Command execution logs
3. Audit or debugging views

A more appropriate production flow is:

1. Generate the new password from a secure external source
2. Run Command performs the password change
3. After the change, securely store the password or trigger a downstream process

## How to Confirm a Command Executed Successfully

You can review results in the Systems Manager execution history,

or query via CLI:

```bash
aws ssm list-command-invocations \
  --command-id <command-id> \
  --details
```

For a single instance:

```bash
aws ssm get-command-invocation \
  --command-id <command-id> \
  --instance-id <instance-id>
```

Key fields to check:

1. `Status`
2. `StandardOutputContent`
3. `StandardErrorContent`

### Success Interpretation Also Differs by Platform

On Linux, exit code and stdout/stderr are the standard signals.

On Windows, in addition to the exit code,

watch for PowerShell silently swallowing errors.

For stricter failure detection, add this at the top of your script:

```powershell
$ErrorActionPreference = "Stop"
```

With this set, any Cmdlet error will cause Run Command to fail outright,

rather than appearing to succeed while quietly ignoring mid-script errors.

## Common Issues

### 1) Instance is Online but Run Command still fails

Check:

1. Whether the caller has `ssm:SendCommand`
2. Whether the correct Document is selected (don't send PowerShell to Linux or Shell to Windows)
3. Whether the EC2 Instance Role has permissions for any AWS resources the script accesses

### 2) A command works when logged in manually on Linux, but fails via Run Command

Typical causes:

1. You logged in as `ec2-user`, but Run Command runs as `root`
2. User-specific environment variables, PATH, or home directory differ
3. The command depends on settings loaded only in an interactive shell session

### 3) Command succeeds on Windows but the result is unexpected

Typical causes:

1. You expected it to run as a specific logged-in user, but it actually runs as `SYSTEM`
2. The operation requires an interactive desktop session, which Run Command does not provide
3. The required PowerShell version or module is not present

## Summary

The value of `Run Command` is that you can centrally issue commands,

collect results, and maintain an audit trail

without logging into each host individually.

But it is not just a remote shell wrapper —

the real focus is the permission model.

Linux and Windows diverge on Document selection, execution identity, and script format,

and those differences will trip you up if you don't address them upfront.

## Homework

If you can already use Run Command to change a local Windows password,

the next question to answer is:

where do you safely store the new password after rotating it?

Two directions worth thinking about:

1. Securely write the secret to `Secrets Manager`
2. Publish an event via `SNS` to hand off to a downstream process for storage or notification

One important distinction to keep in mind:

`SNS` is better suited for notifications and triggering workflows,

not for storing a plaintext password directly.

When the goal is to securely store the credential itself,

`Secrets Manager` is typically the right answer.
