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
{: .prompt-warning}

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

![Grafana Infinity Query](/assets/img/grafana_infinity_query.png)

> `Panel title` 需要和後面 cronjob 裡的 `PANEL_TITLE` 一致，因為 script 會透過這個名稱找到要更新的 panel。
{: .prompt-info }

完成資料來源設定後，接著要在 Infinity query 裡展開 `Parsing options & Result fields`。這裡可以先把後面會用到的欄位定義出來，讓 Grafana 知道要從 JSON 中讀取哪些 key，以及每個欄位應該用什麼型態處理。

因為這個 panel 一開始的 inline data 可能只是 `[]`，真正的資料會等到 cronjob 執行後才寫入，所以 Grafana 不一定能在建立 panel 時自動推斷實際資料結構。如果沒有先指定欄位型態，`ai_credits_used` 有可能被當成字串處理，後面在做 `Group by`、`SUM` 或 `Sort by` 時，結果就可能不如預期。

這裡的欄位名稱會對應到後面 cronjob 寫進 inline data 的 JSON key。雖然現在初始資料還是 `[]`，看不到實際內容，但本文後面下載並合併的 metrics JSON 會包含類似下面的欄位：

```json
[
  {
    "day": "2026-07-09",
    "user_login": "octocat",
    "ai_credits_used": 120
  }
]
```

因此這裡至少需要先設定以下三個欄位：

- `day`：資料日期，型態設定為 `Time` 或日期欄位，後續如果要看每日變化或做時間序圖表，就會用到這個欄位。
- `user_login`：使用者帳號，型態設定為 `String`，後面會用它來分組。
- `ai_credits_used`：Copilot Credit 用量，型態設定為 `Number`，後面會用它來加總與排序。

如果後續想在表格中顯示更多資訊，例如組織、模型或其他 metrics，也可以在這裡繼續新增欄位。不過這篇的目標是做使用者用量排行榜，所以先保留 `day`、`user_login` 與 `ai_credits_used` 這三個欄位就足夠了。

![Grafana Infinity Query parsing option](/assets/img/grafana_infinity_parsing_option.png)

然後切換到 `Transformations`，新增第一個 transformation：`Group by`。

`Group by` 的設定如下：

- Group by field：`user_login`
- Aggregation field：`ai_credits_used`
- Aggregation：`SUM`

這個設定會把同一個使用者在不同日期資料列中的 `ai_credits_used` 加總起來，讓 Dashboard 可以看出每位使用者在最近 28 天內的 Copilot Credit 用量。也就是說，`day` 會保留在原始資料中，用來表示資料的時間序；而這個排行榜 panel 會先依照使用者彙總後再呈現排名。

接著新增第二個 transformation：`Sort by`。

`Sort by` 的設定如下：

- Field：`ai_credits_used`
- Sort order：`Descending`

這樣就可以讓 Credit 用量最高的使用者排在最上方，變成一個簡單的使用量排行榜。

如果想讓排行榜畫面更乾淨，也可以再加上 `Organize fields`，只保留彙總後的 `user_login` 與 `ai_credits_used`，並將欄位名稱改成比較容易閱讀的名稱，例如 `User` 與 `Credits Used`。如果後續要另外做每日趨勢圖，就可以使用前面保留下來的 `day` 欄位。

最後可以再加入 `Limit` transformation 限制顯示筆數。如果組織中的使用者很多，只顯示前 10 名會讓圖表更簡潔。

![Grafana Infinity Query transformations](/assets/img/grafana_infinity_transformations.png)

> 這裡的 `Limit` 只是控制 panel 顯示筆數。
> 如果需要長期保存資料或做更細的統計，
> 建議把資料寫進資料庫後再用 SQL 聚合。
{: .prompt-info }

## cronjob

最後用排程定期更新 Dashboard。這段 script 主要做幾件事：

1. 呼叫 GitHub API 取得 Copilot metrics report 的下載連結。
2. 下載每個 report，並使用 `jq --slurp` 合併成單一 JSON 檔案。
3. 呼叫 Grafana API 取得 Dashboard JSON。
4. 找到 title 為 `GitHub Copilot Usage Rank` 的 panel。
5. 將新的 Copilot metrics JSON 寫入該 panel 的 Infinity inline data。
6. 呼叫 Grafana API 儲存 Dashboard。

> GitHub API 回傳的 report 下載後是 `ndjson`，也稱 `JSON Lines`。
> 這種格式不太適合直接丟給 Grafana 呈現，
> 所以這裡先用 cronjob 轉成 Grafana 比較好處理的 JSON。
{: .prompt-info }

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

成功執行 CronJob 後，原本設定為 `[]` 的 inline data 會被新的 metrics JSON 取代，Grafana 也會依照前面設定的 transformations 顯示排行榜。

![Grafana Panel Result](/assets/img/grafana_github_usage_rank.png)

> 不太適合直接揭露使用者帳號，
> 因此對帳號的部分做了遮罩。
{: .prompt-info }

> 這個範例是以過去 28 天這支 API 為例，
> 調用後在 Grafana 上做呈現，
> 不過 GitHub Copilot 每個月第一天 Credits 用量會歸零，
> 如果要做到使用者累積用量圖，則在 cronjob 上會有比較多客製，
> 有興趣的話，我之後再寫一篇
{: .prompt-warning}

## 小結

這個做法的重點是把 GitHub Copilot Credit 用量從 GitHub 管理介面中抽出來，轉成 Grafana 可以呈現與追蹤的資料。GitHub API 負責提供原始用量資料，cronjob 負責定期整理資料，Grafana 則負責呈現與後續告警。

比較完整的做法是呼叫 API 後先將資料存進資料庫，再由 Grafana 查詢與呈現。這樣可以透過 SQL 將資料整理成想要的格式，也比較適合長期保存。不過如果暫時不想維護資料庫，先處理 JSON 再更新 panel，也是一個足夠簡單的做法。

如果團隊本來就已經使用 Grafana 做監控，這種方式可以讓 Copilot 用量也進入同一套監控流程，不需要讓每個想查看用量的人都進到 GitHub 後台。
