---
layout: post
title: Grafana GPG Key 過期
author: Mark_Mew
category: Grafana
date: 2025-09-01
---

最近在更新 Grafana 的時候

出現了 GPG 相關的錯誤

```bash
Err:4 https://apt.grafana.com stable InRelease The following signatures were invalid: EXPKEYSIG 963FA27710458545 Grafana Labs <engineering@grafana.com> Reading package lists... Done W: An error occurred during the signature verification. The repository is not updated and the previous index files will be used. GPG error: https://apt.grafana.com stable InRelease: The following signatures were invalid: EXPKEYSIG 963FA27710458545 Grafana Labs <engineering@grafana.com> W: Failed to fetch https://apt.grafana.com/dists/stable/InRelease The following signatures were invalid: EXPKEYSIG 963FA27710458545 Grafana Labs <engineering@grafana.com> W: Some index files failed to download. They have been ignored, or old ones used instead.
```

經查詢組要原因是原本的 Grafana apt 存儲庫 GPG 金鑰過期

因此需要刪除舊的 Key 重新取得新的

```bash
# 1. 刪除舊金鑰（過期的那一把）
sudo apt-key del 0E22EB88E39E12277A7760AE9E439B102CF3C0C6

# 2. 建立 keyrings 目錄（如尚未存在）
sudo mkdir -p /etc/apt/keyrings

# 3. 下載新的 GPG key 並轉存為 .gpg 格式
wget -q -O - https://apt.grafana.com/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/grafana.gpg

# 4. 更新 Grafana 的 sources list，指定 signed-by
echo 'deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main' | sudo tee /etc/apt/sources.list.d/grafana.list

# 5. 更新 apt 並測試
sudo apt update
```

因為架設 Grafana 的機械是 Ubuntu

因此這裡只附上 Ubuntu（或是 apt 的解決方式）

只要逐步刪除並加上新的 Key 以後

就可以正常更新並安裝新版 Grafana

---

參考文件：
1. [Repository GPG key expires 2025-08-23](https://github.com/grafana/grafana/issues/108659?utm_source=chatgpt.com)