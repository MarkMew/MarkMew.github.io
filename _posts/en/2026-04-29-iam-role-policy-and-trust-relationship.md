---
layout: post
title: "Deep Dive: Understanding AWS IAM Role Permission Design"
description: "Deconstructing Policy and Trust Relationship: the division of responsibility in IAM Role"
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Role]
keywords: [AWS, IAM, IAM Role, AWS permission, trust relationship, IAM policy]
date: 2026-4-29
---

If you're new to cloud computing,

you probably have a love-hate relationship with IAM.

As you gradually understand each AWS feature,

you start learning about best practices recommended by AWS,

and try to execute everything using roles—that is, IAM Roles.

After spending some time understanding the intricacies of IAM Role,

you'll realize it's actually a brilliantly designed system.

## Permission Management in Traditional Web

In traditional web systems, permissions are typically split into two concerns:

1. Who are you (Authentication)
2. What can you do (Authorization)

For example, when a user logs in, the system first confirms their identity, usually mapping them to an `Account` in the database.

Small systems might directly map `Account` to `Permission`.

Larger systems typically design a `Role` entity,

where `Account` can bind to multiple `Role`s,

and each `Role` can bind to different `Permission`s.

When you apply this concept to AWS, it's essentially the same—just with AWS's identity system as the roles.

## IAM

In AWS, an IAM Role can separate two concerns:

1. "Who can obtain this identity"
2. "What can they do after obtaining it"

This separation is precisely what makes IAM Role design elegant.

IAM Role consists of two parts:

1. Trust Relationship: defines who can Assume this Role
2. Policy: defines what actions this Role can perform on which resources

In other words,

Trust Relationship is the entry rule,

Policy is the behavior rule after entry.

### Trust Relationship

Trust Relationship is not about permissions themselves, but rather "who has the right to assume this role."

If you think of an IAM Role as a job position in a company, then Trust Relationship decides "which people can be appointed to this position."

For example, the following trust policy means: only the EC2 service can Assume this Role.

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

If your scenario involves EKS IRSA, GitHub Actions OIDC, or cross-account access, the `Principal` would be a Federated Provider or another AWS Account, but the core concept remains the same:

First, decide who can obtain this Role.

### Policy

Policy is what everyone typically refers to as "permissions."

It describes: once an entity has successfully Assumed the Role, what exactly can it do?

For example, the following policy only allows reading objects under a specified S3 bucket:

```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": [
				"s3:GetObject"
			],
			"Resource": "arn:aws:s3:::example-bucket/*"
		}
	]
}
```

The most common misconception here is:

thinking that if Trust Relationship is strict, security is guaranteed.

In reality, if the Policy is too permissive (e.g., `Action: *` + `Resource: *`), as long as someone can Assume the Role, the risk remains high.

It works both ways too: even if Policy is perfectly scoped, if Trust Relationship is too broad (allowing Principals that shouldn't have access), there's still a problem.

## 4 Questions to Ask When Designing IAM Role

In practice, I ask these four questions before writing any JSON:

1. Who needs this Role?
2. Under what conditions can this identity Assume the Role?
3. After Assuming, what minimum Actions and Resources are needed?
4. Which operations must absolutely never be allowed?

The benefit of this approach is that you can converge on "identity entry points" and "permission scope" separately, avoiding the trap of bundling everything into an all-purpose role from the start.

## A Complete Mental Model

Think of an IAM Role as a door with two locks:

1. First lock is Trust Relationship: do you have the right to enter the door
2. Second lock is Policy: where can you go after entering

Only when both locks are correctly designed will the permission model be truly secure and maintainable.

## Conclusion

IAM Role is useful not just because it replaces long-term Access Keys, but more importantly because it divides the permission model into two clear dimensions.

Once you understand the division of responsibility between Trust Relationship and Policy, whether for EC2, Lambda, EKS IRSA, or cross-account authorization, your designs will be more consistent.

To summarize in one sentence:

First define who can assume the role, then define what the role can do.

This is the core of IAM Role permission design.
