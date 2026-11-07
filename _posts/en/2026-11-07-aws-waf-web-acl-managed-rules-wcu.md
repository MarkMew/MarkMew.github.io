---
layout: post
title: "AWS WAF & Shield: Getting Started with Web ACLs"
description: "Where to attach an AWS WAF web ACL, how to choose managed rule groups, and what to watch for with WCU limits and pricing."
author: Mark_Mew
categories: [AWS, WAF & Shield]
tags: [AWS WAF, AWS Shield, Web ACL, Managed Rules, WCU]
keywords: [AWS WAF web ACL, AWS Shield, ALB WAF, API Gateway WAF, AWS Managed Rules, OWASP Top 10, WordPress Rule Set, WCU]
lang: en
date: 2026-11-07
---

AWS WAF and AWS Shield are AWS security services. AWS WAF helps protect applications against web attacks, while AWS Shield addresses attacks at the network and transport layers. Security products can sound expensive and difficult to adopt, but adding AWS WAF to an application can be a relatively simple way to start protecting it. With an on-premises firewall, traffic traditionally passes through a device at the network edge. A badly configured rule can disrupt the whole network, and changes often take time to test and roll out. With AWS WAF, you associate a web ACL with the AWS resources you want to protect. Resources that are not associated with it are unaffected, so you can start in a test environment and move to production after checking how the service behaves.

## What exactly is a web ACL?

Seeing WAF and Shield together in the AWS console makes it easy to assume that a web ACL belongs to both. In fact, **a web ACL is an AWS WAF configuration**: you put inspection rules in it, associate it with your website or API entry point, and WAF evaluates incoming HTTP(S) requests against those rules. Shield Standard provides automatic, baseline DDoS protection, mainly for network and transport layer attacks. Shield Advanced has additional protection features. The services are related, but creating a web ACL is not how you “turn on” Shield. [AWS: WAF or Shield?](https://docs.aws.amazon.com/decision-guides/latest/decision-guides/waf-or-shield.html), [AWS: Shield Standard overview](https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html)

A web ACL can contain your own rules or managed rule groups prepared by AWS. Rules can inspect a source IP, country, URL path, or request content. A match can be allowed, blocked, or simply recorded with **Count**. Requests that match no rule follow the web ACL's default action. When adding a rule, starting with Count feels safer: you often need to see real traffic before you know what legitimate requests look like. [AWS: Web ACLs](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html), [AWS: Testing and tuning rules](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## Where can you attach a web ACL?

If your website has an **Application Load Balancer (ALB)** in front of it, you can associate the web ACL with the ALB. For an **API Gateway REST API**, you associate it with a particular Stage. If your site passes through **CloudFront** before reaching the backend, you can also associate a web ACL with the CloudFront distribution so that requests are checked before they reach the origin. [AWS: Supported resources](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)

There are two details that are easy to miss. ALBs and API Gateway REST APIs use regional web ACLs, which must be in the same Region as the resource. CloudFront uses a different scope, managed through `us-east-1`. Also, the API Gateway resource described in the AWS documentation is a **REST API Stage**; don't assume an HTTP API has the same association option. One web ACL can be associated with multiple eligible resources, but a resource can have only one web ACL at a time. [AWS: Association limits](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html), [AWS: Protecting API Gateway REST APIs](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html)

## What rules does AWS provide?

You can write every rule yourself, but AWS Managed Rules are a useful place to look when starting out. For a general website, the **Core Rule Set (CRS)** is a common starting point. Its rule group name is `AWSManagedRulesCommonRuleSet`, and the documentation currently lists it at **700 WCU**. AWS says it covers *some* common high-risk vulnerabilities described in publications such as the OWASP Top 10. Adding CRS does not mean your site is protected against the entire OWASP Top 10. [AWS: Core Rule Set](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)

For a **WordPress** site, there is also `AWSManagedRulesWordPressRuleSet`, currently **100 WCU**. It checks for some exploitable paths and requests associated with WordPress. AWS recommends evaluating it alongside the SQL Database and PHP Application rule groups, depending on your site's architecture. Adding more groups is not automatically better; check what your site actually uses and whether the rules interfere with legitimate features. [AWS: WordPress rule group](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)

**Java** needs a clarification. The current official AWS Managed Rules list has no separate group named “Java Rule Set.” The closest example here is **Known Bad Inputs** (`AWSManagedRulesKnownBadInputsRuleSet`, currently **200 WCU**), which includes rules for Java deserialization and Log4j attack patterns. If you see a Java rule group from another vendor in the AWS console, check whether it is an AWS Marketplace subscription; its maintainer and pricing may differ. WAF does not replace patching your application and dependencies. [AWS: Managed Rules list](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html), [AWS: Known Bad Inputs](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html), [AWS: Marketplace rule groups](https://docs.aws.amazon.com/waf/latest/developerguide/marketplace-rule-groups.html)

## Will adding rules suddenly make it expensive?

AWS uses **WCU (Web ACL Capacity Units)** to measure the capacity consumed by rules. The term is WCU, not ACU. A web ACL can currently use up to **5,000 WCU**, while **1,500 WCU** is included in the base price. You can go beyond 1,500 WCU, but the extra capacity adds request-processing charges in tiers. In other words, 1,500 is the pricing threshold; 5,000 is the capacity limit. [AWS: WCU and capacity limits](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)

For the three groups above, CRS uses 700, Known Bad Inputs 200, and WordPress 100, for a total of **1,000 WCU**. That is only an example of how to count capacity, not a recommendation to add all three to every site. The Console displays the WCU used by the web ACL as you add rules. [AWS: WCU calculation](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)

One more thing: **staying below 1,500 WCU does not make WAF free**. Web ACLs, rules, and request volume have base charges, and some advanced rule groups, Marketplace rules, and other features can cost extra. Before deploying, estimate your traffic and check the [official AWS WAF pricing page](https://aws.amazon.com/waf/pricing/). Then leave new rules in Count for a while, paying particular attention to logins, uploads, and unusual API parameters. Once you know they are not affecting legitimate requests, you can switch them to Block. [AWS: Testing before deployment](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## Creating a web ACL with Terraform

If you already manage your ALB or API Gateway with Terraform, putting WAF in the same configuration makes it easier to see when rules were added. The example below creates a **regional** web ACL with CRS and Known Bad Inputs, then associates it with an existing resource. Together, these two groups currently use **900 WCU**. Their result is initially set to **Count**, so you can inspect matches before deciding whether to block requests.

```terraform
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "aws_region" {
  type = string
}

variable "target_arn" {
  type = string
}

provider "aws" {
  region = var.aws_region
}

resource "aws_wafv2_web_acl" "app" {
  name  = "app-web-acl"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 0

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "app-crs"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "app-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-web-acl"
    sampled_requests_enabled   = true
  }
}

resource "aws_wafv2_web_acl_association" "app" {
  resource_arn = var.target_arn
  web_acl_arn  = aws_wafv2_web_acl.app.arn
}
```

> **Info:** When looking up Terraform examples, you may find `aws_waf_*`, `aws_wafregional_*`, and the `aws_wafv2_*` resources used here. The first two belong to **AWS WAF Classic** (for CloudFront and regional resources respectively); the last belongs to the current AWS WAF. Resource names, rule syntax, and association methods differ, so changing a resource name to `wafv2` is not a migration. AWS lists **September 30, 2025** as WAF Classic's end-of-support date. Older documentation and existing configurations may still appear, but new web ACLs should use `aws_wafv2_*`. For existing Classic resources, consult the migration guide and your Region's timeline in AWS Health. [AWS: WAF Classic migration](https://docs.aws.amazon.com/waf/latest/developerguide/waf-migrating-from-classic.html), [AWS: WAFV2 API](https://docs.aws.amazon.com/waf/latest/APIReference/)
{: .prompt-info}

Set `target_arn` to the ARN of the resource you want to protect. For an ALB, use the `arn` of an existing `aws_lb`; for an API Gateway REST API, use the **Stage ARN**, such as the `arn` of an existing `aws_api_gateway_stage`. Do not use the API's `execution_arn`, which serves another purpose. The resource and web ACL must be in the same Region. Also check whether the resource already has a web ACL associated with it. [Terraform: Web ACL](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl), [Terraform: Web ACL association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association), [Terraform: API Gateway Stage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)

For example, if the ALB and web ACL are both in Tokyo, pass `aws_region = "ap-northeast-1"` and the ALB's ARN. For a REST API Stage, change `target_arn` to that Stage's ARN. If two resources really should share the same rules, add a second `aws_wafv2_web_acl_association` pointing to the same web ACL. **Do not use that association resource for CloudFront.** In Terraform, set `web_acl_id` on `aws_cloudfront_distribution` instead, change the web ACL's `scope` to `CLOUDFRONT`, and use a provider configured for `us-east-1`. [Terraform: CloudFront association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)

In the example, `override_action { count {} }` changes the **rule group's result** to Count. This lets you see whether the group would affect requests, but evaluation inside the group still stops at the first terminating rule. To observe matches for individual rules, set them to Count with `rule_action_override`. Once you are ready to use the group's original actions, change it to `override_action { none {} }`. [AWS: Limits of group-level Count](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-rule-group-override-options.html), [Terraform: Managed rule group settings](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)

For a WordPress site, add the following `rule` inside the same `aws_wafv2_web_acl.app` resource. If the site does not use WordPress, leave it out:

```terraform
rule {
  name     = "AWSManagedRulesWordPressRuleSet"
  priority = 2

  override_action {
    count {}
  }

  statement {
    managed_rule_group_statement {
      vendor_name = "AWS"
      name        = "AWSManagedRulesWordPressRuleSet"
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-wordpress"
    sampled_requests_enabled   = true
  }
}
```

With this rule, the three groups total **1,000 WCU**. Before switching to blocking, review sampled requests and metrics for a while, especially for logins, the admin area, and plugins. [AWS: WordPress rule group](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html), [AWS: Testing WAF rules](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)

## Conclusion

Adding a layer of protection to a website or API is not as difficult as it might seem. As discussed at the start, you can begin with a web ACL: associate it with an ALB or API Gateway in a test environment and see whether the rules affect normal requests. Once things look right, roll it out to production gradually. This lets you get started while keeping the impact of changes manageable.

## References

### AWS documentation

- [AWS WAF or AWS Shield?](https://docs.aws.amazon.com/decision-guides/latest/decision-guides/waf-or-shield.html)
- [Shield Standard overview](https://docs.aws.amazon.com/waf/latest/developerguide/ddos-standard-summary.html)
- [Configuring web ACLs](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl.html)
- [Supported resources and association limits](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-associating-aws-resource.html)
- [Protecting API Gateway REST APIs with WAF](https://docs.aws.amazon.com/apigateway/latest/developerguide/apigateway-control-access-aws-waf.html)
- [Testing and tuning WAF rules](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-testing.html)
- [AWS Managed Rules list](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-list.html)
- [Core Rule Set and Known Bad Inputs](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-baseline.html)
- [Application-specific rule groups, including WordPress](https://docs.aws.amazon.com/waf/latest/developerguide/aws-managed-rule-groups-use-case.html)
- [AWS Marketplace rule groups](https://docs.aws.amazon.com/waf/latest/developerguide/marketplace-rule-groups.html)
- [WCU capacity and calculation](https://docs.aws.amazon.com/waf/latest/developerguide/aws-waf-capacity-units.html)
- [AWS WAF pricing](https://aws.amazon.com/waf/pricing/)
- [Rule group Count override behavior](https://docs.aws.amazon.com/waf/latest/developerguide/web-acl-rule-group-override-options.html)
- [Migrating from WAF Classic](https://docs.aws.amazon.com/waf/latest/developerguide/waf-migrating-from-classic.html)
- [AWS WAFV2 API reference](https://docs.aws.amazon.com/waf/latest/APIReference/)

### Terraform AWS Provider documentation

- [aws_wafv2_web_acl](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl)
- [aws_wafv2_web_acl_association](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/wafv2_web_acl_association)
- [aws_api_gateway_stage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)
