---
layout: post
title: "AWS Application Load Balancer Settings That Are Easy to Miss"
description: "A practical guide to Application Load Balancer settings that are easy to overlook, including WAF fail open, HTTP/2, idle timeout, X-Forwarded-For, Host header handling, TLS headers, listener attributes, rules, and response security headers."
author: Mark_Mew
categories: [AWS, ALB]
tags: [AWS, ALB, Load Balancer, WAF, HTTP, Security]
keywords: [AWS, ALB, AWS ALB, Application Load Balancer, WAF, HTTP/2, X-Forwarded-For, HSTS, CSP]
lang: en
date: 2026-07-01
---

When people first start using AWS Application Load Balancer (ALB), they usually focus on a few things:

1. Whether the ALB is internet-facing or internal
2. Whether the listener should use `80` or `443`
3. Whether the target group should point to EC2, IP targets, Lambda, or Kubernetes services
4. How to configure the health check path
5. Whether the Security Group is correct

These are all important.

But the more interesting parts of ALB often live in the attributes and rule settings that you see after the load balancer is created.

Some settings affect security.

Some change the request headers that your backend receives.

Some affect WebSocket, long-lived connections, and HTTP/2.

Others only become visible when you integrate ALB with WAF, Global Accelerator, OIDC, or mTLS.

This article organizes the ALB settings that are easy to overlook but important to understand in real systems.

## ALB, NLB, and GLB

Before going into the settings, it is useful to separate the major load balancer types.

| Type | Layer | Common use case |
| --- | --- | --- |
| Application Load Balancer | Layer 7 | HTTP, HTTPS, path routing, host routing, OIDC authentication, header handling |
| Network Load Balancer | Layer 4 | TCP, UDP, TLS passthrough, very low latency, static IPs, preserving source IP |
| Gateway Load Balancer | Layer 3 / 4 | Routing traffic through firewalls, IDS/IPS, packet inspection, or other network security appliances |

If your application is a website, API, or internal web system, and you need routing based on Host, Path, or Header, ALB is usually the right choice.

If you are handling non-HTTP protocols, or you want TLS to pass through to the backend without being terminated by the load balancer, the use case is closer to NLB.

If the goal is to inspect traffic through a network security layer, such as a firewall, intrusion detection system, intrusion prevention system, packet inspection appliance, or third-party security appliance, the use case is closer to GLB, or Gateway Load Balancer.

GLB is not for normal website Host or Path routing. It is closer to a transparent way to insert and scale network inspection appliances in the traffic path, without making each appliance a single bottleneck.

The rest of this article focuses on ALB.

## Start with the ALB Configuration Layers

If you expand every ALB setting at once, it quickly becomes a long list of disconnected checkboxes.

A clearer way is to think in layers:

| Layer | Main responsibility |
| --- | --- |
| Load Balancer | ALB-level attributes, overall connection behavior, WAF, access logs, HTTP header handling |
| Listener | The port, protocol, TLS policy, certificate, and listener attributes that receive traffic |
| Rule | The conditions that match a request and the actions to perform |
| Target Group | Backend services, health checks, protocol version, load distribution, and stickiness |

The rest of this article follows that order.

We start with load balancer attributes, then listener attributes, then listener rules, and finally target group considerations and IaC examples.

## Load Balancer Layer

Load Balancer level settings affect the ALB as a whole.

At this layer, I usually split the settings into two categories:

1. Traffic configuration: traffic entry behavior, WAF fail open, and client-to-ALB connection behavior
2. Packet handling: how ALB handles requests, headers, and forwarded information

### Traffic Configuration

This category affects how traffic enters ALB and how clients connect to ALB.

The common settings to check together are Global Accelerator, WAF fail open, HTTP/2, idle timeout, and client keepalive.

> Global Accelerator is not a required companion to ALB.
> Consider it when you need fixed Anycast IP addresses, cross-Region or multi-endpoint traffic shifting, or a global entry point.
> For a normal single-Region website or API, a Route 53 alias record pointing to ALB is usually enough.
{: .prompt-info}

#### Whether to Enable WAF Fail Open

If your ALB is associated with AWS WAF, you will see a setting named `waf.fail_open.enabled`.

This setting asks a direct question:

If ALB cannot forward a request to AWS WAF for inspection, should ALB still route the request to the target?

| Value | Behavior | Priority |
| --- | --- | --- |
| `false` | Do not route the request if WAF inspection cannot happen | Security first |
| `true` | Still route the request to the target | Availability first |

The default is `false`.

This means that if the WAF inspection path has a problem, ALB prefers not to send unchecked traffic to the backend.

For public websites, login entry points, admin portals, and payment flows, keeping the default is usually the safer choice.

You might consider fail open only when the service is strongly availability-oriented, such as an internal API or a non-sensitive read-only service, and you can accept a short period where requests are not inspected by WAF.

There is no universal answer, but avoid enabling fail open just because it sounds like a way to avoid outages.

This setting is fundamentally a tradeoff between security and availability.

#### HTTP/2 Is Enabled by Default

ALB supports HTTP/2, and `routing.http2.enabled` defaults to `true`.

This means clients can use HTTP/2 when connecting to ALB, while HTTP/1.1 is still supported.

The important detail is that this setting describes the frontend connection, which means the client-to-ALB connection.

The protocol version used between ALB and the target group is controlled separately by the target group protocol version.

For most websites and APIs, you can leave HTTP/2 enabled.

HTTP/2 allows multiple requests over the same connection, reducing the need for clients to create many separate connections.

You usually consider disabling it only when you have very old clients, proxies, or special devices that are not compatible with HTTP/2 behavior.

#### Connection Idle Timeout Is Not Request Timeout

The default value of `idle_timeout.timeout_seconds` is `60` seconds.

This setting is often misunderstood.

It does not mean "the backend can process a request for at most 60 seconds."

More precisely, if a connection has no data transfer for the configured period, ALB closes the idle connection.

Common cases where idle timeout matters include:

1. WebSocket
2. Server-Sent Events
3. Long polling
4. Large file uploads or downloads
5. APIs where the backend takes a long time before sending the first response bytes

For normal APIs, 60 seconds is usually enough.

If you use WebSocket or streaming responses, you may need to increase it to values such as `120`, `300`, or higher.

But increasing the timeout is not free.

Longer-lived connections mean ALB and the backend must keep more connection state.

A better design is often to make the application send heartbeat or keep-alive data periodically, instead of only increasing the timeout.

#### Client Keepalive Is Different from Idle Timeout

In addition to idle timeout, ALB also has `client_keep_alive.seconds`.

The default value is `3600` seconds.

This setting controls how long ALB is willing to maintain an HTTP client keepalive connection.

Idle timeout asks: has there been any data during this time window?

Client keepalive asks: how long can this client connection be kept at most?

This becomes more relevant during blue-green deployments, IP address type changes, or situations where you do not want clients to stay on old connections for too long.

In most environments, you do not need to change it immediately.

Just remember that it is a different dimension from idle timeout.

### Packet Handling

This category affects how ALB handles request packets, HTTP headers, forwarded information, and what information is sent to the backend.

If you are building a security baseline or troubleshooting what your backend sees in requests, these settings are usually reviewed together.

#### Desync Mitigation Mode

ALB has a setting named `routing.http.desync_mitigation_mode`.

It controls how ALB handles requests that might pose HTTP desync or request smuggling risks.

There are three possible modes:

| Mode | Description |
| --- | --- |
| `monitor` | Monitor only, without actively blocking |
| `defensive` | Default mode, balancing compatibility and protection |
| `strictest` | Most strict, may block more non-standard requests |

For most production environments, `defensive` is a reasonable default.

If you are building a stricter security baseline and your applications and clients are controlled, you can evaluate `strictest`.

But if your clients are diverse, such as old devices, old SDKs, or customer-managed proxies, do not jump straight to the strictest mode.

A safer approach is to review ALB access logs and application logs first, and confirm whether any non-standard requests would be affected.

#### Drop Invalid Header Fields

`routing.http.drop_invalid_header_fields.enabled` controls whether ALB removes invalid HTTP header fields.

The default is `false`.

If enabled, ALB removes headers that do not conform to valid header field rules and sends only valid headers to the backend.

This setting is related to desync mitigation because both deal with request format safety.

If your backend framework, proxy, or application server handles unusual headers differently, inconsistent parsing between layers can become a risk.

For new systems, I tend to evaluate enabling it.

For legacy systems, first confirm whether any clients actually send non-standard headers, so you do not break integrations unexpectedly.

#### Preserve Host Header

`routing.http.preserve_host_header.enabled` controls whether ALB preserves the original `Host` header.

The default is `false`.

This setting affects the Host value that the backend application sees.

It matters when your application needs the original Host, for example:

1. A multi-tenant system maps tenants by domain
2. The application needs to generate complete callback URLs
3. The backend framework uses Host to determine the canonical URL
4. One target group serves multiple domains

Sometimes people see an unexpected Host value in the application and start changing Nginx or application settings, while the real cause is that ALB already changed it.

If the backend must know the original domain, you typically combine:

1. Enabling preserve host header
2. Configuring the application to trust proxy headers correctly
3. Ensuring the backend can only be reached through ALB

The third point is important.

If the backend can be reached directly from outside, anyone can forge Host or forwarded headers, and the application should not treat those headers as trusted.

#### X-Forwarded-For: Append, Preserve, or Remove

ALB handles the `X-Forwarded-For` header so the backend can know the original client IP.

The related setting is `routing.http.xff_header_processing.mode`.

It has three possible values:

| Mode | Behavior | Common use |
| --- | --- | --- |
| `append` | Add the client IP to the existing `X-Forwarded-For` header | Default, most common |
| `preserve` | Keep the original header unchanged | A trusted proxy in front already handles it |
| `remove` | Remove the `X-Forwarded-For` header | You do not want the backend to use source-chain information |

The default is `append`.

This is usually the most intuitive behavior.

If a request has no `X-Forwarded-For` header, ALB adds the client IP.

If the request already passed through another proxy before reaching ALB, ALB appends the previous-hop client IP that it sees.

But there is an important security point:

`X-Forwarded-For` is just an HTTP header, and clients can send it themselves.

If your backend blindly trusts the first IP and the request is not guaranteed to come only from trusted proxies, the source IP can be forged.

A safer approach is:

1. Allow the backend to be reached only by ALB
2. Configure the application with an explicit trusted proxy range
3. Parse the real client IP from the trusted proxy chain

Do not simply treat the first value in `X-Forwarded-For` as the real user IP.

#### X-Forwarded-For Client Port

`routing.http.xff_client_port.enabled` controls whether ALB includes the client's source port in `X-Forwarded-For`.

The default is `false`.

Most applications do not need the client source port.

Possible use cases include:

1. Detailed network troubleshooting
2. Correlating logs with other network devices
3. Specific audit requirements

If there is no clear requirement, keep it disabled.

Many backend frameworks, log parsers, and SIEM rules expect `X-Forwarded-For` to contain a list of IP addresses.

Adding ports can require parser changes.

#### TLS Version and Cipher Suite Headers

If your ALB listener uses HTTPS, you can enable `routing.http.x_amzn_tls_version_and_cipher_suite.enabled`.

When enabled, ALB adds the TLS version and cipher suite negotiated between the client and ALB to request headers before sending the request to the backend.

Common headers are:

1. `x-amzn-tls-version`
2. `x-amzn-tls-cipher-suite`

This is useful for debugging and security auditing.

For example, you can check whether any clients still use old TLS versions, or preserve TLS negotiation information in backend logs.

Remember that these headers are added by ALB.

The backend should still be reachable only through ALB.

If the backend can be reached directly, outside clients can forge these headers as well.

## Listener Layer

Listener level settings affect a specific port and protocol entry point.

For example, a `443` listener includes HTTPS, certificates, and TLS policy, while an `80` listener is often used to redirect traffic to HTTPS.

Besides its basic configuration, a listener also has listener attributes.

These attributes commonly fall into two categories:

1. Which header names ALB uses when passing TLS or mTLS information to the backend
2. Whether ALB adds or overwrites response headers before sending the response back to the client

### TLS and mTLS Request Header Attributes

#### Listener Attributes Can Rename TLS and mTLS Headers

In listener attributes, you may see several `X-Amzn-*` header name settings, such as:

1. `X-Amzn-Tls-Version`
2. `X-Amzn-Tls-Cipher-Suite`
3. `X-Amzn-Mtls-Clientcert`
4. `X-Amzn-Mtls-Clientcert-Subject`
5. `X-Amzn-Mtls-Clientcert-Issuer`
6. `X-Amzn-Mtls-Clientcert-Serial-Number`
7. `X-Amzn-Mtls-Clientcert-Validity`

These settings do not let you fill in header values.

They let you change the header names that ALB uses when forwarding information to the backend.

When would you change them?

Common reasons include:

1. The backend framework already expects a fixed header name
2. Internal proxy standards require specific names
3. You need to avoid conflicts with existing headers
4. mTLS information must be consumed by an existing application

If you do not have these requirements, keep the defaults.

Do not rename headers just because it looks cleaner.

It adds translation cost to documentation, debugging, and handover.

### Response Header Attributes

#### ALB Can Add Response Headers

ALB listener attributes can also add certain HTTP response headers.

This is useful for centralized entry-point rules, such as security headers or CORS headers.

Common configurable response headers include:

| Header | Common purpose |
| --- | --- |
| `Strict-Transport-Security` | Tell browsers to access the site only through HTTPS in the future |
| `Access-Control-Allow-Origin` | CORS allowed origins |
| `Access-Control-Allow-Headers` | CORS allowed request headers |
| `Access-Control-Allow-Methods` | CORS allowed methods |
| `Access-Control-Allow-Credentials` | Whether CORS allows credentials |
| `Access-Control-Expose-Headers` | Response headers exposed to browsers |
| `Access-Control-Max-Age` | CORS preflight cache duration |
| `Content-Security-Policy` | Restrict resource sources that browsers may load |
| `X-Content-Type-Options` | Reduce MIME sniffing risk |
| `X-Frame-Options` | Control whether the page can be embedded in frames |

The easiest one to start with is `X-Content-Type-Options`.

The only allowed value is `nosniff`.

If the application does not add it, ALB can add it consistently at the edge.

`Strict-Transport-Security` is also common, for example:

```text
max-age=31536000; includeSubDomains
```

But HSTS should be handled carefully.

If you add `includeSubDomains`, browsers will require HTTPS for subdomains as well.

If a subdomain is not ready for HTTPS, users may be unable to access it.

`Content-Security-Policy` requires even more care.

A loose CSP does not help much, while an overly strict one can break frontend resources, third-party scripts, images, or fonts.

I usually prefer to manage CSP in the application or frontend platform, and use ALB for stable headers that are consistent across services.

#### Server Header Can Be Removed

Listener attributes also include `routing.http.response.server.enabled`.

This controls whether ALB includes the `server` header in responses.

If your security scanner requires reducing service fingerprint information, you can consider removing it.

But removing the `server` header is not a primary defense.

The more important controls are:

1. WAF rules
2. TLS policy
3. Backend security updates
4. Permission and network isolation
5. Correct logging and monitoring

Treat this as a small security baseline cleanup, not the core of your security model.

## Rule Layer

Rules are a major part of ALB.

The listener decides which port receives traffic.

Rules decide how a received request is evaluated and handled.

Many people think of rules as only path routing, but each rule actually has two parts:

1. condition: what kind of request matches this rule
2. action: what to do after the request matches

### Conditions

Common rule conditions include:

| Condition | Purpose |
| --- | --- |
| Host header | Route by domain, such as `api.example.com` or `admin.example.com` |
| Path | Route by path, such as `/api/*` or `/admin/*` |
| HTTP header | Route by a specific header |
| HTTP request method | Route by method such as GET or POST |
| Query string | Route by query string |
| Source IP | Route by source IP |

The most common ones are Host header and Path.

For example:

1. `api.example.com` forwards to the API target group
2. `admin.example.com` performs OIDC authentication first, then forwards to the admin target group
3. `/static/*` forwards to another target group

Rule priority is also important.

Lower numbers have higher priority.

ALB evaluates rules from the lowest priority value to the highest.

The first matching rule is executed.

If no rule matches, ALB uses the listener default action.

### Actions

Common rule actions include:

| Action | Purpose |
| --- | --- |
| Forward | Forward the request to a target group |
| Redirect | Return a redirect, such as HTTP to HTTPS |
| Fixed response | Return a fixed response directly from ALB |
| Authenticate | Authenticate users with OIDC or Cognito first |

Forward is the most common action.

If there is only one target group, ALB forwards traffic directly to it.

If there are multiple target groups, you can configure weighted target groups for simple blue-green deployments or canary releases.

Redirect is common on an `80` listener:

```text
HTTP:80 -> HTTPS:443
```

Fixed response is useful for simple blocking or maintenance responses.

For example, a specific path can return `403` directly, or ALB can return a fixed message before the backend is ready.

Authenticate action is easy to overlook but useful.

It can be placed before forward, so ALB authenticates users through OIDC or Amazon Cognito before sending the request to the backend.

This is the approach I used in the Uptime Kuma SSO article.

### Rule Action Order

A rule can have multiple actions, but the order matters.

For OIDC authentication, the common order is:

| Order | Action |
| --- | --- |
| 1 | Authenticate |
| 2 | Forward |

In other words, authenticate first, then forward.

If the order is wrong, a request may be forwarded without authentication, or the rule may not behave as expected.

### Rules vs Attributes

A rule is not an attribute.

It is closer to ALB routing logic.

Attributes control behavior of the load balancer, listener, or target group itself.

A simple way to remember it:

1. attributes decide how ALB handles connections, headers, and security behavior
2. rules decide where a matching request goes, whether it must authenticate first, or whether it should redirect

When troubleshooting ALB, I usually ask two questions:

1. Did the request match the expected rule?
2. After the rule matched, did any attributes change the request or response behavior?

This helps avoid mixing listener, rule, target group, and attribute issues together.

## Target Group Layer

A target group is the collection of backend services behind ALB.

This article focuses mainly on ALB and listener attributes, but target groups still belong in the overall hierarchy.

Common target group settings include:

1. target type: instance, ip, lambda
2. protocol and port
3. protocol version: HTTP/1.1, HTTP/2, gRPC
4. health check path, interval, timeout, and thresholds
5. deregistration delay
6. stickiness

The protocol version is easy to confuse with the earlier HTTP/2 setting.

`routing.http2.enabled` describes whether the client-to-ALB connection supports HTTP/2.

The target group protocol version describes how ALB talks to backend targets.

If you are using gRPC, or you want backend targets to receive HTTP/2, check the target group protocol version.

## Common Recommendations

For a normal public website or API, I usually start with the following:

| Setting | Recommendation |
| --- | --- |
| `routing.http2.enabled` | Keep `true` |
| `idle_timeout.timeout_seconds` | Keep `60` for normal APIs; increase for WebSocket or streaming |
| `client_keep_alive.seconds` | Usually keep the default |
| `waf.fail_open.enabled` | Keep `false` for most public services |
| `routing.http.desync_mitigation_mode` | Keep `defensive`; evaluate `strictest` for stricter security needs |
| `routing.http.drop_invalid_header_fields.enabled` | Evaluate enabling for new systems; test legacy systems first |
| `routing.http.preserve_host_header.enabled` | Enable only when the backend needs the original Host |
| `routing.http.xff_header_processing.mode` | Use `append` for most cases |
| `routing.http.xff_client_port.enabled` | Keep `false` unless needed |
| `routing.http.x_amzn_tls_version_and_cipher_suite.enabled` | Enable when you need TLS audit or debugging information |

For internal systems, also check:

1. Whether the ALB is internal or internet-facing
2. Whether the backend Security Group allows traffic only from ALB
3. Whether OIDC authentication is needed
4. Whether WAF should provide baseline protection
5. Whether access logs and connection logs are enabled

Many ALB issues are not caused by listener rule mistakes.

They come from an unclear trust boundary.

If users can bypass ALB and reach the backend directly, OIDC, WAF, headers, and TLS information handled at ALB are all weakened.

## Terraform Example

The following example shows how to configure several ALB attributes in Terraform.

```terraform
resource "aws_lb" "app" {
  name               = "example-app-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = true

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  idle_timeout               = 60
  client_keep_alive          = 3600
  enable_http2               = true
  enable_waf_fail_open       = false
  drop_invalid_header_fields = true
  preserve_host_header       = false
  enable_xff_client_port     = false

  xff_header_processing_mode = "append"

  desync_mitigation_mode = "defensive"

  enable_tls_version_and_cipher_suite_headers = true

  tags = {
    Service = "example-app"
  }
}
```

Different versions of the Terraform AWS Provider may support different argument names.

Always check the provider version used by your project.

If the provider does not yet support newer listener attributes, you may need to use AWS CLI or CloudFormation temporarily, or wait until the provider supports them before moving the setting into IaC.

## AWS CLI Checks

To view the current attributes of an ALB:

```bash
aws elbv2 describe-load-balancer-attributes \
  --load-balancer-arn <alb-arn>
```

To view listener attributes:

```bash
aws elbv2 describe-listener-attributes \
  --listener-arn <listener-arn>
```

To modify load balancer attributes:

```bash
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn <alb-arn> \
  --attributes Key=routing.http.drop_invalid_header_fields.enabled,Value=true
```

In production, I would avoid clicking these settings manually in the console without recording them.

At minimum, export the current configuration.

Ideally, manage the settings with Terraform, CloudFormation, or CDK.

ALB has many small settings, and some security differences are not obvious at a glance.

## Summary

ALB is not just a tool that distributes traffic to target groups.

It is an entry control point for many AWS web architectures.

It can handle:

1. HTTPS termination
2. HTTP/2
3. WebSocket
4. WAF
5. OIDC authentication
6. Header forwarding
7. Response security headers
8. Global Accelerator integration

Because ALB sits at the entry point, its settings directly affect security, debugging, auditing, and application behavior.

If you treat ALB only as a reverse proxy with health checks, you will miss many important details.

My recommendation is:

After creating an ALB, check not only listeners, rules, and target groups, but also attributes.

Pay particular attention to WAF fail open, desync mitigation, invalid headers, Host header, X-Forwarded-For, idle timeout, and response headers.

They are quiet most of the time, but when you face security scans, login redirects, real client IP handling, WebSocket disconnections, or cross-origin issues, they often become the key to troubleshooting.

## References

1. [Application Load Balancers - Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html)
2. [Listeners for your Application Load Balancers - Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/load-balancer-listeners.html)
3. [Listener rules for your Application Load Balancer - Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/listener-rules.html)
4. [What is a Gateway Load Balancer? - Elastic Load Balancing](https://docs.aws.amazon.com/elasticloadbalancing/latest/gateway/introduction.html)
5. [How AWS Global Accelerator works](https://docs.aws.amazon.com/global-accelerator/latest/dg/introduction-how-it-works.html)
6. [AWS WAF Developer Guide](https://docs.aws.amazon.com/waf/latest/developerguide/waf-chapter.html)
