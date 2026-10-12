---
layout: post
title: "Amazon ECR Cross-Account Access: Repository and IAM Policies"
image: https://fastly.picsum.photos/id/776/1200/630.jpg?hmac=Lb8y0-sLk2uqC_rjc_vHCUEnR1NLKPZjFgwq2FtfAoQ
description: "Grant a specific IAM role in another AWS account pull access to a private ECR repository with repository and IAM policies. Includes AWS CLI and Docker verification and troubleshooting."
author: Mark_Mew
categories: [AWS, ECR]
tags: [AWS, ECR, IAM]
keywords: [ECR cross-account access, ECR repository policy, IAM policy, Docker pull]
lang: en
date: 2026-10-12
---

**To let an IAM role in one AWS account pull images from a private Amazon ECR repository in another account, the destination repository policy must allow the role, and the source role's IAM policy must allow the required ECR actions.** The source role also needs `ecr:GetAuthorizationToken` to authenticate to the registry. A successful login alone does not grant access to a repository.[Amazon ECR repository policies](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html)

This article walks through a least-privilege setup for an application in Account A that pulls an image from a private repository in Account B. It covers the policies, AWS CLI and Docker commands, and common troubleshooting steps. You can also read the [S3 cross-account access guide](/posts/s3-cross-account-access-iam-bucket-policy/).

## Repository policies and IAM policies

An ECR repository policy is a resource-based policy that controls which principals can perform actions on an individual repository. An IAM policy is an identity-based policy attached to a role in the source account. For cross-account access, the destination account grants access through the repository policy, and the source role must also have the required IAM permissions. Any applicable explicit `Deny` overrides an `Allow`.[How Amazon ECR works with IAM](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_service-with-iam.html)

| Where the policy is configured | Policy | What it allows |
|---|---|---|
| Account A IAM role | IAM policy | Authenticate to ECR and pull images from the specified Account B repository |
| Account B ECR repository | Repository policy | Allow the specified Account A role to access that repository |

## Example and prerequisites

| Item | Example value |
|---|---|
| Source account A | `111111111111` |
| Destination account B | `222222222222` |
| AWS Region | `ap-northeast-1` |
| Account A role | `AppPullImageRole` |
| Account B repository | `backend-api` |
| Image tag | `2026.10.12` |
| CLI profile | `account-a-app` |

Replace these example values with your own. This guide assumes the destination repository and source IAM role already exist and that AWS CLI and Docker are installed and configured. An ECR registry URI has this format: `<account-id>.dkr.ecr.<region>.amazonaws.com`. Add the repository name to get the full repository URI.

This setup grants pull access to existing images. It does not grant permission to push images, create repositories, or delete repositories. ECR cross-account and cross-Region replication is a separate way to copy images to another registry. Use a repository policy when consumers should pull directly from the source repository.[Private image replication in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/replication.html)

## Step 1: Grant the Account A role permission to pull

In Account A, attach the following IAM policy to `AppPullImageRole`. The `ecr:GetAuthorizationToken` action requires `Resource: "*"`. Scope the remaining pull actions to the destination repository ARN.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "GetECRAuthorizationToken",
      "Effect": "Allow",
      "Action": "ecr:GetAuthorizationToken",
      "Resource": "*"
    },
    {
      "Sid": "PullFromAccountBRepository",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "arn:aws:ecr:ap-northeast-1:222222222222:repository/backend-api"
    }
  ]
}
```

`GetAuthorizationToken` is required to log in to the registry; a repository policy cannot replace this permission. The other three actions let the client check image layers, retrieve the image manifest, and download layers. If your tooling also lists images or reads repository details, add `ecr:ListImages`, `ecr:DescribeImages`, or `ecr:DescribeRepositories` as needed. The `docker pull` example here does not require those broader permissions.[Amazon ECR identity-based policy examples](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html)

### Terraform: IAM policy for the source role

The following Terraform example creates the identity policy a GitLab Runner needs to pull from the `dockerdind` and `devtool` repositories. Attach the resulting policy to the Runner role in Account A.

```terraform
resource "aws_iam_policy" "pull_ecr_from_other_account_policy" {
  name = "PullECRFromOtherAccountPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "PullCrossAccountRunnerImages"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = [
          "arn:aws:ecr:ap-northeast-1:222222222222:repository/dockerdind",
          "arn:aws:ecr:ap-northeast-1:222222222222:repository/devtool"
        ]
      }
    ]
  })
}
```

## Step 2: Set the repository policy in Account B

In Account B and the `ap-northeast-1` Region, open the ECR `backend-api` repository and add the following repository policy under **Permissions**. If a policy already exists, add this statement while preserving the statements you still need.

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowAccountARoleToPull",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/AppPullImageRole"
      },
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer"
      ],
      "Resource": "*"
    }
  ]
}
```

Set `Principal` to the source IAM role ARN. If the role has a path, use its full ARN, such as `arn:aws:iam::111111111111:role/team/AppPullImageRole`. This example grants access to one role. To delegate to the entire source account, use `arn:aws:iam::111111111111:root` and use an IAM policy in that account to control which identities can use the delegation. Avoid granting access to an entire account or using a wildcard principal unless you need to.[Private repository policy examples in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)

### Terraform: repository policies in the destination account

The following resources grant cross-account pull access to the `devtool` and `dockerdind` repositories in Account B. Update the repository names and source role ARN for your environment.

```terraform
resource "aws_ecr_repository_policy" "devtool" {
  repository = aws_ecr_repository.devtool.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountGitLabRunnerPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::111111111111:role/DummyRole"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_ecr_repository_policy" "dockerdind" {
  repository = aws_ecr_repository.dockerdind.name
  policy     = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountGitLabRunnerPull"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::111111111111:role/DummyRole"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}
```

## Step 3: Verify the source identity and log in to ECR

First, confirm that the AWS CLI is using the expected role in Account A.

```shell
aws sts get-caller-identity --profile account-a-app
```

The `Account` value should be `111111111111`, and the ARN should look like this:

```text
arn:aws:sts::111111111111:assumed-role/AppPullImageRole/example-session
```

If a different role appears, fix the profile or credential source before continuing.

This is an STS role session ARN. Use the IAM role ARN in the repository policy's `Principal` instead.

Retrieve a login password and authenticate Docker to the Account B registry in `ap-northeast-1`:

```shell
aws ecr get-login-password --region ap-northeast-1 --profile account-a-app | docker login --username AWS --password-stdin 222222222222.dkr.ecr.ap-northeast-1.amazonaws.com
```

Docker should respond with `Login Succeeded`. ECR authorization tokens expire; rerun the login command when a token expires.[AWS CLI get-login-password reference](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html)

## Step 4: Pull the image

After logging in, pull the image by its full repository URI and tag.

```shell
docker pull 222222222222.dkr.ecr.ap-northeast-1.amazonaws.com/backend-api:2026.10.12
```

The account ID and Region in the URI must match the destination registry and repository. The repository and tag must also exist. For cross-Region access, log in to and pull from the Region where the image is stored.

## Troubleshooting access denied errors

| Symptom | What to check |
|---|---|
| `get-login-password` returns `AccessDeniedException` | Does the source role's IAM policy allow `ecr:GetAuthorizationToken`? Check for restrictions from SCPs, permissions boundaries, session policies, and other controls. |
| Docker login fails or returns `no basic auth credentials` | Do the registry URI, Region, and account ID match? Is `AWS` used as the Docker username? |
| Login succeeds but `docker pull` is denied | Check the pull actions, repository ARN, and source role ARN in both policies. |
| Image or tag is not found | Check the repository name, tag, registry URI, and Region. |
| The policies look correct but access is denied | Check for explicit denies, SCPs, resource control policies, and VPC endpoint policies. |

In the source IAM policy, scope `Resource` to the repository ARN. In the repository policy, use `"*"` for `Resource` and set `Principal` to the source IAM role ARN. Do not use the STS assumed-role session ARN shown by `get-caller-identity` as the principal. Adding an `Allow` does not override an applicable explicit `Deny`.[Setting a private repository policy statement in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html)

## Frequently asked questions

### Is the repository policy alone enough?

For cross-account access, check both the destination repository policy and the source role's IAM policy. The source identity must also have `ecr:GetAuthorizationToken` in an IAM policy; the repository policy cannot grant this login permission.

### Does this grant permission to push images?

No. This example grants only the actions required to pull. Pushing requires additional actions such as `ecr:CompleteLayerUpload`, `ecr:InitiateLayerUpload`, `ecr:PutImage`, and `ecr:UploadLayerPart`. Add them only when needed and scope them to the intended repository.[Private repository policy examples in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html)

### Do I have to use an IAM role?

This example uses a role so the application can use temporary credentials. Other IAM principals can be used where appropriate, but avoid storing long-term access keys in images, source code, or deployment settings. In AWS compute environments, prefer the workload's execution role or workload identity mechanism.

---

After setup, `AppPullImageRole` in Account A can log in to the Account B ECR registry and pull the specified image from `backend-api`. To grant another role access, add the required principal and repository permissions to the policies, then verify the setup in your AWS environment.

## References

- [Private repository policies in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policies.html): How repository policies and IAM policies control access.
- [Private repository policy examples in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-policy-examples.html): Policy examples, including cross-account access.
- [Amazon ECR identity-based policy examples](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security_iam_id-based-policy-examples.html): IAM policy examples for ECR.
- [Setting a private repository policy statement in Amazon ECR](https://docs.aws.amazon.com/AmazonECR/latest/userguide/set-repository-policy.html): How to configure a repository policy.
- [get-login-password — AWS CLI Command Reference](https://docs.aws.amazon.com/cli/latest/reference/ecr/get-login-password.html): Retrieve an ECR registry login password.
- [aws_iam_policy — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy): Terraform IAM policy resource.
- [aws_ecr_repository_policy — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy): Terraform ECR repository policy resource.
