---
layout: post
title: Containers in EC2 Cannot Obtain Expected Permissions via IAM Instance Profile Role
author: Mark_Mew
category: AWS
tags: [AWS, EC2]
date: 2026-3-11
---

When you need to access AWS resources from workloads running on EC2,

we all know the best practice is to attach an IAM Instance Profile Role with least privilege.

Under the hood, EC2 provides credentials through the metadata service,

and you can retrieve them with the following command:

```bash
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

If everything works correctly, you should see:

```
<IAM Profile Name>
```

However, after enabling an EC2 feature — IMDSv2,

a container running inside EC2 may fail to obtain credentials.

EC2 instance detail page -> `Actions` -> `Instance settings` -> `Modify instance metadata options`

Traditionally, IMDSv2 was often set to Optional,

but AWS later recommended setting it to Required.

This is to reduce the risk of abused applications or vulnerabilities

stealing instance credentials or metadata.

> Inside an EC2 instance, a local URL provides a lot of information, for example:
> ```
> http://169.254.169.254/latest/meta-data/
> ```
> You can get data such as:
> * instance ID
> * IAM role credentials
> * security groups
> * AMI ID
> * hostname
> * region
> Many applications (such as AWS SDKs) use this data to automatically obtain temporary IAM credentials.
{: .prompt-info}

In early IMDSv1, you could get metadata with a simple request.

IMDSv2 adds a session token mechanism:

first get a token, then request metadata.

But if AWS recommends setting IMDSv2 to required,

does that mean changing back to optional is not the right fix?

Exactly. When running Docker on EC2, there are other possible causes as well.

1. IMDSv2 requires a token, but your tooling only supports IMDSv1

   IMDSv2 flow:
   1) Send PUT to obtain a token
   2) Use the token to GET metadata
   Some older tools (or older SDK versions) only support IMDSv1, for example:
   - older AWS CLI versions
   - older SDK versions
   - some CI images
   The result becomes `401 Unauthorized` because no token is provided.

2. Hop limit issue

    EC2 metadata options include:
    ```
    HttpPutResponseHopLimit
    ```
    The default is usually:
    ```
    1
    ```

    But from a Docker container to metadata, there is usually one extra network hop:
    ```
    container
        ↓
    docker bridge
        ↓
    EC2 instance network
        ↓
    169.254.169.254
    ```

    So when hop=1, the token response cannot return to the container.

    This leads to errors like:
    ```
    IMDSv2 token request timeout
    ```

    This is one of the most common causes in CI runners.

    The fix is to increase the hop limit.

    For example:
    ```bash
    aws ec2 modify-instance-metadata-options \
        --instance-id i-xxxx \
        --http-put-response-hop-limit 2
    ```

3. Docker network policy / iptables

    I’m not very familiar with this part yet.

    I may come back and add details in the future.

---

I encountered this issue

while setting up a GitLab CI Runner on EC2.

In the pipeline, container network flow looked like this:

```
container
   ↓
docker bridge (docker0)
   ↓
host network
   ↓
IMDS
```

When the token response came back:

```
IMDS
 ↓
host network
 ↓
docker bridge
 ↓
container
```

The actual hop count could become:
```
2 hops
```

If:
```
HttpPutResponseHopLimit = 1
```

the packet is dropped.

So containers usually end up seeing:

```
IMDS token request timeout
```

or

```
no credentials found
```

There is more than one possible solution:

1. Change IMDSv2 to Optional (not recommended)
2. Increase hop limit
3. Inject IAM user credentials as environment variables at GitLab CI Runner runtime (acceptable)


References
---
1. [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)

2. [Configure instance metadata options for new instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html?utm_source=chatgpt.com)
