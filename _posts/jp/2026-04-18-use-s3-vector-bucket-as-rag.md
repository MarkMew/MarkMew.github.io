---
layout: post
title: "S3 Vector Bucket 実践: Amazon Nova で最新ランジェリー商品カタログを検索可能なベクトル知識ベースにする"
description: "S3 Vector Bucket 実践: Amazon Nova で最新ランジェリー商品カタログを検索可能なベクトル知識ベースにする"
author: Mark_Mew
categories: [AWS, S3]
tags: [AWS, S3, S3 Vector, RAG]
keywords: [AWS, S3, S3 Vector, RAG]
date: 2026-4-18
---

S3（Simple Storage Service）は、AWS が初期から提供している代表的なサービスの一つです。

ファイル保存だけでなく、

Lifecycle 設定によるデータの階層化や削除、

静的サイトのホスティングにも利用できます。

近年の AI ブームの中で、

AWS は 2025 年に S3 Vector Bucket を公開し、

ベクトルデータの保存先として使えるようになりました。

この記事では、

S3 Vector Bucket を RAG の保存基盤として使い、

低コストな知識検索基盤を実際に作る流れを紹介します。

## RAG とは

### 検索拡張生成（RAG）とは何か
検索拡張生成（RAG）は、LLM の出力品質を改善するためのアプローチです。

回答を生成する前に、

学習済みデータ以外の信頼できる知識ベースを参照できます。

大規模言語モデル（LLM）は大量データで学習され、

数十億規模のパラメータによって、

質問応答、翻訳、文章補完などを行います。

RAG を使うと、既存の強力な LLM に対して、

特定ドメインや組織内の知識を追加でき、

モデルを再学習しなくても精度を改善できます。

コスト効率よく LLM の出力品質を高め、

実運用でも関連性・正確性・有用性を維持しやすくなります。

### なぜ RAG が重要なのか
LLM はかなり成熟していますが、

それでも AI 幻覚（ハルシネーション）は発生します。

この問題を抑えるには、ファインチューニングだけでなく、

既存データを直接インデックス化し、

検索対象を明確に絞る方法も有効です。

## ベクトルデータとは
### ベクトルデータとは何か
従来のデータベースには、

年齢や電話番号のようなスカラー値を保存します。

これらはそのままの値です。

一方で、画像・ドキュメント・音声のような実体ファイルは、

そのまま DB に格納しないことが多いです。

これらをモデルで解析すると、

[0.12, 0.98, -0.45...] のような数値列に変換されます。

この数値は特徴や関係性を表します。

画像であれば、色や質感などの特徴を表現できます。

これがベクトルデータです。

### データベースの種類
#### リレーショナルデータベース
Web アプリや業務システム開発では、

MySQL、PostgreSQL、Oracle、SQL Server がよく使われます。

これらはテーブル列を事前定義し、

列構造は動的に増えにくく、

テーブル間の関係は制約で表現します。

この性質を持つものがリレーショナルデータベースです。

#### 非リレーショナルデータベース
##### インメモリデータベース
Redis や Memcache は、

Web 開発でキャッシュ用途によく使われるインメモリ DB です。

##### グラフデータベース
一般的には Graph Database と呼ばれ、

代表例として Neo4j が挙げられます。

グラフデータベースは画像を保存する意味ではなく、

グラフ構造でデータ間の関係を扱うものです。

リレーショナル DB のように集合演算に頼るのではなく、

ノードとエッジで関係を表現します。

##### 検索系データベース
Solr、ELK、OpenSearch Service は、

検索系データベース（私は検索エンジン DB と呼ぶことが多い）としてよく使われます。

ログ分析だけでなく、

全文検索にも広く利用されます。

リレーショナル DB でも似たことはできますが、

全列インデックスを作ると、

ストレージ消費が大きくなり、

検索性能が落ちることがあります。

検索系 DB はフルフィールド索引を前提に作られており、

スコアリングやあいまい検索も得意です。

条件に合わないものを単純除外するのではなく、

近い結果を返せるのが強みです。

この観点では S3 Vector Bucket より高機能です。

そのためデータ規模が大きくなると、

S3 Vector は主検索基盤ではなくなり、

中継レイヤーとして使い、

最終的には専用検索 DB に載せる構成が現実的です。

## 実装: S3 Vector Bucket を作成してベクトルを書き込む

背景説明はここまでにして、実際に作っていきます。

このセクションは AWS CloudShell を使うため、ローカル環境へのツール導入は不要です。AWS Console にログインすればそのまま実行できます。

> 実装には Bedrock と S3 関連の権限が必要です。事前に必要権限を確認してください。
{: .prompt-warning}

### Step 0: 必要権限を確認する

IAM User の認証情報を使う場合も、SSO で IAM Role にマッピングする場合も、

AWS Bedrock モデルを呼び出す権限と、

S3 Bucket / S3 Vector Bucket を作成・操作する権限が必要です。

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3ImageBucket",
            "Effect": "Allow",
            "Action": [
                "s3:CreateBucket",
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::markmew-bra-image",
                "arn:aws:s3:::markmew-bra-image/*"
            ]
        },
        {
            "Sid": "S3VectorBucket",
            "Effect": "Allow",
            "Action": [
                "s3vectors:CreateVectorBucket",
                "s3vectors:GetIndex",
                "s3vectors:CreateIndex",
                "s3vectors:PutVectors",
                "s3vectors:QueryVectors"
            ],
            "Resource": "*"
        },
        {
            "Sid": "BedrockInvokeModel",
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel"
            ],
            "Resource": "arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-2-multimodal-embeddings-v1:0"
        }
    ]
}
```

> この例で使うモデルは amazon.nova-2-multimodal-embeddings です。
> このモデルは ap-northeast-1 ではまだ利用できません。
> 権限設定時は、利用するモデルが
> 対象リージョンで利用可能かを必ず確認してください。
{: .prompt-info}

### Step 1: S3 Vector Bucket を作成する

AWS Console を開き、右上から **CloudShell** を起動します。

現時点では S3 Vector Bucket は S3 Console の UI ではなく AWS CLI で作成します。次のコマンドを実行します。

```bash
aws s3vectors create-vector-bucket \
  --vector-bucket-name markmew-s3-vector \
  --region ap-northeast-1
```

### Step 2: S3 Bucket を作成する

画像素材を保存するための S3 Bucket を作成します。

この Bucket は素材保存用で、

素材は後段でモデルによりベクトル化され、

Step 1 で作成した S3 Vector Bucket に格納されます。

```bash
aws s3api create-bucket \
  --bucket markmew-bra-image \
  --region ap-northeast-1 \
  --create-bucket-configuration LocationConstraint=ap-northeast-1
```

### Step 3: 素材画像をアップロードする

Bucket 作成後、S3 Console で `markmew-bra-image` を開き、右上の **Upload** をクリックします。

![S3 アップロードボタン](/assets/img/amazon_s3_image_upload.png)

**Add files** を押すか、画像を直接ドラッグして選択します。

![画像選択](/assets/img/amazon_s3_image_choose_images.png)

ファイル一覧を確認して **Upload** を実行し、完了後に画像が Bucket 内に表示されることを確認します。

![アップロード結果](/assets/img/amazon_s3_bra_image_upload_result.png)

### Step 3: Index を作成し、ベクトル書き込みと検索を実行する

Vector Bucket の作成を確認したら、次の Python スクリプトを実行します。Index 作成、S3 画像のベクトル化、ベクトル書き込み、テキスト検索テストまでを順に行います。

```python
import boto3
import base64
import json

# --- 設定 ---
S3_REGION = 'ap-northeast-1'
BEDROCK_REGION = 'us-east-1'  # Nova は us-east-1 でのみ利用可能
S3_VECTORS_REGION = 'ap-northeast-1'

IMAGE_BUCKET_NAME = 'markmew-bra-image'
VECTOR_BUCKET_NAME = 'markmew-s3-vector'
NOVA_INDEX_NAME = 'bra-nova-multimodal-1024-cosine'
EMBEDDING_DIMENSION = 1024

# クライアント作成
s3_client = boto3.client('s3', region_name=S3_REGION)
bedrock_runtime_client = boto3.client('bedrock-runtime', region_name=BEDROCK_REGION)
s3_vectors_client = boto3.client('s3vectors', region_name=S3_VECTORS_REGION)

def create_nova_multimodal_index():
    """Nova マルチモーダルのベクトルインデックスを作成"""
    try:
        s3_vectors_client.get_index(
            vectorBucketName=VECTOR_BUCKET_NAME,
            indexName=NOVA_INDEX_NAME
        )
        print(f"✅ Nova マルチモーダルインデックス {NOVA_INDEX_NAME} は既に存在します")
    except Exception:
        print(f"🚀 Nova マルチモーダルインデックスを作成中...")
        s3_vectors_client.create_index(
            vectorBucketName=VECTOR_BUCKET_NAME,
            indexName=NOVA_INDEX_NAME,
            dimension=EMBEDDING_DIMENSION,
            dataType='float32',
            distanceMetric='cosine'
        )
        print(f"✅ Nova マルチモーダルインデックスの作成が完了しました")

def process_images_with_nova_fixed():
    """修正版の Nova API フォーマットで画像を処理"""
    print("🚀 Amazon Nova Multimodal Embeddings（修正版 API フォーマット）で画像を処理中...")
    
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=IMAGE_BUCKET_NAME)
    
    count = 0
    vectors_batch = []
    
    for page in pages:
        if 'Contents' not in page:
            continue
            
        for obj in page['Contents']:
            key = obj['Key']
            if not key.lower().endswith(('.png', '.jpg', '.jpeg', '.webp')):
                continue
            
            print(f"処理中: {key}")
            
            try:
                # 1. 画像を読み込む
                image_obj = s3_client.get_object(Bucket=IMAGE_BUCKET_NAME, Key=key)
                image_bytes = image_obj['Body'].read()
                
                if len(image_bytes) > 25 * 1024 * 1024:
                    print(f"   ↳ ⚠️  スキップ: 画像サイズが 25MB を超えています")
                    continue
                
                # 2. 正しい Nova API フォーマットを使用
                request_body = {
                    "taskType": "SINGLE_EMBEDDING",
                    "singleEmbeddingParams": {
                        "embeddingPurpose": "GENERIC_INDEX",  # 必須パラメータ
                        "embeddingDimension": EMBEDDING_DIMENSION,
                        "image": {
                            "format": "webp" if key.lower().endswith('.webp') else "jpeg",
                            "source": {
                                "bytes": base64.b64encode(image_bytes).decode('utf-8')
                            }
                        }
                    }
                }
                
                response = bedrock_runtime_client.invoke_model(
                    modelId="amazon.nova-2-multimodal-embeddings-v1:0",
                    body=json.dumps(request_body),
                    contentType="application/json"
                )
                
                response_data = json.loads(response['body'].read())
                vector = response_data['embeddings'][0]['embedding']
                
                # 3. ベクトルデータを準備
                vector_data = {
                    "key": f"nova-{count}",
                    "data": {"float32": vector},
                    "metadata": {
                        's3_uri': f's3://{IMAGE_BUCKET_NAME}/{key}',
                        'original_filename': key,
                        'type': 'nova_multimodal'
                    }
                }
                vectors_batch.append(vector_data)
                
                print(f"   ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-{count})")
                count += 1
                
                # バッチ挿入
                if len(vectors_batch) >= 50:
                    s3_vectors_client.put_vectors(
                        vectorBucketName=VECTOR_BUCKET_NAME,
                        indexName=NOVA_INDEX_NAME,
                        vectors=vectors_batch
                    )
                    print(f"   ↳ 📦 {len(vectors_batch)} 件のベクトルをバッチ挿入しました")
                    vectors_batch = []
                    
            except Exception as e:
                print(f"   ↳ ❌ エラー: {e}")
    
    # 残りのベクトルを処理
    if vectors_batch:
        s3_vectors_client.put_vectors(
            vectorBucketName=VECTOR_BUCKET_NAME,
            indexName=NOVA_INDEX_NAME,
            vectors=vectors_batch
        )
        print(f"📦 最後の {len(vectors_batch)} 件のベクトルを挿入しました")
    
    print(f"\n🎉 Nova の処理が完了しました！合計 {count} 枚の画像を処理しました")

def query_by_text_with_nova_fixed(search_text, top_k=5):
    """修正版の Nova API フォーマットでテキスト検索"""
    try:
        print(f"🔍 Nova でテキスト検索を実行: {search_text}")
        
        # 正しい API フォーマットを使用
        request_body = {
            "taskType": "SINGLE_EMBEDDING",
            "singleEmbeddingParams": {
                "embeddingPurpose": "GENERIC_RETRIEVAL",  # 検索時は RETRIEVAL を使用
                "embeddingDimension": EMBEDDING_DIMENSION,
                "text": {
                    "truncationMode": "END",
                    "value": search_text
                }
            }
        }
        
        response = bedrock_runtime_client.invoke_model(
            modelId="amazon.nova-2-multimodal-embeddings-v1:0",
            body=json.dumps(request_body),
            contentType="application/json"
        )
        
        response_data = json.loads(response['body'].read())
        query_vector = response_data['embeddings'][0]['embedding']
        
        # 検索
        search_response = s3_vectors_client.query_vectors(
            vectorBucketName=VECTOR_BUCKET_NAME,
            indexName=NOVA_INDEX_NAME,
            queryVector={"float32": query_vector},
            topK=top_k,
            returnDistance=True,
            returnMetadata=True
        )
        
        print(f"📊 Nova テキスト検索結果:")
        print("-" * 80)
        
        for i, result in enumerate(search_response['vectors']):
            distance = result.get('distance', 0)
            similarity = (1 - distance) * 100
            s3_uri = result['metadata'].get('s3_uri', 'N/A')
            filename = result['metadata'].get('original_filename', 'N/A')
            
            print(f"{i+1:2d}. 類似度: {similarity:6.2f}%")
            print(f"     ファイル: {filename}")
            print(f"     場所: {s3_uri}")
            print()
            
        return search_response
        
    except Exception as e:
        print(f"❌ Nova テキスト検索に失敗: {e}")
        return None

def query_by_image_with_nova_fixed(image_key, top_k=5):
    """修正版の Nova API フォーマットで画像検索"""
    try:
        print(f"🔍 Nova で画像検索を実行: {image_key}")
        
        # 画像を読み込む
        image_obj = s3_client.get_object(Bucket=IMAGE_BUCKET_NAME, Key=image_key)
        image_bytes = image_obj['Body'].read()
        
        # 正しい API フォーマットを使用
        request_body = {
            "taskType": "SINGLE_EMBEDDING",
            "singleEmbeddingParams": {
                "embeddingPurpose": "GENERIC_RETRIEVAL",  # 検索時は RETRIEVAL を使用
                "embeddingDimension": EMBEDDING_DIMENSION,
                "image": {
                    "format": "webp" if image_key.lower().endswith('.webp') else "jpeg",
                    "source": {
                        "bytes": base64.b64encode(image_bytes).decode('utf-8')
                    }
                }
            }
        }
        
        response = bedrock_runtime_client.invoke_model(
            modelId="amazon.nova-2-multimodal-embeddings-v1:0",
            body=json.dumps(request_body),
            contentType="application/json"
        )
        
        response_data = json.loads(response['body'].read())
        query_vector = response_data['embeddings'][0]['embedding']
        
        # 類似画像を検索
        search_response = s3_vectors_client.query_vectors(
            vectorBucketName=VECTOR_BUCKET_NAME,
            indexName=NOVA_INDEX_NAME,
            queryVector={"float32": query_vector},
            topK=top_k,
            returnDistance=True,
            returnMetadata=True
        )
        
        print(f"📊 Nova 画像検索結果:")
        print("-" * 80)
        
        for i, result in enumerate(search_response['vectors']):
            distance = result.get('distance', 0)
            similarity = (1 - distance) * 100
            s3_uri = result['metadata'].get('s3_uri', 'N/A')
            filename = result['metadata'].get('original_filename', 'N/A')
            
            print(f"{i+1:2d}. 類似度: {similarity:6.2f}%")
            print(f"     ファイル: {filename}")
            print(f"     場所: {s3_uri}")
            print()
            
        return search_response
        
    except Exception as e:
        print(f"❌ Nova 画像検索に失敗: {e}")
        return None

if __name__ == "__main__":
    print("🚀 修正版の Nova Multimodal Embeddings API を使用")
    print("=" * 70)
    
    # 1. インデックス作成
    create_nova_multimodal_index()
    
    print("\n" + "=" * 70)
    
    # 2. 画像処理
    process_images_with_nova_fixed()
    
    print("\n" + "=" * 70)
    
    # 3. テキスト検索テスト
    print("🔍 Nova テキスト検索をテスト:")
    
    test_queries = [
        "紫のランジェリー",
        "レースブラ",
        "クリーム色のランジェリー",
        "補整ブラ"
    ]
    
    for query in test_queries:
        print(f"\n--- 検索: {query} ---")
        query_by_text_with_nova_fixed(query, top_k=3)
    
    print("\n" + "=" * 70)
    
    # 4. 画像検索テスト（任意）
    # print("🔍 Nova 画像検索をテスト:")
    # query_by_image_with_nova_fixed("your-image-file.webp", top_k=3)
```

スクリプト実行後、

各画像の実行結果をはっきり確認できます。

`紫のランジェリー` というキーワードを例にすると、

検索結果は確かに紫色フォルダ内の商品を返し、

クリーム色フォルダの商品ではないことが分かります。

素材数は多くありませんが、

結果としては十分妥当だと言えます。

```bash
~ $ python query_similar_images.py 
/usr/local/lib/python3.9/site-packages/boto3/compat.py:89: PythonDeprecationWarning: Boto3 will no longer support Python 3.9 starting April 29, 2026. To continue receiving service updates, bug fixes, and security updates please upgrade to Python 3.10 or later. More information can be found here: https://aws.amazon.com/blogs/developer/python-support-policy-updates-for-aws-sdks-and-tools/
  warnings.warn(warning, PythonDeprecationWarning)
🚀 修正版の Nova Multimodal Embeddings API を使用
======================================================================
✅ Nova マルチモーダルインデックス bra-nova-multimodal-1024-cosine は既に存在します

======================================================================
🚀 Amazon Nova Multimodal Embeddings（修正版 API フォーマット）で画像を処理中...
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_1.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-0)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_10.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-1)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_2.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-2)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_3.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-3)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_4.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-4)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_5.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-5)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_6.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-6)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_7.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-7)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_8.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-8)
処理中: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_9.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-9)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_1.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-10)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_10.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-11)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_2.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-12)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_3.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-13)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_4.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-14)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_5.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-15)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_6.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-16)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_7.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-17)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_8.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-18)
処理中: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp
    ↳ ✅ Nova ベクトルの生成に成功 (ID: nova-19)
📦 最後の 20 件のベクトルを挿入しました

🎉 Nova の処理が完了しました！合計 20 枚の画像を処理しました

======================================================================
🔍 Nova テキスト検索をテスト:

--- 検索: 紫のランジェリー ---
🔍 Nova でテキスト検索を実行: 紫のランジェリー
📊 Nova テキスト検索結果:
--------------------------------------------------------------------------------
 1. 類似度:  40.29%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_8.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_8.webp

 2. 類似度:  38.02%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp

 3. 類似度:  34.87%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_4.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_4.webp


--- 検索: レースブラ ---
🔍 Nova でテキスト検索を実行: レースブラ
📊 Nova テキスト検索結果:
--------------------------------------------------------------------------------
 1. 類似度:  41.13%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp

 2. 類似度:  39.92%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_1.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_1.webp

 3. 類似度:  39.53%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_4.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_4.webp


--- 検索: クリーム色のランジェリー ---
🔍 Nova でテキスト検索を実行: クリーム色のランジェリー
📊 Nova テキスト検索結果:
--------------------------------------------------------------------------------
 1. 類似度:  46.78%
     ファイル: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_7.webp
     場所: s3://markmew-bra-image/【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_7.webp

 2. 類似度:  46.66%
     ファイル: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_4.webp
     場所: s3://markmew-bra-image/【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_4.webp

 3. 類似度:  45.41%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp


--- 検索: 補整ブラ ---
🔍 Nova でテキスト検索を実行: 補整ブラ
📊 Nova テキスト検索結果:
--------------------------------------------------------------------------------
 1. 類似度:  54.27%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_10.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_10.webp

 2. 類似度:  53.83%
     ファイル: 【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp
     場所: s3://markmew-bra-image/【思薇爾】美波曲線系列B-D罩調整型蕾絲集中包覆塑身女內衣(羅蘭紫)/3860x_9.webp

 3. 類似度:  52.88%
     ファイル: 【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_9.webp
     場所: s3://markmew-bra-image/【思薇爾】撩波巴黎之春系列B-E罩涼感蕾絲集中包覆女內衣(奶油色)/3860x_9.webp


======================================================================
```

## まとめ

S3 Vector Bucket は、AI 時代に AWS が提供した軽量なベクトル保存オプションです。

小規模で素早く検証したいケースでは、

Pinecone、Weaviate、OpenSearch のような追加基盤を運用せずに、

画像アップロードからベクトル書き込み、類似検索までを S3 エコシステム内で完結できます。

一方で、本文前半でも触れた通り、

S3 Vector Bucket は現時点で全文索引や高度なスコアリングなどの機能を持ちません。

データ量の増加や検索要件の高度化に伴って、

専用ベクトル DB への移行は自然な選択になります。

そのため、S3 Vector Bucket は PoC や低トラフィック用途の中継レイヤーとして位置付けるのが実践的です。

---

参考リンク:
1. [What is RAG (Retrieval-Augmented Generation)?](https://aws.amazon.com/tw/what-is/retrieval-augmented-generation/)
2. [What is a vector database?](https://aws.amazon.com/tw/what-is/vector-databases/)
3. [什麼是向量資料庫？向量資料庫運作、應用、趨勢懶人包！](https://www.omniwaresoft.com.tw/product-news/vector-database-usecase/what-is-vector-database/)
