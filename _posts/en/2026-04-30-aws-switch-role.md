---
layout: post
title: "Using Switch Role After Signing In to AWS"
description: "This article introduces AWS Console Switch Role for cross-account access, and shows how to configure Trust Relationship and Policy for safer daily operations."
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Role]
keywords: [IAM Role, Switch Role]
date: 2026-4-30
lang: en
---

There are many ways to sign in to AWS Cloud Console:

Sign in with a root account (not recommended),

sign in with IAM User credentials,

use SAML (for example Azure AD) to access AWS Console,

or sign in through AWS SSO.

Among these, there is one especially useful method:

you sign in to one AWS account first,

then switch into another AWS account

using Switch Role.

This article introduces this method

and how to set it up.

## Comparing Sign-in Methods with a Diagram

Here is a simplified flow to compare common sign-in patterns:

```text
[Root / IAM User / SSO Sign-in]
               |
               v
     [Enter Source Account Console]
               |
         (Switch Role)
               |
               v
      [Switch to Target Account Role]
               |
               v
       [Operate Target Resources]
```

If you only look at the result, all methods "enter the Console".

But from a permission design perspective, they are very different.

| Method | Identity Used | Recommended for Long-term Use | Typical Scenario |
| --- | --- | --- | --- |
| Root Account | Account Root User | No | Account initialization, rare emergency operations |
| IAM User | Long-lived user credentials | Depends on org policy | Small teams, no SSO yet |
| SAML/SSO | Enterprise identity system | Yes | Mid-size/large organizations, centralized control |
| Switch Role | Sign in to source account first, then switch role | Yes | Cross-account operations, production isolation |

## Why We Need It

Many teams separate production into a dedicated AWS account.

Engineers normally work in a general account,

and only switch into production when needed.

Conceptually, this is similar to a bastion step before entering production.

This gives at least three benefits:

1. Reduces long-term exposure of high privileges
2. Clearly separates daily identity from target-environment responsibility
3. Makes CloudTrail auditing easier for tracking who switched to which role and when

> In practice, a switchable role is a clear boundary:
> identity verification first, role authorization second, then access to sensitive resources.
{: .prompt-info}

## Setup Guide

Below is the most common cross-account scenario:

1. A user signs in to source account (A)
2. In target account (B), create a role that account A can assume
3. In the Console, switch role into account B

### Step 1: Create an IAM Role in the Target Account

When creating the role in account B,

define its permission policy first.

For example, allow read-only access to CloudWatch Logs and EC2 describe:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:GetLogEvents",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

### Step 2: Configure Trust Relationship

Then configure the target role's trust policy in account B,

to allow a specific IAM User or Role from source account A to assume it.

Common example (allow role `ops-admin` from source account):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<source_account_id>:role/ops-admin"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

If you want stricter control, add conditions (for example MFA):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::<source_account_id>:role/ops-admin"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "Bool": {
          "aws:MultiFactorAuthPresent": "true"
        }
      }
    }
  ]
}
```

### Step 3: Ensure Source Side Also Has AssumeRole Permission

The IAM User/Role in source account A

must have `sts:AssumeRole` permission on the target role.

Otherwise, switching will fail.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": "arn:aws:iam::<target_account_id>:role/<target_role_name>"
    }
  ]
}
```

### Step 4: Switch Role in Console

In the top-right account menu, click `Switch role`,

then fill in:

1. Account ID (target account)
2. Role name (target role)
3. Display name (custom label for easier identification)

After success, the identity shown in the Console header changes,

which means you are now operating with the target role in the same browser session.

## Common Errors and Troubleshooting

### 1) AccessDenied: not authorized to perform sts:AssumeRole

Usually the source side lacks `sts:AssumeRole` permission,

or the target trust relationship does not trust the correct principal.

### 2) Role appears but switching fails

Check Account ID and Role name,

and confirm you are switching to the role in the target account,

not a same-named role in the source account.

### 3) Switch succeeded but resources are not visible

Usually the target role policy is too restrictive,

or you are viewing the wrong AWS region.

## When to Use Which Sign-in Method

A quick decision guide:

1. Personal learning or one-off operation: IAM User (acceptable short-term)
2. Team production operations: SSO + Switch Role
3. High-sensitivity accounts (for example production): no default access; switch only when needed

A common and robust model is:

use SSO for identity authentication first,

then switch roles for different accounts and responsibilities.

## Conclusion

The value of Switch Role is not only cross-account convenience.

More importantly, it separates identity from privilege,

so you can enter high-risk environments in a controlled way.

One-line summary:

Work with low privilege by default, and switch to target role only when needed.

That is a key practice in AWS multi-account governance.

## References

1. AWS IAM User Guide - Switching to a role (console): https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-console.html
2. AWS IAM User Guide - Tutorial: Delegate access across AWS accounts using IAM roles: https://docs.aws.amazon.com/IAM/latest/UserGuide/tutorial_cross-account-with-roles.html
3. AWS IAM JSON policy elements reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements.html
