---
layout: post
title: EC2 中的 Container 無法透過 iam profile role 獲取相對應的權限
description: "EC2 上的容器無法取得執行個體設定檔憑證時，檢查 IMDSv2 Token 請求、Metadata 端點與回應的 hop limit。"
author: Mark_Mew
category: AWS
tags: [AWS, EC2]
date: 2026-3-11
last_modified_at: 2026-11-05
---

在 EC2 上執行需要存取 AWS 資源的程式時，可以為執行個體指派具備最小權限的 IAM Role。EC2 會透過 Instance Metadata Service（IMDS）提供暫時憑證。若要求使用 IMDSv2，必須先取得 Token，再查詢 Metadata：

```bash
TOKEN=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

順利的話應該會出現

```
<IAM Profile Name>
```

不過若將 IMDSv2 設為必須使用，

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
3. 如果工作負載不應共用主機的 Instance Profile，改用適合該平台的短期憑證機制；不要把長期 IAM User Access Key 放進 Runner 的環境變數當作替代方案。


參考資料
---
1. [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)

2. [Configure instance metadata options for new instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html?utm_source=chatgpt.com)
