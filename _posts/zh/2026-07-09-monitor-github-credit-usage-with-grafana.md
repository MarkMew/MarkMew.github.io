---
layout: post
title: "使用 GitHub API 監控 GitHub Copilot Credit 用量，並串接 Grafana Dashboard"
image: https://fastly.picsum.photos/id/137/1200/630.jpg?hmac=0Du7WYxJIaG3T7HmbntNJYWs9zBTmHs0hIkWpR3azNk
description: "GitHub Copilot Credit 用量不一定適合讓所有人直接進 GitHub 檢視，因此可以透過 GitHub API 擷取資料，再轉拋到 Grafana Dashboard 呈現。"
author: Mark_Mew
categories: [GitHub]
tags: [GitHub, GitHub Copilot]
keywords: [GitHub, GitHub Copilot, Grafana, GitHub API]
date: 2026-07-09
---

GitHub Copilot 自從 6/1 大改版以後，開始以用量計價，因此監控使用者的 Credit 用量也變得更重要。

GitHub 本身雖然已經提供 `Budgets and alerts` 功能，可以讓管理者針對用量即將額滿或已額滿的使用者發出告警，不過對於公司高層或其他非開發人員來說，為了查看用量資訊而額外配置 GitHub 權限或席次，仍然不是一個理想的做法。

因此我想把 GitHub Copilot 的用量資料從 GitHub 拉出來，再放到既有的 Grafana Dashboard 中呈現。這樣 GitHub 可以維持在開發與程式碼管理的使用場景，用量監控與告警則回到 Grafana 處理，也能維持既有監控系統的一致性。

這篇文章會記錄完整流程：建立 GitHub Token、準備 Grafana Dashboard、使用 cronjob 抓取 Copilot metrics，最後透過 Grafana API 更新 Dashboard 內的 Infinity panel 資料。

## 前提條件

開始前需要先準備幾個權限與工具：

- GitHub Organization 權限，用來建立可以讀取 Copilot metrics 的 Token。
- Grafana 管理權限，用來安裝 Infinity datasource plugin、建立 Service Account Token，以及建立 Dashboard。
- 可以定期執行 script 的環境，例如 Kubernetes CronJob、Linux cron、GitLab CI schedule 或其他排程工具。
- `curl` 與 `jq`，用來呼叫 API 與處理 JSON。

本篇範例會用 bash 搭配 `curl` 和 `jq` 完成，不需要額外寫一支完整的應用程式。

## GitHub

首先要建立一組可以讀取 Organization Copilot metrics 的 GitHub Token。

進入 GitHub 後，依序前往：

`右上角個人頭像` -> `Settings` -> `Credentials` -> `Fine-grained personal access tokens`

這裡會使用新版的 `Fine-grained personal access tokens`，不要選到舊版的 `Personal access tokens (classic)`。

建立 Token 時要特別注意 Owner 欄位，這裡要選擇 Organization，而不是自己的個人帳號。

![fine-grained personal token generation page](/assets/img/github_new_fine_grained_personal_token.png)

如果 Owner 有正確選到 Organization，就可以在 `Add permissions` 中找到 `Organization Copilot metrics`。成功建立後，你會拿到一組類似下面格式的 token。

```plaintext
ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

> 請務必妥善保管，GitHub 只會在建立當下顯示一次。
{: .prompt-warn }

取得 Token 後，可以先用下面的 API 確認權限是否正常。請將 `YOUR_TOKEN` 與 `{Organization}` 替換成自己的設定。

```bash
curl -L \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/orgs/{Organization}/copilot/metrics/reports/users-28-day/latest
```

如果可以正常取得回應，就代表 Token 權限大致沒有問題，後面就可以把這組 Token 放到排程環境中使用。

## Grafana

Grafana 這邊會做三件事：

1. 安裝 Infinity datasource plugin。
2. 建立 Service Account Token，讓 cronjob 可以透過 Grafana API 更新 Dashboard。
3. 新增一個 Dashboard 與 Panel，讓 cronjob 將處理後的 JSON 寫進 panel 裡。

### 安裝 Infinity 擴充套件

這裡要安裝的是 `yesoreyeram-infinity-datasource`。

![Grafana infinity datasource](/assets/img/grafana_infinity_datasource.png)

Infinity datasource 支援多種資料來源與認證方式，不過這次的用途比較單純：只需要讓 panel 可以吃一段 inline JSON。

> 網路上或 AI 工具可能會建議在安裝完套件後直接設定驗證，
> 不過這次取得的資料格式比較特別，
> 需要先經過處理後才適合呈現在 Grafana。
> 因此 GitHub Token 只會在 cronjob 中使用。
{: .prompt-info }

### 新增 Grafana Service Account Token

接著建立一組 Grafana Service Account Token，讓 cronjob 可以呼叫 Grafana API 更新 Dashboard。

路徑如下：

`Administration` -> `General` -> `Users and Access` -> `Service Accounts`

![Grafana Service Accounts](/assets/img/grafana_service_accounts.png)

建立完成後，將 Token 保存起來，後續會放到 cronjob 的 `GRAFANA_TOKEN` 環境變數中。

### 新增 Dashboard

接著新增一個 Dashboard，並在 Dashboard 裡新增一個 Panel。這個 Panel 會先使用 Infinity datasource 的 inline JSON 當作資料來源，之後 cronjob 會透過 Grafana API 把最新資料寫回這個 panel。

Panel 的基本設定如下：

- Panel title：`GitHub Copilot Usage Rank`
- Datasource：`Infinity`
- Source：`Inline`
- Format：`JSON`
- 初始資料：可以先填入 `[]`

> `Panel title` 需要和後面 cronjob 裡的 `PANEL_TITLE` 一致，因為 script 會透過這個名稱找到要更新的 panel。
{: .prompt-info }

完成資料來源設定後，切換到 `Transformations`，新增第一個 transformation：`Group by`。

`Group by` 的設定如下：

- Group by field：`user_login`
- Aggregation field：`ai_credits_used`
- Aggregation：`SUM`

這個設定會把同一個使用者在不同資料列中的 `ai_credits_used` 加總起來，讓 Dashboard 可以看出每位使用者在最近 28 天內的 Copilot Credit 用量。

接著新增第二個 transformation：`Sort by`。

`Sort by` 的設定如下：

- Field：`ai_credits_used`
- Sort order：`Descending`

這樣就可以讓 Credit 用量最高的使用者排在最上方，變成一個簡單的使用量排行榜。

如果想讓畫面更乾淨，也可以再加上 `Organize fields`，只保留 `user_login` 與 `ai_credits_used`，並將欄位名稱改成比較容易閱讀的名稱，例如 `User` 與 `Credits Used`。

## cronjob

最後用排程定期更新 Dashboard。這段 script 主要做幾件事：

1. 呼叫 GitHub API 取得 Copilot metrics report 的下載連結。
2. 下載每個 report，並使用 `jq --slurp` 合併成單一 JSON 檔案。
3. 呼叫 Grafana API 取得 Dashboard JSON。
4. 找到 title 為 `GitHub Copilot Usage Rank` 的 panel。
5. 將新的 Copilot metrics JSON 寫入該 panel 的 Infinity inline data。
6. 呼叫 Grafana API 儲存 Dashboard。

實際使用時，建議把 `GITHUB_TOKEN`、`GRAFANA_TOKEN` 這類敏感資訊放在 Secret 或環境變數中，不要直接寫死在 script 裡。

```bash
set -eu

apk add --no-cache curl jq

GITHUB_TOKEN=""
GITHUB_ORG=""
GRAFANA_TOKEN=""
GRAFANA_HOST=""
DASHBOARD_UID=""
PANEL_TITLE="GitHub Copilot Usage Rank"

# 取得 GitHub Copilot metrics 下載連結，並將資料合併成單一 JSON 檔案。
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

# 取得 Grafana Dashboard 設定。
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

# 檢查原本寫在 Infinity panel 內的資料。
echo
echo "===== Original Infinity Data ====="

jq -r --arg title "${PANEL_TITLE}" \
  '.dashboard.panels[] | select(.title == $title) | .targets[0].data' \
  /tmp/dashboard.json

# 將新的 metrics JSON 寫回指定 panel。
jq --rawfile newData /tmp/copilot-metrics.json --arg title "${PANEL_TITLE}" '
  (.dashboard.panels[] | select(.title == $title) | .targets[0].data) = $newData
' /tmp/dashboard.json > /tmp/dashboard-updated.json

# 更新 Grafana Dashboard。
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

## 小結

這個做法的重點是把 GitHub Copilot Credit 用量從 GitHub 管理介面中抽出來，轉成 Grafana 可以呈現與追蹤的資料。GitHub API 負責提供原始用量資料，cronjob 負責定期整理資料，Grafana 則負責呈現與後續告警。

如果團隊本來就已經使用 Grafana 做監控，這種方式可以讓 Copilot 用量也進入同一套監控流程，不需要讓每個想查看用量的人都進到 GitHub 後台。
