---
layout: post
title: EC2 上のコンテナが IAM Instance Profile Role 経由で必要な権限を取得できない
description: "EC2 上のコンテナでインスタンスプロファイルの認証情報を取得できない場合に、IMDSv2 のトークン取得とメタデータ応答のホップ制限を確認する。"
author: Mark_Mew
category: AWS
tags: [AWS, EC2]
date: 2026-3-11
last_modified_at: 2026-11-05
lang: ja
---

EC2 上で AWS リソースを操作する場合、

ベストプラクティスは IAM Instance Profile Role をアタッチし、最小権限で運用することです。

EC2 は Instance Metadata Service（IMDS）を通じて、インスタンスプロファイルの一時認証情報を提供します。IMDSv2 が必須の場合、先にトークンを取得してからメタデータをリクエストします。

```bash
TOKEN=$(curl -fsS -X PUT http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')
curl -fsS -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/
```

正常なら次のように表示されます。

```
<IAM Profile Name>
```

ただし、IMDSv2 を必須にすると、

EC2 内のコンテナが認証情報を取得できなくなることがあります。

EC2 インスタンス詳細 -> `Actions` -> `Instance settings` -> `Modify instance metadata options`

従来 IMDSv2 は Optional で運用されることが多かったですが、

現在は AWS が Required を推奨しています。

この変更は、アプリケーションの脆弱性悪用による

インスタンス認証情報やメタデータの窃取を防ぐためです。

> EC2 インスタンス内では、以下のローカル URL から多くの情報を取得できます。
> ```
> http://169.254.169.254/latest/meta-data/
> ```
> 例えば次の情報です。
> * instance ID
> * IAM role credentials
> * security groups
> * AMI ID
> * hostname
> * region
> これらの情報は、AWS SDK などが IAM の一時認証情報を自動取得する際にも利用されます。
{: .prompt-info}

初期の IMDSv1 は、単純なリクエストだけでメタデータを取得できました。

IMDSv2 ではセッショントークン方式が追加され、

先にトークン取得、その後メタデータ取得、という流れになります。

では、推奨どおり Required にした場合、

Optional に戻す以外に手段はないのでしょうか？

実際には、EC2 上で Docker を動かす場合に他の要因もあります。

1. IMDSv2 はトークン必須だが、利用ツールが IMDSv1 しか対応していない

   IMDSv2 の流れ：
   1) PUT で token を取得
   2) token を使って metadata を GET
   一部の古いツール（または古い SDK）は IMDSv1 のみ対応です。例：
   - 古い AWS CLI
   - 古い SDK
   - 一部の CI イメージ
   この場合、token が無いため `401 Unauthorized` になります。

2. hop limit の問題

    EC2 metadata には次の設定があります：
    ```
    HttpPutResponseHopLimit
    ```
    デフォルトは通常：
    ```
    1
    ```

    ただし Docker コンテナから metadata までには、実際には 1 hop 余分に発生します：
    ```
    container
        ↓
    docker bridge
        ↓
    EC2 instance network
        ↓
    169.254.169.254
    ```

    そのため hop=1 だと token 応答がコンテナに戻れません。

    結果として、次のようなエラーになります：
    ```
    IMDSv2 token request timeout
    ```

    これは CI Runner で非常によくある原因です。

    対策は hop limit を上げることです。

    例えば：
    ```bash
    aws ec2 modify-instance-metadata-options \
        --instance-id i-xxxx \
        --http-put-response-hop-limit 2
    ```

3. Docker network policy / iptables

    hop limit を確認してもトークンを取得できない場合は、コンテナのネットワーク設定と `169.254.169.254` への通信を遮断するルールを確認します。

---

私がこの問題に遭遇したのは、

EC2 上に GitLab CI Runner を構築したときでした。

Pipeline 内のコンテナ通信経路は次の通りです：

```
container
   ↓
docker bridge (docker0)
   ↓
host network
   ↓
IMDS
```

token 応答の戻り経路は：

```
IMDS
 ↓
host network
 ↓
docker bridge
 ↓
container
```

実際の hop 数は次のようになります：
```
2 hops
```

もし：
```
HttpPutResponseHopLimit = 1
```

ならパケットが破棄されます。

その結果、コンテナ側では通常次のように見えます：

```
IMDS token request timeout
```

または

```
no credentials found
```

解決策は 1 つではありません：

1. IMDSv2 は必須のままにし、コンテナからメタデータが必要な場合は応答の hop limit を `2` に設定します。コンテナ内からトークンを取得できるか確認してください。
2. `169.254.169.254` への到達性と AWS SDK の IMDSv2 対応を確認します。トークンを取得できても認証に失敗する場合は、インスタンスプロファイルと IAM 権限を別に調べます。
3. ホストのインスタンスプロファイルを共有すべきでないワークロードでは、環境に適した短期認証情報を使います。長期 IAM ユーザーキーを環境変数へ入れる方法は避けてください。


参考資料
---
1. [IAM roles for Amazon EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)

2. [Configure instance metadata options for new instances](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-new-instances.html)
