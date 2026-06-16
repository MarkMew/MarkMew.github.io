---
layout: post
title: "How Should I Start Introducing Observability?"
description: "A practical path for introducing observability, starting from Logs, Metrics, and Traces, with implementation steps and common pitfalls."
author: Mark_Mew
categories: [Observability]
tags: [DevOps, Observability]
keywords: [DevOps, Observability, logs, metrics, traces]
lang: en
date: 2026-06-17
---

A few years ago, people often talked about DevOps and SRE.

In the last couple of years, Platform Engineering has also become a common topic.

These topics often end up landing on DevOps engineers or a company's infrastructure team.

Observability has also been discussed for quite some time.

Is it just another buzzword?

Should a company or department start adopting it?

When everyone is talking about Observability,

where should I actually start?

And how should I help my company introduce it?

As usual, this article will not begin with complicated theory.

Instead, I want to start from a practical perspective

and organize a path for introducing observability.

## Start With The Three Pillars

The three common pillars of observability are:

- `logs`
- `metrics`
- `traces`

In a more intuitive way:

Logs answer "what happened."

Metrics answer "whether the system state is getting worse."

Traces answer "which services a request passed through, and where it got stuck."

When introducing observability,

you do not need to complete all three areas perfectly from the beginning.

A more realistic approach is:

first make sure the team can find events,

then make sure the team can see trends,

and finally trace request paths across services.

### Logs

#### Start By Making Logs Searchable

The first step of observability

usually starts with `Logs`.

When an event happens,

or when an unexpected issue needs troubleshooting,

the first thing we usually do is check the `Logs`

to confirm whether there is enough information to understand the event

and support further investigation.

At this point,

someone might say:

"That's it?"

Yes. If you already have a log collector

and a platform where logs can be searched,

congratulations. You have already completed one third of observability.

#### Build A Log Collection Platform

I believe generating `Logs` is not a problem for most engineers and systems.

But having logs does not mean you have observability.

If logs are scattered across machines, containers, or different services,

it is still difficult to search them quickly during an incident.

After you have logs,

the next step is to build a unified log collection and query platform.

It could be `Loki`, `ELK`, `Splunk`,

or a cloud service such as CloudWatch Logs.

The important part is not the tool name.

The important part is whether the team can quickly find related logs

by time range, service name, request id, error message, and other conditions.

#### Format Log Output

When a system outputs `Logs`,

if messages are printed casually,

the result can easily become hard to query.

```
***************
json value is {"foo": "bar"}
***************
```

Before centralized log management,

this might still be readable in a single file.

But once logs are centralized and queried through a platform,

this kind of output can easily break `query conditions` or `regular expressions`.

Using the example above,

if the query tool treats each line as a separate event,

the two `***************` lines will also become independent log records.

In that case, queries like the following can easily fail:

- Querying a JSON field such as `foo = "bar"`
- Using a `json` parser to parse the whole log line
- Connecting logs from the same request by request id or trace id
- Extracting the content after `json value is ...` with a regular expression
- Counting errors while decorative lines or multiline output interfere with the result

It may look like only a few decorative lines were added.

But for a centralized log platform,

one event may be split into multiple records,

and content that could have been queried structurally may degrade into plain text search.

Therefore, formatting log output is necessary.

For example, output logs as JSON or one-line logs,

and remove unnecessary emoji, separators, and decorative text.

Logs are not articles written for humans to slowly appreciate.

They are data that systems need to parse, filter, and query reliably.

#### Query Tools

If you use Loki,

it is usually paired with Grafana as the dashboard and query tool.

CloudWatch Logs, ELK, and Splunk provide their own query interfaces.

Because every tool works differently,

you should at least become familiar with a few common query patterns

so that you can troubleshoot problems quickly.

For example:

- Query by service name
- Query by error level
- Query by request id
- Query by a specific error message
- Narrow the time range where the issue happened

After this step,

Logs are no longer just stored somewhere.

They can actually help during incidents.

### Metrics

After Logs can be queried centrally,

you can start building metrics.

But before getting started,

you still need to understand what kind of environment you have

and what kind of problem you want to solve.

#### Inventory Your Assets

Is the current infrastructure physical machines, virtual machines, or Kubernetes?

If it is self-managed Kubernetes or managed Kubernetes in the cloud,

Prometheus is usually the first choice.

If it is physical machines or virtual machines,

Prometheus is still an option.

But if traffic is low and there is not much operational capacity,

you can also consider a simpler tool such as Munin first.

#### Why Prometheus

Munin also uses a pull model to collect data from nodes.

Prometheus also uses a pull model to collect data from Node Exporter.

So why is `Prometheus` commonly recommended today?

One difference is scrape frequency and the data model.

Munin relies on the OS-level cronjob mechanism,

and its graph generation model is closer to minute-level monitoring.

The Munin flow looks like this:

```
Master
   ↓
Connect to Node
   ↓
Execute Plugin
   ↓
Get Values
   ↓
Update RRD
   ↓
Regenerate Graphs
```

Even if you try to go beyond the one-minute cronjob design,

once there are many nodes,

the server can easily become overloaded.

So this is usually not how it is used.

Prometheus pulls data,

stores it in a time-series database,

and calculates query results through PromQL before tools such as Grafana visualize them.

So if you are using Kubernetes,

or if you need to collect data at second-level granularity,

you will usually choose `Prometheus`.

#### Install Node Exporter

##### Containers

If services run on Kubernetes,

you usually do not log into each node to install `Node Exporter`.

Instead, you deploy it as a `DaemonSet`

so that every Worker Node automatically runs one `Node Exporter`.

The benefit is that

when nodes are added to or removed from the Kubernetes cluster,

`Node Exporter` is also created or removed automatically.

You do not need to maintain the installation state of each machine manually.

If you do not want to write YAML from scratch at the beginning,

you can start with a Helm Chart such as `kube-prometheus-stack`.

It usually installs Prometheus, Grafana, Alertmanager,

and common Kubernetes exporters together.

For a team just starting to introduce observability,

this makes it easier to see results than assembling every component from scratch.

##### Virtual Machines

If you are using virtual machines or physical machines,

you can install `Node Exporter` directly on the host.

It exposes basic metrics such as CPU, Memory, Disk, and Network.

For Debian or Ubuntu,

you can install it with `apt`:

```bash
sudo apt update
sudo apt install -y prometheus-node-exporter
sudo systemctl enable --now prometheus-node-exporter
```

For RHEL, CentOS, Rocky Linux, or Amazon Linux,

you can install it with `yum`:

```bash
sudo yum install -y epel-release
sudo yum install -y node_exporter
sudo systemctl enable --now node_exporter
```

The actual package name may vary depending on the distribution and repository.

If the package cannot be found,

first check whether the required repository is enabled,

or install it using the official release binary.

After installation,

it usually opens port `9100` by default.

Prometheus Server can then scrape data from this endpoint.

One important thing to remember is:

`Node Exporter` only exposes host metrics.

It does not store data or draw graphs.

The component that periodically scrapes, stores, and queries data

is the `Prometheus Server`.

#### Connect Prometheus Server

After every host or Kubernetes Node has an Exporter,

the next step is to let Prometheus Server know where to scrape data.

In a virtual machine environment,

you can start with static configuration

and write each host's `IP:9100` into the Prometheus scrape config.

If Prometheus Server is also installed on a virtual machine,

you usually edit `/etc/prometheus/prometheus.yml`.

For example:

```yaml
scrape_configs:
  - job_name: "node-exporter"
    static_configs:
      - targets:
          - "10.0.1.10:9100"
          - "10.0.1.11:9100"
```

After modifying the file,

you can check the configuration syntax first:

```bash
promtool check config /etc/prometheus/prometheus.yml
```

If there is no problem,

restart Prometheus:

```bash
sudo systemctl restart prometheus
sudo systemctl status prometheus
```

If Prometheus was not installed through packages,

but runs with Docker or another method,

the idea is the same:

mount `prometheus.yml` into Prometheus Server

and make sure the VM `IP:9100` targets are included in the config.

In Kubernetes,

Prometheus usually uses Service Discovery or `ServiceMonitor` to discover targets automatically,

so you do not need to manually update the config every time a service or node is added.

At the beginning, do not rush to collect every possible metric.

First confirm a few things:

- Prometheus can scrape targets successfully
- The `up` metric is `1`
- Grafana can query CPU, Memory, Disk, and Network
- The values on the dashboard match your understanding of the host state

After these basic metrics are trustworthy,

then you can start thinking about which application metrics to add

and which situations should become alerts.

### Traces

If the system has not reached a certain scale,

I usually recommend making `Logs` and `Metrics` solid first.

`Traces` increase deployment complexity.

They also require storage space.

To put it more directly,

you need to store a large amount of request path data.

To generate these Traces,

the application needs additional packages,

and may also need instrumentation in key flows.

During deployment, you also need to configure Exporters and Collectors

to forward data to the backend storage system.

#### Install Application Packages

If you really want to start introducing Traces,

I recommend starting with `OpenTelemetry`.

The reason is that it is not tied to a single vendor format.

In the future, whether you send data to Jaeger, Tempo, Datadog, New Relic,

or another observability platform,

you will have more flexibility.

For applications,

you usually install the OpenTelemetry SDK or Agent for the corresponding language:

- Python: `opentelemetry-sdk`, `opentelemetry-instrumentation`
- Java: `opentelemetry-javaagent`
- .NET: `OpenTelemetry`, `OpenTelemetry.Extensions.Hosting`

When starting out,

you do not need to manually add spans in every function immediately.

You can begin with automatic instrumentation,

such as HTTP requests, database clients, and message queue clients,

so that the main path of a request can be connected first.

When you really need to analyze a specific business flow,

then add custom spans

for key steps such as payment, order creation, or report generation.

#### Exporter

After the application generates Trace data,

it needs an Exporter to send the data out.

In OpenTelemetry,

the most common choice is `OTLP`,

which stands for OpenTelemetry Protocol.

The application sends Trace data to a specified endpoint,

for example:

```bash
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317
OTEL_SERVICE_NAME=order-service
```

`OTEL_SERVICE_NAME` is especially important.

It determines the service name shown in the Trace system.

If every service is called default or application,

it will be difficult to tell which service had a problem

when you actually need to investigate.

#### Collector

In a Traces architecture,

you usually place an `OpenTelemetry Collector` as an intermediate component.

Its role is similar to Fluent Bit or Vector in the Logs world.

It receives data from applications

and forwards it to the backend storage system according to configuration.

The benefit is that

applications do not need to know which backend platform is being used directly.

If you want to switch from Jaeger to Tempo in the future,

or send data to two platforms at the same time,

you mainly adjust the Collector configuration.

A simplified flow looks like this:

```text
Application
   ↓
OpenTelemetry Collector
   ↓
Trace Backend
   ↓
Grafana / Jaeger UI
```

#### Server

Finally, you need a place to store and query Traces.

Common options include `Jaeger`, `Grafana Tempo`,

or APM services provided by cloud or SaaS platforms.

If the team already uses Grafana,

Tempo is worth considering,

because it can be viewed together with Grafana dashboards, Logs, and Metrics.

If you simply want to understand what Traces look like quickly,

Jaeger is also a good entry-level tool.

No matter which tool you choose,

before introducing Traces, you should confirm a few things:

- Service names are clear
- request id or trace id can be correlated with Logs
- You can really see which services a request passed through
- You can see which part took the most time
- Retention is configured so Trace data does not grow without limit

The value of Traces is not recording every line of code.

It is helping us quickly locate across services:

where did this request get stuck?

## Suggested Adoption Order

If you do not know where to start,

you can proceed step by step in this order:

1. Centralize Logs so the team can find events
2. Format Logs so systems can parse them reliably
3. Build basic Metrics for CPU, Memory, Disk, and Network
4. Use Prometheus and Grafana to build the first dashboard
5. Add a small number of trustworthy alerts
6. Introduce Traces when services become more numerous and request paths become longer

Observability is not about buying every tool at once.

It is also not finished just because all data is collected.

What really matters is:

when a problem happens,

can the team answer three questions faster?

- What happened?
- How large is the impact?
- Where should we investigate next?

## Conclusion

The goal of observability is not to make dashboards look beautiful.

It is also not to create as many alerts as possible.

What it really tries to solve is:

when the system has a problem,

can the team detect it earlier, locate it faster,

and make decisions based on reliable data?

If you do not know where to start yet,

start with Logs.

After Logs are searchable, Metrics are visible, and alerts are trustworthy,

then gradually add Traces.

This approach may not be the flashiest,

but it is easier to keep moving forward in a real team.
