---
title: "Debugging containers using nsenter"
date: 2021-10-11T20:25:08+08:00
slug: "nsenter-debug"
description: ""
keywords: ["debugging", "linux", "kubernetes"]
draft: false
tags: []
math: false
toc: false
---

If you have ever managed a Kubernetes cluster, chances are you have encountered pods that just doesn't want to behave the way they are supposed to.

You checked the logs and traced it back to the source code. Logic checks out :white_check_mark:

You started narrowing down the causes. Networking issue? Configuration issue?

You entered the container and decided to use `ping` to identify network connectivity issues.

```bash
/ $ ping google.com
PING google.com (142.251.12.138): 56 data bytes
ping: permission denied (are you root?)
```

Or maybe you wanted to install another tool like `tcpdump` to observe network traffic.

```bash
$ apt install tcpdump
E: Could not open lock file /var/lib/dpkg/lock-frontend - open (13: Permission denied)
E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), are you root?
```

Well, you can modify the `Dockerfile` to install additional tools.

OR if you have root access to the host machine that is running those containers...

---

**Introducing `nsenter`**.

Firstly, containers aren't really a thing. They are actually constructed using 2 Linux kernel features: `namespaces` and `cgroups`. When we run a container, it really is just running a process.

`namespaces` controls what is visible or accessible (i.e isolate processes from each other) and `cgroups` controls how much resources (`CPU` & `memory`) are allocated to a particular process.

`nsenter` is a tool that allows us to enter the namespaces of one or more other processes and then executes a specified program.

To do so, we first have to retrieve the `PID` of the container process.

```bash
docker ps | grep <container name>

CONTAINER_PID=$(docker inspect <container name> --format='{{ .State.Pid }}')

sudo nsenter -t $CONTAINER_PID -m -u -n -i -p sh #`-m -u -n -i -p` are referring to the various namespaces that you want to access (e.g mount, UTS, IPC, net, pid).
```
Now you are inside the "container" as a root user capable of running the `ping` and `apt install` commands above!

Do note that this is **not considered a vulnerability** as root privileges are required to run `nsenter` in the first place.

---

While researching on this, I chanced upon a docker command that seems to be doing the same thing:
```bash
docker exec -it --user root <container name> sh
```
As expected, I am able to enter container as a root user. However when I tried to execute `ping` command, I get an error:
```bash
/ # whoami
root
/ # ping google.com
PING google.com (74.125.200.139): 56 data bytes
ping: permission denied (are you root?)
```
Why is this happening? Perhaps I will cover this in another post.
