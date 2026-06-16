---
layout: post
title: "オブザーバビリティ導入はどこから始めればよいのか"
description: "Logs、Metrics、Traces から、オブザーバビリティを導入するときの実践的な進め方と注意点を整理します。"
author: Mark_Mew
categories: [Observability]
tags: [DevOps, Observability]
keywords: [DevOps, Observability, オブザーバビリティ, ログ, メトリクス, トレース]
lang: ja
date: 2026-06-17
---

数年前は DevOps や SRE という言葉をよく聞きました。

ここ数年は Platform Engineering という言葉もよく聞くようになりました。

こうした話題は、最終的に DevOps エンジニアや会社のインフラチームに降りてくることが多いです。

Observability、つまりオブザーバビリティも、すでにしばらく議論されているテーマです。

これは単なる buzzword なのでしょうか。

会社や部署として導入すべきなのでしょうか。

みんなが Observability について話しているとき、

結局どこから始めればよいのでしょうか。

そして、会社にどう導入していけばよいのでしょうか。

今回も、複雑な理論から入るのではなく、

実務の観点から、

オブザーバビリティを導入するための道筋を整理してみます。

## まずは 3 本柱から

オブザーバビリティでよく出てくる 3 本柱は次のとおりです。

- `ログ（logs）`
- `メトリクス（metrics）`
- `トレース（traces）`

もう少し直感的に言うと、

ログは「何が起きたのか」を知るためのものです。

メトリクスは「状態が悪くなっていないか」を見るためのものです。

トレースは「1 つのリクエストがどのサービスを通り、どこで詰まったのか」を追うためのものです。

オブザーバビリティを導入するとき、

最初からこの 3 つをすべて完璧にそろえる必要はありません。

現実的には、

まずチームがイベントを検索できるようにし、

次に状態の変化を見えるようにし、

最後にサービスをまたいだリクエスト経路を追えるようにする、

という進め方が取り組みやすいです。

### ログ

#### まずはログを検索できるようにする

オブザーバビリティの第一歩は、

多くの場合 `Logs` から始まります。

何かイベントが起きたとき、

または突発的な障害を調査するとき、

最初に見るのはたいてい `Logs` です。

そのイベントを理解し、

後続の切り分けに必要な情報が十分に残っているかを確認します。

ここまで聞くと、

こう思う人もいるかもしれません。

「それだけ？」

はい。もしすでに Logs のコレクターがあり、

Logs を検索できるプラットフォームもあるなら、

おめでとうございます。

オブザーバビリティの 1/3 はすでにできています。

#### ログ収集基盤を作る

`Logs` を出すこと自体は、

多くのエンジニアやシステムにとって大きな問題ではないと思います。

ただし、Logs があることとオブザーバビリティがあることは別です。

Logs が各サーバー、各 container、各サービスに散らばっているだけでは、

インシデント発生時に素早く検索するのは難しくなります。

ログが出ているなら、

次に必要なのは統一されたログ収集・検索基盤です。

それは `Loki`、`ELK`、`Splunk` でもよいですし、

CloudWatch Logs のようなクラウドサービスでもかまいません。

重要なのはツール名ではありません。

必要なときにチームが、

時間、サービス名、request id、エラーメッセージなどの条件で、

関連する Logs を素早く見つけられるかどうかです。

#### Logs の出力をフォーマットする

システムが `Logs` を出力するとき、

メッセージをなんとなく出しているだけだと、

検索しにくい内容になりがちです。

```
***************
json value is {"foo": "bar"}
***************
```

ログを集中管理する前であれば、

単一ファイルの中ではまだ読みやすいかもしれません。

しかし、ログを集中管理し、

検索システムと組み合わせて使うようになると、

このような出力は`検索条件`や`正規表現`を壊しやすくなります。

上の出力を例にすると、

検索ツールが 1 行を 1 つのイベントとして扱う場合、

上下の `***************` も独立した Log として扱われます。

その結果、次のような検索が失敗しやすくなります。

- `foo = "bar"` のような JSON フィールド検索
- `json` parser で 1 行全体を解析する処理
- request id や trace id で同じリクエストをつなぐ処理
- 正規表現で `json value is ...` の後ろを抽出する処理
- error 件数の集計が、装飾行や複数行出力に邪魔されるケース

見た目には装飾行が数行増えただけに見えます。

しかし集中ログ基盤から見ると、

1 つのイベントが複数のレコードに分割されたり、

構造化して検索できるはずの内容が単なる全文検索になってしまったりします。

そのため、Logs の出力をフォーマットすることは重要です。

たとえば JSON 形式や one line log にして、

不要な emoji、区切り線、装飾文字を取り除きます。

Logs は、人間がゆっくり読むための文章ではありません。

システムが安定して解析、フィルタリング、検索できるデータであるべきです。

#### クエリツール

Loki を使う場合、

通常は Grafana と組み合わせてダッシュボードや検索に使います。

CloudWatch Logs、ELK、Splunk には、それぞれ検索インターフェースがあります。

ツールごとに使い方は異なるため、

少なくともよく使うクエリ構文はいくつか覚えておく必要があります。

そうすることで、問題発生時に素早く調査できます。

たとえば次のような検索です。

- サービス名で検索する
- エラーレベルで検索する
- request id で検索する
- 特定のエラーメッセージで検索する
- 時間範囲を絞って問題発生区間を特定する

ここまでできると、

Logs はただ保存されているだけではなく、

インシデント時に実際に役立つ情報になります。

### メトリクス

Logs を集中して検索できるようになったら、

次はメトリクスの整備に進めます。

ただし始める前に、

まず現在の環境がどのようなものか、

そして何を解決したいのかを確認する必要があります。

#### 資産を棚卸しする

現在の基盤は物理サーバーでしょうか。

仮想マシンでしょうか。

それとも Kubernetes でしょうか。

オンプレミスの Kubernetes やクラウドのマネージド Kubernetes であれば、

基本的には Prometheus を優先して選ぶことが多いです。

物理サーバーや仮想マシンであれば、

Prometheus 以外にも選択肢はあります。

トラフィックが大きくなく、

運用に割けるリソースも少ない場合は、

まず Munin のようなシンプルなツールを検討してもよいです。

#### なぜ Prometheus なのか

Munin も Pull 型で Node からデータを取得します。

Prometheus も Pull 型で Node Exporter から情報を取得します。

では、なぜ現在は `Prometheus` がよく推奨されるのでしょうか。

違いの 1 つは、取得頻度とデータモデルです。

Munin は OS の cronjob に依存する設計で、

グラフ生成も分単位の監視を前提にした設計に近いです。

Munin の流れは次のようになります。

```
Master
   ↓
Node に接続
   ↓
Plugin を実行
   ↓
値を取得
   ↓
RRD を更新
   ↓
グラフを再生成
```

cronjob の 1 分単位という設計を無理に超えようとしても、

接続する Node が増えると Server 側の負荷が高くなりやすいです。

そのため、通常はそのような使い方はしません。

一方 Prometheus はデータを Pull したあと、

時系列データベースに保存します。

クエリ時に PromQL で計算し、

Grafana などのツールで可視化します。

そのため Kubernetes を使っている場合や、

秒単位の粒度で情報を収集したい場合は、

`Prometheus` を使うことが多くなります。

#### Node Exporter をインストールする

##### コンテナ

サービスが Kubernetes 上で動いている場合、

各 Node にログインして `Node Exporter` をインストールすることは通常ありません。

代わりに `DaemonSet` としてデプロイし、

すべての Worker Node に `Node Exporter` が自動で配置されるようにします。

この方法の利点は、

Kubernetes クラスターに Node が追加・削除されたとき、

`Node Exporter` も自動で作成・回収されることです。

各マシンのインストール状態を個別に管理する必要がありません。

最初から YAML を自分で書きたくない場合は、

`kube-prometheus-stack` のような Helm Chart から始めることもできます。

これは通常、Prometheus、Grafana、Alertmanager、

そして Kubernetes でよく使われる Exporter をまとめてインストールします。

オブザーバビリティを導入し始めたばかりのチームにとっては、

各コンポーネントをゼロから組み合わせるよりも、

成果を確認しやすくなります。

##### 仮想マシン

一般的な仮想マシンや物理サーバーであれば、

ホスト上に直接 `Node Exporter` をインストールできます。

CPU、Memory、Disk、Network などの基本的なメトリクスを公開します。

Debian や Ubuntu 系であれば、

`apt` でインストールできます。

```bash
sudo apt update
sudo apt install -y prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

RHEL、CentOS、Rocky Linux、Amazon Linux などであれば、

`yum` でインストールできます。

```bash
sudo yum install -y epel-release
sudo yum install -y node_exporter
sudo systemctl enable --now node_exporter
```

実際のパッケージ名は、ディストリビューションや repository によって異なることがあります。

パッケージが見つからない場合は、

必要な repository が有効になっているか確認するか、

公式の release binary を使ってインストールします。

インストール後は、

通常 `9100` port が開きます。

Prometheus Server はこの endpoint からデータを取得できます。

ここで注意したいのは、

`Node Exporter` はホストのメトリクスを公開するだけだということです。

データの保存やグラフ描画は担当しません。

定期的に取得し、保存し、検索する役割を持つのは、

後段の `Prometheus Server` です。

#### Prometheus Server と接続する

各ホストや Kubernetes Node に Exporter が用意できたら、

次は Prometheus Server に取得先を教えます。

仮想マシン環境では、

まず静的設定から始めることができます。

各ホストの `IP:9100` を Prometheus の scrape config に書きます。

Prometheus Server も仮想マシン上にインストールしている場合、

通常は `/etc/prometheus/prometheus.yml` を編集します。

例は次のとおりです。

```yaml
scrape_configs:
  - job_name: "node-exporter"
    static_configs:
      - targets:
          - "10.0.1.10:9100"
          - "10.0.1.11:9100"
```

変更後は、

まず設定ファイルの構文を確認します。

```bash
promtool check config /etc/prometheus/prometheus.yml
```

問題がなければ、

Prometheus を再起動します。

```bash
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

Prometheus をパッケージではなく、

Docker など別の方法で起動している場合も考え方は同じです。

`prometheus.yml` を Prometheus Server にマウントし、

取得対象の VM `IP:9100` が設定に含まれていることを確認します。

Kubernetes の場合は、

通常 Service Discovery や `ServiceMonitor` を使って Prometheus が自動で target を発見します。

そのため、サービスや Node が増えるたびに手動で設定を変更する必要はありません。

最初からすべてのメトリクスを集めようとしなくても大丈夫です。

まずは次の点を確認します。

- Prometheus が target を正常に scrape できている
- `up` metric が `1` になっている
- Grafana で CPU、Memory、Disk、Network を確認できる
- Dashboard の値がホスト状態の認識と一致している

これらの基本データが信頼できることを確認してから、

どのアプリケーションメトリクスを追加するか、

どの状態をアラートにするかを考え始めます。

### トレース

システムがある程度の規模に達していない場合、

まずは `Logs` と `Metrics` をしっかり整えることをおすすめします。

`Traces` はデプロイの複雑さを増やします。

また、Traces を保存するための容量も必要になります。

もっと直接言えば、

大量のリクエスト経路データを保存する必要があります。

これらの Traces を生成するには、

Application に追加パッケージが必要です。

さらに重要な処理には instrumentation を追加する必要があるかもしれません。

デプロイ時には Exporter と Collector も設定し、

データを後段のストレージシステムに転送します。

#### Application にパッケージを導入する

本当に Traces を導入するなら、

まず `OpenTelemetry` から始めるのがおすすめです。

理由は、特定ベンダーの形式に強く依存しないためです。

将来、Jaeger、Tempo、Datadog、New Relic、

あるいは別のオブザーバビリティプラットフォームに送る場合でも、

調整の余地を残しやすくなります。

Application 側では、

通常は言語ごとの OpenTelemetry SDK または Agent を導入します。

- Python：`opentelemetry-sdk`、`opentelemetry-instrumentation`
- Java：`opentelemetry-javaagent`
- .NET：`OpenTelemetry`、`OpenTelemetry.Extensions.Hosting`

導入初期であれば、

いきなりすべての function に手動で span を追加する必要はありません。

まずは自動 instrumentation から始められます。

たとえば HTTP request、database client、message queue client などです。

これにより、まず 1 つのリクエストの主要な経路をつなげられます。

特定の業務フローを分析する必要が出てきたら、

その時点で custom span を追加します。

たとえば決済、注文作成、レポート生成などの重要な処理です。

#### Exporter

Application が Trace を生成したら、

Exporter を通してデータを外部に送ります。

OpenTelemetry では、

最もよく使われるのが `OTLP` です。

これは OpenTelemetry Protocol のことです。

Application は指定された endpoint に Trace を送信します。

例は次のとおりです。

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAME=order-service
```

ここで `OTEL_SERVICE_NAME` はとても重要です。

Trace システム上で表示されるサービス名を決めるためです。

すべてのサービス名が default や application になっていると、

実際に調査するときに、

どのサービスで問題が起きたのか分かりにくくなります。

#### Collector

Traces の構成では、

通常 `OpenTelemetry Collector` を中継役として配置します。

Logs における Fluent Bit や Vector に近い役割です。

Application から送られてきたデータを受け取り、

設定に従って後段のストレージシステムに転送します。

この構成の利点は、

Application が後段のプラットフォームを直接意識しなくてよいことです。

将来 Jaeger から Tempo に切り替えたい場合や、

同時に 2 つのプラットフォームへ送信したい場合でも、

主に Collector の設定を変更すれば対応できます。

簡略化すると、流れは次のようになります。

```text
Application
   ↓
OpenTelemetry Collector
   ↓
Trace Backend
   ↓
Grafana / Jaeger UI
```

#### Server

最後に Traces を保存し、検索する場所が必要です。

よく使われる選択肢には `Jaeger`、`Grafana Tempo`、

クラウドや SaaS が提供する APM サービスがあります。

チームがすでに Grafana を使っているなら、

Tempo は検討しやすい選択肢です。

Grafana の Dashboard、Logs、Metrics と一緒に確認できるためです。

とりあえず Trace がどのようなものかを素早く理解したいだけであれば、

Jaeger も入門用として使いやすいです。

ただし、どのツールを選ぶ場合でも、

Traces を導入する前に次の点を確認しておくべきです。

- サービス名が分かりやすい
- request id または trace id を Logs と突き合わせられる
- 1 つのリクエストがどのサービスを通ったか本当に見える
- どの区間に最も時間がかかっているか見える
- Trace データが無制限に増えないよう retention が設定されている

Traces の価値は、

コードのすべての行を記録することではありません。

サービス間で素早く特定することです。

このリクエストは、いったいどこで詰まったのか。

## 導入順序のおすすめ

どこから始めればよいか分からない場合は、

次の順番で少しずつ進めるとよいです。

1. Logs を集中管理し、チームがイベントを検索できるようにする
2. Logs をフォーマットし、システムが安定して解析できるようにする
3. CPU、Memory、Disk、Network などの基本的な Metrics を整備する
4. Prometheus と Grafana で最初の Dashboard を作る
5. 少数の信頼できるアラートを追加する
6. サービス数が増え、リクエスト経路が長くなってから Traces を導入する

オブザーバビリティは、

すべてのツールを一度にそろえることではありません。

すべてのデータを集めれば終わり、というものでもありません。

本当に重要なのは、

問題が起きたときに、

チームが次の 3 つの問いにより早く答えられるかどうかです。

- 何が起きたのか？
- 影響範囲はどれくらいか？
- 次にどこを調べるべきか？

## 結語

オブザーバビリティの目的は、

Dashboard をきれいに見せることではありません。

アラートを大量に増やすことでもありません。

本当に解決したいのは、

システムに問題が起きたとき、

チームがより早く気づき、より早く原因を絞り込み、

信頼できるデータにもとづいて判断できるかどうかです。

もし今どこから始めればよいか分からないなら、

まず Logs から始めればよいと思います。

Logs が検索でき、Metrics が見え、アラートを信頼できるようになったら、

そこから少しずつ Traces を追加します。

この進め方は一番派手ではないかもしれません。

しかし、実際のチームの中で継続して進めやすい方法です。
