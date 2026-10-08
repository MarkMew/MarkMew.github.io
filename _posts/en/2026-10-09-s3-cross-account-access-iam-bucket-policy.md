---
layout: post
title: "Cross-Account S3 Access: Setting Up IAM and Bucket Policies"
image: https://fastly.picsum.photos/id/905/1200/630.jpg?hmac=ZWehW4CmzynIJ9lxyGHPkwHnki7vekeNFaXiaJWJaeo
description: "Set up read-only S3 access across AWS accounts with IAM and bucket policies, restrict access to a prefix, verify it with the AWS CLI, and troubleshoot AccessDenied errors."
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, IAM]
keywords: [S3 cross-account access, S3 bucket policy, IAM policy, S3 prefix permissions, AccessDenied]
lang: en
date: 2026-10-09
---

**To let an IAM identity access an S3 bucket in another AWS account directly, both the source account's IAM policy and the destination bucket's policy must allow the operation.** Having S3 read permissions in the source account isn't enough if the destination bucket hasn't granted access to that identity. A bucket policy alone isn't enough either. [AWS documentation on cross-account access](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies-cross-account-resource-access.html)

The request must also satisfy any other applicable permission restrictions, and an explicit `Deny` must not block it.

In this walkthrough, an application in Account A needs to read files from an S3 bucket in Account B. We'll grant read-only access to a specific prefix, verify it with the AWS CLI, and work through common causes of `AccessDenied`.

## Why do you need both an IAM policy and a bucket policy?

Each account controls its own side of the permissions. The source account decides what its IAM identities can do, while the destination account decides who can access its bucket.

| Where to configure it | Policy | What it allows |
|---|---|---|
| IAM role in source Account A | IAM policy | Lets the role read specific S3 objects in Account B |
| S3 bucket in destination Account B | Bucket policy | Lets the specified role in Account A read those objects |

For example, to download `reports/sample.txt`, the source role's IAM policy must allow `s3:GetObject` on that object. The destination bucket policy must allow the same role to perform that operation. The request uses Account A's identity throughout.

## Example setup and prerequisites

Our application uses `AppReadReportsRole` in Account A to read objects under `reports/` in Account B.

| Item | Example value |
|---|---|
| Source Account A | `111111111111` |
| Destination Account B | `222222222222` |
| Role in Account A | `AppReadReportsRole` |
| Bucket in Account B | `example-cross-account-reports-222222222222` |
| Allowed prefix | `reports/` |
| Test object | `reports/sample.txt` |
| CLI profile | `account-a-app` |

Replace these example values with your own. This walkthrough assumes:

- The role in Account A already exists, and the application or operator is authorized to obtain temporary credentials for it.
- The bucket in Account B already exists and contains a test file at `reports/sample.txt`.
- The CLI profile `account-a-app` is configured to use that role.
- The bucket's Object Ownership setting is **Bucket owner enforced**.
- The test object uses server-side encryption with S3 managed keys (SSE-S3).

`Bucket owner enforced` disables ACLs and makes the bucket owner the owner of all objects in the bucket, so you can manage access through policies. This is the default for new S3 buckets. [S3 Object Ownership documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

The examples below include the expected results. You'll still need to verify them in your own AWS environment.

## Step 1: Grant the role permissions in Account A

In Account A, open IAM, find `AppReadReportsRole`, and add the following IAM policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListReportsPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222",
      "Condition": {
        "StringLike": {
          "s3:prefix": "reports/*"
        }
      }
    },
    {
      "Sid": "ReadReportObjects",
      "Effect": "Allow",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222/reports/*"
    }
  ]
}
```

This policy allows two operations:

| Permission | Purpose | Resource |
|---|---|---|
| `s3:ListBucket` | List objects under the allowed prefix | Bucket ARN |
| `s3:GetObject` | Read objects under the allowed path | Object ARN |

For `ListBucket`, the resource is the bucket itself, so we use `s3:prefix` to limit what can be listed. For `GetObject`, the object path goes directly in `Resource`.

Here, `reports/*` also matches `reports/`. That's why the listing command later in this guide explicitly includes `--prefix reports/`. An S3 prefix is the beginning of an object key, such as `reports/2026/report.csv`; it isn't a real filesystem directory. [AWS examples of prefix-based permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/amazon-s3-policy-keys.html)

## Step 2: Configure the bucket policy in Account B

In Account B, open the destination bucket and go to **Permissions → Bucket policy**. Add the following permissions.

If the bucket already has a policy, merge these statements into it, keeping any existing rules you still need.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARoleToListReports",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppReadReportsRole"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222",
      "Condition": {
        "StringLike": {
          "s3:prefix": "reports/*"
        }
      }
    },
    {
      "Sid": "AllowAccountARoleToReadReports",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppReadReportsRole"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::example-cross-account-reports-222222222222/reports/*"
    }
  ]
}
```

`Principal` identifies the source role allowed to access the bucket. If your role has a path, copy its full ARN from IAM so you don't accidentally leave the path out.

The two policies answer different questions:

- Account A's IAM policy: Which resources can this role access, and what can it do with them?
- Account B's bucket policy: Who can access this bucket, and which operations are allowed?

**These `Allow` statements grant the permissions listed here; they don't revoke other permissions that already exist.** If the role or bucket has broader permissions elsewhere, review those too.

## Step 3: Verify access with the AWS CLI

### Check which identity you're using

```shell
aws sts get-caller-identity --profile account-a-app
```

The `Account` value should be `111111111111`, and the ARN should look like this:

```text
arn:aws:sts::111111111111:assumed-role/AppReadReportsRole/example-session
```

If you see a different role, fix the profile or credential source before testing S3 access.

This output contains an STS role session ARN. The bucket policy should still use the IAM role ARN shown earlier.

### List objects under the allowed prefix

```shell
aws s3api list-objects-v2 --bucket example-cross-account-reports-222222222222 --prefix reports/ --profile account-a-app
```

With the policies configured correctly, the request should succeed and list objects under `reports/`. If it succeeds but returns no objects, check that the bucket contains object keys matching that prefix.

### Download the test object

```shell
aws s3api get-object --bucket example-cross-account-reports-222222222222 --key reports/sample.txt --profile account-a-app ./downloaded-sample.txt
```

The file should be saved locally as `downloaded-sample.txt`. The final argument to `get-object` is the output file path. [AWS CLI GetObject reference](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html)

### Check that access outside the prefix is denied

Now try listing a prefix that isn't covered by the policies:

```shell
aws s3api list-objects-v2 --bucket example-cross-account-reports-222222222222 --prefix private/ --profile account-a-app
```

If no other applicable permissions grant access, you should receive `AccessDenied`.

This negative check helps confirm that the permissions are scoped as intended. If the request succeeds, look for other policies on the role or bucket that grant broader access.

## Troubleshooting AccessDenied

First, determine whether the failure happens when listing objects or downloading an object. Then check the following:

| Check | What to look for |
|---|---|
| Caller identity | Does `get-caller-identity` show the expected account and role? |
| Source IAM policy | Does it allow the required action on the correct resource? |
| Destination bucket policy | Does `Principal` contain the correct role ARN? |
| Bucket and object ARNs | Does `ListBucket` use the bucket ARN, and does `GetObject` use the object ARN? |
| Prefix conditions | Does the request include `reports/`, with the correct case and slashes? |
| Explicit denies and permission limits | Is an SCP, RCP, permissions boundary, session policy, or another policy restricting the request? |
| Network conditions | Is a specific VPC endpoint or source IP required? Does an endpoint policy restrict access? |
| Object ownership | If an older bucket still uses ACLs, does another account own the object? |

Adding an `Allow` won't override an applicable explicit `Deny`. Include organization-level controls and network conditions in your review where relevant. [AWS guide to troubleshooting S3 403 errors](https://docs.aws.amazon.com/AmazonS3/latest/userguide/troubleshoot-403-errors.html)

Two common patterns can help narrow things down:

**You can list files but can't download them**

The `ListBucket` request is working. Next, check that both policies allow `GetObject`, that the resource paths cover the object, and that the object exists.

**You can download a known file but can't list files**

You may only have `GetObject` permission, or the prefix in the listing request may not match the policy condition. Listing and downloading are separate operations, so check their permissions separately.

## Frequently asked questions

### Do I need to turn off S3 Block Public Access?

No. This example grants access to a specific IAM role, so you can keep Block Public Access enabled.

However, if other statements cause S3 to classify the bucket policy as public, `RestrictPublicBuckets` can affect cross-account access. Review the entire policy. [S3 Block Public Access documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)

### Is s3:ListBucket always required?

No. If an application knows the full object key and only needs to download that object, `s3:GetObject` can be enough. This example includes `ListBucket` so the application can list files under `reports/`. [GetObject permissions](https://docs.aws.amazon.com/cli/latest/reference/s3api/get-object.html)

**If you're using IAM user credentials—an access key ID and secret access key—with an S3 client such as WinSCP or FileZilla Pro to browse folders, you need `s3:ListBucket`.** The client needs to list the contents of the bucket or prefix to display folders and files. Without that permission, you may be able to connect or see the bucket but get `AccessDenied` when you try to open a folder. This requirement comes from the listing operation; it applies to IAM roles too. [WinSCP support explanation](https://winscp.net/forum/viewtopic.php?t=34760)

For cross-account access, both the source IAM user's policy and the destination bucket policy must allow the relevant `s3:ListBucket` operation. Update the bucket policy's `Principal` to the ARN of the IAM user you're actually using.

Also, this example only allows listing `reports/` and prefixes beneath it, not the bucket root. A client that starts by listing the root can still be denied even with `s3:ListBucket`. Set the default remote directory to `/your-bucket-name/reports/` so the listing request matches the allowed prefix. Listing available buckets and listing objects inside a bucket are separate operations; you may also need to specify the path to a cross-account bucket directly. [WinSCP S3 connection settings](https://winscp.net/eng/docs/guide_amazon_s3), [FileZilla Pro S3 connection settings](https://filezillapro.com/docs/v3/cloud/configure-filezilla-pro-to-connect-to-s3/)

### Do I need to configure ACLs?

This example uses `Bucket owner enforced`, which disables ACLs. Manage access with IAM and bucket policies instead. For older setups that still use ACLs, also check object ownership. [S3 Object Ownership documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

### What if I also need to upload files?

Add `s3:PutObject` for the intended object ARNs in both the source IAM policy and the destination bucket policy.

### Why does the CLI work while browsing in the console doesn't?

These policies grant API access to a specific bucket and prefix. The console may call additional APIs as you navigate, so these permissions don't necessarily support the full console experience. Use the CLI commands above to verify this setup. [S3 IAM policy examples and console permissions](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-policies-s3.html)
