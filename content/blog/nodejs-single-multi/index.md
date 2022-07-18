---
title: "Is Node.js single-threaded or multi-threaded?"
date: 2022-07-09T14:25:21+08:00
slug: ""
description: "Or both?"
keywords: []
draft: false
tags: []
math: false
toc: false
---

I am sure most of us who have used Node.js have heard of this statement:

> Node.js is single-threaded.

Is this statement correct? Well yes, partially.

Node.js uses an asynchronous event-driven architecture consisting of an `event loop` and a `worker pool`.

When we say that Node.js is single-threaded, we are actually referring to the `event loop` which is also known as the **single main/event thread**. This `event loop` handles the orchestration of new client connection and the corresponding response.

The `worker pool`, as the name suggests, consists of multiple threads forming a thread pool, used particularly for expensive tasks that are I/O-intensive and/or CPU-intensive so that the main thread doesn't get blocked.

The short answer to the question is Node.js: it is both single and multi threaded depending on what tasks are being executed.

---

## Worker pool

According to the ["don't block the event loop"](https://nodejs.org/en/docs/guides/dont-block-the-event-loop/) guide, these are the Node.js APIs that uses the `worker pool`:

> I/O-intensive tasks
> - DNS (`dns.lookup()`, `dns.lookupService()`)
> - File system (all file system API except `fs.FSWatcher()` and those that are explicitly synchronous)

> CPU-intensive tasks
> - Crypto (`crypto.pbkdf2()`, `crypto.scrypt()`, `crypto.randomBytes()`, `crypto.randomFill()`, `crypto.generateKeyPair()`)
> - Zlib (all except those are explicitly synchronous)

On top of these, it's also possible for applications and modules that use a [C++ add-on](https://nodejs.org/api/addons.html) to submit tasks to the `worker pool`.

This means all other intensive tasks do not make use of the worker pool:
* very long running for-loop (e.g a really inefficient way of determining if a number is a prime number)
* synchronous version of APIs listed above (e.g `crypto.randomFillSync()`, `zlib.inflateSync` etc)

How does the application performance differ between using, for example, `crypto.randomFill()` (using `worker pool`) and `crypto.randomFillSync()` (non `worker pool`)?

---

## Experiment

#### Setup

Node application source code: <<link to github here>>

To prevent [noisy neighbour effect](https://docs.microsoft.com/en-us/azure/architecture/antipatterns/noisy-neighbor/noisy-neighbor) from affecting the result of the experiment, I chose to run the node application on my idle raspberry pi 4 (4CPU, 4GB memory) running `ubuntu 21.10`.

```bash
ubuntu@ubuntu:~$ cat /etc/*-release
DISTRIB_ID=Ubuntu
DISTRIB_RELEASE=21.10
DISTRIB_CODENAME=impish
DISTRIB_DESCRIPTION="Ubuntu 21.10"
PRETTY_NAME="Ubuntu 21.10"
NAME="Ubuntu"
VERSION_ID="21.10"
VERSION="21.10 (Impish Indri)"
VERSION_CODENAME=impish
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=impish

ubuntu@ubuntu:~$ uname -r
5.13.0-1031-raspi

ubuntu@ubuntu:~$ lscpu
Architecture:                    aarch64
CPU op-mode(s):                  32-bit, 64-bit
Byte Order:                      Little Endian
CPU(s):                          4
On-line CPU(s) list:             0-3
Thread(s) per core:              1
Core(s) per socket:              4
Socket(s):                       1
Vendor ID:                       ARM
Model:                           3
Model name:                      Cortex-A72
Stepping:                        r0p3
CPU max MHz:                     1500.0000
CPU min MHz:                     600.0000
BogoMIPS:                        108.00
Vulnerability Itlb multihit:     Not affected
Vulnerability L1tf:              Not affected
Vulnerability Mds:               Not affected
Vulnerability Meltdown:          Not affected
Vulnerability Spec store bypass: Vulnerable
Vulnerability Spectre v1:        Mitigation; __user pointer sanitization
Vulnerability Spectre v2:        Vulnerable
Vulnerability Srbds:             Not affected
Vulnerability Tsx async abort:   Not affected
Flags:                           fp asimd evtstrm crc32 cpuid

ubuntu@ubuntu:~$ free -m
               total        used        free      shared  buff/cache   available
Mem:            3791         227        3453           2         110        3426
Swap:              0           0           0
```

Talk about the `--v8-pool-size=2` https://nodejs.org/api/cli.html#--v8-pool-sizenum
Talk about the outcome of using worker pool vs non worker pool.

---

## Restaurant analogy

By now we should be clear of the existence of the `event loop` and `worker pool`, as well as how are they being used, but it can still being confusing as to how they both work together.

Let's use an analogy.

