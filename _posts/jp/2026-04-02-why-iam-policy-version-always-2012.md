---
layout: post
title: "AWS豆知識: IAM Policy の Version がいつも 2012-10-17 なのはなぜか"
description: "AWS IAM Policy の Version がなぜ 2012-10-17 なのかを解説します。Version の意味、各 AWS サービスの API バージョンとの違い、Version を省略した場合の挙動までまとめて確認できます。"
author: Mark_Mew
categories: [AWS]
tags: [AWS, IAM, IAM Policy, Policy Variables]
keywords: [AWS IAM Policy Version, 2012-10-17, IAM Policy Variables, IAM JSON Policy, AWS Security]
date: 2026-4-2
---

AWS を使っていると、IAM Policy の `Version` に `2012-10-17` が指定されているのをよく見かけます。

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

初めて見ると、次のような疑問を持つ人も多いと思います。

- なぜいつもこの日付なのか
- AWS は更新され続けているのに、なぜ Version は変わらないのか

この記事では、この日付が何を意味しているのかを、よくある疑問に沿って整理していきます。

## IAM Policy の Version が 2012-10-17 なのはなぜか

結論から言うと、`2012-10-17` は IAM Policy Language のバージョンです。AWS の全サービスで共通して使われる API バージョンではありません。

AWS の API バージョンはサービスごとに異なります。たとえば、次のようなものがあります。

- Amazon S3: `2006-03-01`
  [Amazon S3 API リファレンス](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- AWS Lambda: `2015-03-31`
  [AWS Lambda GetFunction API リファレンス](https://docs.aws.amazon.com/lambda/latest/api/API_GetFunction.html)
  ```
  GET /2015-03-31/functions/FunctionName?Qualifier=Qualifier HTTP/1.1
  ```

- Amazon EC2: `2016-11-15`
  ```
  API Version: 2016-11-15
  ```
  [Class: AWS.EC2 - JavaScript SDK](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html)

つまり、IAM Policy でよく使われる Version は `2012-10-17` ですが、AWS の API がすべて同じバージョンという意味ではありません。

## なぜ 2012-10-17 という日付なのか

もっともよく知られている説明は、`2012-10-17` が IAM Policy Language の大きなアップデートを示す日付だ、というものです。

このバージョンでは `${aws:username}` や `${aws:PrincipalTag}` のような Policy Variables が導入され、1 つのポリシーを多くのユーザーやロールに対して柔軟に使い回しやすくなりました。

そのため、IAM Policy では `2012-10-17` が事実上の標準として広く使われています。

## Version を書かないとどうなるか

`Version` を省略すると、AWS は古い `2008-10-17` のルールでポリシーを解釈します。

その場合、`${aws:username}` のような文字列は変数として解釈されず、ただの文字列として扱われることがあります。

## どこで `2008-10-17` をまだ見かけるのか

2012 年以前に作成され、その後あまり手が入っていない AWS アカウントでは、Version フィールドを持たない Inline Policy が今でも多く残っていることがあります。

公式には、JSON ポリシードキュメントで `Version` を完全に省略した場合、IAM は `2008-10-17` の解釈ルールを使います。

そのため、表からは見えにくいものの、2008 世代のポリシーが今もそのまま使われているケースがあります。

また、AWS Console で一部のリソース向けアクセスポリシーを作成すると、自動生成される JSON テンプレートが `2008-10-17` を初期値にしていることがあります。これは `2012-10-17` が使えないからではなく、既存システムや API との互換性を優先しているためです。

- SQS Queue Policies: SQS コンソールで「ポリシーを編集」を開くと、初期テンプレートが `2008-10-17` のままになっていることがあります。
- SNS Topic Policies: SQS と同じく、SNS の既定ポリシー JSON でも 2008 形式が表示されることがあります。
- VPC Endpoint Policies (Gateway タイプのみ): S3 や DynamoDB 向けの Gateway Endpoint では、既定ポリシーが 2008 と記載されることがあります。

## なぜこれらの古い Version は自動的に更新されないのか

これは、サービス側 API の設計、たとえば SQS の `SetQueueAttributes` などと関係しています。

- API 互換性: 多くの Resource Policy は IAM API ではなく、各サービスの API 経由で管理されます。古くからある API との互換性を壊さないために、AWS は既定値をあえて維持しています。
- 求められる要件が比較的シンプル: SQS や SNS では、多くの場合、特定の ARN に対して Allow または Deny を設定できれば十分で、2012 版の高度な変数機能が必須とは限りません。

## 将来 Version は更新されるか

今後新しいバージョンが出る可能性はありますが、現時点では公式な発表はありません。

仮に新バージョンが登場しても、AWS は通常、既存との互換性を保つために旧バージョンをしばらく残します。実運用では、可能な範囲で新しいバージョンを使うのがよいでしょう。

## 参考資料
- [IAM JSON policy elements: Version](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_version.html)
- [Amazon S3 API リファレンス](https://docs.aws.amazon.com/AmazonS3/latest/API/Welcome.html)
- [AWS Lambda GetFunction API リファレンス](https://docs.aws.amazon.com/lambda/latest/api/API_GetFunction.html)
- [Class: AWS.EC2 - JavaScript SDK](https://docs.aws.amazon.com/AWSJavaScriptSDK/latest/AWS/EC2.html)
