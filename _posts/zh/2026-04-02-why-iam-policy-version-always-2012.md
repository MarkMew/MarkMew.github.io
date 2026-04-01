---
layout: post
title: "AWS 冷知識：IAM Policy Version 為什麼總是 2012-10-17？"
description: "為什麼 AWS IAM Policy 的 Version 常見 2012-10-17？本文快速解析版本真正意義、與 AWS API 版本差異，以及不寫 Version 的影響。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Policy, Policy Variables]
keywords: [AWS IAM Policy Version, 2012-10-17, IAM Policy Variables, IAM JSON Policy, AWS Security, IAM Policy 2012-10-17, 為什麼 IAM Policy Version 是 2012-10-17]
date: 2026-4-2
---

AWS 的使用者，對於 IAM Policy 中常看到 `Version` 欄位是 `2012-10-17` 感到非常熟悉。

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

很多人第一次看到都會疑惑：

- 為什麼永遠是這個日期？
- AWS 都更新這麼多年了，版本不會變嗎？

這篇文章整理了常見疑問，快速說明這個日期的真正意義。

## IAM Policy 的 Version 為什麼總是 2012-10-17

先說結論：`2012-10-17` 指的是 IAM Policy Language 的版本，而不是所有 AWS 服務共用的一個統一 API 版本。

每個 AWS 服務都有自己的 API 版本，例如：

- Amazon S3：`2006-03-01`
  [Amazon S3 API 文件](https://docs.aws.amazon.com/zh_tw/AmazonS3/latest/API/Welcome.html)
- AWS Lambda：`2015-03-31`
  [AWS Lambda GetFunction API 文件](https://docs.aws.amazon.com/zh_tw/lambda/latest/api/API_GetFunction.html)
  ```
  GET /2015-03-31/functions/FunctionName?Qualifier=Qualifier HTTP/1.1
  ```

- Amazon EC2：`2016-11-15`
  ```
  API Version: 2016-11-15
  ```
  [Class: AWS.EC2 - JavaScript SDK](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html)

所以更精確的說法是：IAM Policy 語言目前常用版本是 `2012-10-17`，但這不代表所有 AWS API 都是同一個版本。

## 為什麼是 2012-10-17 這個日期

較常見、也較可信的解釋是：`2012-10-17` 是 AWS 發布新版政策語言的重要時間點。

這一版帶來了 Policy Variables，像是 `${aws:username}`、`${aws:PrincipalTag}` 這類變數能力，讓同一條政策可以更彈性地套用到大量使用者或角色。

也因此，`2012-10-17` 在 IAM Policy 中成為最常見、也最建議使用的版本。

## 如果不寫 Version 會怎樣

如果在政策中省略 `Version`，AWS 會以較舊的 `2008-10-17` 規則處理。

在這種情況下，像 `${aws:username}` 這類字串可能不會被正確當作變數解析，而只會被視為一般文字。

## 哪些地方還看得到 `2008-10-17` 的版本

如果你去翻閱一些在 2012 年以前就建立且從未更新過的 AWS 帳號，你會發現大量的 Inline Policy 都沒有 Version 欄位。

官方規則：在 IAM 邏輯中，如果 JSON 裡完全省略 "Version" 欄位，AWS 會預設使用 2008-10-17 的解析引擎。

因此，這些「隱形」的 2008 版政策在現有的舊架構中依然大量存在。

而 AWS Console 建立某些資源的存取政策時，系統自動生成的 JSON 模板往往會預設帶入 2008-10-17。這並不是因為它們不支援 2012 版，而是為了與舊有的系統與 API 維持最大相容性：

- SQS 佇列政策 (SQS Queue Policies)：在 SQS 控制台中點擊「編輯政策」時，產生的預設代碼通常還是 2008-10-17。

- SNS 主題政策 (SNS Topic Policies)：與 SQS 類似，SNS 的預設存取權限 JSON 經常顯示 2008 版。

- VPC 端點政策 (VPC Endpoint Policies - 僅限 Gateway 類型)：例如針對 S3 或 DynamoDB 的 Gateway Endpoint，其預設政策語言常標註為 2008。

## 為什麼這些舊 Version「強制」改版？

這涉及到底層 API 的設計（例如 SQS 的 SetQueueAttributes API）。

- API 相容性：許多服務的 Resource Policy 是透過該服務自己的 API（而非 IAM API）來管理的。這些 API 在 2012 年前就定義好了，為了不破壞全球開發者的自動化腳本，AWS 選擇維持預設值。

- 功能需求較單純：對於 SQS 或 SNS 來說，多數情況只需要簡單的 Allow/Deny 某個 ARN，不需要用到 2012 版才有的「政策變數（Policy Variables）」。

## 未來版本會更新嗎

未來當然有可能推出新版本，但目前沒有官方公告。

如果哪天真的出現新版本，依 AWS 過往做法，舊版本通常仍會保留一段時間，確保既有政策不會立刻失效；只是實務上仍建議優先採用較新的語言版本。


## 參考文件
- [IAM JSON policy elements: Version](https://docs.aws.amazon.com/zh_tw/IAM/latest/UserGuide/reference_policies_elements_version.html)
- [Amazon S3 API 文件](https://docs.aws.amazon.com/zh_tw/AmazonS3/latest/API/Welcome.html)
- [AWS Lambda GetFunction API 文件](https://docs.aws.amazon.com/zh_tw/lambda/latest/api/API_GetFunction.html)
- [Class: AWS.EC2 - JavaScript SDK](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html)