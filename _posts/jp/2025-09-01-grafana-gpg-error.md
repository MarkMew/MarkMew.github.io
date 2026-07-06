---
layout: post
title: "GrafanaのGPGキー期限切れ：Ubuntu APTのEXPKEYSIGを解消する方法"
description: "UbuntuでGrafanaを更新した際にEXPKEYSIGが発生する原因と、Grafana公式GPGキーを安全に更新してAPTの署名エラーを解消する方法を説明します。"
author: Mark_Mew
category: Grafana
tags: [Grafana]
keywords: [Grafana, GPG, APT, EXPKEYSIG, Ubuntu]
date: 2025-09-01
lang: ja
---

Ubuntu上でGrafanaを更新するために `apt update` を実行したところ、GPG署名の検証エラーが発生しました。

```text
Err:4 https://apt.grafana.com stable InRelease
  The following signatures were invalid:
  EXPKEYSIG 963FA27710458545 Grafana Labs <engineering@grafana.com>

W: An error occurred during the signature verification.
W: Failed to fetch https://apt.grafana.com/dists/stable/InRelease
```

これはGrafanaサービス自体の障害ではありません。APTがGrafanaリポジトリのパッケージインデックスを検証できず、新しくダウンロードしたデータの利用を拒否している状態です。システムは以前のインデックスキャッシュを使い続けることがありますが、この警告を無視すると、Grafanaの最新版を取得できなかったり、インストール可能な候補が見つからないというエラーが発生したりします。

## APTにGPGキーが必要な理由

APTリポジトリは秘密鍵でパッケージインデックスに署名し、Ubuntuホストはインストール済みの公開鍵を使って署名を検証します。この仕組みにより、インデックスが確かにGrafana Labsから公開されたものであり、転送中に改ざんされていないことを確認できます。

`EXPKEYSIG` は、署名に使用された鍵をAPTが期限切れと判断したことを示します。今回の対象となる鍵のフィンガープリントは次のとおりです。

```text
B53A E77B ADB6 30A6 8304 6005 963F A277 1045 8545
```

Grafana Labsは2025年8月22日に、この鍵の有効期限を2年間延長しました。延長前にダウンロードした公開鍵がマシンに残っている場合、APTは以前の有効期限情報を参照し続けます。そのため、公式の公開鍵を再度ダウンロードする必要があります。つまり、今回のポイントは任意の古い鍵を削除することではなく、ローカルに保存された公開鍵を更新することです。

## Ubuntu／Debianでの解決方法

現在は、サードパーティーのリポジトリ鍵を `/etc/apt/keyrings` に個別に保存し、`signed-by` でGrafanaリポジトリが使用するkeyringを限定する方法が推奨されています。システム全体の信頼ストアへ鍵を追加するより管理しやすく、非推奨の `apt-key` を使う必要もありません。

```bash
# 1. サードパーティーのリポジトリ鍵を保存するディレクトリを作成
sudo install -d -m 0755 /etc/apt/keyrings

# 2. Grafana公式の完全な公開鍵を再ダウンロード
sudo wget -O /etc/apt/keyrings/grafana.asc \
  https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc

# 3. Grafanaリポジトリがこのkeyringを使うよう明示的に設定
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' \
  | sudo tee /etc/apt/sources.list.d/grafana.list

# 4. パッケージインデックスを再取得して検証
sudo apt update
```

ここでは、公式が提供している `gpg-full.key` を使用し、ASCII-armored形式のまま `grafana.asc` として保存しています。既存のリポジトリ設定が `/usr/share/keyrings/grafana.key` や `/etc/apt/keyrings/grafana.gpg` など別のファイルを参照している場合は、`signed-by` のパスも更新してください。パスが古いままだと、APTは引き続き古い鍵を読み込みます。

## 修復できたことを確認する

もう一度 `apt update` を実行し、出力に `EXPKEYSIG` や `The following signatures were invalid` が表示されなければ署名エラーは解消しています。APTが利用可能なGrafanaのバージョンを認識しているかどうかも確認できます。

```bash
apt-cache policy grafana
```

エラーが残る場合は、Grafanaリポジトリが重複して設定されていないか確認します。

```bash
grep -R "apt.grafana.com" \
  /etc/apt/sources.list /etc/apt/sources.list.d/
```

同じリポジトリの新旧設定が同時に存在すると、APTが古いkeyringを参照するエントリーを読み込むことがあります。必要なsourceだけを残し、`signed-by` が `/etc/apt/keyrings/grafana.asc` を指していることを確認してから、再度 `sudo apt update` を実行してください。

## 対象となる環境

この記事は、UbuntuまたはDebianでGrafana LabsのAPTリポジトリからGrafanaをインストールしている環境を対象としています。Dockerイメージ、Grafana Cloud、またはOS標準のリポジトリを使用した環境は、通常このAPTキーの問題による影響を受けません。RPM、YUM、DNFではリポジトリと鍵の管理方法が異なるため、この記事のコマンドをそのまま適用しないでください。

---

## 参考資料

- [Grafana公式APTリポジトリ](https://apt.grafana.com/)
- [DebianまたはUbuntuにGrafanaをインストールする](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/)
- [Repository GPG key expires 2025-08-23](https://github.com/grafana/grafana/issues/108659)
