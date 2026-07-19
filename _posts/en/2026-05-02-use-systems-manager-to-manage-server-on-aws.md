---
layout: post
title: "Managing EC2 on AWS with Systems Manager"
description: "This guide walks through the core concepts and setup steps for AWS Systems Manager, so you can securely manage EC2 instances without opening SSH ports."
author: Mark_Mew
categories: [AWS, Systems Manager]
tags: [AWS, EC2, IAM, SSM]
keywords: [AWS Systems Manager, Session Manager, EC2]
date: 2026-5-2
lang: en
---

When we talk about on-prem virtualization management, tools like `VMWare` and `Hyper-V` usually come to mind first.

With platforms such as `vCenter Server` or `System Center Virtual Machine Manager`, you can centrally allocate and manage virtual resources.

So what about in the cloud?

You can absolutely do centralized operations there too,

but the operating model is a bit different from on-prem.

On AWS, the service that plays this role is `Systems Manager`.

In cloud environments, you can already scale compute and storage dynamically from EC2 itself,

but if you want stronger visibility and control over operational policies, commands, and node state,

`Systems Manager` is one of the most practical tools to adopt.

## What is Systems Manager?

`AWS Systems Manager` helps you view, manage, and operate nodes at scale across AWS, on-prem environments, and even multi-cloud setups.

It is not a single feature.

It is a suite of management capabilities under one service umbrella.

Most core features do not have a direct extra charge,

and the service mainly works through the `SSM Agent` running on your nodes.

In practice, most cost comes from supporting services you pair with it,

such as CloudWatch Logs, VPC Endpoints, and KMS.

## What can Systems Manager help you manage?

Systems Manager is a broad AWS service family,

which can be roughly grouped into four areas:

1. Operations management
2. Application management
3. Change management
4. Node management

For day-to-day operations, teams usually start with these three:

1. Session Manager: shell access without exposing SSH/RDP ports
2. Run Command: run commands across multiple instances in bulk
3. Patch Manager: assess and apply OS patches consistently

## What you should prepare first

To make an EC2 instance manageable through Systems Manager,

you generally need these three prerequisites:

1. The instance is attached to a correct IAM Role (Instance Profile)
2. The instance can reach Systems Manager endpoints over TCP 443
3. The `SSM Agent` is installed and running

## Configure IAM Role

### Trust Relationship

Every EC2 instance you want to manage should have an IAM Role attached.

A standard Trust Relationship looks like this:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### IAM Policy

For IAM Policy, start with the AWS managed policy:

`AmazonSSMManagedInstanceCore`

This is the baseline permission set required for EC2 to be managed by Systems Manager.

## Install and verify SSM Agent

### Linux

If you use Amazon Linux 2 or Amazon Linux 2023, `SSM Agent` is typically preinstalled.

Ubuntu is usually supported as well,

but very new LTS releases can have temporary support gaps,

so check the official list first: [Supported operating systems and machine types](https://docs.aws.amazon.com/systems-manager/latest/userguide/operating-systems-and-machine-types.html)

Check the service status:

```bash
sudo systemctl status amazon-ssm-agent
```

If needed, enable and start it:

```bash
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
```

### Windows Server

For Windows Server, setup is straightforward:

```powershell
[System.Net.ServicePointManager]::SecurityProtocol = 'TLS12'
$progressPreference = 'silentlyContinue'
Invoke-WebRequest `
    https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/windows_amd64/AmazonSSMAgentSetup.exe `
    -OutFile $env:USERPROFILE\Desktop\SSMAgent_latest.exe
```

```powershell
Start-Process `
    -FilePath $env:USERPROFILE\Desktop\SSMAgent_latest.exe `
    -ArgumentList "/S"
```

```powershell
rm -Force $env:USERPROFILE\Desktop\SSMAgent_latest.exe
```

Also make sure outbound TCP 443 is allowed,

so your instance can communicate with AWS services via either an Internet Gateway or NAT Gateway path.

## How to configure isolated/private subnets

If your EC2 instance is in a private subnet without direct internet egress (no NAT / IGW),

you need Interface VPC Endpoints.

At minimum, create these three endpoint services:

```
com.amazonaws.<region>.ssm
com.amazonaws.<region>.ssmmessages
com.amazonaws.<region>.ec2messages
```

Also check:

1. The endpoint Security Group allows TCP 443 from your EC2 subnet
2. EC2 Security Group / NACL allows traffic to the endpoint on TCP 443

## How to connect with Session Manager

### Via AWS Console

1. Open the EC2 console
2. Select the target instance
3. Click `Connect`
4. Choose the `Session Manager` tab
5. Click `Connect`

### Via AWS CLI

```bash
aws ssm start-session --target <instance-id>
```

If you connect through CLI,

make sure Session Manager plugin is installed on your local machine.

### Can Session Manager upload files with scp directly?

This is an important distinction:

`aws ssm start-session` opens an interactive shell session,

but does not natively provide `scp` / `sftp` file transfer.

If you used to upload files with PEM-based `scp -i`,

these are practical alternatives after moving to Session Manager:

1. Recommended: upload to S3 first, then pull from EC2

```bash
# local -> S3
aws s3 cp ./app.tar.gz s3://<bucket>/transfer/app.tar.gz

# EC2 pulls from S3
aws s3 cp s3://<bucket>/transfer/app.tar.gz /tmp/app.tar.gz
```

2. If you want to keep scp workflow: use SSM port forwarding, then run scp against localhost

```bash
aws ssm start-session \
  --target <instance-id> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["22"],"localPortNumber":["10022"]}'
```

Then in another terminal:

```bash
scp -P 10022 ./app.tar.gz ec2-user@127.0.0.1:/tmp/
```

> If you forward to port 22 on the same EC2 instance as in this example, you usually do not need to open additional inbound port 22 rules on the EC2 Security Group.
> The connection goes through the SSM channel first, then gets forwarded by the agent to the local service on the node.
> You still need SSH server running on the instance, and local host firewall rules (for example iptables / firewalld) must not block it.
> If you forward to a service on a different host, then you do need to check that host's Security Group / NACL inbound rules.
{: .prompt-info}

The second option still depends on SSH server on the target,

just without exposing port 22 publicly.

If your goal is to avoid SSH dependency entirely,

S3-based transfer is usually the cleanest approach.

## How to verify an instance is managed by SSM

You can check node status with:

```bash
aws ssm describe-instance-information \
  --query "InstanceInformationList[].{InstanceId:InstanceId,PingStatus:PingStatus,PlatformName:PlatformName,AgentVersion:AgentVersion}" \
  --output table
```

If `PingStatus` is `Online`,

your agent, IAM, and network setup are typically in good shape.

## Common issues and troubleshooting

### 1) TargetNotConnected

Most common causes:

1. The instance role is missing `AmazonSSMManagedInstanceCore`
2. Agent is not running or too old
3. Network path is blocked (cannot reach SSM endpoints on 443)

### 2) Session Manager tab is not visible in Console

Check whether your current console identity has permission for `ssm:StartSession`.

### 3) Endpoints exist but private instance still cannot connect

In many cases, TCP 443 is still blocked by endpoint Security Group or NACL,

or there is a route/DNS issue.

## Summary

The biggest value of Systems Manager is this:

you can operate EC2 securely, at scale, and with auditability,

without exposing SSH/RDP ports.

A practical rollout path is to start with Session Manager,

then expand into Run Command and Patch Manager.

---

## References

1. What is AWS Systems Manager?: https://docs.aws.amazon.com/systems-manager/latest/userguide/what-is-systems-manager.html
2. Session Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html
3. AmazonSSMManagedInstanceCore managed policy: https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AmazonSSMManagedInstanceCore.html
4. Create VPC endpoints for Systems Manager: https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html
5. Supported operating systems and machine types: https://docs.aws.amazon.com/systems-manager/latest/userguide/operating-systems-and-machine-types.html
