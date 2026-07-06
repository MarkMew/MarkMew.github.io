---
layout: post
title: "Grafana GPG Key Expired: Fixing EXPKEYSIG on Ubuntu APT"
description: "Getting EXPKEYSIG while updating Grafana on Ubuntu? Learn why APT rejects the repository signature and how to refresh Grafana's official GPG key safely."
author: Mark_Mew
category: Grafana
tags: [Grafana]
keywords: [Grafana, GPG, APT, EXPKEYSIG, Ubuntu]
date: 2025-09-01
lang: en
---

While updating Grafana on Ubuntu, I recently encountered a GPG signature verification error after running `apt update`:

```text
Err:4 https://apt.grafana.com stable InRelease
  The following signatures were invalid:
  EXPKEYSIG 963FA27710458545 Grafana Labs <engineering@grafana.com>

W: An error occurred during the signature verification.
W: Failed to fetch https://apt.grafana.com/dists/stable/InRelease
```

This does not mean that the Grafana service itself is broken. APT cannot verify the package index provided by the Grafana repository, so it refuses to use the newly downloaded data. The system may continue using a cached index, but the warning should not be ignored: you might be unable to retrieve a newer Grafana release or see errors stating that no installation candidate is available.

## Why Does APT Need a GPG Key?

An APT repository signs its package index with a private key. An Ubuntu host then verifies that signature with the installed public key. This process confirms that the index was published by Grafana Labs and was not modified in transit.

`EXPKEYSIG` means that APT considers the key used for the signature to be expired. The fingerprint of the key involved in this case is:

```text
B53A E77B ADB6 30A6 8304 6005 963F A277 1045 8545
```

Grafana Labs extended this key's lifetime by two years on August 22, 2025. If a machine still has the public key downloaded before that extension, APT continues to see the original expiration information. The official key therefore needs to be downloaded again. In other words, the important step is to refresh the locally stored public key, not merely delete an arbitrary old key.

## Fixing the Error on Ubuntu or Debian

The recommended approach is to keep third-party repository keys separately under `/etc/apt/keyrings` and use `signed-by` to restrict the Grafana repository to its own keyring. This is easier to manage than adding the key to the system-wide trust store and avoids the deprecated `apt-key` command.

```bash
# 1. Create the directory for third-party repository keys
sudo install -d -m 0755 /etc/apt/keyrings

# 2. Download the complete public key provided by Grafana
sudo wget -O /etc/apt/keyrings/grafana.asc \
  https://apt.grafana.com/gpg-full.key
sudo chmod 0644 /etc/apt/keyrings/grafana.asc

# 3. Configure the Grafana repository to use this keyring explicitly
echo 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' \
  | sudo tee /etc/apt/sources.list.d/grafana.list

# 4. Download and verify the package index again
sudo apt update
```

This procedure uses the official `gpg-full.key` and stores it directly in ASCII-armored format as `grafana.asc`. If the existing repository configuration points to another file, such as `/usr/share/keyrings/grafana.key` or `/etc/apt/keyrings/grafana.gpg`, update the `signed-by` path as well. Otherwise, APT will continue reading the old key.

## Verifying the Fix

After running `apt update` again, the output should no longer contain `EXPKEYSIG` or `The following signatures were invalid`. You can also verify that APT can see an available Grafana package version:

```bash
apt-cache policy grafana
```

If the error remains, check whether the Grafana repository has been configured more than once:

```bash
grep -R "apt.grafana.com" \
  /etc/apt/sources.list /etc/apt/sources.list.d/
```

When old and new entries for the same repository coexist, APT may still load an entry that points to the old keyring. Keep only the intended source, confirm that `signed-by` points to `/etc/apt/keyrings/grafana.asc`, and run `sudo apt update` again.

## Scope

This solution applies to Grafana installed from the Grafana Labs APT repository on Ubuntu or Debian. Installations using a Docker image, Grafana Cloud, or the operating system's own repository are generally not affected by this APT key issue. RPM, YUM, and DNF use different repository and key-management procedures, so the commands in this article should not be applied to them directly.

---

## References

- [Grafana official APT repository](https://apt.grafana.com/)
- [Install Grafana on Debian or Ubuntu](https://grafana.com/docs/grafana/latest/setup-grafana/installation/debian/)
- [Repository GPG key expires 2025-08-23](https://github.com/grafana/grafana/issues/108659)
