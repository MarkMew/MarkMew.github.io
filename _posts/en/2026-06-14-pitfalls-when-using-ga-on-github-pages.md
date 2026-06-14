---
layout: post
title: "Pitfalls When Submitting a Sitemap from GitHub Pages to Google Search Console"
description: "A practical note on fixing the 'Couldn't fetch' sitemap issue in Google Search Console for GitHub Pages by using a custom domain, CloudFlare DNS, and GitHub Pages settings."
author: Mark_Mew
categories: [GitHub]
tags: [GitHub, GitHub Pages, Google Search Console, SEO]
keywords: [GitHub, GitHub Pages, Google Search Console, SEO]
lang: en
date: 2026-06-14
---

Let me start with the conclusion.

If you do not have a custom domain,

no matter how you submit your sitemap to Google Search Console,

it may simply never be accepted.

If you want your static website to be indexed by Google faster,

buying a domain and binding it to GitHub Pages is the real solution.

## How I Stepped on This Landmine

### Background

Around February or March,

I decided to start taking my GitHub Pages site seriously.

First, I replaced the site with a new theme,

then I connected Google Analytics and Google Search Console for management.

The Google Analytics tracking code was verified very quickly.

Google Search Console was also verified smoothly because it could be linked directly through Google Analytics.

But after submitting the sitemap multiple times in Google Search Console,

![sitemap](/assets/img/google-search-console-create-sitemap-failed.png)

I was honestly speechless.

Not only did I fail to fix the issue,

I also wasted a lot of time discussing it with AI tools and burning tokens on meaningless changes.

### The Useless Modification Loop

#### Useless Suggestions from AI

- `site.url` is wrong
- `Sitemap URL` and `GSC property` do not match
- The `<lastmod>` format may be invalid
- The plugin is not supported, so another plugin should generate the sitemap
- `robots.txt` is blocking it
- The sitemap contains "invalid URLs" such as js or css assets
- The URL does not actually exist
- Use the simplest possible sitemap

My sitemap was generated with AI tools,

or built with AI-assisted development.

In the end, I validated it with online tools,

and confirmed that it was valid XML and also a valid sitemap.xml.

However, after adding the sitemap in Google Search Console,

the status was always `Couldn't fetch`.

I am not saying the AI suggestions were bad.

If this were a pure static site hosted on Apache2,

or a server managed by myself,

those suggestions would make sense as a checklist.

But in this case, I was using a static website hosting service,

with many OS-level details that I could not touch.

So those checks may not have been very meaningful.

#### A Bare-Minimum sitemap.xml

Since a fancy sitemap might contain elements that Google would ignore,

I also tried an almost bare-minimum sitemap.xml.

It only contained the site itself and posts,

without update frequency hints.

But in the end, GSC still did not accept it.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">

  <url>
    <loc>https://markmew.github.io/</loc>
  </url>

  {% for post in site.posts %}
  <url>
    <loc>{{ site.url }}{{ post.url }}</loc>
    <lastmod>{{ post.date | date_to_xmlschema }}</lastmod>
  </url>
  {% endfor %}

</urlset>
```

#### The Trust Level of `GitHub Pages`

👉 How Google may see GitHub Pages:
- Lower crawl frequency
- Lower trust
- Many spammy sites are hosted there

👉 Result: with the same sitemap, a GitHub Pages site may be more likely to be delayed or fail.

While discussing the issue with AI,

one interesting point came up.

Before using a custom domain,

the domain is always `GitHubName`.github.io,

and all of them end with github.io.

Whether that domain has high enough trust and priority is honestly debatable.

#### Stability Issues with `GitHub Pages`

💥 Key point: the long-standing GitHub Pages + Googlebot problem

GitHub Pages has these characteristics:
- CDN (Fastly)
- Cache layer
- Distributed edge nodes

👉 When you run curl, you may hit:

X-Served-By: cache-nrt-xxxx (a Japan node)

👉 But Googlebot:

may crawl from the United States or Europe.

It may hit a different node.

Aside from domain trust,

CDN stability or cross-region crawl stability could also be a factor (though I personally do not really buy it).

But after checking everything from sitemap generation to the hosting layer,

there was only one solution left for me:

buy a domain and bind it.

## How I Solved It

### Buying a Domain

I had previously bought domains from GoDaddy.

But CloudFlare has always had some interesting features.

This time, because of those features,

I decided to buy the domain on CloudFlare.

#### DNS Service

As everyone knows, Google DNS is `8.8.8.8`.

CloudFlare also provides a DNS service: `1.1.1.1`.

So if I buy and configure the domain there,

maybe DNS propagation will be faster too.

#### Built-In CDN

Even the free version of CloudFlare includes CDN support.

If I point my domain to CloudFlare,

then for a content-focused GitHub Pages site,

I probably do not need to buy or think about a separate CDN service.

### CloudFlare Setup

To point CloudFlare to GitHub Pages, you need to configure four A records and one CNAME record.

| Type | Name | Value |
| --- | --- | --- |
| A | @ | 185.199.110.153 |
| A | @ | 185.199.111.153 |
| A | @ | 185.199.109.153 |
| A | @ | 185.199.108.153 |
| CNAME | www | markmew.github.io |

### Custom Domain

In the `Pages` tab on the left,

the `Custom domain` section at the bottom lets you set a custom domain.

DNS verification may take some time.

Also, every time you refresh the page,

GitHub Pages checks the DNS status again.

After adding the domain, all you can do is wait patiently and `do not` refresh the page.

Wait until you see `DNS check successful`.

At this point, I recommend enabling Enforce HTTPS.

![GitHub Pages custom domain](/assets/img/github-pages-customized-domain.png)

### Submitting the Sitemap

Then we return to Google Search Console.

Unlike GA, GSC does not let you directly change the URL of an existing property.

So you can only add a new property,

and submit the sitemap from that new property.

After submission, Google showed success very quickly.

![Google Search Console create sitemap success](/assets/img/google-search-console-create-sitemap-success.png)

### An Extra Bonus

After the sitemap submission succeeded,

I went back the next day to explore some CloudFlare features.

Unexpectedly, CloudFlare provides metrics for AI crawlers.

You can see whether your site has been crawled by AI bots,

or even included by AI agents.

![CloudFlare AI agent metrics](/assets/img/cloudflare-ai-agent-metrics.png)

## Conclusion

Looking back at the whole process, I spent a lot of time checking sitemap, robots.txt, and all kinds of settings.

But the key step turned out to be very simple: buy a custom domain and bind it.

For a free service like GitHub Pages,

Google Search Console may have lower trust in domains ending with `github.io`.

So even a perfect sitemap may still be difficult to submit successfully.

The main point is: **custom domain = sitemap can be submitted = faster indexing**.

If you run into the same issue, buying a domain directly is the most straightforward solution.

The time and energy saved are worth far more than the domain fee.
