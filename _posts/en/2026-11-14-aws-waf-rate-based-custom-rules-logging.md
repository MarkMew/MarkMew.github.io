---
layout: post
title: "AWS WAF Beyond the Basics: Rate-Based Rules, Custom Rules, WAF Logs, and Moving from Count to Block"
description: "A follow-up to the web ACL intro: how to set up AWS WAF rate-based rules, handle false positives with custom rules, choose between CloudWatch Logs and S3 for WAF logs, and what to check before switching rules from Count to Block."
author: Mark_Mew
categories: [AWS, WAF & Shield]
tags: [AWS WAF, Rate-based Rule, Web ACL, CloudWatch Logs, Terraform]
keywords: [AWS WAF rate-based rule, AWS WAF rate limiting, AWS WAF custom rules, AWS WAF logs, WAF CloudWatch Logs Insights, WAF logs S3 Athena, WAF Count to Block, WAF false positives, SizeRestrictions_BODY, aws_wafv2_web_acl_logging_configuration]
lang: en
date: 2026-11-14
---

In the [previous article](/en/posts/aws-waf-web-acl-managed-rules-wcu/), we created a web ACL and set the AWS managed rule groups to Count. The next questions usually look like this: how do I stop brute-force attempts on the login page? What do I do when a rule blocks file uploads? And after running in Count for a while, when is it safe to switch to Block?

Here's the short answer up front: **rate-based rules handle "the same source is sending too much," custom rules handle "exceptions or restrictions under specific conditions," and WAF logs are what tell you whether a rule is ready to move from Count to Block.** Switching to Block without logs is guesswork.

## Rate-based rules: limiting requests to the login page

A rate-based rule counts requests from each source over a time window and applies an action once the count goes over a limit. The most common use is limiting how many times a single IP can hit a login API. [AWS: Rate-based rule statement](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)

A few settings are worth understanding first:

| Setting | What it does |
|---|---|
| Evaluation window | 60, 120, 300, or 600 seconds; the default is 300 |
| Rate limit | Number of requests allowed within the window; the minimum is 10 |
| Aggregation | By source IP, by an IP in a header (such as `X-Forwarded-For`), by custom keys, or by counting all requests together |
| Scope-down statement | Only counts requests that match a condition, such as requests to `/login` |
| Action | Block, Count, CAPTCHA, or Challenge |

[AWS: Rate-based rule high-level settings](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)

I'd recommend **always adding a scope-down statement**. Without one, every request to the site counts toward the limit. A single page load can trigger dozens of requests for static assets, so even normal users could get blocked. If you only count paths that tend to be abused, like login, sign-up, and password reset, the limit is much easier to tune and less likely to hit legitimate users.

Also keep in mind that rate-based rules don't count each request in real time. There's a short delay between going over the limit and the action kicking in, and the number of requests blocked won't match the limit exactly. They work well for stopping obvious floods, not as a precise request counter. [AWS: Rate-based rule caveats](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)

### If CloudFront sits in front of your ALB

If your architecture is CloudFront → ALB and the web ACL is associated with the ALB, the source IP the ALB sees belongs to a CloudFront edge server, not the user. Aggregating by source IP in this setup lumps a large group of users together as a single source.

Aggregating by `X-Forwarded-For` instead seems to fix this, but WAF uses the **first** IP in that header, and clients can set it to whatever they want. An attacker can bypass the limit by sending a different fake IP with each request. The more reliable approach is to associate the web ACL with CloudFront, so WAF sees the real client IP directly. [AWS: Forwarded IP address](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-forwarded-ip-address.html)

### Terraform example

Add the following to `aws_wafv2_web_acl.app` from the previous article. If a single IP sends more than 100 requests to `/api/login` within 5 minutes, WAF responds with `429 Too Many Requests`. A default Block returns `403`, which makes it hard for the frontend to tell rate limiting apart from a permissions problem, so I usually change it to 429.

```terraform
rule {
  name     = "rate-limit-login"
  priority = 10

  action {
    block {
      custom_response {
        response_code = 429
      }
    }
  }

  statement {
    rate_based_statement {
      limit                 = 100
      evaluation_window_sec = 300
      aggregate_key_type    = "IP"

      scope_down_statement {
        byte_match_statement {
          search_string         = "/api/login"
          positional_constraint = "STARTS_WITH"

          field_to_match {
            uri_path {}
          }

          text_transformation {
            priority = 0
            type     = "LOWERCASE"
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-rate-limit-login"
    sampled_requests_enabled   = true
  }
}
```

`100` is only an example. The right number depends on how your real users behave. For an internal system where everyone shares the same egress IP, the limit needs to be much higher. If you're not sure, change `action` to `count {}`, let it run for a while, and use the logs to see where normal peaks land before deciding. [Terraform: rate_based_statement](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

> **Info:** `evaluation_window_sec` is a relatively new argument. Older versions of the Terraform AWS Provider won't recognize it, so upgrade the provider if you get an error.
{: .prompt-info}

## Custom rules: covering what managed rules can't

Managed rules are general-purpose, so sooner or later you'll hit a case where they don't fit your site. That's when you write your own rules. Two cases come up often.

### Example 1: allowing the admin area only from office IPs

First, store your office egress IPs in an IP set. Then write a rule that says: **if the path starts with `/admin` and the source is not in the IP set, block it.**

```terraform
resource "aws_wafv2_ip_set" "office" {
  name               = "office-ips"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = ["203.0.113.0/24"]
}
```

```terraform
rule {
  name     = "admin-office-only"
  priority = 5

  action {
    block {}
  }

  statement {
    and_statement {
      statement {
        byte_match_statement {
          search_string         = "/admin"
          positional_constraint = "STARTS_WITH"

          field_to_match {
            uri_path {}
          }

          text_transformation {
            priority = 0
            type     = "LOWERCASE"
          }
        }
      }

      statement {
        not_statement {
          statement {
            ip_set_reference_statement {
              arn = aws_wafv2_ip_set.office.arn
            }
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-admin-office-only"
    sampled_requests_enabled   = true
  }
}
```

This is deliberately written as "block if not an office IP" rather than "allow if an office IP." The reason is evaluation order: WAF evaluates rules by `priority` from lowest to highest, and **stops as soon as it hits Allow or Block**. Nothing after that gets checked. A high-priority Allow rule would let office IP requests skip every managed rule, effectively turning off protection for those sources. [AWS: Rule actions and evaluation](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html)

### Example 2: CRS blocks file uploads

This is probably the most common false positive after adding the Core Rule Set (CRS). The `SizeRestrictions_BODY` rule in CRS checks whether the request body is larger than 8 KB, so APIs that accept file uploads or long forms trip it easily.

Turning off the whole CRS is a waste. A better approach is to use **labels**: when a managed rule matches, it adds a label to the request, even if that rule is set to Count. So you can:

1. Use `rule_action_override` in CRS to set only `SizeRestrictions_BODY` to Count.
2. Add a custom rule **after** CRS that blocks requests carrying this label, unless the path is the upload API.

```terraform
# Add this inside the managed_rule_group_statement for AWSManagedRulesCommonRuleSet
rule_action_override {
  name = "SizeRestrictions_BODY"

  action_to_use {
    count {}
  }
}
```

```terraform
rule {
  name     = "block-large-body-except-upload"
  priority = 20

  action {
    block {}
  }

  statement {
    and_statement {
      statement {
        label_match_statement {
          scope = "LABEL"
          key   = "awswaf:managed:aws:core-rule-set:SizeRestrictions_Body"
        }
      }

      statement {
        not_statement {
          statement {
            byte_match_statement {
              search_string         = "/api/upload"
              positional_constraint = "STARTS_WITH"

              field_to_match {
                uri_path {}
              }

              text_transformation {
                priority = 0
                type     = "LOWERCASE"
              }
            }
          }
        }
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-block-large-body"
    sampled_requests_enabled   = true
  }
}
```

Every other path still has the body size limit; only the upload API gets an exception. The label rule's `priority` must be higher than CRS's (meaning it runs later). Otherwise the label hasn't been added yet when the rule is evaluated, and it will never match. [AWS: Label match rule statement](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-label-match.html), [AWS: CRS rules and labels](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)

## WAF logs: CloudWatch Logs or S3?

Sampled requests in the console only cover the last 3 hours, which isn't enough to judge false positives. If you're serious about tuning rules, you need WAF logging. [AWS: Viewing a sample of web requests](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing-view-sample.html)

WAF logs can go to three kinds of destinations, and a web ACL can only use one at a time:

| Destination | Good for | How to query |
|---|---|---|
| CloudWatch Logs | Actively tuning rules and needing answers quickly | Logs Insights |
| S3 | Long-term retention and audit records | Athena |
| Data Firehose | Forwarding to a SIEM or another analytics platform | Depends on the destination |

Whichever you choose, **the name must start with `aws-waf-logs-`**, for example a log group called `aws-waf-logs-app`. This is easy to forget, and the configuration fails if the name is wrong. [AWS: Logging destinations](https://docs.aws.amazon.com/waf/latest/developerguide/logging-destinations.html)

My habit is to send logs to CloudWatch Logs during the weeks I'm tuning rules, since it's the fastest to query. Once the rules are stable and I need long-term retention for audits, I switch to S3, which is cheaper to store. On cost: WAF logs sent to CloudWatch Logs are billed as vended logs, which adds up over a month on a high-traffic site. Check [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) before turning it on in production.

### Logging only what you need

On a busy site, a logging filter can keep only blocked and counted requests and drop everything that was allowed normally. That cuts log volume a lot:

```terraform
resource "aws_cloudwatch_log_group" "waf" {
  name              = "aws-waf-logs-app"
  retention_in_days = 30
}

resource "aws_wafv2_web_acl_logging_configuration" "app" {
  resource_arn            = aws_wafv2_web_acl.app.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  logging_filter {
    default_behavior = "DROP"

    filter {
      behavior    = "KEEP"
      requirement = "MEETS_ANY"

      condition {
        action_condition {
          action = "BLOCK"
        }
      }

      condition {
        action_condition {
          action = "COUNT"
        }
      }
    }
  }
}
```

`redacted_fields` masks the `Authorization` header in the logs so tokens don't end up there. If you keep session data in cookies, you can redact those too. [Terraform: Logging configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration), [AWS: Redacting and filtering logs](https://docs.aws.amazon.com/waf/latest/developerguide/logging-management.html)

> **Warning:** There's a trap here. When a managed rule group is set to Count as a whole with `override_action { count {} }`, the request's final `action` is the web ACL's default action, `ALLOW`, **not `COUNT`**, so the filter above drops it. If your observation period is mainly about managed rule groups set to Count, skip the logging filter for now, or keep those requests with a label condition (`label_name_condition`) instead.
{: .prompt-warning}

### Finding false positives with Logs Insights

Once logs are coming in, open CloudWatch Logs Insights, select `aws-waf-logs-app`, and start by checking which rules block the most and on which paths:

```sql
fields @timestamp, terminatingRuleId, httpRequest.clientIp, httpRequest.uri
| filter action = "BLOCK"
| stats count(*) as requests by terminatingRuleId, httpRequest.uri
| sort requests desc
| limit 20
```

During the observation period, what you want to know is what CRS *would* block while it's in Count mode. You can find that by label:

```sql
fields @timestamp, httpRequest.clientIp, httpRequest.uri
| filter @message like /awswaf:managed:aws:core-rule-set/
| stats count(*) as hits, count_distinct(httpRequest.clientIp) as ips by httpRequest.uri
| sort hits desc
| limit 20
```

This is how I read the results: **many hits from widely spread IPs on a path that's one of your own normal features** is very likely a false positive. **Hits concentrated on a handful of IPs, on paths like `/wp-login.php` or `/.env` that don't even exist on your site,** are scanners, and blocking them is fine. [AWS: Log fields](https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html), [AWS: Logs Insights query syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)

### If you send logs to S3

Logs are stored under `AWSLogs/{account ID}/WAFLogs/{Region}/{web ACL name}/YYYY/MM/dd/HH/mm` and written roughly every 5 minutes. To query them, create a table in Athena and use SQL. AWS provides a ready-made table definition. I'd recommend using partition projection with it; otherwise, once the data grows, every query scans the whole bucket. [AWS: Sending WAF logs to S3](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html), [Athena: Querying AWS WAF logs](https://docs.aws.amazon.com/athena/latest/ug/waf-logs.html)

## Moving from Count to Block: my checklist

Everything above leads to this step. My process goes roughly like this:

**1. Make the observation period cover at least one full business cycle.** For a typical site, that's about two weeks. But if you have features that only run at certain times, like month-end billing or quarterly reports, wait until they've run at least once. False positives tend to show up in features nobody uses day to day.

**2. Reach a conclusion for every rule that matched.** Use the queries from the previous section to list every rule and path that matched in Count mode, and decide for each whether it's an attack or a false positive. There are three ways to handle false positives, from best to worst:

| Approach | When to use it |
|---|---|
| Label + custom rule as an exception | Only specific paths are false positives; other paths still need the rule |
| Add a scope-down statement to the rule group | The whole rule group doesn't fit certain paths, such as a webhook receiver |
| Keep the rule in Count permanently with `rule_action_override` | The rule is meaningless for your site |

**3. Switch one rule group at a time.** Start with the group that has the fewest false positives, such as Known Bad Inputs, and leave CRS, which has many rules and a higher chance of false positives, for last. If you switch everything at once and something breaks, it's hard to tell which group caused it.

**4. Pick an off-peak window and have a rollback ready.** This is where managing WAF with Terraform pays off: rolling back means changing `override_action` from `none {}` back to `count {}` and running `apply`. Before switching, make sure that PR can be merged right away.

**5. Watch the metrics after switching.** WAF's CloudWatch metrics are in the `AWS/WAFV2` namespace. Look for sudden increases in `BlockedRequests`, and keep an eye on the ALB's `HTTPCode_ELB_4XX_Count` as well as support tickets and user reports. You can also set an alarm on `BlockedRequests` to notify you when the numbers look unusual. [AWS: WAF CloudWatch metrics](https://docs.aws.amazon.com/waf/latest/developerguide/waf-metrics.html)

> **Tip:** AWS updates managed rule groups from time to time. If you're worried that an update could introduce new false positives, use `version` in `managed_rule_group_statement` to pin a static version, and upgrade after testing. The trade-off is that new protections also won't take effect until you upgrade manually. [AWS: Managed rule group versioning](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-rule-groups-versioning.html)
{: .prompt-tip}

## FAQ

### What should the rate limit be?

There's no standard answer. Run it in Count for a while, use the logs to find the highest number of requests a normal user sends within the window, and leave some headroom above that. Be especially generous when many users share an egress IP, such as offices, schools, and mobile networks.

### How long does it take for an IP blocked by a rate-based rule to be unblocked?

You don't have to unblock it manually. WAF keeps counting, and once that source's requests within the window drop below the limit, the action no longer applies.

### Do requests blocked by WAF show up in the backend access logs?

No. WAF handles the request before it reaches your backend application. If the web ACL is associated with an ALB, the ALB access logs will have a record, but to see the full reason (which rule matched), you still need the WAF logs.

### Does turning on WAF logging affect site performance?

No. WAF writes logs asynchronously, so it doesn't add latency to requests. The main concern is the cost of storing and querying the logs.

## Conclusion

Writing WAF rules isn't the hard part. The hard part is making sure they don't block your own users. That's why most of this article is about logs and the switching process rather than rule syntax. Turn on logging, collect data in Count mode, and decide what to block based on that data. It's a lot less painful than blocking everything from day one and fixing things as users complain.

## References

### AWS official documentation

- [Rate-based rule statement](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html)
- [Rate-based rule high-level settings](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html)
- [Rate-based rule caveats](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html)
- [Forwarded IP address](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-forwarded-ip-address.html)
- [Rule actions and evaluation order](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-action.html)
- [Label match rule statement](https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-label-match.html)
- [Core Rule Set rules and labels](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)
- [Viewing a sample of web requests](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing-view-sample.html)
- [Logging destinations](https://docs.aws.amazon.com/waf/latest/developerguide/logging-destinations.html)
- [Redacting and filtering logs](https://docs.aws.amazon.com/waf/latest/developerguide/logging-management.html)
- [Log fields](https://docs.aws.amazon.com/waf/latest/developerguide/logging-fields.html)
- [Sending WAF logs to S3](https://docs.aws.amazon.com/waf/latest/developerguide/logging-s3.html)
- [WAF CloudWatch metrics](https://docs.aws.amazon.com/waf/latest/developerguide/waf-metrics.html)
- [Managed rule group versioning](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-rule-groups-versioning.html)
- [CloudWatch Logs Insights query syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html)
- [Athena: Querying AWS WAF logs](https://docs.aws.amazon.com/athena/latest/ug/waf-logs.html)
- [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/)

### Terraform AWS Provider official documentation

- [aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [aws_wafv2_ip_set](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_ip_set)
- [aws_wafv2_web_acl_logging_configuration](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_logging_configuration)
