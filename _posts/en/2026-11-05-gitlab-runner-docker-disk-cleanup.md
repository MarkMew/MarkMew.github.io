---
layout: post
title: "GitLab CI Runner Out of Disk Space: Cleaning Up Docker Images and Volumes"
description: "A troubleshooting log for a GitLab CI Runner host that ran low on disk space: from df, system logs, and Docker build cache to the Docker images and Runner cache volumes that turned out to matter, plus the differences and risks of docker system prune, docker volume prune, and clear-docker-cache."
author: Mark_Mew
categories: [CICD, GitLab]
tags: [GitLab Runner, Docker, CI/CD, Ubuntu, Disk Cleanup]
keywords: [GitLab Runner out of disk space, docker system prune, docker volume prune, docker builder prune, clear-docker-cache, GitLab Runner cache volume, journalctl vacuum, Docker cleanup]
lang: en
date: 2026-11-05
---

**When the disk on our GitLab CI Runner host was nearly full, I first suspected logs and the Docker build cache. The space that actually came back was mostly in Docker images and GitLab Runner cache volumes that had piled up over time.** This post is a record of how I investigated and cleaned up, which commands left a reclaimed-space figure and which didn't, and what to watch out for before you run any of it.

A note on scope: the environment is Ubuntu running GitLab Runner and Docker. All I have is the shell history from that session and the output of the last two cleanup commands. I can't tell you how much the earlier steps (logs, build cache) reclaimed, and I'm not going to invent a number.

## Introduction: What Happens When a Runner Runs Out of Disk

When a Runner host fills up, the symptoms show up in your pipelines: jobs can't pull images, builds can't write files, caches fail to extract, and in bad cases the Docker daemon itself misbehaves. The error messages often don't say "no space left on device" outright, which makes it easy to chase the wrong problem for a while.

So when I get a low-disk alert, I first work out what is actually using the space and only then decide what to clean, instead of reaching for `prune` right away.

## Step 1: Check Disk Usage

```bash
df -h
sudo du -sh /var/lib/docker
sudo docker system df -v
```

Each of these looks at a different level:

| Command | What it shows |
|---|---|
| `df -h` | Overall usage per mount point, so you know which filesystem is the problem |
| `du -sh /var/lib/docker` | Total size of the Docker data directory (default location) |
| `docker system df -v` | Docker's own accounting of images, containers, local volumes, and build cache; `-v` lists every item |

I start with `df -h` to find the filesystem, then drill down with `du` and `docker system df`. The `RECLAIMABLE` column of `docker system df` is handy because it tells you roughly how much could be freed, but it's only an estimate. The actual amount reclaimed is whatever the cleanup command reports.

During this incident I ran `df -h` many times, once after each cleanup step, to confirm the space was really being released.

## Step 2: Check System Logs First

After Docker, `/var/log` is the most common suspect, and it's cheap to check, so I looked there first:

```bash
sudo du -sh /var/log
sudo journalctl --disk-usage
```

`journalctl --disk-usage` shows how much space the systemd journal occupies. I then shortened the retention with `--vacuum-time`, first to 1 year and later to 6 months:

```bash
sudo journalctl --vacuum-time=1year
sudo journalctl --vacuum-time=6months
```

A few limitations are worth knowing. This command only removes archived journal files. The active file currently being written isn't touched. It also works by age, not by target size. If you want to cap by size, use `--vacuum-size`, or set a permanent limit in `journald.conf`.

I also dealt with rotated old files under `/var/log` that were more than six months old. I listed them with `-print` first, and only after the list looked reasonable did I run the same conditions with `-delete`:

```bash
# List only, do not delete
sudo find /var/log -type f -mtime +183 \
  \( -name '*.log.*' -o -name '*.gz' -o -name '*.old' \) \
  -print
```

Once the list looked right, I ran the deletion:

```bash
sudo find /var/log -type f -mtime +183 \
  \( -name '*.log.*' -o -name '*.gz' -o -name '*.old' \) \
  -delete
```

### Cautions When Using find -delete

`find ... -delete` has no recycle bin. Once it's gone, it's gone. A few habits I always keep:

- **Always review the list with `-print` first**, then switch to `-delete` with exactly the same conditions. The position and order of conditions can change the result, so don't edit the command from memory.
- **Restrict by extension and age**, and only touch rotated old files (`*.gz`, `*.log.*`, `*.old`). Never touch the live `.log` files.
- **Back up any audit or security logs you need to keep**, or check whether your company has a retention requirement.

Before this, I also used `find ... -printf '%s\n' | awk ...` to roughly estimate the total size of files older than a year. I didn't keep that output, so I won't quote a number here.

And this is the part I have to be honest about: after cleaning the logs, I don't have enough data to say how much they reclaimed, so I can't say what share of the problem they were.

## Step 3: Clean the Docker Build Cache

```bash
sudo docker builder prune -a
```

The Docker build cache is the set of intermediate results that `docker build` (BuildKit) keeps to speed up repeated builds. It's different from an image: an image is the finished output of a build, while the build cache is the cached layers left over during the build.

- **`-a` (`--all`)**: By default, `docker builder prune` only removes dangling build cache. Adding `-a` removes all unused build cache.
- **The cost**: After it's gone, the next build can't reuse the cache and runs from scratch, so build times get longer.
- **Limited scope**: `docker builder prune` only deals with build cache. It does **not** delete images or volumes.

I ran this command twice according to the history, but again there's no reclaimed-space figure for either run. The change in `df -h` afterward wasn't enough for me to attribute anything, so all I can say is that it was one of the steps I took, not the main cause of this incident.

One more distinction: the GitLab CI `cache:` keyword (pipeline-level cache), the Docker build cache, and Docker image layers are three different things. The first is managed by the Runner and, with the Docker executor, is stored in volumes. The other two are managed by Docker. Clearing one doesn't clear the others.

## Step 4: Check Space Used by GitLab Runner and Docker

After handling logs and build cache, free space still hadn't returned to a safe level, so I took a closer look at Docker itself:

```bash
docker ps -a
sudo docker system df -v
sudo du -sh /var/lib/docker
sudo du -sh /var/lib/docker/{overlay2,volumes,buildkit,containers} 2>/dev/null
```

I also looked up the executor and cache-related fields in the Runner configuration file:

```bash
sudo grep -E 'executor|builds_dir|cache_dir|volumes' \
  /etc/gitlab-runner/config.toml
```

Each of these resources corresponds to a different location:

| Resource | Description | Typical location |
|---|---|---|
| Images | Pulled or built images; each tag is kept separately | `/var/lib/docker/overlay2` (depends on the storage driver) |
| Containers | Writable layers and logs of containers; `docker ps -a` also shows stopped ones | `/var/lib/docker/containers`, `overlay2` |
| Local Volumes | Named and anonymous volumes | `/var/lib/docker/volumes` |
| Build Cache | BuildKit's build cache | `/var/lib/docker/buildkit` |
| GitLab Runner Cache | CI cache stored as volumes with the Docker executor | Volumes under `/var/lib/docker/volumes` |

The key point here: **with the Docker executor, GitLab Runner cache lives in Docker volumes.** It doesn't show up in `docker images`, and `docker builder prune` won't clear it. You have to look at it from the volume side.

I won't paste the contents of `config.toml` because it contains tokens and environment details. The volume names shown below are also consistent with the Docker executor storing its cache in volumes.

## Step 5: Clean Up Docker Images and Other Unused Resources

Next came one of the two steps with a clear reclaimed-space figure:

```bash
sudo docker system prune -a -f
```

First, what the flags mean:

- **`system prune`**: Removes unused Docker resources, including stopped containers, unused networks, unused images, and build cache.
- **`-a` (`--all`)**: Removes not just dangling images but every image that isn't used by any container, including tagged ones.
- **`-f` (`--force`)**: Skips the confirmation prompt.
- **No volumes**: Without `--volumes`, `docker system prune` does **not** delete volumes. So this command does not touch the Runner cache volumes.
- **Images in use are kept**: Images referenced by a running or existing (including stopped) container are not deleted.

The output had many `untagged` lines, all different tags of the same project (anonymized here as an example):

```text
untagged: .../dummy-foo-bar:87
untagged: .../dummy-foo-bar:88
untagged: .../dummy-foo-bar:92
untagged: .../dummy-foo-bar:93
untagged: .../dummy-foo-bar:94
untagged: .../dummy-foo-bar:latest
deleted: sha256:...

Total reclaimed space: 20.05GB
```

This output says a lot: CI produces a new tag on every build, and when nobody cleans up the old images, they stay on the Runner host one after another.

**It reclaimed 20.05 GB.** To be precise, though, that's the **total** reported by `docker system prune`, covering images and other cleanable resources. I can't say the full 20.05 GB was images.

## Step 6: Clean Up GitLab Runner Cache Volumes

With images out of the way, I moved on to volumes.

### Start with the Runner's own cleanup script

GitLab Runner packages usually ship a `clear-docker-cache` script, and that's what I used:

```bash
sudo /usr/share/gitlab-runner/clear-docker-cache space
sudo /usr/share/gitlab-runner/clear-docker-cache prune-volumes
```

As I understand the official docs and the script, the two arguments differ like this:

| Argument | Purpose |
|---|---|
| `space` | Checks free space and only cleans up if it falls below the threshold set in the script |
| `prune-volumes` | Removes volumes managed by the Runner (those carrying the Runner's labels) |

The point of this script is that it **only targets resources the GitLab Runner created itself**, so its scope is narrower than `docker volume prune`. But the script's contents, default thresholds, and behavior can vary between GitLab Runner versions. I recommend reading `/usr/share/gitlab-runner/clear-docker-cache` on your own host and treating the official docs as the authority rather than relying on my description alone.

I ran both `space` and `prune-volumes` this time, and I didn't record a reclaimed amount for either, so I can't say how much each contributed.

### What Runner Cache Volumes Look Like

The later `docker volume prune` output listed a large number of volumes with names like these (excerpt):

```text
runner-257c3558d36448c8ac6d9afa4cf72e23-cache-3c3f060a0374fc8bc39395164f415a70-protected
runner-e54a922b4213cf9950575ff3c43575c2-cache-3c3f060a0374fc8bc39395164f415a70-protected
runner-bc6bbf6bc42a848aa9d131e37a07e1f2-cache-c33bcaa1fd277edf3893b41966cea8
```

The `runner-<id>-cache-<hash>` pattern matches how the Docker executor names the volumes it creates for CI cache, and the `-protected` suffix corresponds to cache for protected branches. Different jobs and Runners each produce their own, so given enough time they add up. Volume naming rules do change between Runner versions, though, and I'm judging by the name pattern here. I didn't map each volume back to a specific job.

### Cleaning Up the Volumes

```bash
sudo docker volume prune -a -f
```

- **`docker volume prune`**: Removes local volumes that aren't used by any container.
- **`-a` (`--all`)**: As of Docker 23.0, the default only removes anonymous volumes. Adding `-a` removes named volumes too. Runner cache volumes are named, so `-a` is needed.
- **`-f`**: Skips the confirmation prompt.

The final output:

```text
Total reclaimed space: 12.91GB
```

**It reclaimed 12.91 GB.**

### Why Volume Cleanup Needs Extra Care

I want to stress this: `docker volume prune -a` doesn't clean **only** GitLab Runner cache. It removes **every** volume on the host that no container is using. If the same host has a database or another service with a named volume, and its container happens to be stopped at that moment, that volume gets deleted as well.

A deleted image can be pulled again, and a deleted cache just makes the next build slower, but if a volume holds real data, deleting it means losing that data. This time it was a Runner host, and the volume names in the output were almost all in the Runner cache format, which is why I chose to do it this way. On a host whose purpose I'm not sure about, I'd first take inventory with `docker volume ls`, or use the narrower `clear-docker-cache prune-volumes` instead.

## Results

| Cleanup item | Command | Space reclaimed |
|---|---|---|
| Docker System Prune | `docker system prune -a -f` | 20.05 GB |
| Docker Volume Prune | `docker volume prune -a -f` | 12.91 GB |
| Total | | 32.96 GB |

This is the sum of what each command reported, **not** the increase in free space measured with `df -h`. The logs, build cache, and `clear-docker-cache` were cleaned as well, but their contributions weren't recorded separately, so they aren't in this table.

## Risks and Precautions

The scope of this cleanup was not small. These are the points I think matter most in practice:

- **Make sure no CI job is running.** If an image or volume is in use by a job while you clean it, the job may fail. Pause the Runner first, or pick a time when nothing is scheduled.
- **Confirm the host only serves CI.** If other services run on the same host, find out which images and volumes they depend on before deciding whether to use `-a`.
- **The impact of `docker system prune -a`.** It removes every image no container uses, including `latest` or commonly used base images. The next job has to pull them again, which costs time and bandwidth.
- **The data-loss risk of `docker volume prune -a`.** As noted above, it doesn't care about purpose, only whether a container is using the volume. If a volume holds data, it can't be recovered.
- **The next build gets slower after the CI cache is cleared.** Package downloads and dependency installs have to be redone. That's an expected cost.
- **Don't manually delete files inside `/var/lib/docker`.** Even if `overlay2` looks huge, don't `rm` it directly. That leaves Docker's metadata and the actual files inconsistent. Clean up through Docker's own commands.
- **In production, take inventory first, then plan.** Use `docker system df -v` and `docker volume ls` to understand what each resource is for, then decide on the commands and frequency.

## Preventing It from Happening Again

This time I only acted when the disk was nearly full, which is reactive. To avoid a repeat, I'd consider:

- **Checking disk space regularly**, with a usage alert (for example, notify above a certain percentage) so the work happens before jobs start failing.
- **Monitoring Docker resources with `docker system df`** to see which category (images, volumes, build cache) is growing.
- **Deciding on a build cache cleanup interval.** The price of clearing build cache is slower builds, so it's a trade-off between space and build time.
- **Managing a retention policy for Runner cache**, for example periodically using a narrow-scope tool such as `clear-docker-cache`, rather than waiting until it has accumulated to gigabytes.
- **Designing the cleanup routine around the host's purpose and job schedule**: run it when no jobs are executing, target only resources managed by the Runner, and record `docker system df` before and after, so you have data to compare against.

I would not recommend scheduling `docker volume prune -a` to run unconditionally every day. Its scope is too broad. If a volume you need to keep ever shows up on the host, it would be deleted without anyone noticing.

## Conclusion

The biggest takeaway from this incident: **when a CI Runner runs low on disk space, logs or build cache aren't necessarily the cause. Docker images and Runner cache volumes that accumulate over a long time can be the main reason.** I spent some time on logs and build cache. Those steps are cheap and worth ruling out first, but if I had started with `docker system df -v` to see how much each type of resource was using, I probably would have found the direction faster.

The other lesson is record-keeping. Because I didn't capture before-and-after numbers at every step, only the last two commands in this post come with a firm reclaimed-space figure. Next time I'll record `df -h` and `docker system df` before and after cleanup, so my conclusions don't depend on memory.

## References

- [Docker Docs: docker system prune](https://docs.docker.com/reference/cli/docker/system/prune/)
- [Docker Docs: docker builder prune](https://docs.docker.com/reference/cli/docker/builder/prune/)
- [Docker Docs: docker volume prune](https://docs.docker.com/reference/cli/docker/volume/prune/)
- [Docker Docs: docker system df](https://docs.docker.com/reference/cli/docker/system/df/)
- [GitLab Docs: Docker executor (including cache and clearing the Docker cache)](https://docs.gitlab.com/runner/executors/docker/)
- [systemd: journalctl](https://www.freedesktop.org/software/systemd/man/latest/journalctl.html)
