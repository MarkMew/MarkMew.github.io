---
layout: post
title: "GitLab CI Runner 磁碟空間不足：Docker Images 與 Volumes 清理實戰"
description: "GitLab CI Runner 主機磁碟空間不足的排查紀錄：從 df、系統 Log、Docker Build Cache 一路查到 Docker Images 與 Runner Cache Volumes，並說明 docker system prune、docker volume prune 與 clear-docker-cache 的差異與風險。"
author: Mark_Mew
categories: [CICD, GitLab]
tags: [GitLab Runner, Docker, CI/CD, Ubuntu, Disk Cleanup]
keywords: [GitLab Runner 磁碟空間不足, docker system prune, docker volume prune, docker builder prune, clear-docker-cache, GitLab Runner cache volume, journalctl vacuum, Docker 清理]
lang: zh-TW
date: 2026-11-05
---

**GitLab CI Runner 主機磁碟快滿的時候，我一開始先懷疑 Log 和 Docker Build Cache，但最後真正回收最多空間的，是長期累積的 Docker Images 與 GitLab Runner 的 Cache Volumes。** 這篇記錄那次的排查與清理過程，包含哪些指令有留下回收量、哪些沒有，以及清理前後該注意的風險。

先說明範圍：環境是 Ubuntu，上面跑 GitLab Runner 與 Docker。我手上只有當時的 Shell History 和最後兩個清理指令的輸出，所以前面幾個步驟（Log、Build Cache）各自回收了多少，我沒有數據可以說，文章裡也不會補一個數字。

## 前言：Runner 沒空間會發生什麼事

Runner 主機的磁碟滿了，影響會直接反映在 Pipeline 上：Job 拉不到 Image、Build 寫不出檔案、Cache 無法解壓縮，嚴重時連 Docker daemon 都可能出問題。而且這類失敗的錯誤訊息常常不直接寫「磁碟已滿」，容易繞很多遠路。

所以收到空間不足的警訊時，我的做法是先確認空間到底被誰吃掉，再決定清什麼，而不是一上來就 `prune`。

## 第一步：確認磁碟使用情況

```bash
df -h
sudo du -sh /var/lib/docker
sudo docker system df -v
```

這三個指令看的層級不同：

| 指令 | 看什麼 |
|---|---|
| `df -h` | 各掛載點的整體使用率，確認哪個分割區滿了 |
| `du -sh /var/lib/docker` | Docker 資料目錄（預設位置）總共用了多少 |
| `docker system df -v` | Docker 自己統計的 Images、Containers、Local Volumes、Build Cache 用量，`-v` 會列出每一個項目 |

先看 `df -h` 確認是哪個分割區有問題，再用 `du` 與 `docker system df` 往下切。`docker system df` 的 `RECLAIMABLE` 欄位很實用，它會告訴你理論上可以回收多少，但那只是估計值，實際清理後的回收量要以指令輸出為準。

這次我在整個過程中反覆執行了多次 `df -h`，每清完一個項目就看一次，確認空間有沒有真的釋放。

## 第二步：先檢查系統 Logs

Docker 之外，`/var/log` 是最常見的第二個嫌疑對象，而且檢查成本低，所以我先看這裡：

```bash
sudo du -sh /var/log
sudo journalctl --disk-usage
```

`journalctl --disk-usage` 顯示 systemd journal 佔用的空間。接著我用 `--vacuum-time` 縮減保留時間，先設成 1 年，後來再縮到 6 個月：

```bash
sudo journalctl --vacuum-time=1year
sudo journalctl --vacuum-time=6months
```

這個指令有幾個限制要知道：它只會清理已經封存（archived）的 journal 檔，目前正在寫入的 active 檔案不受影響；而且是依時間刪除，不是依目標大小。如果想用大小控制，要用 `--vacuum-size`，或在 `journald.conf` 設定長期上限。

接著我也處理了 `/var/log` 底下超過半年的輪替舊檔。這裡我是先用 `-print` 列出來，確認清單合理之後，才把同一組條件換成 `-delete`：

```bash
# 先只列出，不刪除
sudo find /var/log -type f -mtime +183 \
  \( -name '*.log.*' -o -name '*.gz' -o -name '*.old' \) \
  -print
```

確認清單沒問題後，才執行刪除：

```bash
sudo find /var/log -type f -mtime +183 \
  \( -name '*.log.*' -o -name '*.gz' -o -name '*.old' \) \
  -delete
```

### 用 find -delete 的注意事項

`find ... -delete` 沒有垃圾桶，刪了就沒了，所以幾個習慣我一定會做：

- **一定先用 `-print` 看過清單**，條件完全相同再換成 `-delete`。`-delete` 和 `-print` 的位置、條件順序也會影響結果，不要憑印象改指令。
- **限定副檔名與時間**，只處理已輪替的舊檔（`*.gz`、`*.log.*`、`*.old`），不要碰正在使用的 `.log`。
- **需要留存的稽核或資安 Log 要先備份**，或確認公司有沒有保留期限的規定。

另外，執行前我有用 `find ... -printf '%s\n' | awk ...` 粗估過一年以上檔案的總大小，但那份輸出我沒有留下，所以這裡不引用數字。

最後也是這個步驟需要老實承認的地方：Log 清完之後，我沒有足夠的資料證明它回收了多少，也就無法斷定它佔了多少比例。

## 第三步：清理 Docker Build Cache

```bash
sudo docker builder prune -a
```

Docker Build Cache 是 `docker build`（BuildKit）為了加速重複建置而保留的中間結果。它跟 Image 是不同的東西：Image 是建置完成的產出，Build Cache 是建置過程中留下的快取層。

- **`-a`（`--all`）**：預設的 `docker builder prune` 只清理 dangling 的 Build Cache，加上 `-a` 會清除所有未被使用的 Build Cache。
- **代價**：清掉之後，下一次 Build 無法重用 Cache，會從頭執行，建置時間會變長。
- **範圍有限**：`docker builder prune` 只處理 Build Cache，**不會**刪除 Images，也不會刪除 Volumes。

這個指令我在歷史紀錄中執行了兩次，但同樣沒有留下各次的回收量。執行後 `df -h` 的變化也不足以讓我歸因，所以我只能說它是我清理過程中的一個步驟，不是這次空間不足的主因。

另外要區分一件事：GitLab CI 的 `cache:` 關鍵字（Pipeline 層級的 Cache）、Docker Build Cache、Docker Image Layer 是三種不同的東西。前者由 Runner 管理，在 Docker executor 下是存放在 Volume 裡；後兩者由 Docker 管理。清掉其中一種，不代表其他兩種跟著消失。

## 第四步：確認 GitLab Runner 與 Docker 的空間使用

Log 和 Build Cache 處理完之後，空間還是沒有回到安全範圍，我開始更仔細看 Docker 本身：

```bash
docker ps -a
sudo docker system df -v
sudo du -sh /var/lib/docker
sudo du -sh /var/lib/docker/{overlay2,volumes,buildkit,containers} 2>/dev/null
```

我也查了 Runner 設定檔裡的 Executor 與 Cache 相關欄位：

```bash
sudo grep -E 'executor|builds_dir|cache_dir|volumes' \
  /etc/gitlab-runner/config.toml
```

這幾個要看的東西各自對應不同的目錄：

| 資源 | 說明 | 大致位置 |
|---|---|---|
| Images | 已拉取或建置的 Image，不同 Tag 各自保留 | `/var/lib/docker/overlay2`（依 storage driver 而定） |
| Containers | 容器的可寫層與紀錄檔，`docker ps -a` 可看到已停止的 | `/var/lib/docker/containers`、`overlay2` |
| Local Volumes | 具名或匿名的 Volume | `/var/lib/docker/volumes` |
| Build Cache | BuildKit 的建置快取 | `/var/lib/docker/buildkit` |
| GitLab Runner Cache | Docker executor 下，用 Volume 保存的 CI Cache | 以 Volume 形式存在於 `/var/lib/docker/volumes` |

這裡的關鍵是：**GitLab Runner Cache 在 Docker executor 下是以 Docker Volume 的形式存在**，所以它不會出現在 `docker images`，也不會被 `docker builder prune` 清掉，而是要從 Volume 的角度去看。

`config.toml` 的內容我不在文章中貼出，因為涉及 Token 與環境資訊。後面 Volume 的名稱特徵（見下方）也符合 Docker executor 以 Volume 存放 Cache 的做法。

## 第五步：清理 Docker Images 與其他未使用資源

接下來是這次回收量最明確的步驟之一：

```bash
sudo docker system prune -a -f
```

先把參數講清楚：

- **`system prune`**：清理未使用的 Docker 資源，包含已停止的 Containers、未使用的 Networks、未使用的 Images，以及 Build Cache。
- **`-a`（`--all`）**：不只清理 dangling images，而是所有「沒有被任何容器使用」的 Images，包含有 Tag 的。
- **`-f`（`--force`）**：跳過確認提示。
- **不含 Volumes**：沒有加 `--volumes` 時，`docker system prune` **不會**刪除 Volumes。所以這個指令不會碰到 Runner Cache Volume。
- **不會刪除使用中的 Image**：被執行中或已存在（含已停止）容器引用的 Image 不會被刪除。

清理時輸出有多筆 `untagged`，都是同一個專案、不同 Tag 的 Image（以下為去識別化的示意）：

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

這個畫面很能說明問題：CI 每次 Build 都會產生一個新的 Tag，舊的 Image 沒人清，就一個一個留在 Runner 主機上。

**回收了 20.05 GB。** 不過要精確一點：這是 `docker system prune` 回報的**總**回收量，包含 Images 與其他可清理的資源，我不能說這 20.05 GB 全部都是 Images。

## 第六步：清理 GitLab Runner Cache Volumes

Images 清完之後，我接著處理 Volumes。

### 先看 Runner 自己的清理腳本

GitLab Runner 的套件通常會附一個 `clear-docker-cache` 腳本，我是用這個：

```bash
sudo /usr/share/gitlab-runner/clear-docker-cache space
sudo /usr/share/gitlab-runner/clear-docker-cache prune-volumes
```

依我對官方文件與腳本的理解，兩個參數的差異如下：

| 參數 | 用途 |
|---|---|
| `space` | 檢查可用空間，低於腳本內設定的門檻時才執行清理 |
| `prune-volumes` | 清理由 Runner 管理（帶有 Runner 標籤）的 Volumes |

這個腳本的重點是**只針對 GitLab Runner 自己建立的資源**，範圍比 `docker volume prune` 小。但不同 GitLab Runner 版本的腳本內容、預設門檻與行為可能不同，我建議在自己的主機上直接看 `/usr/share/gitlab-runner/clear-docker-cache` 的內容，並以官方文件為準，不要只依賴我這篇的描述。

這次我執行了 `space` 和 `prune-volumes`，也沒有留下它們單獨的回收量，所以無法判斷它們各自有多大貢獻。

### Runner Cache Volume 長什麼樣子

後面的 `docker volume prune` 輸出裡有大量 Volume，名稱長這樣（節錄）：

```text
runner-257c3558d36448c8ac6d9afa4cf72e23-cache-3c3f060a0374fc8bc39395164f415a70-protected
runner-e54a922b4213cf9950575ff3c43575c2-cache-3c3f060a0374fc8bc39395164f415a70-protected
runner-bc6bbf6bc42a848aa9d131e37a07e1f2-cache-c33bcaa1fd277edf3893b41966cea8
```

這種 `runner-<識別碼>-cache-<hash>` 的格式，符合 Docker executor 為 CI Cache 建立 Volume 的命名特徵，結尾的 `-protected` 則是對應 Protected branch 的 Cache。不同 Job、不同 Runner 會各自產生，所以時間一長就會累積很多。不過 Volume 命名規則會隨 Runner 版本而變，我在這裡是依名稱特徵做的判斷，並沒有逐一對照每個 Volume 屬於哪個 Job。

### 清理 Volumes

```bash
sudo docker volume prune -a -f
```

- **`docker volume prune`**：刪除沒有被任何容器使用的 Local Volumes。
- **`-a`（`--all`）**：預設行為在 Docker 23.0 之後只清理匿名 Volume，加上 `-a` 才會連具名 Volume 一起清。Runner Cache Volume 是具名的，所以需要 `-a`。
- **`-f`**：跳過確認。

最後輸出：

```text
Total reclaimed space: 12.91GB
```

**回收了 12.91 GB。**

### 為什麼 Volume 清理要特別謹慎

這裡我必須強調，`docker volume prune -a` **不只**清 GitLab Runner Cache，而是這台主機上**所有**沒有被容器使用的 Volume。如果同一台主機上還有資料庫、其他服務的具名 Volume，剛好容器暫時停掉，這些 Volume 也會被刪。

Image 被刪了還能重新拉，Cache 被刪了只是下次 Build 慢一點，但 Volume 裡如果是真正的資料，刪了就是遺失。這次是 Runner 主機，而且輸出的 Volume 名稱幾乎都是 Runner Cache 的格式，我才選擇這樣處理；在不確定用途的主機上，我會先用 `docker volume ls` 逐一盤點，或只用 `clear-docker-cache prune-volumes` 這種限縮範圍的方式。

## 清理成果

| 清理項目 | 指令 | 回收空間 |
|---|---|---|
| Docker System Prune | `docker system prune -a -f` | 20.05 GB |
| Docker Volume Prune | `docker volume prune -a -f` | 12.91 GB |
| 合計 | | 32.96 GB |

這是兩個指令各自回報的回收量加總，**不是**用 `df -h` 直接量到的可用空間增加量。前面的 Log、Build Cache 與 `clear-docker-cache` 也都做過清理，它們的貢獻沒有被單獨記錄，因此不在這張表裡。

## 清理風險與注意事項

這次的清理範圍不小，整理幾點我認為實務上最需要注意的：

- **先確認沒有正在執行的 CI Job。** 清理中的 Image 或 Volume 如果剛好被 Job 使用，可能導致 Job 失敗。可以先暫停 Runner，或挑沒有排程的時段。
- **確認這台主機只服務 CI。** 如果同一台主機還跑其他服務，要先盤點它們依賴哪些 Image 與 Volume，再決定能不能用 `-a`。
- **`docker system prune -a` 的影響。** 它會移除所有沒有容器使用的 Image，包含 `latest` 或常用的基底 Image。清掉之後，下一次 Job 需要重新拉取，會多花時間與頻寬。
- **`docker volume prune -a` 的資料遺失風險。** 前面已經講過，它不分用途，只看有沒有被容器使用。Volume 裡如果是資料，無法復原。
- **CI Cache 被清掉後，下次建置會變慢。** 套件下載、依賴安裝都要重做，這是預期內的代價。
- **不要直接手動刪除 `/var/lib/docker` 內部檔案。** 即使你看到 `overlay2` 佔了很多空間，也不要直接 `rm`，這會讓 Docker 的中繼資料與實際檔案不一致，應該透過 Docker 的指令清理。
- **正式環境先盤點、再規劃。** 先用 `docker system df -v`、`docker volume ls` 了解各項資源的用途，再決定清理指令與頻率。

## 如何避免問題再次發生

這次是等到空間快滿才處理，比較被動。如果要避免重複發生，我會考慮：

- **定期檢查磁碟空間**，並設定使用率告警（例如超過某個百分比就通知），讓處理發生在 Job 失敗之前。
- **用 `docker system df` 監控 Docker 資源**，觀察 Images、Volumes、Build Cache 哪一類在成長。
- **評估 Build Cache 的清理週期**，Build Cache 清理的代價是建置變慢，要在「空間」與「建置時間」之間取捨。
- **管理 Runner Cache 的保留策略**，例如評估是否需要定期透過 `clear-docker-cache` 之類限縮範圍的方式清理，而不是等累積成 GB 等級。
- **依主機用途與 Job 排程設計清理流程**：在沒有 Job 執行的時段、只針對 Runner 管理的資源、清理前後記錄 `docker system df`，這樣才有數據能回頭比較。

我不會建議無條件每天排程執行 `docker volume prune -a`。它的範圍太廣，如果主機上哪天多了一個要保留的 Volume，就會在沒有人注意的情況下被清掉。

## 結語

這次最大的收穫是：**CI Runner 磁碟空間不足，不一定是 Log 或 Build Cache 造成的，長期累積的 Docker Images 與 Runner Cache Volumes，也可能是主要原因。** 我花了一些時間在 Log 與 Build Cache 上，那些步驟成本低、值得先排除，但如果一開始就用 `docker system df -v` 把各類資源的佔用看清楚，大概能更快找到方向。

另外一點是記錄：因為當時沒有每個步驟都留下清理前後的數據，所以這篇文章中，只有最後兩個指令能提供確切的回收量。下次我會在清理前後各記錄一次 `df -h` 與 `docker system df`，讓判斷不需要依賴印象。

## 參考資料

- [Docker Docs：docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/)
- [Docker Docs：docker builder prune](https://docs.docker.com/reference/cli/docker/builder/prune/)
- [Docker Docs：docker volume prune](https://docs.docker.com/reference/cli/docker/volume/prune/)
- [Docker Docs：docker system df](https://docs.docker.com/reference/cli/docker/system/df/)
- [GitLab Docs：Docker executor（含 Cache 與 Clear the Docker cache）](https://docs.gitlab.com/runner/executors/docker/)
- [systemd：journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html)
