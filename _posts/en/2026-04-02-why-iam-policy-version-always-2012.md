---
layout: post
title: AWS Trivia: Why Do IAM Policies Almost Always Use Version 2012-10-17?
description: Why do AWS IAM policies almost always use Version 2012-10-17? This post explains what that version actually means, how it differs from service API versions, and what happens if you leave it out.
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Policy, Policy Variables]
keywords: [AWS IAM Policy Version, 2012-10-17, IAM Policy Variables, IAM JSON Policy, AWS Security]
date: 2026-4-2
---

If you work with AWS, you have probably seen IAM policies with `Version` set to `2012-10-17` over and over again.

```json
{
  "Version":"2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

If you are seeing it for the first time, you probably have the same questions most people do:

- Why is it always this date?
- AWS keeps evolving, so why does the version not change?

In this post, I will break down what that date actually means and why it shows up so often.

## Why Do IAM Policies Use Version 2012-10-17

Short answer: `2012-10-17` is the version of the IAM policy language. It is not a single API version shared across all AWS services.

Each AWS service has its own API version. For example:

- Amazon S3: `2006-03-01`
  [Amazon S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- AWS Lambda: `2015-03-31`
  [AWS Lambda GetFunction API Reference](https://docs.aws.amazon.com/lambda/latest/api/API_GetFunction.html)
  ```
  GET /2015-03-31/functions/FunctionName?Qualifier=Qualifier HTTP/1.1
  ```

- Amazon EC2: `2016-11-15`
  ```
  API Version: 2016-11-15
  ```
  [Class: AWS.EC2 - JavaScript SDK](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html)

So the accurate way to put it is this: IAM policies commonly use `2012-10-17`, but that does not mean every AWS API uses the same version.

## Why 2012-10-17 Specifically

The most widely accepted explanation is that `2012-10-17` marks a major update to the IAM policy language.

That version introduced policy variables such as `${aws:username}` and `${aws:PrincipalTag}`, making it possible to write policies that scale much more cleanly across users and roles.

That is why `2012-10-17` became the de facto standard you see in most IAM policies today.

## What Happens If You Leave Out Version

If you leave out `Version`, AWS falls back to the older `2008-10-17` behavior.

In that case, strings like `${aws:username}` may be treated as literal text instead of policy variables.

## Where You Still See `2008-10-17`

If you look through AWS accounts that were created before 2012 and never fully cleaned up, you will often find inline policies with no `Version` field at all.

Officially, if `Version` is completely omitted from a JSON policy document, IAM defaults to the `2008-10-17` policy language behavior.

That means plenty of "hidden" 2008-era policies are still hanging around in older environments.

You can also still run into `2008-10-17` when the AWS Console generates policy JSON for certain resources. In most cases, this is there for backward compatibility with older systems and APIs, not because `2012-10-17` is unsupported.

- SQS queue policies: when you click "Edit policy" in the SQS console, the generated template is often still `2008-10-17`.
- SNS topic policies: similar to SQS, the default access policy JSON often still uses the 2008 format.
- VPC endpoint policies (gateway type only): for example, gateway endpoints for S3 or DynamoDB often still show policy language marked as 2008.

## Why These Older Versions Are Not Automatically Upgraded

This mostly comes down to how the underlying service APIs were designed, such as SQS `SetQueueAttributes`.

- API compatibility: many resource policies are managed through service-specific APIs rather than the IAM API. Those APIs were defined years ago, so AWS keeps the defaults stable to avoid breaking existing automation.
- Simpler policy needs: in many SQS and SNS use cases, a basic allow or deny on a specific ARN is enough, so the newer policy variable features are often unnecessary.

## Will There Ever Be a New Version

A new version is certainly possible, but there is no official announcement right now.

If AWS ever introduces a new version, it will likely keep the older one around for compatibility so existing policies do not break overnight. In practice, though, you should usually use the newer version whenever possible.

## References
- [IAM JSON policy elements: Version](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_version.html)
- [Amazon S3 API Reference](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- [AWS Lambda GetFunction API Reference](https://docs.aws.amazon.com/lambda/latest/api/API_GetFunction.html)
- [Class: AWS.EC2 - JavaScript SDK](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html)
