---
layout: post
title: EC2 中的 Container 無法透過 iam profile role 獲取相對應的權限
author: Mark_Mew
category: AWS
tags: [AWS, EC2]
date: 2026-3-11
---

在操作 EC2 裡面要操作 AWS 的資源的時候，

我們都知道最佳實踐是綁定 IAM Profile Role 並關聯最小權限去操作。

因為實際上 EC2 底層在運行的時候，

會塞一個憑證在底層，

需要使用以下指令呼叫才能夠獲取。

```bash
curl http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

順利的話應該會出現

```
<IAM Profile Name>
```

不過如果調整一個 EC2 上的 feature - IMDSv2，

就有可能讓 EC2 中的 Container 無法順利獲取權限。

EC2 Instance 明細頁 -> `Actions` -> `Instance settings` -> `Modify instance metadata options`

傳統上 IMDSv2 的設定是 Optional，

不過後來官方建議改成 Required，

這個修改是用來防止應用程式或漏洞被濫用，

偷拿 instance 的憑證或 metadata。

> EC2 instance 內部可以透過一個本地 URL 取得很多資訊，例如：
> ```
> http://169.254.169.254/latest/meta-data/
> ```
> 可以拿到像是：
> * instance ID
> * IAM role credentials
> * security groups
> * AMI ID
> * hostname
> * region
> 這些資料很多應用程式（像 AWS SDK）會用來自動取得 IAM temporary credentials。
{: .prompt-info}

早期的 IMDSv1 只有送個 request 就可以拿到 meta-data，

IMDSv2 加了一個 session token 機制，

會先拿 token 再拿 meta-data。

不過既然官方都建議要設為 required，

那應該是總不可能改為 optional 吧？

沒錯，實際上在 EC2 中執行 Docker 的時候取不到權限還有別的問題

1. IMDSv2 需要 Token，但是只支援 IMDSv1
	
	IMDSv2 的流程是：
	1) 先 PUT 取得 token
	2) 再用 token GET metadata
	有些舊版工具（或舊版 SDK）只支援 IMDSv1，例如：
	- 舊版 AWS CLI
	- 舊版 SDK
	- 某些 CI image
	結果就會變成 `401 Unauthorized`，因為沒有 token。
2. hop limit 問題
	
    EC2 metadata 有一個設定：
    ```
    HttpPutResponseHopLimit
    ```
    預設通常是：
    ```
    1
    ```
    
    但 Docker container 到 metadata 其實會多一個 network hop：
    ```
    container
        ↓
    docker bridge
        ↓
    EC2 instance network
        ↓
    169.254.169.254
    ```

    所以 hop=1 時 token 回應回不到 container。
    
    這會導致：
    ```
    IMDSv2 token request timeout
    ```
    
    這是 CI Runner 最常遇到的原因。
    
    解法是把 hop limit 調高。
    
    例如：
    ```bash
    aws ec2 modify-instance-metadata-options \
        --instance-id i-xxxx \
        --http-put-response-hop-limit 2
    ```

3. Docker network policy / iptables
	
    不過我對於這方法不是很清楚

    也許未來有遇到我會再回來補充

---

當時會遇到這問題，

是在 EC2 上架設 Gitlab CI Runner 時發生，

在 Pipeline 中執行 Container 流程如下：

```
container
   ↓
docker bridge (docker0)
   ↓
host network
   ↓
IMDS
```

token 回應回來時會變成：

```
IMDS
 ↓
host network
 ↓
docker bridge
 ↓
container
```

實際 hop 可能變：
```
2 hops
```

如果：
```
HttpPutResponseHopLimit = 1
```

封包會被丟掉。

所以 container 看到的結果通常是：

```
IMDS token request timeout
```

或

```
no credentials found
```

解決方式不只一種：

1. IMDSv2 改為 Optional（不建議）
2. 增加 hop limit
3. 將 IAM User Credentails 注入在 Environment Variable 中，Gitlab CI Runner 在執行時注入（尚可）


參考資料
---
1. [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)

2. [Configure instance metadata options for new instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html?utm_source=chatgpt.com)