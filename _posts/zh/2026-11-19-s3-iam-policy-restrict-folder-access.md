---
layout: post
title: "S3 IAM Policy 限制只能存取特定資料夾：s3:prefix 與 s3:delimiter 設定教學"
description: "示範如何用 IAM Policy 讓使用者只能存取 S3 Bucket 中的特定資料夾，說明 s3:prefix、s3:delimiter 與 Null 條件的寫法，並比較常見的錯誤範例，讓 WinSCP、S3 Browser 等 Client 工具也能正常瀏覽。"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, IAM]
keywords: [S3 IAM Policy, S3 資料夾權限, S3 prefix 權限, s3:prefix, s3:delimiter, s3:ListBucket, AccessDenied]
lang: zh-TW
date: 2026-11-19
---

之前的文章有寫過 [Amazon S3 跨 AWS 帳號存取](/posts/s3-cross-account-access-iam-bucket-policy/)，不過實務上有個需求會比跨 AWS Account 存取更常見：**多個使用者或系統共用同一個 Bucket，但各自只能存取被授權的資料夾。**

無論是透過 IAM User Credentials（Access Key ID 與 Secret Access Key），還是 IAM Role 存取，權限都是由附加在該身分上的 IAM Policy 決定，因此本文的 Policy 兩種方式都適用。

**要把權限限制在特定資料夾，物件操作（`GetObject`、`PutObject`）只要把路徑寫進 Resource 即可；真正容易寫錯的是 `s3:ListBucket`。** 它的 Resource 是 Bucket 本身，只能透過 `s3:prefix` 與 `s3:delimiter` 條件限制可以列出的範圍。這篇會用一個實際踩過的錯誤範例，說明各個條件該怎麼寫。

## 本文範例

| 項目 | 範例值 |
|---|---|
| Bucket | `markmew-test-bucket` |
| 允許存取的資料夾 | `foo/bar/` |
| 允許的操作 | 在 `foo/bar/` 底下列出、下載、上傳、刪除檔案 |
| 存取方式 | AWS CLI，或 WinSCP、S3 Browser 等 Client 工具 |

S3 其實沒有真正的資料夾，`foo/bar/report.csv` 只是一個 Object Key，Console 與 Client 工具是依照 `/` 把它顯示成資料夾。因此「限制資料夾」在 Policy 裡其實是「限制 Key 的 Prefix」。

## 先了解 Client 工具會呼叫哪些 API

使用者從 Client 工具點進 `foo/bar/` 的過程，大致會發出以下請求：

| 使用者動作 | API | 需要的權限 | 條件內容 |
|---|---|---|---|
| 列出帳號中的 Buckets | `ListBuckets` | `s3:ListAllMyBuckets` | 無 |
| 取得 Bucket 所在 Region | `GetBucketLocation` | `s3:GetBucketLocation` | 無 |
| 開啟 Bucket 根目錄 | `ListObjectsV2` | `s3:ListBucket` | prefix 為空或不帶，delimiter 為 `/` |
| 點進 `foo/` | `ListObjectsV2` | `s3:ListBucket` | prefix 為 `foo/`，delimiter 為 `/` |
| 點進 `foo/bar/` | `ListObjectsV2` | `s3:ListBucket` | prefix 為 `foo/bar/` |
| 下載、上傳、刪除檔案 | `GetObject` 等 | `s3:GetObject` 等 | Resource 為 `foo/bar/*` |

如果是透過 Client 端工具存取，而不是直接用 API 存取特定路徑，那 `s3:ListAllMyBuckets` 的權限通常是必要的。雖然使用者可能會因此看到其他 S3 Bucket 的名稱，不過對 AWS Account 來說，Bucket 清單就是第一層路徑；沒有這個權限，會導致 Client 端可以連上，但畫面沒有權限顯示任何內容。

```json
{
    "Action": [
        "s3:ListAllMyBuckets"
    ],
    "Effect": "Allow",
    "Resource": "*"
}
```

> `s3:ListAllMyBuckets` 只能看到 Bucket 名稱，無法看到 Bucket 內容。如果工具可以直接設定目標 Bucket 與遠端路徑（例如 WinSCP 的預設遠端目錄設為 `/markmew-test-bucket/foo/bar/`），就可以省略這個權限。
{: .prompt-tip }

## 錯誤範例：先全部 Allow，再用 Deny 排除

一開始我參考網路上的寫法，先允許整個 Bucket 的 `s3:ListBucket`，再用 `Deny` 加上 `StringNotLike` 排除其他資料夾：

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

這份 Policy 看起來有限制，實際上有幾個問題：

1. **`HomeDirObjectAccess` 開放了整個 Bucket 的讀取權限。** Resource 是 `markmew-test-bucket/*`，只要知道 Object Key，就能下載任何資料夾的檔案。列表限制只是「看不到」，不等於「拿不到」。
2. **`foo/*` 讓其他子資料夾也能被列出。** Deny 的例外清單包含 `foo/*`，代表 `foo/other/`、`foo/secret/` 都不會被拒絕，使用者可以看到其他資料夾裡的檔案名稱。
3. **空字串 `""` 沒有限制 delimiter。** 不帶 delimiter、prefix 為空的請求（例如 `aws s3 ls s3://markmew-test-bucket --recursive`）會列出整個 Bucket 的所有 Object Key。
4. **Client 不帶 prefix 參數時會被 Deny。** 有些 Client 開啟 Bucket 根目錄時，請求中完全沒有 prefix 參數。對 `StringNotLike` 這類否定運算子來說，**Key 不存在時條件會被視為成立**，因此請求會被明確拒絕，Client 便無法打開 Bucket。[IAM 條件運算子說明](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_elements_condition_operators.html)
5. **明確的 Deny 會蓋過所有 Allow。** 日後如果有其他 Policy 想額外開放某個資料夾，也會被這條 Deny 擋下，排查時不容易看出原因。

## 正確範例：只 Allow 需要的 prefix

比較好的做法是不要先全部開放，而是**依照 Client 實際會發出的請求，逐一 Allow 需要的 prefix 與 delimiter 組合**：

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

### 每個 Statement 的用途

| Sid | 允許的請求 | 為什麼需要 |
|---|---|---|
| `ListAllBucketsForClient` | 列出 Bucket 清單 | Client 工具的第一層畫面 |
| `GetBucketLocation` | 查詢 Bucket Region | Client 與 Console 需要知道要連到哪個 Region |
| `ListBucketRootWithoutPrefix` | 不帶 prefix、delimiter 為 `/` 的列表 | 處理開啟根目錄時完全不帶 prefix 參數的 Client |
| `ListParentFoldersTopLevelOnly` | 根目錄、`foo/` 這幾層的「單層」列表 | 讓使用者能一路點進 `foo/bar/`，但只看得到資料夾名稱 |
| `ListTargetFolder` | `foo/bar/` 底下任意列表 | 目標資料夾內可以自由瀏覽，也允許遞迴列出 |
| `TargetFolderObjectAccess` | 下載、上傳、刪除 `foo/bar/` 內的檔案 | 物件操作直接用 Resource 限制路徑 |

### 為什麼上層資料夾要限制 `s3:delimiter`？

`ListObjectsV2` 帶 `delimiter=/` 時，S3 只會回傳「這一層」的檔案與子資料夾名稱（CommonPrefixes），不會往下展開。因此使用者在根目錄只會看到 `foo/`，在 `foo/` 只會看到 `bar/` 與其他同層資料夾的名稱，看不到其他資料夾裡的檔案。

如果不限制 delimiter，prefix 為 `foo/` 的請求就能遞迴列出 `foo/` 底下所有 Object Key，包含 `foo/other/` 的內容，等於繞過了資料夾限制。

同樣的道理，`foo/bar`（沒有結尾的 `/`）也放在需要 delimiter 的 Statement：prefix `foo/bar` 也會比對到 `foo/barbaz/` 這類名稱相近的資料夾，不限制 delimiter 就可能列出不該看到的檔案。

> 上層資料夾的單層列表仍然會顯示同一層的資料夾名稱，以及直接放在 `foo/` 底下的檔案名稱，但無法下載。如果連名稱都不能曝光，可以讓使用者直接連到 `/markmew-test-bucket/foo/bar/`，並移除 `ListBucketRootWithoutPrefix` 與 `ListParentFoldersTopLevelOnly` 兩個 Statement。
{: .prompt-warning }

### 為什麼目標資料夾用 `StringLike`？

`foo/bar/*` 的 `*` 可以比對零個或多個字元，所以同時涵蓋 `foo/bar/` 本身與底下任意深度的 prefix，而且不限制 delimiter，`aws s3 ls --recursive` 或 `aws s3 sync` 這類需要遞迴列出的操作也能使用。

### 為什麼移除了 ACL 相關權限？

新建立的 Bucket 預設為 `Bucket owner enforced`，ACL 已經停用，`s3:GetObjectAcl`、`s3:PutObjectAcl` 不會有作用。若是仍啟用 ACL 的舊 Bucket，且 Client 會讀寫 ACL，再依需求加回即可。[S3 Object Ownership 官方說明](https://docs.aws.amazon.com/AmazonS3/latest/userguide/about-object-ownership.html)

## 使用 AWS CLI 驗證

設定完成後，可以用 AWS CLI 確認允許與拒絕的範圍是否符合預期：

```bash
# 允許：列出根目錄，只看得到 foo/
aws s3 ls s3://markmew-test-bucket/

# 允許：列出 foo/ 這一層
aws s3 ls s3://markmew-test-bucket/foo/

# 允許：列出、遞迴列出目標資料夾
aws s3 ls s3://markmew-test-bucket/foo/bar/
aws s3 ls s3://markmew-test-bucket/foo/bar/ --recursive

# 允許：上傳、下載、刪除目標資料夾內的檔案
aws s3 cp ./test.txt s3://markmew-test-bucket/foo/bar/test.txt
aws s3 cp s3://markmew-test-bucket/foo/bar/test.txt ./download.txt
aws s3 rm s3://markmew-test-bucket/foo/bar/test.txt
```

以下操作都應該回傳 `AccessDenied`：

```bash
# 拒絕：遞迴列出整個 Bucket
aws s3 ls s3://markmew-test-bucket --recursive

# 拒絕：列出其他資料夾
aws s3 ls s3://markmew-test-bucket/foo/other/

# 拒絕：上傳到目標資料夾以外的位置
aws s3 cp ./test.txt s3://markmew-test-bucket/foo/test.txt

# 拒絕：下載其他資料夾的檔案
aws s3 cp s3://markmew-test-bucket/foo/other/secret.txt ./secret.txt
```

## 常見問題

### 可以讓每個使用者只存取自己的資料夾嗎？

可以，使用 Policy 變數 `${aws:username}` 取代固定路徑，例如把 Resource 寫成 `arn:aws:s3:::markmew-test-bucket/home/${aws:username}/*`，所有 IAM User 就能共用同一份 Policy。這個變數只適用於 IAM User；IAM Role 可改用 Session Tags 搭配 `${aws:PrincipalTag/...}`。[IAM Policy 變數說明](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_variables.html)

在 Terraform 的字串中，`${...}` 會被當成插值語法，需要寫成 `$${aws:username}` 跳脫。

### Bucket 使用 SSE-KMS 加密時還需要什麼權限？

如果 Bucket 使用客戶管理的 KMS Key 加密，除了 S3 權限之外，下載需要 `kms:Decrypt`，上傳需要 `kms:GenerateDataKey`，且 KMS Key Policy 也必須允許該身分使用。使用 SSE-S3 或 AWS 管理的 `aws/s3` Key 則不需要額外設定。

### Console 有些頁籤顯示權限不足，正常嗎？

正常。本文的 Policy 足以在 Console 一路點進 `foo/bar/` 並操作檔案，但 Console 的 Bucket 屬性、權限等頁籤會呼叫其他 API（例如 `GetBucketPolicyStatus`、`GetBucketVersioning`），沒有授權時會顯示錯誤訊息，不影響檔案操作。

### 只透過程式存取，也需要這麼多 ListBucket 條件嗎？

不需要。如果應用程式知道完整的 Object Key，只需要 `TargetFolderObjectAccess`；需要列出檔案時，再加上 `ListTargetFolder` 即可。上層資料夾的列表權限是為了讓 Client 工具與 Console 能一層一層點進去。

## 延伸閱讀

- [Amazon S3 跨 AWS 帳號存取教學：Bucket Policy 與 IAM 權限設定](/posts/s3-cross-account-access-iam-bucket-policy/)
- [將檔案上傳到 S3 的 5 種方法：Console、CLI、API、SFTP 與 Presigned URL](/posts/upload-files-to-amazon-s3/)
- [深入淺出 AWS IAM Role 的權限設計](/posts/iam-role-policy-and-trust-relationship/)
- [AWS 官方範例：Amazon S3 Bucket Policy 範例](https://docs.aws.amazon.com/AmazonS3/latest/userguide/example-bucket-policies.html)
