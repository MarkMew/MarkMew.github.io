---
layout: post
title: "GitLab CI Runner のディスク容量不足：Docker イメージとボリュームのクリーンアップ記録"
description: "GitLab CI Runner ホストのディスク容量が不足したときの調査記録です。df、システムログ、Docker ビルドキャッシュを順に確認し、最終的に Docker イメージと Runner のキャッシュボリュームを整理した流れと、docker system prune・docker volume prune・clear-docker-cache の違いやリスクをまとめます。"
author: Mark_Mew
categories: [CICD, GitLab]
tags: [GitLab Runner, Docker, CI/CD, Ubuntu, Disk Cleanup]
keywords: [GitLab Runner ディスク容量不足, docker system prune, docker volume prune, docker builder prune, clear-docker-cache, GitLab Runner キャッシュボリューム, journalctl vacuum, Docker クリーンアップ]
lang: ja
date: 2026-11-05
---

**GitLab CI Runner ホストのディスクが残りわずかになったとき、私は最初にログと Docker のビルドキャッシュを疑いました。ところが、実際に最も多くの容量が戻ってきたのは、長期間たまっていた Docker イメージと GitLab Runner のキャッシュボリュームでした。** この記事では、そのときの調査とクリーンアップの流れ、どのコマンドで回収量が残っていて、どれは残っていないのか、そして実行前に注意すべき点を記録します。

先に範囲をお断りしておきます。環境は Ubuntu 上で GitLab Runner と Docker を動かしているホストです。手元にあるのは当時のシェル履歴と、最後の 2 つのクリーンアップコマンドの出力だけです。そのため、前段のステップ（ログ、ビルドキャッシュ）がそれぞれどれだけ回収したかは分からず、数字を補って書くこともしません。

## はじめに：Runner のディスクが足りなくなるとどうなるか

Runner ホストのディスクがいっぱいになると、影響はパイプラインにそのまま現れます。ジョブがイメージを pull できない、ビルドがファイルを書き込めない、キャッシュを展開できない、ひどい場合は Docker デーモン自体が不安定になる、といった具合です。しかも、エラーメッセージに「ディスクが満杯」と明記されないことも多く、原因の切り分けで遠回りしがちです。

そのため、容量不足のアラートを受けたときは、いきなり `prune` を実行せず、まず何が容量を使っているのかを確認してから、何を消すかを決めるようにしています。

## ステップ 1：ディスク使用状況を確認する

```bash
df -h
sudo du -sh /var/lib/docker
sudo docker system df -v
```

この 3 つは、それぞれ見ている階層が違います。

| コマンド | 確認できること |
|---|---|
| `df -h` | マウントポイントごとの全体的な使用率。どのパーティションが逼迫しているかを把握する |
| `du -sh /var/lib/docker` | Docker のデータディレクトリ（デフォルトの場所）の合計サイズ |
| `docker system df -v` | Docker 自身が集計したイメージ、コンテナ、ローカルボリューム、ビルドキャッシュの使用量。`-v` で各項目を一覧表示する |

まず `df -h` で問題のあるパーティションを特定し、そこから `du` と `docker system df` で掘り下げます。`docker system df` の `RECLAIMABLE` 列は、理論上どれだけ回収できるかの目安になって便利ですが、あくまで推定値です。実際の回収量は、クリーンアップコマンドの出力で確認する必要があります。

今回は、作業の途中で `df -h` を何度も実行し、各ステップのたびに容量が本当に解放されているかを確認しました。

## ステップ 2：まずシステムログを確認する

Docker 以外で次に疑わしいのは `/var/log` です。確認のコストが低いので、最初にここを見ました。

```bash
sudo du -sh /var/log
sudo journalctl --disk-usage
```

`journalctl --disk-usage` は、systemd のジャーナルが使っている容量を表示します。続いて `--vacuum-time` で保持期間を短縮しました。最初は 1 年、のちに 6 か月まで縮めています。

```bash
sudo journalctl --vacuum-time=1year
sudo journalctl --vacuum-time=6months
```

このコマンドには、知っておくべき制約がいくつかあります。対象はアーカイブ済み（archived）のジャーナルファイルだけで、現在書き込み中のアクティブなファイルには影響しません。また、削除の基準は期間であって、目標サイズではありません。サイズで制御したい場合は `--vacuum-size` を使うか、`journald.conf` で恒久的な上限を設定します。

あわせて、`/var/log` 配下にある、半年以上前のローテーション済みファイルも整理しました。ここでは、まず `-print` で一覧を出し、内容が妥当だと確認してから、同じ条件で `-delete` に切り替えています。

```bash
# まずは一覧表示のみ。削除はしない
sudo find /var/log -type f -mtime +183 \
  \( -name '*.log.*' -o -name '*.gz' -o -name '*.old' \) \
  -print
```

一覧に問題がないことを確認してから、削除を実行しました。

```bash
sudo find /var/log -type f -mtime +183 \
  \( -name '*.log.*' -o -name '*.gz' -o -name '*.old' \) \
  -delete
```

### find -delete を使うときの注意点

`find ... -delete` にはごみ箱がありません。消したら元に戻せないため、私は次の習慣を必ず守っています。

- **必ず先に `-print` で一覧を確認する**。そのうえで、まったく同じ条件で `-delete` に切り替えます。条件の位置や順序によって結果が変わることがあるので、記憶だけでコマンドを書き換えないようにします。
- **拡張子と期間で絞り込み**、ローテーション済みの古いファイル（`*.gz`、`*.log.*`、`*.old`）だけを対象にします。使用中の `.log` には手を出しません。
- **保管が必要な監査ログやセキュリティログは、事前にバックアップする**か、社内に保持期間の規定がないかを確認します。

また、実行前に `find ... -printf '%s\n' | awk ...` で、1 年より古いファイルの合計サイズをおおまかに見積もりました。ただ、その出力は残していないので、ここでは数字を引用しません。

そしてこのステップで正直にお伝えしなければならないのは、ログを整理したあと、どれだけ回収できたかを示すデータがないということです。そのため、全体のうちどれくらいの割合を占めていたのかも断言できません。

## ステップ 3：Docker ビルドキャッシュを整理する

```bash
sudo docker builder prune -a
```

Docker のビルドキャッシュとは、`docker build`（BuildKit）が、繰り返しのビルドを高速化するために保持している中間結果のことです。イメージとは別物で、イメージはビルドの最終成果物、ビルドキャッシュはビルドの途中で残るキャッシュレイヤーです。

- **`-a`（`--all`）**：デフォルトの `docker builder prune` は、dangling（宙に浮いた）ビルドキャッシュだけを削除します。`-a` を付けると、未使用のビルドキャッシュをすべて削除します。
- **代償**：削除したあとの次回ビルドではキャッシュを再利用できず、最初から実行されるため、ビルド時間が長くなります。
- **範囲は限定的**：`docker builder prune` が扱うのはビルドキャッシュだけです。イメージやボリュームは削除**しません**。

履歴上、このコマンドは 2 回実行していますが、どちらの回収量も残っていません。実行後の `df -h` の変化だけでは、何かを帰属させるには根拠が足りないため、このステップは「実施した作業のひとつ」であり、今回の容量不足の主因ではなかった、というところまでしか言えません。

もうひとつ区別しておきたいことがあります。GitLab CI の `cache:` キーワード（パイプラインレベルのキャッシュ）、Docker のビルドキャッシュ、Docker のイメージレイヤーは、それぞれ別のものです。1 つ目は Runner が管理し、Docker executor では Docker ボリュームに保存されます。残りの 2 つは Docker が管理しています。どれか 1 つを消しても、ほかが消えるわけではありません。

## ステップ 4：GitLab Runner と Docker の容量使用状況を確認する

ログとビルドキャッシュを片付けても、空き容量が安全な水準まで戻らなかったため、Docker 自体をもう少し詳しく調べることにしました。

```bash
docker ps -a
sudo docker system df -v
sudo du -sh /var/lib/docker
sudo du -sh /var/lib/docker/{overlay2,volumes,buildkit,containers} 2>/dev/null
```

Runner の設定ファイルで、executor とキャッシュに関する項目も確認しました。

```bash
sudo grep -E 'executor|builds_dir|cache_dir|volumes' \
  /etc/gitlab-runner/config.toml
```

確認対象のリソースは、それぞれ異なる場所に対応しています。

| リソース | 説明 | おおよその場所 |
|---|---|---|
| Images | pull またはビルドしたイメージ。タグごとに別々に保持される | `/var/lib/docker/overlay2`（ストレージドライバーによる） |
| Containers | コンテナの書き込み可能レイヤーとログ。`docker ps -a` なら停止済みのものも見える | `/var/lib/docker/containers`、`overlay2` |
| Local Volumes | 名前付きボリュームと匿名ボリューム | `/var/lib/docker/volumes` |
| Build Cache | BuildKit のビルドキャッシュ | `/var/lib/docker/buildkit` |
| GitLab Runner Cache | Docker executor で、ボリュームとして保存される CI キャッシュ | `/var/lib/docker/volumes` 配下のボリューム |

ここでの要点は、**Docker executor では、GitLab Runner のキャッシュは Docker ボリュームとして存在する**ということです。`docker images` には表示されず、`docker builder prune` でも消えません。ボリュームの観点から調べる必要があります。

`config.toml` の中身は、トークンや環境情報を含むため記事には載せません。のちほど示すボリューム名の特徴も、Docker executor がキャッシュをボリュームに保存するやり方と矛盾しません。

## ステップ 5：Docker イメージとその他の未使用リソースを整理する

次は、回収量がはっきり残っている 2 つのステップのうち、1 つ目です。

```bash
sudo docker system prune -a -f
```

まず、オプションの意味を整理します。

- **`system prune`**：未使用の Docker リソースを削除します。停止中のコンテナ、未使用のネットワーク、未使用のイメージ、ビルドキャッシュが対象です。
- **`-a`（`--all`）**：dangling イメージだけでなく、どのコンテナからも使われていないイメージをすべて削除します。タグ付きのものも含まれます。
- **`-f`（`--force`）**：確認プロンプトを省略します。
- **ボリュームは対象外**：`--volumes` を付けない場合、`docker system prune` はボリュームを削除**しません**。したがって、このコマンドでは Runner のキャッシュボリュームには手が付きません。
- **使用中のイメージは削除されない**：実行中、または既存（停止中を含む）のコンテナが参照しているイメージは削除されません。

出力には多数の `untagged` が含まれていました。いずれも同じプロジェクトの、異なるタグのイメージです（以下は匿名化した例です）。

```text
untagged: .../dummy-foo-bar:87
untagged: .../dummy-foo-bar:88
untagged: .../dummy-foo-bar:92
untagged: .../dummy-foo-bar:93
untagged: .../dummy-foo-bar:94
untagged: .../dummy-foo-bar:latest
deleted: sha256:...

Total reclaimed space: 20.05GB
```

この出力は多くのことを物語っています。CI はビルドのたびに新しいタグを生成し、古いイメージを誰も片付けなければ、Runner ホスト上に 1 つずつ残り続けます。

**回収できたのは 20.05 GB です。** ただし正確に言うと、これは `docker system prune` が報告した**合計**であり、イメージとその他の削除可能なリソースを含んでいます。20.05 GB の全量がイメージだとは言い切れません。

## ステップ 6：GitLab Runner のキャッシュボリュームを整理する

イメージを片付けたので、続けてボリュームに取りかかりました。

### まず Runner 付属のクリーンアップスクリプトを使う

GitLab Runner のパッケージには、通常 `clear-docker-cache` というスクリプトが付属しており、私はこれを使いました。

```bash
sudo /usr/share/gitlab-runner/clear-docker-cache space
sudo /usr/share/gitlab-runner/clear-docker-cache prune-volumes
```

公式ドキュメントとスクリプトについての私の理解では、2 つの引数の違いは次のとおりです。

| 引数 | 用途 |
|---|---|
| `space` | 空き容量を確認し、スクリプト内に設定されたしきい値を下回る場合にのみクリーンアップを実行する |
| `prune-volumes` | Runner が管理している（Runner のラベルが付いた）ボリュームを削除する |

このスクリプトのポイントは、**GitLab Runner 自身が作成したリソースだけを対象にする**ことです。範囲は `docker volume prune` より狭くなります。ただし、スクリプトの内容、デフォルトのしきい値、挙動は GitLab Runner のバージョンによって異なる可能性があります。私の説明だけに頼らず、ご自身のホスト上の `/usr/share/gitlab-runner/clear-docker-cache` の中身を確認し、公式ドキュメントを基準にしてください。

今回は `space` と `prune-volumes` の両方を実行しましたが、それぞれの回収量は記録していません。そのため、どちらがどれだけ貢献したのかは判断できません。

### Runner のキャッシュボリュームはどんな見た目か

のちに実行した `docker volume prune` の出力には、次のような名前のボリュームが大量に並んでいました（抜粋）。

```text
runner-257c3558d36448c8ac6d9afa4cf72e23-cache-3c3f060a0374fc8bc39395164f415a70-protected
runner-e54a922b4213cf9950575ff3c43575c2-cache-3c3f060a0374fc8bc39395164f415a70-protected
runner-bc6bbf6bc42a848aa9d131e37a07e1f2-cache-c33bcaa1fd277edf3893b41966cea8
```

`runner-<識別子>-cache-<ハッシュ>` という形式は、Docker executor が CI キャッシュ用に作成するボリュームの命名の特徴と一致します。末尾の `-protected` は、protected ブランチ向けのキャッシュに対応するものです。ジョブや Runner ごとに別々に生成されるため、長い時間が経てば相当な数になります。ただし、ボリュームの命名規則は Runner のバージョンによって変わりますし、ここでは名前の特徴から判断しているだけで、各ボリュームがどのジョブのものかを 1 つずつ突き合わせたわけではありません。

### ボリュームを整理する

```bash
sudo docker volume prune -a -f
```

- **`docker volume prune`**：どのコンテナからも使われていないローカルボリュームを削除します。
- **`-a`（`--all`）**：Docker 23.0 以降、デフォルトでは匿名ボリュームだけが対象です。`-a` を付けると、名前付きボリュームも削除されます。Runner のキャッシュボリュームは名前付きなので、`-a` が必要になります。
- **`-f`**：確認プロンプトを省略します。

最終的な出力は次のとおりです。

```text
Total reclaimed space: 12.91GB
```

**回収できたのは 12.91 GB です。**

### ボリュームの整理に特に慎重さが必要な理由

ここは強調しておきたい点です。`docker volume prune -a` が削除するのは、GitLab Runner のキャッシュ**だけではありません**。ホスト上で、どのコンテナからも使われていない**すべての**ボリュームが対象になります。同じホストにデータベースやほかのサービスの名前付きボリュームがあり、たまたまそのコンテナが停止していた場合、それらも削除されてしまいます。

イメージは削除しても再度 pull できますし、キャッシュを消しても次回のビルドが遅くなるだけです。しかしボリュームに実際のデータが入っていた場合、削除はデータの喪失を意味します。今回は Runner ホストであり、出力されたボリューム名もほぼすべて Runner のキャッシュの形式だったため、この方法を選びました。用途が分からないホストでは、まず `docker volume ls` で棚卸しをするか、範囲を絞った `clear-docker-cache prune-volumes` を使うようにします。

## クリーンアップの成果

| クリーンアップ項目 | コマンド | 回収量 |
|---|---|---|
| Docker System Prune | `docker system prune -a -f` | 20.05 GB |
| Docker Volume Prune | `docker volume prune -a -f` | 12.91 GB |
| 合計 | | 32.96 GB |

これは各コマンドが報告した回収量の合計であり、`df -h` で実測した空き容量の増加分では**ありません**。ログ、ビルドキャッシュ、`clear-docker-cache` も整理していますが、それぞれの寄与は個別に記録していないため、この表には含まれていません。

## クリーンアップのリスクと注意事項

今回のクリーンアップは、範囲が小さくありませんでした。実務上、特に重要だと考える点を挙げます。

- **実行中の CI ジョブがないことを確認する。** クリーンアップ中のイメージやボリュームがジョブで使われていると、そのジョブが失敗する可能性があります。先に Runner を一時停止するか、スケジュールのない時間帯を選びます。
- **このホストが CI 専用であることを確認する。** 同じホストでほかのサービスが動いている場合は、それらがどのイメージやボリュームに依存しているかを調べてから、`-a` を使ってよいかを判断します。
- **`docker system prune -a` の影響。** どのコンテナからも使われていないイメージはすべて削除されます。`latest` や、よく使うベースイメージも例外ではありません。次回のジョブで再度 pull が必要になり、時間と帯域を消費します。
- **`docker volume prune -a` によるデータ喪失のリスク。** 前述のとおり、用途は関係なく、コンテナが使っているかどうかだけで判断されます。ボリュームにデータが入っていれば、復元できません。
- **CI キャッシュを消すと、次回のビルドが遅くなる。** パッケージのダウンロードや依存関係のインストールをやり直す必要があります。これは想定内のコストです。
- **`/var/lib/docker` 内のファイルを手作業で削除しない。** `overlay2` が非常に大きく見えても、直接 `rm` してはいけません。Docker のメタデータと実ファイルの整合性が崩れます。クリーンアップは Docker のコマンドで行います。
- **本番環境では、まず棚卸し、それから計画する。** `docker system df -v` や `docker volume ls` で各リソースの用途を把握したうえで、コマンドと実行頻度を決めます。

## 再発を防ぐには

今回は、ディスクが残りわずかになってから対応したので、後手に回った形でした。繰り返さないために、次のようなことを検討します。

- **ディスク容量を定期的に確認し**、使用率のアラート（たとえば一定の割合を超えたら通知）を設定して、ジョブが失敗する前に対応できるようにする。
- **`docker system df` で Docker のリソースを監視し**、イメージ、ボリューム、ビルドキャッシュのどれが増えているのかを把握する。
- **ビルドキャッシュのクリーンアップ周期を検討する。** ビルドキャッシュを消す代償はビルドの遅延なので、容量とビルド時間のトレードオフになります。
- **Runner のキャッシュの保持方針を管理する。** たとえば `clear-docker-cache` のような範囲を絞った方法で定期的に整理し、GB 単位にたまるまで放置しないようにする。
- **ホストの用途とジョブのスケジュールに合わせて、クリーンアップの手順を設計する。** ジョブが動いていない時間帯に、Runner が管理するリソースだけを対象にし、前後で `docker system df` を記録して、比較できるデータを残す。

`docker volume prune -a` を毎日、無条件で実行するようなスケジュールは、おすすめしません。範囲が広すぎるからです。残しておくべきボリュームがホストに追加された日には、誰にも気づかれないまま削除されてしまいます。

## おわりに

今回の最大の収穫は、**CI Runner のディスク容量不足は、必ずしもログやビルドキャッシュが原因とは限らず、長期間にわたってたまった Docker イメージと Runner のキャッシュボリュームが主な原因になることもある**、という点です。私はログとビルドキャッシュの確認にいくらか時間を使いました。それらのステップはコストが低く、最初に除外しておく価値はありますが、最初から `docker system df -v` で各種リソースの使用量を見ていれば、もっと早く方向性をつかめたはずです。

もうひとつの教訓は、記録です。各ステップの前後の数値を残していなかったため、この記事で確かな回収量を示せるのは、最後の 2 つのコマンドだけです。次回は、クリーンアップの前後で `df -h` と `docker system df` を記録し、結論が記憶に頼らないようにします。

## 参考資料

- [Docker Docs: docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/)
- [Docker Docs: docker builder prune](https://docs.docker.com/reference/cli/docker/builder/prune/)
- [Docker Docs: docker volume prune](https://docs.docker.com/reference/cli/docker/volume/prune/)
- [Docker Docs: docker system df](https://docs.docker.com/reference/cli/docker/system/df/)
- [GitLab Docs: Docker executor（キャッシュと Docker キャッシュのクリア）](https://docs.gitlab.com/runner/executors/docker/)
- [systemd: journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html)
