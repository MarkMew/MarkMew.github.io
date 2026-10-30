---
layout: post
title: "ALB 預設 ELBSecurityPolicy-2016-08 不安全嗎？如何升級 Security Policy 通過稽核"
description: "ALB 以 CLI、CloudFormation、Terraform 建立 HTTPS Listener 時預設可能是 ELBSecurityPolicy-2016-08，仍允許 TLS 1.0/1.1 與 CBC 加密套件。本文整理如何選擇、切換與驗證新的 Security Policy。"
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, ELB, TLS, Security]
keywords: [ALB security policy, ELBSecurityPolicy-2016-08, ELBSecurityPolicy-TLS13-1-2-Res-2021-06, ALB 停用 TLS 1.0, ALB 啟用 TLS 1.3, ALB TLS 合規, ALB Post-Quantum TLS]
lang: zh-TW
date: 2026-10-30
---

在使用的 AWS ALB 的時候，如果是 AWS CLI 或 IaC 建立時，預設的 Policy 通常為 ELBSecurityPolicy-2016-08，這個預設 Policy 不安全嗎？其實沒有，這個 Policy 支援 TLS 1.0、TLS 1.1、TLS 1.2，是一個支援度相當好的 Policy，**不過 ALB 的 `ELBSecurityPolicy-2016-08` 在今天的稽核與弱點掃描中，通常會被標記為不合規。** 它仍允許 TLS 1.0、TLS 1.1，也包含 CBC 模式與不具 Forward Secrecy 的 RSA 金鑰交換套件。多數情況下，建議改用 `ELBSecurityPolicy-TLS13-1-2-Res-2021-06`（TLS 1.3 + 1.2，且只保留 AEAD 加密套件）；若要走 AWS 最新建議，則是 `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`。[AWS：ALB 的 Security Policy](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html)

要注意的是，**預設值取決於建立方式**：在 Console 建立 HTTPS Listener，預設是 `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`；用 AWS CLI、CloudFormation、CDK 等方式沒指定時，預設仍是 `ELBSecurityPolicy-2016-08`。所以舊環境或 IaC 建出來的 ALB，很可能還停在舊的政策。

## 為什麼 2016-08 會被稽核抓到

| 項目 | ELBSecurityPolicy-2016-08 |
|---|---|
| TLS 版本 | TLS 1.0、1.1、1.2（不支援 1.3） |
| 加密套件 | 18 組，包含 `AES128-SHA`、`AES256-SHA256` 等 CBC 套件 |
| 前向保密 | 部分套件（如 `AES128-GCM-SHA256`、`AES256-SHA`）使用純 RSA 金鑰交換，不具 Forward Secrecy |

> **Forward Secrecy** 指的是：即使伺服器的私鑰日後外洩，過去錄下來的加密流量也無法被解開。
> TLS 1.3 強制使用具 Forward Secrecy 的金鑰交換；TLS 1.2 則取決於 tls handshake 用到的加密套件。2016-08 同時包含 ECDHE 與純 RSA 的套件，Client 仍可能使用到沒有 Forward Secrecy 的那一組。
{: .prompt-info}


PCI DSS 等規範普遍要求停用 TLS 1.0/1.1，CIS 與各類雲端合規掃描（如 Datadog、Trend Micro Cloud One 等）也會檢查 Listener 是否使用較新的 Security Policy。這些工具的具體判斷標準不同，請以你們實際使用的規範版本為準。

## 如何選擇 Security Policy

ALB **不支援自訂 Security Policy**，只能從 AWS 提供的清單中選。常見選擇如下：

| 需求 | 建議政策 | TLS 版本 |
|---|---|---|
| 一般公開服務，兼顧相容性與安全 | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` | 1.3、1.2 |
| 同上，並開始導入 Post-Quantum TLS（PQ-TLS） | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` | 1.3、1.2 |
| 所有 Client 都已支援 TLS 1.3 | `ELBSecurityPolicy-TLS13-1-3-2021-06` | 僅 1.3 |
| 需要 FIPS 140 驗證模組 | `ELBSecurityPolicy-TLS13-1-2-Res-FIPS-2023-04` | 1.3、1.2 |
| 需要 CNSA 1.0 / RFC 9151 | `ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP4-FIPS-2023-07` 起步 | 1.3、1.2 |
| 還有舊 Client 必須用 CBC 套件 | `ELBSecurityPolicy-TLS13-1-2-2021-06` 或 `Ext1`／`Ext2` 系列 | 1.3、1.2 |

名稱中的 `Res` 代表 Restricted，只保留 `TLS_AES_*`、`TLS_CHACHA20_POLY1305_SHA256` 與 ECDHE + GCM 套件，共 7 組，不含任何 CBC。`PQ` 是 Post-Quantum 的縮寫，指能抵抗未來量子電腦攻擊的金鑰交換；這類政策多了 Hybrid Post-Quantum 金鑰交換群組（如 `X25519MLKEM768`，結合傳統 X25519 與 ML-KEM），Client 不支援時仍會退回傳統金鑰交換，所以不會因此連不上。

若稽核只要求「停用 TLS 1.0/1.1」，`ELBSecurityPolicy-TLS13-1-2-2021-06` 就能達成，並保留較多相容性；若要求「只能使用強加密套件」，則選 `Res` 系列。

## 切換前先確認 Client 相容性

升級最大的風險不是設定本身，而是**還有 Client 使用舊 TLS 或舊套件**，切換後直接連線失敗。先開啟 [Connection logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-connection-logs.html) 寫入 S3，觀察一段時間（建議涵蓋完整的月結或批次週期），重點看這三個欄位：

- `tls_protocol`：是否仍有 `TLSv1`、`TLSv1.1`
- `tls_cipher`：是否使用 CBC 或 `AES128-SHA` 這類套件
- `tls_keyexchange`：金鑰交換方式

可以用 Athena 查詢，找出仍使用舊版本的來源 IP，再逐一通知或汰換。常見的受影響對象包含舊版 Java 7、舊 Android、舊嵌入式裝置與老舊的監控或掃描工具。

## 切換方式

### Console

EC2 → Load Balancers → 選擇 ALB → Listeners and rules → 選擇 HTTPS:443 → Manage listener → Edit listener → 在 Security policy 選擇新政策後儲存。

### AWS CLI

```bash
aws elbv2 modify-listener \
  --listener-arn arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:listener/app/my-alb/xxxxxxxx/yyyyyyyy \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

想先查詢有哪些政策、各自支援什麼，可以用：

```bash
# 只列出支援 TLS 1.3 的政策名稱
aws elbv2 describe-ssl-policies \
  --query "SslPolicies[?contains(SslProtocols,'TLSv1.3')].Name"

# 查看單一政策的套件清單
aws elbv2 describe-ssl-policies \
  --names ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

### Terraform

`aws_lb_listener` 沒指定 `ssl_policy` 時，不要假設會是新政策，明確寫出來比較保險：

```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
```

### CloudFormation

```yaml
HttpsListener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    LoadBalancerArn: !Ref LoadBalancer
    Port: 443
    Protocol: HTTPS
    SslPolicy: ELBSecurityPolicy-TLS13-1-2-Res-2021-06
    Certificates:
      - CertificateArn: !Ref Certificate
    DefaultActions:
      - Type: forward
        TargetGroupArn: !Ref TargetGroup
```

修改 Listener 的 Security Policy 不需要重建 ALB，也不會中斷既有連線；變更後新建立的 TLS handshake 才會套用新政策。

## 驗證設定是否生效

用 `openssl` 測試舊版本是否已被拒絕、新版本是否可連線：

```bash
# 應失敗：TLS 1.1
openssl s_client -connect example.com:443 -tls1_1 </dev/null

# 應成功：TLS 1.2
openssl s_client -connect example.com:443 -tls1_2 </dev/null

# 應成功：TLS 1.3
openssl s_client -connect example.com:443 -tls1_3 </dev/null
```

若要提供稽核佐證，可用 `nmap` 列舉實際支援的版本與套件：

```bash
nmap --script ssl-enum-ciphers -p 443 example.com
```

也可以用 SSL Labs 或內部的弱點掃描工具重掃，並保留掃描報告。

## 多個 Listener 與後端連線的注意事項

- 同一個 ALB 上若有多個 HTTPS Listener，彼此使用的 Security Policy 必須相容，不能任意混用。
- ALB 到後端 Target 的 HTTPS 連線，你**不能直接指定**政策；後端使用的政策由 Listener 的前端政策決定。例如前端用 TLS 1.3 系列政策，後端使用 `ELBSecurityPolicy-TLS13-1-0-2021-06`。因此，若後端是 HTTPS，仍要檢查後端服務是否支援這些版本與套件。
- 如果 ALB 前面還有 CloudFront、WAF 或其他 CDN，各層的 TLS 設定是獨立的，要分別檢查。CloudFront 的最低 TLS 版本是在 Distribution 的 Security policy 設定。
- NLB 使用另一組政策清單，兩者的預設值也不同，不能把 ALB 的設定直接套到 NLB。

## 如何避免日後又被改回去

稽核不只看現況，也看是否有機制防止退步，可以考慮：

1. **IaC 明確指定**：所有 Listener 都寫出 `ssl_policy`，不依賴預設值。
2. **AWS Config**：使用相關的受管規則或自訂規則，持續檢查 Listener 的政策。
3. **IAM／SCP 條件限制**：Elastic Load Balancing 提供條件鍵，可限制使用者能選擇的 Security Policy，具體鍵名與寫法請參考 [ELB 的 IAM 文件](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-authentication-access-control.html)。
4. **定期檢視**：AWS 會推出新政策，例如 2025 年新增的 PQ 系列，建議每年檢視一次。

## 常見問題

### 切換 Security Policy 會讓 ALB 中斷嗎？

不會重建 ALB，也不影響已建立的連線。只有新連線會依新政策協商，所以真正的風險是舊 Client 無法再連線，要靠事前觀察 Connection logs 降低。

### 只想停用 TLS 1.0/1.1，要選哪個？

`ELBSecurityPolicy-TLS13-1-2-2021-06`。它支援 TLS 1.3 與 1.2，相容性比 `Res` 系列高。若稽核另外要求不得使用 CBC，再改用 `Res` 系列。

> 我自己則是 **ELBSecurityPolicy-TLS-1-2-2017-01** 和 **ELBSecurityPolicy-TLS13-1-2-Res-2021-06** 都有使用
{: .prompt-info}

### 可以只開 TLS 1.3 嗎？

可以，使用 `ELBSecurityPolicy-TLS13-1-3-2021-06`。但只有確定所有 Client 都支援 TLS 1.3 才適合，對外公開的服務通常仍保留 TLS 1.2。

### PQ 政策需要改 Client 嗎？

不需要。PQ 政策同時支援傳統金鑰交換，Client 支援 ML-KEM 時才會使用 Hybrid Post-Quantum 金鑰交換，不支援則維持原本的行為。

### 為什麼切換後掃描器還是說支援舊版本？

先確認掃描的是不是同一個 Listener 或網域，是否前面還有 CloudFront、其他 Proxy，並確認 Listener 的政策已套用成功。SSL Labs 也可能有快取，重掃時可以勾選清除快取。
