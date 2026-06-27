---
layout: post
title: "VM Server Not Reachable from Host? localhost vs 127.0.0.1 vs 0.0.0.0"
description: "Learn why a VM server is unreachable from the host and how localhost, 127.0.0.1, 0.0.0.0, NAT, Vagrant port forwarding, and Docker affect connectivity."
author: Mark_Mew
tags: [Docker, network]
keywords: [Docker, network, localhost, 127.0.0.1, 0.0.0.0]
lang: en
date: 2026-06-27
---

I have long preferred to create a VM on my computer and do my development work inside it. The main reason is consistency: assigning similar CPU and memory resources to each VM reduces the impact of performance differences between developers' computers.

However, I often ran into the same problem: the server had started successfully inside the VM, but the browser on the host machine still could not connect to it.

Eventually, I understood the key distinction: **the host's localhost is not the VM's localhost, and the host's “local machine” is not the VM's “local machine.”**

Many people eventually find the same answer through Google:

> Change `127.0.0.1` to `0.0.0.0` and it will work.

That solution often works, but why? How can changing one address suddenly make the service reachable? This article starts with the fundamentals and explains the differences between `localhost`, `127.0.0.1`, and `0.0.0.0`, as well as the roles they play in VMs and Docker containers.

## The Short Answer

| Name | Type | Meaning | Common Use |
| --- | --- | --- | --- |
| `localhost` | Hostname | The hostname of the local machine | A human-friendly way to refer to the local machine |
| `127.0.0.1` | IP Address | The IPv4 loopback address | Allows access only from within the same network environment |
| `0.0.0.0` | Special Address | All available IPv4 network interfaces | Allows a service to accept connections through multiple interfaces |

The most important idea is:

> `127.0.0.1` refers only to “this machine” in the current network environment. It does not refer to the host.

## localhost: A Name, Not an IP Address

`localhost` is a hostname, not an IP address. Most systems define a mapping similar to the following in their `hosts` file:

```text
127.0.0.1 localhost
```

As a result, `localhost` usually resolves to `127.0.0.1`. Some systems may resolve it to the IPv6 address `::1` first.

In short:

- `localhost` is a name.
- `127.0.0.1` is the actual IPv4 loopback address.

They are often interchangeable in practice, but they are not the same concept.

## 127.0.0.1: Accept Connections Only from Itself

`127.0.0.1` is the IPv4 loopback address. Packets sent to this address never pass through a physical network interface; they are routed directly back to the current network environment.

Suppose an application is configured like this:

```python
app.run(host="127.0.0.1", port=5000)
```

This means that the server listens only on the loopback interface and accepts connections only from within the same machine, container, or VM.

If the computer's LAN IP address is `192.168.1.100`, the following URLs will work locally:

```text
http://127.0.0.1:5000
http://localhost:5000
```

However, other devices cannot connect through this URL:

```text
http://192.168.1.100:5000
```

The reason is that the server is not listening on the network interface associated with `192.168.1.100`.

## 0.0.0.0: Listen on All Network Interfaces

In a server's bind configuration, `0.0.0.0` means “listen on all available IPv4 network interfaces.” It is not an actual destination IP address.

A computer may have several addresses at the same time:

```text
127.0.0.1
192.168.1.100
10.0.0.5
```

If the application is configured as follows:

```python
app.run(host="0.0.0.0", port=5000)
```

The server listens on port `5000` across all available interfaces, so it may be reachable through all of these addresses:

```text
127.0.0.1:5000
192.168.1.100:5000
10.0.0.5:5000
```

However, `0.0.0.0` is a **server-side listening configuration**, not usually an address you enter in a browser. The browser should connect to an actual IP address of the host or VM that it can reach.

> Binding to `0.0.0.0` may allow other devices on the same network to access the service. This is convenient during development, but it should still be combined with firewall rules, authentication, and appropriate network restrictions to avoid unintentionally exposing the service.
{: .prompt-warning}

## Why Can't the Host Connect When the VM Binds to 127.0.0.1?

From a networking perspective, a VM behaves like a separate computer. The host and VM each have their own loopback interface, IP addresses, and network interfaces:

```text
Host
├── localhost / 127.0.0.1
└── 192.168.56.1

VM
├── localhost / 127.0.0.1
└── 192.168.56.101
```

If the application inside the VM is configured as follows:

```python
app.run(host="127.0.0.1", port=5000)
```

It listens only on the VM's own loopback interface:

```text
lo    127.0.0.1       ← listening
eth0  192.168.56.101  ← not listening
```

Opening `http://127.0.0.1:5000` inside the VM will work, but the host cannot access the service through `http://192.168.56.101:5000`.

After changing the configuration to:

```python
app.run(host="0.0.0.0", port=5000)
```

The server listens on `lo`, `eth0`, and the VM's other interfaces. As long as the host can reach the VM's network, it can connect through:

```text
http://192.168.56.101:5000
```

## Why Is It Still Unreachable After Changing to 0.0.0.0?

Whether a service is listening and whether the network is reachable are two different problems:

- **Bind**: Is the server willing to accept connections through this network interface?
- **Routing**: Can the host deliver packets to the VM?
- **Firewall**: Do the operating system or cloud firewall rules allow traffic through that port?

`0.0.0.0` solves only the binding problem. Whether the host can reach the VM still depends on the VM's network mode and firewall settings.

### NAT

NAT is a common default network mode:

```text
Host → Virtual NAT → VM → Internet
```

The VM can usually access the Internet, but external systems cannot initiate connections directly to the VM. To let the host access a service inside the VM, you usually need **port forwarding**, such as forwarding port `5000` on the host to port `5000` in the VM.

> Vagrant's `forwarded_port` is an example of this setup. The following configuration forwards port `8080` on the host to port `5000` in the VM. The `host_ip` setting restricts access to the host itself:
>
> ```ruby
> config.vm.network "forwarded_port",
>   guest: 5000,
>   host: 8080,
>   host_ip: "127.0.0.1"
> ```
>
> The connection path is `Host 127.0.0.1:8080 → Vagrant NAT port forwarding → VM port 5000 → Server`. The server inside the VM must therefore still listen on `0.0.0.0:5000`. If it listens only on the VM's own `127.0.0.1:5000`, traffic forwarded to the VM's network interface still cannot reach it. After applying the configuration with `vagrant reload`, the host can access the service at `http://127.0.0.1:8080`.
{: .prompt-info}

### Host-Only

A host-only network creates a virtual network used only for communication between the host and the VM:

```text
Host  192.168.56.1
  ↕
VM    192.168.56.101
```

As long as the service is listening on the corresponding VM interface, the host can access it through:

```text
http://192.168.56.101:5000
```

### Bridged

Bridged mode connects the VM directly to the same physical network as the host:

```text
Router
├── Host  192.168.1.100
└── VM    192.168.1.101
```

The VM now behaves like another computer on the LAN. If the network and firewall allow it, the host or even a mobile device can access the service through:

```text
http://192.168.1.101:5000
```

## Which VM IP Address Should I Use?

A VM may have several network interfaces at the same time:

```text
lo       127.0.0.1
ens33    10.0.2.15
ens34    192.168.56.101
docker0  172.17.0.1
```

Even if the server reports that it is listening on `0.0.0.0:5000`, the correct IP address to enter in the browser still depends on:

- Whether the host can reach that subnet.
- Whether the VM uses NAT, host-only, or bridged networking.
- Whether the firewalls on the VM and host allow port `5000`.

Inside a Linux VM, use the following command to inspect its IP addresses:

```bash
ip addr
```

You can also check the addresses and ports on which the application is actually listening:

```bash
ss -lntp
```

## Why Does Docker Also Need to Bind to 0.0.0.0?

A container also has its own isolated network environment. Suppose the application inside a container listens only on:

```python
app.run(host="127.0.0.1", port=5000)
```

Even if port mapping is configured when the container starts:

```bash
docker run -p 5000:5000 my-app
```

The host may still be unable to connect because the application accepts connections only through the container's loopback interface.

Change the application to:

```python
app.run(host="0.0.0.0", port=5000)
```

The server will then listen on the container's network interfaces, allowing Docker's port mapping to forward connections from the host to the application.

## Troubleshooting Checklist

When a connection fails, check the following in order:

1. **Is the application actually running?** Test it inside the VM or container with `curl http://127.0.0.1:5000`.
2. **Where is the application listening?** Use `ss -lntp` to check whether it is listening on `127.0.0.1:5000` or `0.0.0.0:5000`.
3. **What is the VM's IP address?** Use `ip addr` to find an address the host can reach.
4. **Is the VM's network mode correct?** NAT usually requires port forwarding, while host-only and bridged modes require the corresponding VM IP address.
5. **Does the firewall allow the connection?** Make sure the VM, host, or cloud environment is not blocking the port.
6. **If Docker is involved, has the port been published?** Check that `docker ps` shows the expected port mapping.

## Summary

- `localhost` is a hostname that usually resolves to `127.0.0.1` or `::1`.
- `127.0.0.1` is a loopback address that refers only to the current network environment itself.
- `0.0.0.0` tells a server to listen on all IPv4 network interfaces; it is not the actual IP address a browser should connect to.
- The host, VM, and container each have their own network environment and their own `localhost`.
- A listening service is not necessarily reachable. Routing, VM network mode, and firewall rules must also be checked.

Once these concepts are clear, it becomes much easier to locate network problems in VMs, Docker, Kubernetes, cloud environments, and even physical servers—instead of merely remembering to “change `127.0.0.1` to `0.0.0.0`.”
