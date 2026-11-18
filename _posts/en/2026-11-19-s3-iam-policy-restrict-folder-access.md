---
layout: post
title: "Restrict S3 Access to a Specific Folder with IAM Policy: s3:prefix and s3:delimiter"
description: "Learn how to write an IAM policy that limits a user to a single folder in an S3 bucket, how to use the s3:prefix, s3:delimiter, and Null conditions, and why a common Deny-based policy fails, while keeping WinSCP and S3 Browser working."
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, IAM]
keywords: [S3 IAM policy, S3 folder permissions, S3 prefix permissions, s3:prefix, s3:delimiter, s3:ListBucket, AccessDenied]
lang: en
date: 2026-11-19
---

I previously wrote about [cross-account access to Amazon S3](/en/posts/s3-cross-account-access-iam-bucket-policy/). In practice, though, another requirement comes up far more often: **multiple users or systems share one bucket, and each of them may only access the folder they've been granted.**

Whether access uses IAM user credentials (an access key ID and secret access key) or an IAM role, permissions come from the IAM policy attached to that identity. The policy in this post works for both.

**To restrict access to a folder, object operations such as `GetObject` and `PutObject` only need the path in the Resource element. The tricky part is `s3:ListBucket`.** Its resource is the bucket itself, so the only way to limit what can be listed is with the `s3:prefix` and `s3:delimiter` condition keys. This post walks through a policy I actually got wrong and explains how each condition should be written.

## Example setup

| Item | Example value |
|---|---|
| Bucket | `markmew-test-bucket` |
| Allowed folder | `foo/bar/` |
| Allowed operations | List, download, upload, and delete files under `foo/bar/` |
| Access method | AWS CLI, or clients such as WinSCP and S3 Browser |

S3 doesn't actually have folders. `foo/bar/report.csv` is just an object key, and the console and client tools display it as folders by splitting on `/`. So "restricting a folder" in a policy really means "restricting the key prefix."

## Which APIs do client tools call?

When a user navigates into `foo/bar/` in a client tool, the client typically sends these requests:

| User action | API | Required permission | Request details |
|---|---|---|---|
| List buckets in the account | `ListBuckets` | `s3:ListAllMyBuckets` | None |
| Get the bucket's Region | `GetBucketLocation` | `s3:GetBucketLocation` | None |
| Open the bucket root | `ListObjectsV2` | `s3:ListBucket` | Empty or missing prefix, delimiter `/` |
| Open `foo/` | `ListObjectsV2` | `s3:ListBucket` | Prefix `foo/`, delimiter `/` |
| Open `foo/bar/` | `ListObjectsV2` | `s3:ListBucket` | Prefix `foo/bar/` |
| Download, upload, or delete files | `GetObject`, etc. | `s3:GetObject`, etc. | Resource `foo/bar/*` |

If users access S3 through a client tool rather than calling the API on a known path, `s3:ListAllMyBuckets` is usually required. Users may see the names of other S3 buckets, but from the AWS account's point of view, the bucket list is the first level of the path. Without this permission, the client connects successfully but can't display anything.

```json
{
    "Action": [
        "s3:ListAllMyBuckets"
    ],
    "Effect": "Allow",
    "Resource": "*"
}
```

> `s3:ListAllMyBuckets` only reveals bucket names, not bucket contents. If your tool lets you set the target bucket and remote path directly (for example, setting WinSCP's default remote directory to `/markmew-test-bucket/foo/bar/`), you can omit this permission.
{: .prompt-tip }

## Wrong example: Allow everything, then exclude with Deny

At first, I followed a pattern I found online: allow `s3:ListBucket` on the whole bucket, then exclude other folders with a `Deny` statement and `StringNotLike`:

```terraform
resource "aws_iam_policy" "s3_foo_bar_access_policy" {
    name   = "S3FooBarAccessPolicy"

    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "HomeDirObjectAccess",
                "Action": [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:GetObjectACL"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket/*"
                ]
            },
            {
                "Action": [
                    "s3:PutObject",
                    "s3:GetObject",
                    "s3:DeleteObject",
                    "s3:DeleteObjectVersion",
                    "s3:GetObjectVersion",
                    "s3:GetObjectACL",
                    "s3:PutObjectACL",
                    "s3:AbortMultipartUpload"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket/foo/bar/*"
                ]
            },
            {
                "Action": [
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ]
            },
            {
                "Sid": "DisallowListingOfOtherFolder",
                "Action": [
                    "s3:ListBucket"
                ],
                "Condition": {
                    "StringNotLike": {
                        "s3:prefix": [
                            "",
                            "foo/",
                            "foo/*",
                            "foo/bar/",
                            "foo/bar/*"
                        ]
                    }
                },
                "Effect": "Deny",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ]
            },
            {
                "Action": [
                    "s3:ListAllMyBuckets"
                ],
                "Effect": "Allow",
                "Resource": "*"
            }
        ]
    })
}
```

This policy looks restrictive, but it has several problems:

1. **`HomeDirObjectAccess` grants read access to the entire bucket.** The resource is `markmew-test-bucket/*`, so anyone who knows an object key can download files from any folder. Restricting listing only hides files. It doesn't stop anyone from downloading them.
2. **`foo/*` lets other subfolders be listed.** Because the Deny exception list includes `foo/*`, requests for `foo/other/` or `foo/secret/` aren't denied, and the user can see file names in those folders.
3. **The empty string `""` doesn't restrict the delimiter.** A request with an empty prefix and no delimiter, such as `aws s3 ls s3://markmew-test-bucket --recursive`, lists every object key in the bucket.
4. **Clients that omit the prefix parameter are denied.** Some clients open the bucket root without any prefix parameter at all. With a negated operator like `StringNotLike`, **a missing key makes the condition evaluate to true**, so the request is explicitly denied and the client can't open the bucket. [IAM condition operators](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition_operators.html)
5. **An explicit Deny overrides every Allow.** If another policy later tries to grant access to an additional folder, this Deny still blocks it, and the cause is hard to spot when troubleshooting.

## Correct example: Allow only the prefixes you need

A better approach is to avoid granting broad access up front. Instead, **allow only the prefix and delimiter combinations that the client actually sends**:

```terraform
resource "aws_iam_policy" "s3_foo_bar_access_policy" {
    name   = "S3FooBarAccessPolicy"

    policy = jsonencode({
        "Version": "2012-10-17",
        "Statement": [
            {
                "Sid": "ListAllBucketsForClient",
                "Action": [
                    "s3:ListAllMyBuckets"
                ],
                "Effect": "Allow",
                "Resource": "*"
            },
            {
                "Sid": "GetBucketLocation",
                "Action": [
                    "s3:GetBucketLocation"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ]
            },
            {
                "Sid": "ListBucketRootWithoutPrefix",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ],
                "Condition": {
                    "Null": {
                        "s3:prefix": "true"
                    },
                    "StringEquals": {
                        "s3:delimiter": "/"
                    }
                }
            },
            {
                "Sid": "ListParentFoldersTopLevelOnly",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ],
                "Condition": {
                    "StringEquals": {
                        "s3:prefix": [
                            "",
                            "foo",
                            "foo/",
                            "foo/bar"
                        ],
                        "s3:delimiter": "/"
                    }
                }
            },
            {
                "Sid": "ListTargetFolder",
                "Action": [
                    "s3:ListBucket"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket"
                ],
                "Condition": {
                    "StringLike": {
                        "s3:prefix": [
                            "foo/bar/*"
                        ]
                    }
                }
            },
            {
                "Sid": "TargetFolderObjectAccess",
                "Action": [
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:DeleteObjectVersion",
                    "s3:AbortMultipartUpload"
                ],
                "Effect": "Allow",
                "Resource": [
                    "arn:aws:s3:::markmew-test-bucket/foo/bar/*"
                ]
            }
        ]
    })
}
```

### What each statement does

| Sid | Allowed requests | Why it's needed |
|---|---|---|
| `ListAllBucketsForClient` | List buckets | The first screen in client tools |
| `GetBucketLocation` | Look up the bucket's Region | Clients and the console need to know which Region to connect to |
| `ListBucketRootWithoutPrefix` | Listings with no prefix and delimiter `/` | Handles clients that open the root without any prefix parameter |
| `ListParentFoldersTopLevelOnly` | Single-level listings of the root and `foo/` | Lets users click through to `foo/bar/` while only seeing folder names |
| `ListTargetFolder` | Any listing under `foo/bar/` | Free browsing inside the target folder, including recursive listings |
| `TargetFolderObjectAccess` | Download, upload, and delete files in `foo/bar/` | Object operations are restricted by the Resource path |

### Why restrict `s3:delimiter` on parent folders?

When `ListObjectsV2` is called with `delimiter=/`, S3 returns only the files and subfolder names (CommonPrefixes) at that level, without expanding further. At the root, the user sees only `foo/`. In `foo/`, they see `bar/` and the names of sibling folders, but not the files inside those other folders.

Without the delimiter restriction, a request with prefix `foo/` could recursively list every object key under `foo/`, including the contents of `foo/other/`, which bypasses the folder restriction.

For the same reason, `foo/bar` (without the trailing `/`) also goes in the statement that requires a delimiter. The prefix `foo/bar` also matches similarly named folders such as `foo/barbaz/`, so without a delimiter it could list files the user shouldn't see.

> Single-level listings of parent folders still show sibling folder names and the names of files stored directly under `foo/`, though the user can't download them. If even the names must stay hidden, have users connect directly to `/markmew-test-bucket/foo/bar/` and remove the `ListBucketRootWithoutPrefix` and `ListParentFoldersTopLevelOnly` statements.
{: .prompt-warning }

### Why use `StringLike` for the target folder?

The `*` in `foo/bar/*` matches zero or more characters, so it covers both `foo/bar/` itself and prefixes at any depth below it. Because it doesn't restrict the delimiter, operations that need recursive listing, such as `aws s3 ls --recursive` and `aws s3 sync`, also work.

### Why were the ACL permissions removed?

New buckets default to `Bucket owner enforced`, which disables ACLs, so `s3:GetObjectAcl` and `s3:PutObjectAcl` have no effect. If you have an older bucket with ACLs still enabled and your client reads or writes ACLs, add them back as needed. [S3 Object Ownership documentation](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

## Verify with the AWS CLI

After applying the policy, use the AWS CLI to confirm that the allowed and denied scopes match your expectations:

```bash
# Allowed: list the root, only foo/ is visible
aws s3 ls s3://markmew-test-bucket/

# Allowed: list the foo/ level
aws s3 ls s3://markmew-test-bucket/foo/

# Allowed: list the target folder, including recursively
aws s3 ls s3://markmew-test-bucket/foo/bar/
aws s3 ls s3://markmew-test-bucket/foo/bar/ --recursive

# Allowed: upload, download, and delete files in the target folder
aws s3 cp ./test.txt s3://markmew-test-bucket/foo/bar/test.txt
aws s3 cp s3://markmew-test-bucket/foo/bar/test.txt ./download.txt
aws s3 rm s3://markmew-test-bucket/foo/bar/test.txt
```

The following operations should all return `AccessDenied`:

```bash
# Denied: recursively list the whole bucket
aws s3 ls s3://markmew-test-bucket --recursive

# Denied: list another folder
aws s3 ls s3://markmew-test-bucket/foo/other/

# Denied: upload outside the target folder
aws s3 cp ./test.txt s3://markmew-test-bucket/foo/test.txt

# Denied: download a file from another folder
aws s3 cp s3://markmew-test-bucket/foo/other/secret.txt ./secret.txt
```

## Frequently asked questions

### Can each user access only their own folder?

Yes. Replace the fixed path with the policy variable `${aws:username}`, for example by setting the resource to `arn:aws:s3:::markmew-test-bucket/home/${aws:username}/*`, so all IAM users can share one policy. This variable only works for IAM users. For IAM roles, use session tags with `${aws:PrincipalTag/...}` instead. [IAM policy variables](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html)

In Terraform strings, `${...}` is interpolation syntax, so escape it as `$${aws:username}`.

### What else is needed if the bucket uses SSE-KMS encryption?

If the bucket is encrypted with a customer managed KMS key, downloads also need `kms:Decrypt` and uploads need `kms:GenerateDataKey`, and the KMS key policy must allow the identity to use the key. If you use SSE-S3 or the AWS managed key `aws/s3`, no extra setup is needed.

### Some console tabs show permission errors. Is that normal?

Yes. This policy is enough to navigate to `foo/bar/` in the console and work with files, but the bucket's Properties and Permissions tabs call other APIs (such as `GetBucketPolicyStatus` and `GetBucketVersioning`). Without permission for those, the console shows error messages, but file operations aren't affected.

### Do I need all these ListBucket conditions if I only access S3 from code?

No. If your application knows the full object key, it only needs `TargetFolderObjectAccess`. If it needs to list files, add `ListTargetFolder`. The parent folder listing permissions exist so client tools and the console can click through one level at a time.

## Further reading

- [Cross-Account S3 Access: Setting Up IAM and Bucket Policies](/en/posts/s3-cross-account-access-iam-bucket-policy/)
- [5 Ways to Upload Files to Amazon S3: Console, CLI, API, SFTP, and Presigned URLs](/en/posts/upload-files-to-amazon-s3/)
- [Deep Dive: Understanding AWS IAM Role Permission Design](/en/posts/iam-role-policy-and-trust-relationship/)
- [AWS examples: Bucket policies for Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
