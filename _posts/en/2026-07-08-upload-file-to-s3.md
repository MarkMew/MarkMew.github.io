---
layout: post
title: "5 Ways to Upload Files to Amazon S3: Console, CLI, API, SFTP, and Presigned URLs"
description: "Compare five ways to upload files to Amazon S3 using the AWS Management Console, AWS CLI, API Gateway, AWS Transfer Family, and presigned URLs, including use cases, limitations, security considerations, and examples."
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3]
keywords: [AWS, S3, AWS Management Console, AWS CLI, API Gateway, Transfer Family, Presigned URL]
lang: en
date: 2026-07-08
---

Uploading files to S3 is one of the most common operations on AWS.

However, “uploading a file” can refer to very different scenarios: an engineer uploading from a local machine, a CI pipeline publishing static assets, a backend accepting user attachments, a browser uploading a large file directly, or a partner that can only use SFTP. Although all of these workflows ultimately write objects to S3, the best entry point is not the same.

This article compares five practical approaches:

1. Upload directly through the AWS Management Console
2. Use the AWS CLI
3. Integrate API Gateway directly with S3, or upload through a backend
4. Use AWS Transfer Family for external file exchange over SFTP or FTPS
5. Use a presigned URL for direct uploads from a frontend or external client

## Quick Comparison

| Method | Best suited for | Advantages | Main limitations |
| --- | --- | --- | --- |
| AWS Management Console | One-off tasks, a small number of files, getting started with S3 | No tools to install and easy to use | Manual and unsuitable for automation or repeated bulk operations |
| AWS CLI | Engineers, local operations, CI/CD | Simple, direct, and supports directories and large files | The environment needs an AWS identity and IAM permissions |
| API Gateway/backend | Small attachments and APIs that require business logic and validation | Centralized authentication, authorization, auditing, and naming rules | Subject to API payload limits; routing through a backend also consumes compute resources |
| AWS Transfer Family | Partners, legacy systems, and SFTP/FTPS workflows | Partners do not need to switch to an AWS API | Requires endpoint, user, network, and service cost management |
| Presigned URL | Direct uploads from web apps, mobile apps, or third-party systems | Files bypass the backend and the design scales easily | Requires careful handling of URL expiration, CORS, object names, and upload constraints |

## Method 1: AWS Management Console

Before adopting the CLI or infrastructure-as-code tools, the most straightforward option is to sign in to the AWS Management Console, open Amazon S3, select the target bucket, and choose **Upload**.

This method requires no installation or commands, making it useful for one-off uploads, testing, or learning how S3 works. The interface also lets you configure metadata, storage class, and other object properties during the upload.

Console operations are manual and difficult to repeat or automate, so they are not suitable for CI/CD or scheduled jobs. The Amazon S3 console currently supports individual files of up to 160 GB. For larger files, use the AWS CLI, an AWS SDK, or the S3 REST API.

## Method 2: AWS CLI

The AWS CLI is useful for engineers uploading directly from a local machine, bastion host, or CI pipeline. It is simple to get started with, but IAM permissions and credential management still require care.

### Upload a Single File

```bash
aws s3 cp ./report.csv s3://example-bucket/uploads/report.csv
```

After the upload, verify that the object exists:

```bash
aws s3 ls s3://example-bucket/uploads/report.csv
```

### Upload an Entire Directory

Use `--recursive` to upload a directory recursively:

```bash
aws s3 cp ./dist s3://example-bucket/site/ --recursive
```

If the source and destination need to remain synchronized over time, use `sync`:

```bash
aws s3 sync ./dist s3://example-bucket/site/
```

The AWS CLI high-level S3 commands automatically switch to multipart upload when a file reaches the multipart threshold, so you do not need to split each part manually. In production, use AWS IAM Identity Center for local access and IAM roles or temporary credentials for EC2, ECS, EKS, and CI runners. Avoid storing long-term access keys in source code or pipeline variables.

> If a bastion host or another EC2 instance contains files that need to be backed up, `cron` can run `aws s3 sync` on a schedule. Use an EC2 IAM role, restrict access to a dedicated S3 prefix, and do not store long-term access keys on the instance.
{: .prompt-info }

### Permissions

#### Uploading with WinSCP or S3 Browser

Graphical clients such as WinSCP and S3 Browser access objects through the S3 API; they do not run the AWS CLI underneath. In addition to `s3:PutObject`, which is required to upload objects, a client needs `s3:ListBucket` to display objects in a specific bucket.

Some clients first list every bucket in the account and therefore require `s3:ListAllMyBuckets`. This permission exposes the names of the account's buckets. If the client can be configured to open a known bucket directly, you can omit it. The following example allows a user to browse and upload to `uploads/`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListUploadPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uploads", "uploads/*"]
        }
      }
    },
    {
      "Sid": "UploadObjects",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    },
    {
      "Sid": "ListBucketsInClient",
      "Effect": "Allow",
      "Action": "s3:ListAllMyBuckets",
      "Resource": "*"
    }
  ]
}
```

Add `s3:GetObject` or `s3:DeleteObject` only if users also need to download or delete objects. There is no reason to grant all of these permissions by default.

#### Uploading with the CLI

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListUploadPrefix",
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::example-bucket",
      "Condition": {
        "StringLike": {
          "s3:prefix": ["uploads", "uploads/*"]
        }
      }
    },
    {
      "Sid": "UploadObjects",
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    }
  ]
}
```

These permissions are sufficient to upload to and list `uploads/`. To run the earlier directory upload targeting `site/`, add that prefix to the policy. If uploads do not need to list objects, remove `s3:ListBucket`.

## Method 3: Integrate API Gateway with S3 or Upload Through a Backend

### Upload Directly from API Gateway to S3

API Gateway can invoke more than Lambda. A REST API can use an AWS service integration to pass a request directly to S3 without an intermediate Lambda function:

```text
Client → API Gateway REST API → Amazon S3
```

Create an execution role for API Gateway and allow it to call `s3:PutObject` for the intended location. The following policy only permits writes to `uploads/`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::example-bucket/uploads/*"
    }
  ]
}
```

Next, create a `PUT` method in the REST API, select S3 as the AWS service integration, map the filename in the URL to the S3 object key, and forward the required `Content-Type`. To accept binary files, configure the API's binary media types as well.

The execution role only gives API Gateway permission to write to S3; it does not authenticate the caller. A public-facing API still needs IAM authorization, a Cognito authorizer, or another authorization mechanism. Although this design removes Lambda, the file still passes through API Gateway and remains subject to the 10 MB payload limit.

### Upload Through Lambda or Another Backend

This approach is appropriate when authentication, authorization, and auditing must be controlled centrally by the backend. It offers more flexibility but also increases system complexity.

```text
Client → API Gateway → Lambda/Backend → Amazon S3
```

The backend can validate the user's identity, file type, business reference, and object name before calling `PutObject` through an AWS SDK. The core operation looks like this; HTTP request parsing and error handling depend on the framework:

```python
import boto3

s3 = boto3.client("s3")

s3.put_object(
    Bucket="example-bucket",
    Key="uploads/report.pdf",
    Body=file_bytes,
    ContentType="application/pdf",
)
```

The advantage is that every rule remains in the backend. For example, only the owner of an order may upload an attachment, an object may be created only after a database write succeeds, or each upload may need to trigger malware scanning and review.

The disadvantage is that the file passes through both API Gateway and the backend, consuming network bandwidth and compute resources at both layers. API Gateway HTTP APIs have a fixed 10 MB payload limit. If the request also requires Base64 encoding, the maximum raw file size is even smaller. This method is therefore better suited to small attachments than large videos, backups, or datasets.

For large files, use a presigned URL so that API Gateway only authenticates the user and issues upload authorization instead of carrying the file itself.

## Method 4: AWS Transfer Family

AWS Transfer Family is suitable when external systems need to exchange files over SFTP or FTPS, allowing an existing workflow to connect to S3 with fewer changes.

AWS Transfer Family is a managed file transfer service supporting SFTP, FTPS, FTP, AS2, and browser-based transfers, with S3 or EFS as the backend. Partners can continue using familiar tools such as WinSCP, Cyberduck, FileZilla, or OpenSSH without learning the AWS CLI or obtaining AWS credentials.

The basic process is:

1. Create the S3 bucket and the IAM role used by Transfer Family.
2. Create a Transfer Family server that supports SFTP or FTPS.
3. Choose service-managed users, Microsoft AD, or a custom identity provider.
4. Configure each user's home directory and accessible S3 prefix.
5. Provide the Transfer Family endpoint to the partner.

Uploading with an SFTP client works like any other SFTP server:

```bash
sftp -i ~/.ssh/partner-key partner@s-0123456789abcdef0.server.transfer.ap-northeast-1.amazonaws.com
sftp> put report.csv /uploads/report.csv
```

Remember that S3 has no true directory hierarchy. Directories displayed by an SFTP client are object key prefixes, and filesystem operations such as `chmod` and symbolic links do not necessarily map to S3.

Transfer Family works well for existing B2B file exchanges, fixed source IP addresses, enterprise identity requirements, and legacy systems that are difficult to change. If one user only needs to upload an occasional file, Transfer Family is usually more complex than a presigned URL and also introduces endpoint and data transfer costs.

## Method 5: Presigned URL

A presigned URL lets a frontend or third-party client upload directly to S3, reducing traffic through the backend. It requires an appropriate expiration time and upload constraints.

```text
1. Client requests upload authorization from the backend
2. Backend authenticates the client and generates a presigned URL
3. Client uses the URL to PUT the file directly to S3
4. An S3 event starts downstream processing
```

The IAM principal generating the presigned URL must have permission to upload to the target object key. The following Python example creates a `PUT` URL that remains valid for 15 minutes and applies only to the specified object key:

```python
import boto3

s3 = boto3.client("s3")

upload_url = s3.generate_presigned_url(
    ClientMethod="put_object",
    Params={
        "Bucket": "example-bucket",
        "Key": "uploads/8f6c2f4a/report.pdf",
        "ContentType": "application/pdf",
    },
    ExpiresIn=900,
)
```

After receiving the URL, the client can upload directly:

```bash
curl --request PUT \
  --header "Content-Type: application/pdf" \
  --upload-file ./report.pdf \
  "<presigned-url>"
```

If `Content-Type` is included in the signature, the client must send the same header or S3 will reject the request because the signature does not match. Direct browser uploads also require a bucket CORS configuration that permits the intended origin and HTTP method.

Treat a presigned URL as a short-lived bearer token: anyone who obtains it can use it until it expires. At minimum:

- Let the backend choose the bucket and object key instead of trusting a full path supplied by the user.
- Use a UUID or tenant prefix to prevent users from overwriting the same key.
- Set a short, reasonable expiration time and do not write the URL to public logs or analytics tools.
- Validate allowed filename extensions, MIME types, and business state before upload, then inspect the actual content afterward.
- If file size or form fields must be restricted, consider a presigned POST with policy conditions.
- For large files, use a presigned multipart upload so that the client can upload parts in parallel and retry failures.

The same presigned URL can be reused before it expires. If the target key already exists, an upload may overwrite the object when versioning is disabled or create a new version when versioning is enabled. It is not a one-time URL, so a previous successful use alone does not make it safe.

## Shared Security and Operational Considerations

Regardless of the method, review the following areas.

### Least-Privilege IAM Permissions

Restrict the accessible bucket, prefix, and operations. An upload-only application usually needs only `s3:PutObject`. Add `s3:ListBucket`, `s3:GetObject`, or `s3:DeleteObject` only when listing, downloading, or deletion is genuinely required. Administrative permissions such as modifying bucket policies or lifecycle rules should not be granted to a regular uploader.

### Prevent Accidental Overwrites

An S3 object key identifies the object. Uploading to the same key again may overwrite the existing object. Enable S3 Versioning or generate unique keys when history must be retained.

### Encryption and Sensitive Data

S3 automatically encrypts newly uploaded objects with SSE-S3. If regulation, auditing, or separation-of-duties requirements call for a customer-managed key, configure the bucket to use SSE-KMS by default and grant the required KMS permissions.

### Do Not Trust Filename Extensions Alone

The client supplies `.jpg`, `.pdf`, and `Content-Type`, so none of them proves that the content is safe. External uploads should first enter an isolated prefix. An event-driven process can then validate the format, scan for malware, or request manual review before moving the object to its final location.

### Large Files and Incomplete Uploads

A single S3 `PUT` can upload up to 5 GB. Larger objects require multipart upload, and a single S3 object can currently be as large as 50 TB. Parts from an incomplete multipart upload continue to incur storage charges, so configure a lifecycle rule to remove stale incomplete uploads automatically.

## Conclusion

There is no single best method. The right choice depends on who is uploading, the size of the file, whether an existing protocol must remain compatible, and whether the file content needs to pass through the backend.

- For one-off uploads of a few files, use the AWS Management Console.
- For trusted engineers or CI/CD, start with the AWS CLI.
- For small files that only need to be forwarded to S3, consider an API Gateway AWS service integration.
- For small files that require backend business logic, use API Gateway with a backend.
- If a partner can only use SFTP or FTPS, use AWS Transfer Family.
- For direct uploads from web apps, mobile apps, or third parties, prefer presigned URLs.

For most end-user upload features, the backend can handle authorization and choose the object key, while the client sends the file directly to S3 with a presigned URL. This design often provides a good balance among security, performance, and system complexity.

---

## References

- [AWS CLI `s3 cp` Command Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html)
- [Uploading objects - Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/upload-objects.html)
- [Listing Amazon S3 general purpose buckets](https://docs.aws.amazon.com/AmazonS3/latest/userguide/list-buckets.html)
- [Tutorial: Create a REST API as an Amazon S3 proxy](https://docs.aws.amazon.com/apigateway/latest/developerguide/integrating-api-with-aws-services-s3.html)
- [Quotas for configuring and running a REST API in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-execution-service-limits-table.html)
- [Quotas for configuring and running an HTTP API in API Gateway](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-quotas.html)
- [What is AWS Transfer Family?](https://docs.aws.amazon.com/transfer/latest/userguide/what-is-aws-transfer-family.html)
- [Download and upload objects with presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/userguide/using-presigned-url.html)
- [Configuring cross-origin resource sharing (CORS)](https://docs.aws.amazon.com/AmazonS3/latest/userguide/ManageCorsUsing.html)
- [Configuring default encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/default-bucket-encryption.html)
- [Deleting incomplete multipart uploads with a Lifecycle rule](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpu-abort-incomplete-mpu-lifecycle-config.html)
