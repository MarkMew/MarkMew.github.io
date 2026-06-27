---
layout: post
title: "VM Server 啟動卻連不到？localhost、127.0.0.1、0.0.0.0 詳解"
description: "VM 裡的 Server 已啟動，Host 瀏覽器卻無法連線？本文解析 localhost、127.0.0.1、0.0.0.0、NAT、Vagrant Port Forwarding 與 Docker 的連線原理。"
author: Mark_Mew
tags: [Docker, network]
keywords: [Docker, network, localhost, 127.0.0.1, 0.0.0.0]
date: 2026-06-27
---

一直以來，我習慣在自己的電腦裡建立 VM，並在 VM 中進行開發。這麼做主要是為了維持開發環境與資源配置的一致性：只要為每台 VM 配置相近的 CPU 與 Memory，就能降低不同電腦效能差異造成的影響。

不過，我也經常遇到一個問題：Server 明明已經在 VM 裡成功啟動，Host（本機）的瀏覽器卻怎麼也連不上。

後來我才真正理解：**Host 的 localhost，不是 VM 的 localhost；Host 的「本機」，也不是 VM 的「本機」。**

很多人最後會從 Google 得到一個答案：

> 把 `127.0.0.1` 改成 `0.0.0.0` 就好了。

這個做法經常有效，但真正的原因是什麼？為什麼改一個位址就能連線？這篇文章會從基礎觀念開始，說明 `localhost`、`127.0.0.1`、`0.0.0.0` 的差異，以及它們在 VM 和 Docker 中扮演的角色。

## 先說結論

| 名稱 | 類型 | 代表意義 | 常見用途 |
| --- | --- | --- | --- |
| `localhost` | Hostname | 本機的主機名稱 | 讓人容易閱讀與使用 |
| `127.0.0.1` | IP Address | IPv4 Loopback 位址 | 只允許同一個網路環境內的程式存取 |
| `0.0.0.0` | Special Address | 所有可用的 IPv4 網路介面 | 讓服務接受來自不同網路介面的連線 |

最重要的觀念是：

> `127.0.0.1` 只代表目前這個網路環境的「自己」，不代表 Host。

## localhost：它是名稱，不是 IP

`localhost` 是一個 Hostname（主機名稱），不是 IP 位址。大部分系統都會在 `hosts` 檔案中定義類似以下的對應：

```text
127.0.0.1 localhost
```

因此，`localhost` 通常會被解析成 `127.0.0.1`；部分系統也可能優先解析成 IPv6 的 `::1`。

簡單來說：

- `localhost` 是名稱。
- `127.0.0.1` 是實際使用的 IPv4 Loopback 位址。

兩者常常可以互換，但概念並不相同。

## 127.0.0.1：只接受自己連線

`127.0.0.1` 是 IPv4 的 Loopback Address（迴路位址）。送往這個位址的封包不會經過實體網路卡，而是直接回到目前的網路環境。

假設程式設定如下：

```python
app.run(host="127.0.0.1", port=5000)
```

這表示 Server 只監聽 Loopback 介面，也就是只接受來自同一台機器、Container 或 VM 內部的連線。

假設這台電腦在區域網路中的 IP 是 `192.168.1.100`，那麼以下網址可以使用：

```text
http://127.0.0.1:5000
http://localhost:5000
```

但其他裝置無法透過下面的網址連線：

```text
http://192.168.1.100:5000
```

原因是 Server 並沒有監聽 `192.168.1.100` 所在的網路介面。

## 0.0.0.0：監聽所有網路介面

在 Server 的綁定設定中，`0.0.0.0` 表示監聽所有可用的 IPv4 網路介面，而不是某一個實際可連線的 IP。

一台電腦可能同時擁有以下位址：

```text
127.0.0.1
192.168.1.100
10.0.0.5
```

如果程式設定為：

```python
app.run(host="0.0.0.0", port=5000)
```

代表 Server 會在所有可用介面上監聽 `5000` Port，因此可能透過以下位址連線：

```text
127.0.0.1:5000
192.168.1.100:5000
10.0.0.5:5000
```

不過，`0.0.0.0` 是 Server 的**監聽設定**，通常不是瀏覽器實際連線時使用的目的位址。瀏覽器仍應使用 VM 或主機真正可到達的 IP。

> 綁定 `0.0.0.0` 可能讓同一網路中的其他裝置存取服務。開發時很方便，但仍要搭配防火牆、身分驗證與適當的網路限制，避免意外暴露服務。
{: .prompt-warning}

## 為什麼 VM 綁定 127.0.0.1，Host 就連不到？

從網路角度來看，VM 就像另一台獨立的電腦。Host 和 VM 各自擁有自己的 Loopback 介面、IP 位址與網路卡：

```text
Host（本機）
├── localhost / 127.0.0.1
└── 192.168.56.1

VM
├── localhost / 127.0.0.1
└── 192.168.56.101
```

如果 VM 裡的程式設定為：

```python
app.run(host="127.0.0.1", port=5000)
```

它只會監聽 VM 自己的 Loopback 介面：

```text
lo    127.0.0.1       ← 有監聽
eth0  192.168.56.101  ← 沒有監聽
```

所以在 VM 裡開啟 `http://127.0.0.1:5000` 可以成功，但 Host 無法使用 `http://192.168.56.101:5000` 存取。

改成以下設定後：

```python
app.run(host="0.0.0.0", port=5000)
```

Server 就會同時監聽 `lo`、`eth0` 等介面。只要 Host 可以到達 VM 的網路，便能透過下面的網址連線：

```text
http://192.168.56.101:5000
```

## 為什麼改成 0.0.0.0 還是連不到？

因為「服務是否監聽」和「網路是否可達」是兩個不同層次的問題：

- **Bind（綁定）**：Server 是否願意接受這個網路介面的連線？
- **Routing（路由）**：Host 是否有辦法把封包送到 VM？
- **Firewall（防火牆）**：作業系統或雲端規則是否允許該 Port 通過？

`0.0.0.0` 只解決 Bind 的問題。Host 能不能找到 VM，仍取決於 VM 的網路模式與防火牆設定。

### NAT

NAT 是常見的預設模式：

```text
Host → Virtual NAT → VM → Internet
```

VM 通常可以連上 Internet，但外部無法直接主動連入 VM。若要讓 Host 存取 VM 裡的服務，通常需要設定 **Port Forwarding**，例如將 Host 的 `5000` Port 轉發到 VM 的 `5000` Port。

> Vagrant 的 `forwarded_port` 就是這種情境。以下設定會將 Host 的 `8080` Port 轉發到 VM 的 `5000` Port，並透過 `host_ip` 限制只有 Host 自己可以存取：
>
> ```ruby
> config.vm.network "forwarded_port",
>   guest: 5000,
>   host: 8080,
>   host_ip: "127.0.0.1"
> ```
>
> 此時的連線路徑為 `Host 的 127.0.0.1:8080 → Vagrant NAT Port Forwarding → VM 的 5000 Port → Server`。因此，VM 裡的 Server 仍需監聽 `0.0.0.0:5000`；如果只監聽 VM 自己的 `127.0.0.1:5000`，轉發到 VM 網路介面的流量仍然無法抵達。設定完成並執行 `vagrant reload` 後，就能在 Host 使用 `http://127.0.0.1:8080` 存取服務。
{: .prompt-info}

### Host-Only

Host-Only 會建立一個只供 Host 與 VM 溝通的虛擬網路：

```text
Host  192.168.56.1
  ↕
VM    192.168.56.101
```

只要服務有監聽 VM 的對應介面，Host 就可以使用以下網址存取：

```text
http://192.168.56.101:5000
```

### Bridged

Bridged 模式會讓 VM 直接加入與 Host 相同的實體網路：

```text
Router
├── Host  192.168.1.100
└── VM    192.168.1.101
```

此時 VM 就像區域網路中的另一台電腦。網路與防火牆允許的情況下，Host 或手機都可以透過以下網址存取：

```text
http://192.168.1.101:5000
```

## 要連 VM 的哪一個 IP？

VM 可能同時擁有多個網路介面，例如：

```text
lo       127.0.0.1
ens33    10.0.2.15
ens34    192.168.56.101
docker0  172.17.0.1
```

即使 Server 顯示正在監聽 `0.0.0.0:5000`，真正要在瀏覽器輸入哪一個 IP，仍取決於：

- Host 是否能到達該網段。
- VM 使用 NAT、Host-Only 還是 Bridged 模式。
- VM 與 Host 的防火牆是否允許 `5000` Port。

在 Linux VM 中，可以使用以下指令查看 IP：

```bash
ip addr
```

也可以確認程式實際監聽的位址與 Port：

```bash
ss -lntp
```

## Docker 為什麼也要綁定 0.0.0.0？

Container 也有自己獨立的網路環境。假設 Container 內的程式只監聽：

```python
app.run(host="127.0.0.1", port=5000)
```

即使啟動 Container 時設定 Port Mapping：

```bash
docker run -p 5000:5000 my-app
```

Host 仍可能無法連線，因為程式只接受 Container 內部 Loopback 介面的連線。

將程式改為：

```python
app.run(host="0.0.0.0", port=5000)
```

Server 才會監聽 Container 的網路介面，Docker 的 Port Mapping 也才能把 Host 收到的連線轉交給程式。

## 連不到時的排查順序

遇到問題時，可以依序檢查：

1. **程式是否真的啟動？** 先在 VM 或 Container 內使用 `curl http://127.0.0.1:5000` 測試。
2. **程式監聽在哪裡？** 使用 `ss -lntp` 確認是 `127.0.0.1:5000` 還是 `0.0.0.0:5000`。
3. **VM 的 IP 是什麼？** 使用 `ip addr` 找出 Host 可以到達的 IP。
4. **VM 網路模式是否正確？** NAT 模式通常需要 Port Forwarding；Host-Only 或 Bridged 則要使用 VM 的對應 IP。
5. **防火牆是否允許？** 確認 VM、Host 或雲端環境沒有封鎖該 Port。
6. **如果使用 Docker，Port 是否發布？** 確認 `docker ps` 顯示正確的 Port Mapping。

## 總結

- `localhost` 是主機名稱，通常會解析成 `127.0.0.1` 或 `::1`。
- `127.0.0.1` 是 Loopback 位址，只代表目前網路環境的自己。
- `0.0.0.0` 用於讓 Server 監聽所有 IPv4 網路介面，不是瀏覽器應該連線的實際 IP。
- Host、VM 與 Container 都有各自的網路環境，以及各自的 `localhost`。
- 服務有監聽，不代表網路一定可達；還要檢查路由、VM 網路模式與防火牆。

理解這些概念後，面對 VM、Docker、Kubernetes、雲端環境，甚至實體伺服器的網路問題時，就能更快判斷問題究竟發生在哪一層，而不只是記住「把 `127.0.0.1` 改成 `0.0.0.0`」。
