---
layout: post
title: "Grafana GPG Key 過期：Ubuntu APT 的 EXPKEYSIG 修復方式"
description: "Ubuntu 更新 Grafana 時遇到 EXPKEYSIG？本文說明 Grafana APT repository 的 GPG 金鑰驗證機制、錯誤原因，以及重新匯入官方金鑰的處理方式。"
author: Mark_Mew
category: Grafana
tags: [Grafana]
keywords: [Grafana]
date: 2025-09-01
---

最近在 Ubuntu 上更新 Grafana 時，執行 `apt update` 出現了 GPG 簽章驗證錯誤：

```text
Err:4 https://apt.grafana.com stable InRelease
  The following signatures were invalid:
  EXPKEYSIG 963FA27710458545 Grafana Labs <engineering@grafana.com>

W: An error occurred during the signature verification.
W: Failed to fetch https://apt.grafana.com/dists/stable/InRelease
```

這不是 Grafana 服務本身故障，而是 APT 無法驗證 Grafana repository 提供的套件索引，因此拒絕採用這次下載的資料。系統可能繼續使用舊的索引快取，但此時不應直接忽略警告，否則可能無法取得新版 Grafana，或在安裝時看到找不到候選版本等問題。

## 為什麼 APT 需要 GPG Key？

APT repository 會用私鑰簽署套件索引，而 Ubuntu 主機則使用已安裝的公鑰驗證簽章。這個機制可確認索引確實由 Grafana Labs 發布，並且在傳輸途中沒有遭到竄改。

錯誤中的 `EXPKEYSIG` 代表 APT 判斷簽章使用的金鑰已過期。這次出現問題的金鑰指紋為：

```text
B53A E77B ADB6 30A6 8304 6005 963F A277 1045 8545
```

Grafana Labs 已於 2025 年 8 月 22 日將這把金鑰的有效期限延長兩年。若主機仍保存延長前的舊副本，APT 讀到的仍是原本的到期資訊，因此需要重新下載官方金鑰。換句話說，這次處理的重點是「更新本機保存的公鑰」，不只是刪除任意一把舊 Key。

## Ubuntu／Debian 的處理方式

目前建議將第三方 repository 的金鑰獨立放在 `/etc/apt/keyrings`，再透過 `signed-by` 指定 Grafana repository 只能使用這個 keyring。這比把金鑰加入全系統信任範圍更容易管理，也不需要使用已淘汰的 `apt-key`。

```bash
# 1. 建立存放第三方 repository 金鑰的目錄
sudo install -d -m 0755 /etc/apt/keyrings

# 2. 重新下載 Grafana 官方提供的完整公鑰
sudo wget -O /etc/apt/keyrings/grafana.asc \
  https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc

# 3. 讓 Grafana repository 明確使用這個 keyring
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' \
  | sudo tee /etc/apt/sources.list.d/grafana.list

# 4. 重新下載並驗證套件索引
sudo apt update
```

這裡使用官方目前提供的 `gpg-full.key`，並直接以 ASCII-armored 格式儲存為 `grafana.asc`。如果原本的 repository 設定指向其他檔案，例如 `/usr/share/keyrings/grafana.key` 或 `/etc/apt/keyrings/grafana.gpg`，必須同步更新 `signed-by` 的路徑，否則 APT 仍會讀取舊金鑰。

## 如何確認修復成功？

重新執行 `apt update` 後，輸出中不應再出現 `EXPKEYSIG` 或 `The following signatures were invalid`。也可以確認 APT 已經讀到 Grafana 的套件版本：

```bash
apt-cache policy grafana
```

若錯誤仍然存在，先檢查系統是否重複設定了 Grafana repository：

```bash
grep -R "apt.grafana.com" \
  /etc/apt/sources.list /etc/apt/sources.list.d/
```

同一個 repository 若同時存在新舊兩份設定，APT 可能仍會載入指向舊 keyring 的項目。確認只保留預期的來源，並檢查 `signed-by` 指向 `/etc/apt/keyrings/grafana.asc` 後，再執行一次 `sudo apt update`。

## 適用範圍

本文處理的是透過 Grafana Labs APT repository 安裝 Grafana，且作業系統為 Ubuntu 或 Debian 的情境。若使用 Docker image、Grafana Cloud，或由作業系統自己的 repository 安裝 Grafana，通常不會受到這個 APT 金鑰問題影響。RPM、YUM 與 DNF 使用不同的 repository 與金鑰管理流程，也不應直接套用本文指令。

---

## 參考文件

- [Grafana 官方 APT repository 說明](https://apt.grafana.com/)
- [Install Grafana on Debian or Ubuntu](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/)
- [Repository GPG key expires 2025-08-23](https://github.com/grafana/grafana/issues/108659)
