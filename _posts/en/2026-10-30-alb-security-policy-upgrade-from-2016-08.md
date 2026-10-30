---
layout: post
title: "Is the ALB Default ELBSecurityPolicy-2016-08 Safe? Upgrading Your Security Policy for Audits"
description: "HTTPS listeners created with the CLI, CloudFormation, or Terraform can default to ELBSecurityPolicy-2016-08, which still allows TLS 1.0/1.1 and CBC ciphers. Here is how to choose, switch, and verify a newer ALB security policy."
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, ELB, TLS, Security]
keywords: [ALB security policy, ELBSecurityPolicy-2016-08, ELBSecurityPolicy-TLS13-1-2-Res-2021-06, ALB disable TLS 1.0, ALB enable TLS 1.3, ALB TLS compliance, ALB post-quantum TLS]
lang: en
date: 2026-10-30
---

**Is `ELBSecurityPolicy-2016-08` unsafe? Not outright, but it will likely fail an audit.** If you create an ALB HTTPS listener with the AWS CLI, CloudFormation, CDK, or Terraform and don't set a policy, this is what you get. It accepts TLS 1.0, TLS 1.1, and TLS 1.2, which makes it very compatible, but it also allows CBC cipher suites and RSA key exchange without Forward Secrecy. Vulnerability scanners and compliance checks flag all of that today.

For most workloads, switch to `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` (TLS 1.3 and 1.2, AEAD ciphers only). If you want to follow AWS's current recommendation, use `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. See [Security policies for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html).

The default depends on how the listener was created. In the console it is `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. With the CLI, CloudFormation, or CDK and no explicit policy, it is still `ELBSecurityPolicy-2016-08`. So the ALBs worth checking are the older ones and anything built from IaC.

## Why 2016-08 Fails Audits

| Item | ELBSecurityPolicy-2016-08 |
|---|---|
| TLS versions | TLS 1.0, 1.1, 1.2 (no 1.3) |
| Cipher suites | 18, including CBC suites such as `AES128-SHA` and `AES256-SHA256` |
| Forward Secrecy | Some suites (such as `AES128-GCM-SHA256` and `AES256-SHA`) use plain RSA key exchange, which has no Forward Secrecy |

> **Forward Secrecy** means that if the server's private key leaks later, traffic recorded in the past still can't be decrypted.
> TLS 1.3 requires key exchange with Forward Secrecy. In TLS 1.2 it depends on the cipher suite picked during the TLS handshake. 2016-08 includes both ECDHE suites and plain RSA suites, so a client can still end up on one without Forward Secrecy.
{: .prompt-info}

PCI DSS and similar standards generally require TLS 1.0/1.1 to be disabled, and CIS benchmarks and cloud compliance scanners (Datadog, Trend Micro Cloud One, and others) check whether listeners use a recent security policy. Each tool applies its own criteria, so check against the standard and version you are actually audited on.

## Choosing a Security Policy

ALB **does not support custom security policies**. You pick from the list AWS provides. These are the usual choices:

| Need | Policy | TLS versions |
|---|---|---|
| General public service, balancing compatibility and security | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` | 1.3, 1.2 |
| Same, plus starting to adopt Post-Quantum TLS (PQ-TLS) | `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09` | 1.3, 1.2 |
| Every client already supports TLS 1.3 | `ELBSecurityPolicy-TLS13-1-3-2021-06` | 1.3 only |
| FIPS 140 validated module required | `ELBSecurityPolicy-TLS13-1-2-Res-FIPS-2023-04` | 1.3, 1.2 |
| CNSA 1.0 / RFC 9151 required | Start with `ELBSecurityPolicy-TLS13-1-2-RFC9151-INTEROP4-FIPS-2023-07` | 1.3, 1.2 |
| Legacy clients that still need CBC | `ELBSecurityPolicy-TLS13-1-2-2021-06`, or the `Ext1`/`Ext2` series | 1.3, 1.2 |

`Res` stands for Restricted. Those policies keep only `TLS_AES_*`, `TLS_CHACHA20_POLY1305_SHA256`, and ECDHE with GCM, seven suites in total and no CBC. `PQ` stands for Post-Quantum, meaning key exchange designed to resist future quantum computers. These policies add hybrid post-quantum key exchange groups such as `X25519MLKEM768` (classic X25519 combined with ML-KEM). Clients that don't support them fall back to classic key exchange, so nothing breaks.

If the audit only asks you to disable TLS 1.0/1.1, `ELBSecurityPolicy-TLS13-1-2-2021-06` does it and keeps more compatibility. If it asks for strong ciphers only, go with a `Res` policy.

## Check Client Compatibility First

The risk in this change is not the setting itself. It is clients still on old TLS versions or old ciphers, which will fail to connect right after the switch. Turn on [connection logs](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-connection-logs.html) to S3 and let them run for a while (long enough to cover month-end jobs and batch cycles). Look at these three fields:

- `tls_protocol`: any `TLSv1` or `TLSv1.1` left?
- `tls_cipher`: any CBC or `AES128-SHA` style suites?
- `tls_keyexchange`: which key exchange is in use

Query the logs with Athena to find the source IPs still using old versions, then notify the owners or retire those clients. The usual suspects are Java 7, old Android versions, embedded devices, and aging monitoring or scanning tools.

## How to Switch

### Console

EC2 → Load Balancers → select the ALB → Listeners and rules → select HTTPS:443 → Manage listener → Edit listener → choose the new policy under Security policy and save.

### AWS CLI

```bash
aws elbv2 modify-listener \
  --listener-arn arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:listener/app/my-alb/xxxxxxxx/yyyyyyyy \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

To see which policies exist and what each one supports:

```bash
# List only the policies that support TLS 1.3
aws elbv2 describe-ssl-policies \
  --query "SslPolicies[?contains(SslProtocols,'TLSv1.3')].Name"

# Show the cipher suites of one policy
aws elbv2 describe-ssl-policies \
  --names ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

### Terraform

Don't assume `aws_lb_listener` picks a modern policy when `ssl_policy` is missing. Set it explicitly:

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

Changing the security policy doesn't require recreating the ALB, and existing connections are not dropped. The new policy applies to TLS handshakes that start after the change.

## Verify the Change

Use `openssl` to confirm that old versions are rejected and new ones work:

```bash
# Should fail: TLS 1.1
openssl s_client -connect example.com:443 -tls1_1 </dev/null

# Should succeed: TLS 1.2
openssl s_client -connect example.com:443 -tls1_2 </dev/null

# Should succeed: TLS 1.3
openssl s_client -connect example.com:443 -tls1_3 </dev/null
```

For audit evidence, `nmap` can list the versions and ciphers the endpoint actually accepts:

```bash
nmap --script ssl-enum-ciphers -p 443 example.com
```

Rescanning with SSL Labs or your internal vulnerability scanner and keeping the report works too.

## Multiple Listeners and Backend Connections

- If an ALB has several HTTPS listeners, their security policies have to be compatible with each other. You can't mix them freely.
- You **can't choose** the policy for the connection from the ALB to your targets. It follows from the front-end listener policy. For example, with a TLS 1.3 family policy on the listener, the backend side uses `ELBSecurityPolicy-TLS13-1-0-2021-06`. If your targets speak HTTPS, make sure they support those versions and ciphers.
- If CloudFront, WAF, or another CDN sits in front of the ALB, each layer has its own TLS settings and needs its own check. CloudFront's minimum TLS version is set in the distribution's security policy.
- NLB has its own policy list with different defaults. Don't copy ALB settings over to an NLB.

## Keep It from Regressing

Auditors look at the current state, and also at whether something prevents it from getting worse. Some options:

1. **Be explicit in IaC**: set `ssl_policy` on every listener and don't rely on defaults.
2. **AWS Config**: use a managed or custom rule to keep checking listener policies.
3. **IAM / SCP conditions**: Elastic Load Balancing provides condition keys that limit which security policies users can select. See the [ELB IAM documentation](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-authentication-access-control.html) for the key names and syntax.
4. **Review regularly**: AWS keeps adding policies, such as the PQ series in 2025, so a yearly review makes sense.

## FAQ

### Does switching the security policy cause downtime?

No. The ALB isn't recreated and established connections are unaffected. Only new connections are negotiated under the new policy, so the real risk is old clients that can no longer connect. Watch the connection logs beforehand to catch them.

### I only need to disable TLS 1.0/1.1. Which policy?

`ELBSecurityPolicy-TLS13-1-2-2021-06`. It supports TLS 1.3 and 1.2 and is more compatible than the `Res` series. If the audit also forbids CBC, move to a `Res` policy.

> In my own environments I use both **ELBSecurityPolicy-TLS-1-2-2017-01** and **ELBSecurityPolicy-TLS13-1-2-Res-2021-06**.
{: .prompt-info}

### Can I enable TLS 1.3 only?

Yes, with `ELBSecurityPolicy-TLS13-1-3-2021-06`. It only makes sense when you are sure every client supports TLS 1.3. Public-facing services usually keep TLS 1.2.

### Do PQ policies require client changes?

No. PQ policies still support classic key exchange. Clients that support ML-KEM get hybrid post-quantum key exchange, and everyone else behaves as before.

### Why does my scanner still report old TLS versions after the switch?

Check that the scan is hitting the same listener or domain, and whether CloudFront or another proxy sits in front. Also confirm that the listener's policy was actually applied. SSL Labs can serve cached results, so tick the option to clear the cache when you rescan.
