---
layout: post
title: "More about AWS Systems Manager: Inventory, Compliance and Configuration Management"
description: "Deep dive into AWS Systems Manager: inventory collection, patch & compliance tracking, maintenance windows, AppConfig and Parameter Store for automated ops and ISO audit readiness."
author: Mark_Mew
categories: [AWS]
tags: [AWS, SSM, State Manager, Systems Manager, ISO, Audit, Inventory, Compliance]
keywords: ["AWS Systems Manager", "Systems Manager inventory", "SSM inventory", "patch management", "maintenance window", "AppConfig", "Parameter Store", "ISO audit", "automation", "configuration management"]
lang: en
date: 2026-06-13
---

In previous posts we covered several Systems Manager capabilities.

You can enable Session Manager to allow different users to connect to the same machine.

You can schedule patches for vulnerability remediation.

You can run scripts on target instances.

You can perform state and compliance management.

All of these share the same ultimate goal:

They help us gain better visibility and control over our managed instances.

That improved control directly relates to ISO auditing.

Of course, ISO requires more than just these features.

In this post I will fill in additional Systems Manager capabilities that help with operational control.

## Inventory

### What is Inventory

`Inventory` is a Systems Manager feature that collects and organizes information about your managed EC2 instances. It can periodically scan managed instances and gather details such as operating system, installed applications, and network configuration.

### Use State Manager to run AWS-GatherSoftwareInventory on a schedule

By creating an Association in State Manager that invokes the `AWS-GatherSoftwareInventory` document, you can regularly collect software inventory:

1. **Automated collection**: no need to inspect each host manually; the system runs periodically
2. **Comprehensive software list**: records not only OS versions but the installed software and versions on each instance
3. **Cloud-native asset management**: acts like an enterprise IT asset tool (e.g., Lansweeper) in the cloud

### Benefits of Inventory

- **Audit readiness**: quickly generate an asset list for auditors
- **Vulnerability tracking**: know which software and versions are installed across your fleet
- **Cost optimization**: understand software licensing usage and avoid over-provisioning

## Compliance

### What is Compliance

`Compliance` is Systems Manager's dashboard for tracking the execution status and compliance posture of Associations.

### Core Compliance capabilities

Associations created in State Manager (including Patch Manager tasks) surface execution results in the Compliance dashboard:

1. **Patch Manager results**
   - Which instances successfully applied patches
   - Which instances failed to apply patches and why
   - Detailed failure reasons for patch installations

2. **Association execution tracking**
   - Last run time for each Association
   - Success or failure status
   - Whether instances are correctly associated with the intended documents

3. **Compliance dashboard**
   - A quick overview of the compliance posture for all managed instances
   - Identify non-compliant instances for targeted remediation
   - Generate compliance reports for ISO audits

### Practical recommendations

Establish a clear compliance monitoring strategy:
- Define explicit compliance baselines
- Review Compliance reports regularly
- Configure alerts and automated remediation for non-compliant items

## Maintenance Window

### What is a Maintenance Window

`Maintenance Window` lets you define specific time slots during which maintenance tasks (such as patching or software installs) run.

### Value of Maintenance Windows

1. **Avoid business disruption**: perform critical updates during approved windows to minimize impact
2. **Align with change management**: ensure maintenance runs during authorized timeframes
3. **Automate maintenance scheduling**: reduce manual coordination by scheduling tasks to run automatically

### Key steps to configure a Maintenance Window

- Define the start time and duration of the window
- Specify tasks to run (for example, Patch Manager)
- Choose target instances (by Tag or Resource Group)
- Configure retry behavior on failures

## Configuration Management

Configuration management is central to modern operations, and Systems Manager provides multiple layers to manage configuration.

### AppConfig

`AppConfig` manages application configuration and is useful when you need to change application behavior dynamically.

#### AppConfig key features

1. **Dynamic configuration updates**
   - Change configuration without redeploying applications
   - Support for feature flags
   - Distribute configuration for A/B testing

2. **Phased deployments**
   - Validate configuration changes before broad rollout
   - Gradually deploy new configuration to instances
   - Automatic rollback on failure

3. **Integration with applications**
   - SDKs for major languages (Java, Python, Node.js, etc.)
   - Applications can fetch the latest configuration at runtime

#### AppConfig use cases

- Feature flag management: quickly enable or disable features
- A/B testing: provide different behavior to user segments
- Dynamic throttling: adjust rate limits based on system load

### Parameter Store

`Parameter Store` is a key-value store in Systems Manager for centralized management of application and server configuration.

#### Parameter Store key features

1. **Centralized parameter management**
   - Store DB connection strings, API keys and other sensitive data
   - Support encrypted storage (KMS)
   - Versioning for easy rollback

2. **Flexible parameter types**
   - String: plain text parameters
   - StringList: list of strings
   - SecureString: encrypted sensitive values (passwords, API keys)

3. **IAM integration**
   - Control access with IAM policies
   - Audit access through logs

#### Parameter Store vs. environment variables

| Feature | Environment Variables | Parameter Store |
|--------:|----------------------:|----------------:|
| Storage location | Local OS | AWS cloud |
| Security | Requires manual encryption | KMS-backed encryption |
| Versioning | Not supported | Supports multiple versions |
| Centralized management | Not supported | Centralized across applications |
| Change notifications | None | Can use EventBridge |

#### Parameter Store best practices

```
/myapp/prod/db/hostname
/myapp/prod/db/port
/myapp/prod/db/username
/myapp/prod/api/key
/myapp/prod/cache/ttl
```

Use a hierarchical naming scheme to organize parameters for easy management and discovery.

## Systems Manager and ISO audit readiness

### Why Systems Manager matters for ISO audits

1. **Comprehensive audit trails**
   - Inventory: prove your asset list is complete and controlled
   - Compliance: demonstrate patching and maintenance processes are followed
   - CloudTrail integration: capture complete operational logs

2. **Automate compliance requirements**
   - State Manager: ensure periodic compliance checks run reliably
   - Maintenance Window: enforce controlled change windows
   - Parameter Store: provide traceable secrets and configuration management

3. **Reduce human error**
   - Automation reduces manual steps that cause drift
   - Versioning ensures configuration consistency
   - Execution records provide audit evidence

### ISO audit recommendations

1. **Establish a configuration baseline**
   - Use Inventory to record the initial asset state
   - Regularly compare current state to the baseline

2. **Implement compliance monitoring**
   - Review Compliance dashboard regularly
   - Set alerts for non-compliant items

3. **Document operational processes**
   - Record all Associations and Maintenance Window definitions
   - Retain execution logs for audit queries

4. **Adopt change management**
   - Manage configuration changes through Parameter Store
   - Use versioning to track history

## Conclusion

AWS Systems Manager not only provides powerful automation tools for operations, but it also delivers comprehensive compliance and audit capabilities. By combining Inventory, Compliance, Maintenance Window, AppConfig and Parameter Store, organizations can:

- **Improve operational efficiency**: automate routine maintenance
- **Enhance security**: centralize secret management and track changes
- **Ensure compliance**: produce audit evidence and simplify audits
- **Reduce risk**: minimize human error and enforce configuration consistency

This is the core value of modern cloud operations.
