---
layout: post
title: "Zeabur Security Incident Explained: API Key Leak Review and Lessons Learned"
image: https://fastly.picsum.photos/id/258/1200/630.jpg?hmac=1tNJdsrdyuIv3qsmBvgDQVZjIs5pTV_JqsWFtqD3Qik
description: "A breakdown of the August 2026 Zeabur security incident, covering how OpenAI, AWS, and other API keys were leaked, the official response, and the immediate steps users should take."
author: Mark_Mew
categories: [Security]
tags: [Zeabur, Security, AI, LiteLLM, API Key]
keywords: [Zeabur, Security Incident, API Key Leak, LiteLLM, Security]
lang: en
date: 2026-08-30
---

On August 27, the cloud deployment platform Zeabur suffered a security incident: an unauthorized party gained access to an internal service credential used to retrieve project environment variable records, and used it to obtain some users' environment variables. According to what Zeabur disclosed, the exposed environment variables included API keys for AI tools such as OpenAI and Anthropic, as well as GitHub PATs and AWS-related credentials. What an attacker can actually do with a leaked key depends on the permissions granted to it — in this case, some victims' keys were used by attackers, with the resulting bills charged to the original account owners.

## What happened
* Aug 27: An internal Zeabur service credential was accessed without authorization
* The attacker used this credential to obtain users' environment variables
* Types of leaked credentials: OpenAI / Anthropic / OpenRouter / GitHub PAT / AWS / Cloudflare / Stripe tokens (see the official status page for details: ![Zeabur Status Page](https://status.zeabur.com/incident/1037896))
* It has been confirmed that some users' AI API keys were abused (unusual billing)

## Investigation leads
The official status page disclosed suspicious activity on LiteLLM, the service used by Zeabur AI Hub. Whether this activity is related to the incident is still under investigation. Although unconfirmed, as a precaution and to prevent any further potential impact, Zeabur has temporarily suspended the Zeabur AI Hub service during the investigation.

## How the founder responded
Founder Yuan-Lin Lin posted an update on Threads on Aug 29:
- Initial containment was completed the same day the anomaly was detected
- Continued monitoring for further anomalies
- Notifying all potentially affected users individually and publishing announcements
- Cooperating with upstream vendors and law enforcement on further investigation

**Users are urged to immediately rotate all API keys and passwords stored on Zeabur, and check usage and billing. If abuse is found, keep evidence such as timestamps, amounts, token usage, and source IPs, and submit them to support.**
![Zeabur Founder Announcement](/assets/img/zeabur_founder_announcement.png)

## If you're a Zeabur user, here's what to do now
1. Immediately rotate all keys and passwords stored in Zeabur environment variables
2. Check billing for every service and associated API key used with Zeabur
3. If you notice unusual usage, take screenshots as evidence and submit them to Zeabur support
4. Rotate database passwords, JWT secrets, and any other credentials as well

## Lessons learned
### Set usage limits
Regardless of the platform you use, remember to set usage limits or budgets.

### Principle of least privilege
Since the rise of cloud computing, platforms have repeatedly urged following the principle of least privilege — restricting permissions limits the blast radius of any breach. Now that AI tools are widely used by the public, the same principle applies to API usage.

### Consider Federated Authentication
In recent years, many platforms have moved away from long-lived keys toward system-to-system Federated Authentication (e.g., OIDC), which uses short-lived credentials and fine-grained trust relationships to restrict access scope. This can significantly reduce the risk of abuse after a credential leak.

## References
- [Zeabur Status Page - Incident Report](https://status.zeabur.com/incident/1037896)
- [BlockTempo - Zeabur environment variable leak, OpenAI/Anthropic API keys stolen](https://www.blocktempo.com/zeabur-environment-variable-leak-openai-anthropic-api-key-stolen-compensation/)
- [Inside - Zeabur environment variable leak, API keys stolen](https://www.inside.com.tw/article/42241-zeabur-environment-variable-leak-api-keys-stolen)
- [geekMickey - Facebook post](https://www.facebook.com/geekMickey/posts/pfbid0Hz2edfN8yAWayebxLy9JbirdiJfSws3QisrGi5cuubvtwhLU2c6X5dDuERaR9wRfl)
- [Yuan-Lin Lin (Zeabur founder) - Threads post](https://www.threads.com/@yuaanlin/post/DcmVCO7kuG6)
- [Threads share link](https://www.threads.com/share/E3cDHLVLV/)
