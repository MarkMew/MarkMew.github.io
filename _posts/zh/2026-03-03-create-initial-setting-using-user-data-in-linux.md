---
layout: post
title: 使用 User Data 為 Linux EC2 建立初始資料
author: Mark_Mew
category: AWS
tags: [AWS, EC2]
date: 2026-3-3
---

EC2 是 AWS 相當常用 IaaS 功能

簡單來說就是一個虛擬機械

可以供使用者連線進去做操作

不過在佈建 EC2 或是這類型虛擬機的時候

我們會遇到一個狀況

就是機械會有多個使用者共同操作使用

而不是只有一個使用者

如果只有一台機械還好

只需要登入後執行一次 Script 就好

假使有多台機械或是機械是由 autoscaling group 所建立

這時候就需要在建立機械的同時

就將使用者資訊和 Credentials 寫入的虛擬機中

而 EC2 中的 User Data 就是為此而生

無論是 template 或是按需建立的 EC2

都可以在建立的同時將需要一併執行的 script 放入

這時候便可以在機械啟動的同時也執行這段 script

以下分別為 Amazon Linux 2023 和 Ubuntu 建立的範例

Amazon Linux 2023 範例如下
```bash
#!/bin/bash
user="mark"
echo "Copying the Mark's SSH Key to the server"

adduser $user

# Add the user's auth key to allow ssh access
mkdir /home/$user/.ssh
echo "ssh-rsa publickey
 mark" >> /home/$user/.ssh/authorized_keys
# Change ownership and access modes for the new directory/file
chown -R $user:$user /home/$user/.ssh
chmod -R go-rx /home/$user/.ssh
```

Ubuntu 範例如下
```bash
#!/bin/bash
user="mark"
echo "Copying the SSH Key to the server"

adduser --disabled-password --gecos "" $user
usermod -a -G adm $user
usermod -a -G sudo $user
echo "$user ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/90-cloud-init-users

# Add the user's auth key to allow ssh access
mkdir /home/$user/.ssh
echo "publickey mark" >> /home/$user/.ssh/authorized_keys
# Change ownership and access modes for the new directory/file
chown -R $user:$user /home/$user/.ssh
chmod -R go-rx /home/$user/.ssh
```

> [!CAUTION]  
> 執行失敗的話，EC2 還是可以正常啟動，只是結果不如預期，
> 多行指令需要執行的話，從執行失敗的程式碼開始就會被中斷


> [!NOTE]  
> 想要查看自己輸入的 User Data 是甚麼，或是變數是否有正常載入，在登入 AWS Cloud Console 以後，在 EC2 的頁面中，點選 EC2 ID > 進到 EC2 明細頁中，可在 Actions > Instance settings > Edit user data 中找到

---

參考資料

1. [AWS User Data Script to create users when launching an Ubuntu server EC2 instance](https://gist.github.com/vasansr/db7911b555f9556737694df26596ab1f)

2. [How do I add new user accounts with SSH access to my EC2 instance using cloud-init and user data?](https://repost.aws/knowledge-center/ec2-user-account-cloud-init-user-data)
