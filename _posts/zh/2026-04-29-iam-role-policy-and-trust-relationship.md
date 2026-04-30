---
layout: post
title: "深入淺出 AWS IAM Role 的權限設計"
description: "拆解 IAM Role 中的 Policy 和 Trust Relationship 的權責分工"
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Role]
keywords: [AWS, IAM, IAM Role]
date: 2026-4-29
---

初學雲端的使用者，

肯定對於 IAM 又愛又恨，

逐步了解 AWS 的每項功能後，

就開始學習官方建議的最佳實踐，

儘量以角色也就是 IAM Role 的方式來執行，

實際上花一些時間了解 IAM Role 的箇中奧妙後，

確實會發現這是個獨具巧思的設計。

## 傳統 Web 中的權限管理

在傳統 Web 系統裡，權限通常可以拆成兩件事：

1. 你是誰（Authentication）
2. 你能做什麼（Authorization）

舉例來說，當使用者登入後，系統會先確認這個人是誰，通常在資料庫中會對應到 `Account`。

小型系統會將 `Account` 和 `Permission` 做對應，

有點規模的系統可能會設計角色 `Role`，

`Account` 可以綁定到多個 `Role`，

而每個 `Role` 可以綁定到不同 `Permission`，

把這個概念放到 AWS，其實也一樣，只是角色換成了 AWS 的身份系統。

## IAM

在 AWS 中，IAM Role 可以把「誰可以拿到這個身份」和「拿到之後可以做什麼」拆開來管理。

這個拆分，正是 IAM Role 設計最漂亮的地方。

1. Trust Relationship：定義誰可以 Assume 這個 Role
2. Policy：定義這個 Role 能對哪些資源做哪些操作

也就是說，

Trust Relationship 是入口規則，

Policy 是進來之後的行為規則。

### Trust Relationship

Trust Relationship 的重點不是權限本身，而是「誰有資格扮演這個角色」。

如果把 IAM Role 想成公司裡的某個職位，那 Trust Relationship 就是在決定「哪些人可以被任命到這個職位」。

例如，以下這份信任政策表示：只有 EC2 服務可以 Assume 這個 Role。

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

如果你的場景是 EKS IRSA、GitHub Actions OIDC，或跨帳號存取，`Principal` 就會換成 Federated Provider 或其他 AWS Account，但核心觀念不變：

先決定誰可以拿到這個 Role。

### Policy

Policy 才是大家最常說的「權限」。

它描述的是：當某個實體已經成功 Assume Role 之後，到底能做什麼事。

例如下面這份政策，只允許讀取指定 S3 bucket 底下的物件：

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

這裡最常見的誤解是：

把 Trust Relationship 寫得很嚴格，就以為權限一定安全。

事實上如果 Policy 給得過大（例如 `Action: *` + `Resource: *`），只要有人能 Assume 進來，風險依然很高。

反過來也一樣，Policy 再精準，如果 Trust Relationship 設太寬（例如讓不該進來的 Principal 也能 Assume），也會有問題。

## IAM Role 設計時，建議先問的 4 個問題

實務上我會先問這四題，再開始寫 JSON：

1. 誰需要拿這個 Role？
2. 這個身份在什麼條件下可以 Assume Role？
3. Assume 後最小需要哪些 Action 與 Resource？
4. 哪些操作一定不該被允許？

這樣做的好處是，你可以把「身份入口」和「權限範圍」分開收斂，避免一開始就把所有權限打包成萬用角色。

## 一個完整心智模型

把 IAM Role 想成一扇有兩道鎖的門會比較好記：

1. 第一把鎖是 Trust Relationship：你有沒有資格進門
2. 第二把鎖是 Policy：進門後你能走到哪些區域

只有兩把鎖都設計正確，權限模型才會真正安全又可維護。

## 小結

IAM Role 之所以好用，不只是因為它可以取代長期 Access Key，更重要的是它把權限模型拆成兩個清楚的維度。

當你把 Trust Relationship 和 Policy 的責任分工想清楚後，無論是 EC2、Lambda、EKS IRSA，還是跨帳號授權，設計都會更有一致性。

最後用一句話總結：

先定義誰可以扮演角色，再定義角色可以做什麼。

這就是 IAM Role 權限設計的核心。