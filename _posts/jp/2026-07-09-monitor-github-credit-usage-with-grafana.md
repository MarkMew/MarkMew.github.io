---
layout: post
title: "GitHub APIでGitHub Copilot Credit使用量を監視し、Grafana Dashboardに連携する"
image: https://fastly.picsum.photos/id/137/1200/630.jpg?hmac=0Du7WYxJIaG3T7HmbntNJYWs9zBTmHs0hIkWpR3azNk
description: "GitHub Copilot Creditの使用量を全員がGitHub上で直接確認するのは現実的ではありません。この記事では、GitHub APIでデータを取得し、Grafana Dashboardへ連携する方法を紹介します。"
author: Mark_Mew
categories: [GitHub]
tags: [GitHub, GitHub Copilot]
keywords: [GitHub, GitHub Copilot, Grafana, GitHub API]
lang: ja
date: 2026-07-09
---

GitHub Copilotは6月1日の大きな変更以降、使用量ベースの課金になりました。そのため、各ユーザーのCredit使用量を監視する重要性も高くなっています。

GitHub自体にも`Budgets and alerts`機能があり、管理者は使用量が上限に近づいたユーザー、または上限に達したユーザーに対してアラートを出せます。しかし、経営層や開発者以外のメンバーが使用量を見るためだけに、追加のGitHub権限やシートを付与するのは、あまり理想的な方法ではありません。

そこで、GitHub Copilotの使用量データをGitHubから取得し、既存のGrafana Dashboard上に表示する方法を考えました。これにより、GitHubは開発とソースコード管理の用途に集中させ、使用量の監視やアラートはGrafana側に寄せることができます。既存の監視フローとも統一しやすくなります。

この記事では、GitHub Tokenの作成、Grafana Dashboardの準備、cronjobによるCopilot metricsの取得、そしてGrafana APIを使ってDashboard内のInfinity panelデータを更新するまでの流れを記録します。

## 前提条件

始める前に、次の権限とツールを準備します。

- Copilot metricsを読み取るTokenを作成するためのGitHub Organization権限。
- Infinity datasource pluginのインストール、Service Account Tokenの作成、Dashboardの作成に必要なGrafana管理権限。
- Kubernetes CronJob、Linux cron、GitLab CI scheduleなど、scriptを定期実行できる環境。
- API呼び出しとJSON処理に使う`curl`と`jq`。

この記事の例では、bashと`curl`、`jq`を使います。そのため、別途アプリケーションを実装する必要はありません。

## GitHub

まず、Organization Copilot metricsを読み取れるGitHub Tokenを作成します。

GitHubで次の順に移動します。

`右上のプロフィール画像` -> `Settings` -> `Credentials` -> `Fine-grained personal access tokens`

ここでは新しい`Fine-grained personal access tokens`を使用します。古い`Personal access tokens (classic)`を選ばないように注意してください。

Tokenを作成するときは、Owner欄に注意します。個人アカウントではなく、Organizationを選択してください。

![fine-grained personal token generation page](/assets/img/github_new_fine_grained_personal_token.png)

OwnerにOrganizationを正しく選択できていれば、`Add permissions`の中で`Organization Copilot metrics`を選べます。Tokenを作成すると、次のような形式のtokenが発行されます。

```plaintext
ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> Tokenは安全に保管してください。GitHubでは作成時に一度だけ表示されます。
{: .prompt-warn }

Tokenを取得したら、次のAPIで権限が正しく動作するか確認できます。`YOUR_TOKEN`と`{Organization}`は自分の値に置き換えてください。

```bash
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/orgs/{Organization}/copilot/metrics/reports/users-28-day/latest
```

正常にレスポンスが返ってくれば、Tokenの権限はおおむね問題ありません。以降はこのTokenを定期実行環境で利用します。

## Grafana

Grafana側では、次の3つを行います。

1. Infinity datasource pluginをインストールする。
2. cronjobがGrafana API経由でDashboardを更新できるように、Service Account Tokenを作成する。
3. DashboardとPanelを作成し、cronjobが処理後のJSONをそのpanelへ書き込めるようにする。

### Infinityプラグインをインストールする

インストールするpluginは`yesoreyeram-infinity-datasource`です。

![Grafana infinity datasource](/assets/img/grafana_infinity_datasource.png)

Infinity datasourceはさまざまなデータソースや認証方式に対応していますが、今回は用途がシンプルです。panelにinline JSONを読み込ませるために使用します。

> インターネット上の記事やAIツールでは、pluginをインストールした後に直接認証設定を行う方法が提案されることがあります。
> しかし、今回取得するデータ形式は少し特殊です。
> Grafanaで表示しやすい形にするには、先にデータを処理する必要があります。
> そのため、GitHub Tokenはcronjob内でのみ使用します。
{: .prompt-info }

### Grafana Service Account Tokenを作成する

次に、cronjobからGrafana APIを呼び出してDashboardを更新するため、Grafana Service Account Tokenを作成します。

パスは次のとおりです。

`Administration` -> `General` -> `Users and Access` -> `Service Accounts`

![Grafana Service Accounts](/assets/img/grafana_service_accounts.png)

作成後はTokenを保存しておきます。後続のcronjobでは、`GRAFANA_TOKEN`環境変数として使用します。

### Dashboardを作成する

次にDashboardを作成し、その中にPanelを追加します。このPanelは、最初はInfinity datasourceのinline JSONをデータソースとして使用します。その後、cronjobがGrafana APIを通して最新データをこのpanelへ書き戻します。

Panelの基本設定は次のとおりです。

- Panel title：`GitHub Copilot Usage Rank`
- Datasource：`Infinity`
- Source：`Inline`
- Format：`JSON`
- 初期データ：まずは`[]`で問題ありません

> `Panel title`は、後続のcronjobで使う`PANEL_TITLE`と一致させる必要があります。scriptはこの名前を使って更新対象のpanelを探します。
{: .prompt-info }

データソースの設定が終わったら、`Transformations`に切り替えて、最初のtransformationとして`Group by`を追加します。

`Group by`の設定は次のとおりです。

- Group by field：`user_login`
- Aggregation field：`ai_credits_used`
- Aggregation：`SUM`

この設定により、同じユーザーの複数行に分かれた`ai_credits_used`を合計できます。これで、直近28日間に各ユーザーが使用したCopilot CreditをDashboard上で確認できます。

次に、2つ目のtransformationとして`Sort by`を追加します。

`Sort by`の設定は次のとおりです。

- Field：`ai_credits_used`
- Sort order：`Descending`

これでCredit使用量が多いユーザーから順に表示され、簡単な使用量ランキングになります。

表示をさらに見やすくしたい場合は、`Organize fields`を追加し、`user_login`と`ai_credits_used`だけを残して、表示名を`User`や`Credits Used`のように変更してもよいです。

## cronjob

最後に、定期実行ジョブでDashboardを更新します。このscriptでは主に次の処理を行います。

1. GitHub APIを呼び出し、Copilot metrics reportのダウンロードリンクを取得する。
2. 各reportをダウンロードし、`jq --slurp`で1つのJSONファイルにまとめる。
3. Grafana APIを呼び出し、Dashboard JSONを取得する。
4. titleが`GitHub Copilot Usage Rank`のpanelを探す。
5. 新しいCopilot metrics JSONを、そのpanelのInfinity inline dataに書き込む。
6. Grafana APIを呼び出し、Dashboardを保存する。

実際に使う場合は、`GITHUB_TOKEN`や`GRAFANA_TOKEN`のような機密情報をSecretや環境変数に保存してください。script内に直接書き込むのは避けます。

```bash
set -eu

apk add --no-cache curl jq

GITHUB_TOKEN=""
GITHUB_ORG=""
GRAFANA_TOKEN=""
GRAFANA_HOST=""
DASHBOARD_UID=""
PANEL_TITLE="GitHub Copilot Usage Rank"

# GitHub Copilot metricsのダウンロードリンクを取得し、データを1つのJSONファイルにまとめる。
curl --fail-with-body --silent --show-error \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  "https://api.github.com/orgs/${GITHUB_ORG}/copilot/metrics/reports/users-28-day/latest" |
jq -r ".download_links[]" |
while IFS= read -r url; do
  curl --fail --silent --show-error --location "${url}"
done |
jq --slurp "." > /tmp/copilot-metrics.json

cat /tmp/copilot-metrics.json

# Grafana Dashboardの設定を取得する。
echo
echo "Dashboard UID: ${DASHBOARD_UID}"

curl --fail-with-body --silent --show-error \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  "${GRAFANA_HOST}/api/dashboards/uid/${DASHBOARD_UID}" \
  > /tmp/dashboard.json

PANEL_COUNT=$(
  jq --arg title "${PANEL_TITLE}" \
    '[.dashboard.panels[] | select(.title == $title)] | length' \
    /tmp/dashboard.json
)

if [ "${PANEL_COUNT}" -eq 0 ]; then
  echo "ERROR: Cannot find panel '${PANEL_TITLE}' in dashboard ${DASHBOARD_UID}"
  exit 1
fi

# Infinity panelに保存されている元データを確認する。
echo
echo "===== Original Infinity Data ====="

jq -r --arg title "${PANEL_TITLE}" \
  '.dashboard.panels[] | select(.title == $title) | .targets[0].data' \
  /tmp/dashboard.json

# 新しいmetrics JSONを対象panelへ書き戻す。
jq --rawfile newData /tmp/copilot-metrics.json --arg title "${PANEL_TITLE}" '
  (.dashboard.panels[] | select(.title == $title) | .targets[0].data) = $newData
' /tmp/dashboard.json > /tmp/dashboard-updated.json

# Grafana Dashboardを更新する。
jq '{
  dashboard: .dashboard,
  overwrite: true,
  message: "Updated GitHub Copilot metrics data"
}' /tmp/dashboard-updated.json |
curl --fail-with-body --silent --show-error \
  -X POST \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -H "Content-Type: application/json" \
  --data-binary @- \
  "${GRAFANA_HOST}/api/dashboards/db"

echo
echo "Dashboard updated successfully."
```

## まとめ

この方法のポイントは、GitHub Copilot Credit使用量をGitHubの管理画面から取り出し、Grafanaで表示・追跡できるデータに変換することです。GitHub APIが元データを提供し、cronjobが定期的にデータを整形し、Grafanaが可視化と今後のアラートを担当します。

チームですでにGrafanaを監視基盤として使っている場合、この方法によりCopilotの使用量も同じ監視フローに載せられます。使用量を見たい人全員にGitHub管理画面へのアクセスを付与する必要もありません。
