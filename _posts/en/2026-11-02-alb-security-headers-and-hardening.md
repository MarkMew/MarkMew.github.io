---
layout: post
title: "Fixing 7 Common Web Scanner Findings with ALB Settings, Without Touching Your Backend"
description: "How to address seven common scanner findings (HTTP Request Smuggling, invalid headers, weak cipher suites, HSTS, X-Content-Type-Options, X-Frame-Options, and CSP) using ALB attributes, listener attributes, and security policies, with AWS CLI, Terraform, and verification steps."
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, Security, HTTP, TLS, Terraform]
keywords: [ALB desync mitigation mode, ALB drop invalid header fields, ALB HSTS, ALB X-Frame-Options, ALB Content-Security-Policy, ALB listener attributes, ALB response header, ALB security headers Terraform]
lang: en
date: 2026-11-02
---

**Several common findings in vulnerability scan reports can be addressed by changing ALB settings, with no changes to your backend code.** That includes HTTP Request Smuggling, invalid HTTP headers, weak cipher suites, and missing HSTS, `X-Content-Type-Options`, `X-Frame-Options`, and `Content-Security-Policy` response headers. These settings only reduce risk, though. They don't replace secure application design, and CSP in particular can't be handled with one generic value. See [HTTP header modification for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html).

I covered TLS in the previous post, [Upgrading ALB Security Policies](/en/posts/alb-security-policy-upgrade-from-2016-08/), so this post only summarizes the cipher suite section. The other six items focus on ALB settings, with both AWS CLI and Terraform examples.

## Where the ALB Sits in Your Architecture

The ALB is the termination point between clients and your backend. It parses the client's HTTP request before forwarding it to a target, terminates TLS, and sends the response back to the client. Because it handles all three, you can adjust how requests are parsed, which TLS policy applies, and which headers appear in responses at this layer.

The three kinds of settings live at different levels, so it's worth keeping them apart:

| Level | Where it's set | Used in this post |
|---|---|---|
| Load balancer attribute | The whole ALB | `routing.http.desync_mitigation_mode`, `routing.http.drop_invalid_header_fields.enabled` |
| Listener | Security policy of an HTTPS listener | `ssl-policy` |
| Listener attribute | A single listener | `routing.http.response.*.header_value` (HSTS, X-Content-Type-Options, X-Frame-Options, CSP) |

The four response headers are **listener attributes**. They're set on each listener individually, not on the load balancer. Header modification is off by default and has to be enabled per listener.

## Summary

| Scanner finding | ALB setting | Level | Recommended value | Still needs help from |
|---|---|---|---|---|
| HTTP Request Smuggling | `routing.http.desync_mitigation_mode` | Load balancer | `defensive` (default) or `strictest` | Backend web server's HTTP parsing, WAF |
| Invalid HTTP Headers | `routing.http.drop_invalid_header_fields.enabled` | Load balancer | `true` | Backend handling of other non-compliant requests |
| Weak SSL Cipher Suites | Security policy | Listener | `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` | CloudFront or other proxies in front of the ALB, HTTPS from ALB to targets |
| Missing HSTS | `routing.http.response.strict_transport_security.header_value` | Listener attribute | `max-age=31536000` | HTTPS working across the whole site |
| Missing X-Content-Type-Options | `routing.http.response.x_content_type_options.header_value` | Listener attribute | `nosniff` | Backend still needs to send the correct `Content-Type` |
| Missing X-Frame-Options | `routing.http.response.x_frame_options.header_value` | Listener attribute | `SAMEORIGIN` or `DENY` | Use CSP `frame-ancestors` if embedding is needed |
| Missing CSP | `routing.http.response.content_security_policy.header_value` | Listener attribute | Tailor to your site's resources | Output encoding and resource management in the application |

## 1. HTTP Request Smuggling

HTTP Request Smuggling (also called HTTP desync) happens when a front-end proxy and a back-end web server disagree about where one request ends and the next begins. For example, a request with multiple `Content-Length` headers, or with both `Content-Length` and `Transfer-Encoding`, may be read as a different number of requests by each layer. An attacker can use that to slip an extra request into the same connection.

The ALB's **desync mitigation mode** classifies each request by threat level and then handles it according to the mode you choose:

| Classification | Description | `monitor` | `defensive` | `strictest` |
|---|---|---|---|---|
| Compliant | Complies with RFC 7230, no known threat | Allowed | Allowed | Allowed |
| Acceptable | Doesn't comply with RFC 7230, but no known threat | Allowed | Allowed | Blocked |
| Ambiguous | Doesn't comply with RFC 7230, and different web servers or proxies may handle it differently | Allowed | Allowed, but the client and target connections are closed | Blocked |
| Severe | High security risk | Allowed | Blocked | Blocked |

Blocked requests get a 400 response and the client connection is closed. See [Desync mitigation mode](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html).

A few practical points:

- **The default is already `defensive`**, so most ALBs don't need any change. Still, writing it explicitly in IaC keeps it from being changed later without anyone noticing.
- `monitor` doesn't block anything, so it's only useful for observation. Non-compliant requests increment the `DesyncMitigationMode_NonCompliant_Request_Count` CloudWatch metric, and the access log records each request's classification.
- `strictest` only lets RFC 7230-compliant requests through. Older clients or unusual tools that send Acceptable-level requests will be rejected, so check the access logs under `monitor` or `defensive` first and confirm there's no non-compliant traffic before switching.
- In `defensive` mode, a large number of Ambiguous requests can incur additional charges. See the AWS documentation above for details.

> This setting reduces the risk of desync at the ALB layer. It doesn't mean your backend web server's HTTP parsing is safe. The AWS documentation doesn't list which specific attack variants the ALB covers, so I won't describe this as a complete fix.
{: .prompt-warning}

## 2. Invalid HTTP Headers

HTTP header field names have format rules. Elastic Load Balancing requires header names to contain only alphanumeric characters and hyphens (`-`). If a name contains underscores, spaces, or other characters, different proxies and web servers handle it differently: some ignore it, others normalize it and forward it. That inconsistency can be abused to bypass checks.

When `routing.http.drop_invalid_header_fields.enabled` is `true`, the ALB removes headers whose names are invalid. The default is `false`, meaning those headers are forwarded to targets as usual. See [modify-load-balancer-attributes](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-load-balancer-attributes.html).

Keep the scope of this setting in mind:

- It only deals with **invalid header field names**. It does not cover every request that violates the HTTP spec. Malformed requests in general, such as the conflicting `Content-Length` case from the previous section, are handled by desync mitigation.
- After you enable it, any existing client or internal system that sends names with underscores (for example, a custom `X_Api_Key`) will have those headers dropped by the ALB, and your backend may stop receiving them. Check what header names your clients actually send before you enable it.

These two settings are often mentioned together, but they address different problems, so I recommend enabling both.

## 3. Weak SSL Cipher Suites

The TLS versions and cipher suites on an ALB are determined by the HTTPS listener's security policy. You can't customize them, only pick from the list AWS provides. Scanners most often flag TLS 1.0, TLS 1.1, CBC cipher suites, and RSA key exchange without forward secrecy. TLS 1.3 keeps only AEAD ciphers and requires key exchange with forward secrecy.

For most modern web systems, `ELBSecurityPolicy-TLS13-1-2-Res-2021-06` is a good choice. It supports TLS 1.3 and 1.2, excludes TLS 1.0/1.1, and has no CBC cipher suites. AWS currently recommends the PQ policy `ELBSecurityPolicy-TLS13-1-2-Res-PQ-2025-09`. For choosing between them, checking client compatibility, and the full switching procedure, see the [previous post](/en/posts/alb-security-policy-upgrade-from-2016-08/). See also [Security policies for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html).

This setting only affects the segment between the client and the ALB. The TLS settings of CloudFront, other CDNs, or proxies have to be checked separately.

## 4. Missing HSTS Header

HSTS (HTTP Strict Transport Security) is a response header that tells the browser a site should only be accessed over HTTPS. For the duration of `max-age`, even if a user types `http://` or follows an old HTTP link, the browser switches to HTTPS on its own without sending an HTTP request first. That reduces the risk of HTTPS downgrade and SSL stripping attacks.

| Directive | Description |
|---|---|
| `max-age=<seconds>` | How long the browser remembers to use HTTPS only |
| `includeSubDomains` | Applies the policy to all subdomains as well |
| `preload` | Requests inclusion in the browsers' built-in HSTS preload list. Requires `max-age` of at least `31536000` and `includeSubDomains` |

See [Strict-Transport-Security — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security).

Before rolling it out, confirm the following:

- **The whole site works over HTTPS** (including subdomains, if you add `includeSubDomains`). Once a browser has remembered the policy, users can't click through a warning if the certificate expires or HTTPS breaks.
- HSTS only takes effect on HTTPS responses. Browsers ignore this header on HTTP responses.
- Once a domain is on the `preload` list, removing it is difficult. Don't add `preload` until you've inventoried all subdomains.

In production, increase `max-age` gradually. For example:

| Stage | Value |
|---|---|
| 1 | `max-age=300` (5 minutes) |
| 2 | `max-age=86400` (1 day) |
| 3 | `max-age=604800` (1 week) |
| 4 | `max-age=31536000` (1 year) |

Watch for problems at each stage before moving to the next. If the backend already sends the same header, the ALB **overwrites** it with the configured value once enabled, so you won't end up with duplicate HSTS headers.

> The Terraform documentation for `routing_http_response_strict_transport_security_header_value` mentions a default of `max-age=31536000; includeSubDomains; preload`, but doesn't say when that default applies. **This needs to be confirmed.** Don't rely on it; set the value you want explicitly.
{: .prompt-warning}

## 5. Missing X-Content-Type-Options

When the `Content-Type` doesn't match the actual content, some browsers try to guess the content type on their own. This is called MIME type sniffing. For example, if a server labels a user-uploaded file as `text/plain` and the browser decides it looks like HTML or JavaScript, it may treat the file as executable content, which can be exploited.

`X-Content-Type-Options: nosniff` tells the browser to follow the `Content-Type` and not guess. The ALB attribute only accepts `nosniff`.

This is the lowest-risk setting of the seven. The one prerequisite is that your backend sends the correct `Content-Type`. Otherwise, JS or CSS files that only loaded because the browser guessed correctly will start being rejected. This header reduces the risk of MIME confusion. It is not a setting that prevents XSS.

## 6. Missing X-Frame-Options

In clickjacking, an attacker embeds the target site in an `iframe` on their own page and overlays it with a transparent layer to trick users into clicking. Users think they're interacting with the attacker's page, but they're actually clicking buttons on the target site.

`X-Frame-Options` controls whether a page may be embedded:

| Value | Description |
|---|---|
| `DENY` | No site can embed the page, including the same origin |
| `SAMEORIGIN` | Only pages from the same origin can embed it |
| `ALLOW-FROM <origin>` | Obsolete. Modern browsers ignore the entire header |

See [X-Frame-Options — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options).

The Terraform field description lists `ALLOW-FROM`, but since modern browsers ignore it, **I don't recommend using it**.

This setting doesn't suit every site:

- If other domains embed your site in an iframe (for example, a widget you provide to partners), both `DENY` and `SAMEORIGIN` will break the embedding. Use CSP `frame-ancestors` instead and specify which origins may embed the page.
- If your site embeds its own pages in same-origin iframes (for example, an admin console that loads reports in an iframe), use `SAMEORIGIN`.
- The ALB attribute takes a single value, and **all paths share it**. If you need different values per path, handle it in the backend.

MDN recommends `frame-ancestors`, a CSP directive, as the replacement for `X-Frame-Options`. It can list multiple sources, so it's more flexible. Neither MDN page says which takes precedence when both are present, so if you need to set both, test it in your own browsers to confirm.

## 7. Missing Content-Security-Policy

CSP lets a site tell the browser which sources it may load and execute resources from. It can reduce the impact of a successful XSS and limit loading of malicious resources, but **it's defense in depth, not a fix for XSS**. The application still needs proper output encoding and input validation.

Common directives:

| Directive | Purpose |
|---|---|
| `default-src` | Default source for resource types not listed separately |
| `script-src` | Sources for JavaScript |
| `style-src` | Sources for CSS |
| `img-src` | Sources for images |
| `connect-src` | Targets that `fetch`, XHR, and WebSocket can connect to |
| `frame-ancestors` | Which sources may embed this page in an iframe |
| `object-src` | Sources for `<object>` and `<embed>` |
| `base-uri` | URLs that the `<base>` element may use |

There is **no universal CSP**, because every site loads different resources. The CDNs, Google Analytics, font services, inline scripts, and third-party sign-in you use all have to be listed. If the policy is too strict, images disappear, styles break, and third-party sign-in or payment components stop working. If it's too loose (for example, lots of `'unsafe-inline'`), it protects very little.

### Testing Gradually with Report-Only

The usual approach is to start with `Content-Security-Policy-Report-Only`, which reports violations without blocking anything. Collect reports for a while, then turn it into the enforced policy.

> **The ALB has no listener attribute for `Content-Security-Policy-Report-Only`.** I checked the AWS header modification documentation, and the only CSP response header attribute listed is `content_security_policy`, with no Report-Only version. To test with Report-Only, you have to send that header from your backend application or web server. Alternatively, apply the ALB setting in a test environment first, and move it to production once you're confident.
{: .prompt-warning}

Also, the documentation doesn't say whether the ALB's `content_security_policy` attribute supports directives such as `report-to`, and header values have character restrictions (see the notes below). If you want to use reporting, confirm it in a test environment first.

### A Demo-Only CSP

The policy below is only an example. **Don't use it in production as is.** It must be adjusted to your site's actual resources:

```text
default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'
```

This policy only allows same-origin loading. Inline scripts and inline styles will be blocked, so pages that use them will break.

## Hands-On Setup

### Console

**Load balancer attributes** (desync mitigation mode, drop invalid header fields):

EC2 → Load Balancers → select the ALB → Attributes → Edit → set Desync mitigation mode and Drop invalid header fields under **Packet handling** → Save changes.

**Security policy**:

EC2 → Load Balancers → select the ALB → Listeners and rules → select HTTPS:443 → Manage listener → Edit listener → Security policy.

**Listener attributes** (response headers):

EC2 → Load Balancers → select the ALB → Listeners and rules → open the listener → Attributes → Edit → expand **Add response headers**, enable the headers you want, and enter their values → Save changes.

### AWS CLI

Load balancer attributes:

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN> \
  --attributes \
    Key=routing.http.desync_mitigation_mode,Value=defensive \
    Key=routing.http.drop_invalid_header_fields.enabled,Value=true
```

Security policy:

```bash
aws elbv2 modify-listener \
  --listener-arn <LISTENER_ARN> \
  --ssl-policy ELBSecurityPolicy-TLS13-1-2-Res-2021-06
```

Listener attributes. The CSP value contains spaces and semicolons, so JSON is less error-prone:

```bash
aws elbv2 modify-listener-attributes \
  --listener-arn <LISTENER_ARN> \
  --attributes '[
    {"Key":"routing.http.response.strict_transport_security.header_value","Value":"max-age=31536000"},
    {"Key":"routing.http.response.x_content_type_options.header_value","Value":"nosniff"},
    {"Key":"routing.http.response.x_frame_options.header_value","Value":"SAMEORIGIN"},
    {"Key":"routing.http.response.content_security_policy.header_value","Value":"default-src '\''self'\''; img-src '\''self'\'' data:; script-src '\''self'\''; style-src '\''self'\''; object-src '\''none'\''; base-uri '\''self'\''; frame-ancestors '\''self'\''"}
  ]'
```

> The CSP value contains single quotes, which have to be written as `'\''` inside a single-quoted Bash string. That's hard to read. If you'd rather avoid it, save the JSON to a file and pass it with `--attributes file://listener-attributes.json`.
{: .prompt-info}

### Terraform

Load balancer attributes are set on `aws_lb`. Listener attributes are plain arguments of `aws_lb_listener`, not separate blocks:

```terraform
resource "aws_lb" "main" {
  name               = "my-alb"
  load_balancer_type = "application"
  subnets            = var.public_subnet_ids
  security_groups    = [aws_security_group.alb.id]

  desync_mitigation_mode     = "defensive"
  drop_invalid_header_fields = true
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-Res-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  routing_http_response_strict_transport_security_header_value = "max-age=31536000"
  routing_http_response_x_content_type_options_header_value    = "nosniff"
  routing_http_response_x_frame_options_header_value           = "SAMEORIGIN"
  routing_http_response_content_security_policy_header_value   = "default-src 'self'; img-src 'self' data:; script-src 'self'; style-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}
```

I confirmed these field names against the `aws_lb_listener` documentation in `hashicorp/terraform-provider-aws`. **I couldn't find which provider version first supports them, so that needs to be confirmed.** If `terraform validate` reports that these arguments aren't recognized, upgrade the provider first.

## Verification

### AWS CLI

```bash
# Load balancer attributes
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <ALB_ARN> \
  --query "Attributes[?Key=='routing.http.desync_mitigation_mode' || Key=='routing.http.drop_invalid_header_fields.enabled']"

# Listener attributes
aws elbv2 describe-listener-attributes \
  --listener-arn <LISTENER_ARN>

# Security policy
aws elbv2 describe-listeners \
  --listener-arns <LISTENER_ARN> \
  --query "Listeners[0].SslPolicy"
```

### Checking Response Headers

```bash
curl -sI https://example.com
```

You should see:

```text
strict-transport-security: max-age=31536000
x-content-type-options: nosniff
x-frame-options: SAMEORIGIN
content-security-policy: default-src 'self'; ...
```

In the browser, open Developer Tools → Network → select any request → Headers to check the response headers. If your CSP is too strict, violations show up in the Console tab.

### Checking TLS

```bash
# Should fail: TLS 1.1
openssl s_client -connect example.com:443 -tls1_1 </dev/null

# Should succeed: TLS 1.2 and 1.3
openssl s_client -connect example.com:443 -tls1_2 </dev/null
openssl s_client -connect example.com:443 -tls1_3 </dev/null
```

To list every supported cipher suite, use `nmap --script ssl-enum-ciphers -p 443 example.com` or SSL Labs.

### What Simple Tools Can Verify

| Setting | `describe-*` | `curl -I` | `openssl` | Other |
|---|---|---|---|---|
| Desync mitigation | Confirms the value | No | No | Access log classification and CloudWatch metric, or a dedicated security testing tool |
| Drop invalid header | Confirms the value | Not suitable | No | Send a request with an invalid header name and check whether the backend receives it |
| Security policy | Confirms the policy name | No | Yes | `nmap`, SSL Labs |
| HSTS, nosniff, XFO, CSP | Confirms the value | Yes | No | Browser Developer Tools |

Verifying Request Smuggling for real means crafting requests by hand and comparing how each layer parses them. `curl -I` can't do that. Use an appropriate security testing tool, and only against environments you're authorized to test.

## Notes and Limitations

- **Distinguish scanner findings, configuration gaps, and actual exploitability.** A missing header is a configuration gap, not proof the site can be attacked. Likewise, adding a header doesn't mean a vulnerability is fixed.
- **Header value restrictions**: values can contain only alphanumeric characters and a specific set of symbols, and can't exceed 1K bytes. The ALB only does basic format validation and doesn't check whether the value makes sense for that header, so a wrong value won't be rejected. Setting an empty value reverts to the default behavior. See [Limitations of header modification](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html).
- **Backend already sends the same header**: the ALB overwrites it with the configured value. If some paths need different values (for example, a different `X-Frame-Options` per page), a single ALB setting can't handle that.
- **Responses generated by the ALB itself** (such as fixed responses or 5xx error pages): I couldn't find anything in the official documentation about whether these headers are added, so this **needs to be confirmed**.
- **HTTP listeners**: the documentation doesn't say clearly whether the response header attributes apply only to HTTPS. Browsers ignore HSTS on HTTP responses, so in practice you only need to set it on the HTTPS listener.
- **ALB settings don't replace secure application design or AWS WAF.** SQL injection, XSS, and access control problems still have to be handled by the application and WAF.
- **Be explicit in IaC.** The default for desync mitigation is `defensive`, but `drop_invalid_header_fields` defaults to `false`, and the security policy default for the CLI and CloudFormation is still the old `ELBSecurityPolicy-2016-08`. Don't rely on defaults.

## FAQ

### Will these changes drop existing connections?

Load balancer attribute and listener attribute changes apply to new requests. The real risk is compatibility: `strictest` may block non-compliant clients, dropping invalid headers may remove custom headers, CSP may break page functionality, and with HSTS, a bad setting is remembered by browsers for a while.

### Can ALB settings alone get me through a vulnerability scan?

Not necessarily. Scanners use different criteria, and some items (for example, whether a CSP is too permissive) depend on your site's resources. The ALB can handle part of the list, and the rest still depends on the backend and WAF.

### Why not just set the strictest possible CSP?

The strictest CSP blocks inline scripts, third-party resources, and `eval`. Applying it without first taking stock of the resources your site uses will easily break pages. Collect violations in a test environment first, then tighten it step by step.

## Conclusion

Of the seven items, desync mitigation, invalid header dropping, and the security policy are ALB-level settings, while HSTS, `X-Content-Type-Options`, `X-Frame-Options`, and CSP are response headers the ALB helps you add. `nosniff` carries the least risk, HSTS needs `max-age` raised gradually, `X-Frame-Options` depends on whether you use iframes, and CSP always has to be tailored to your site's resources and tested with Report-Only somewhere other than the ALB.

ALB settings are a supplement, not a substitute. The backend's HTTP parsing, the application's security design, and the WAF all remain part of the overall defense.

## References

- [HTTP header modification for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/header-modification.html): Response header attributes, value restrictions, and overwrite behavior.
- [Enable HTTP header modification](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/enable-header-modification.html): Console steps and the list of header modification attributes.
- [Edit load balancer attributes](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/edit-load-balancer-attributes.html): Desync mitigation mode classifications and behavior of each mode.
- [modify-load-balancer-attributes — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-load-balancer-attributes.html): Attribute descriptions including `drop_invalid_header_fields`.
- [modify-listener-attributes — AWS CLI](https://docs.aws.amazon.com/cli/latest/reference/elbv2/modify-listener-attributes.html): CLI syntax for listener attributes.
- [Security policies for your Application Load Balancer](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/describe-ssl-policies.html): Security policies supported by the ALB.
- [HTTP Request Smuggling on AWS — Virtue Security](https://www.virtuesecurity.com/kb/http-request-smuggling-aws/): Third-party explanation of the ALB invalid header setting (2022 article).
- [Strict-Transport-Security — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Strict-Transport-Security): HSTS directives and preload requirements.
- [X-Frame-Options — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/X-Frame-Options): Accepted values and the relationship with `frame-ancestors`.
- [Content Security Policy — MDN](https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/CSP): CSP and how to use Report-Only.
- [aws_lb_listener — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener): Terraform listener arguments.
- [aws_lb — Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb): Terraform `desync_mitigation_mode` and `drop_invalid_header_fields`.
