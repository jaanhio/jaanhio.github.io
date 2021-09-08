---
title: "Debugging high CPU usage and memory leak on Nodejs application"
date: 2021-09-04T15:28:44+08:00
slug: "debugging-nodejs-app"
description: ""
keywords: ["debug", "performance analysis", "nodejs"]
draft: false
tags: ["debug", "performance analysis", "nodejs"]
math: false
toc: false
---

Recently one of our nodejs application (responsible for scraping metrics for external services) running in our EKS cluster was experiencing high CPU usage and memory leak and I was tasked to figure out the root cause.
In this post, I will share my troubleshooting process and interesting stuff I discovered along the way.

It all began with an alert notifying us of the application experiencing CPU throttling. Looking at the dashboard, it became apparent that high CPU usage isn't the only issue; it was also experiencing memory leak and oddly high incoming and outgoing traffic.

{{<zoomable-img src="old-cpu-usage.png" caption="CPU usage">}}
{{<zoomable-img src="old-cpu-throttling.png" caption="CPU throttling">}}
{{<zoomable-img src="old-memory-usage.png" caption="Memory usage">}}
{{<zoomable-img src="old-network-bandwidth.png" caption="Network bandwidth">}}
{{<zoomable-img src="old-packet-rate.png" caption="Packet rate">}}

I also noticed the application producing a rather large amount of error logs (approximately 20logs/s).

I checked the application to verify the logic for triggering the scrape. It does so using an infinite recursive loop with delays between scrape implemented via `setTimeout` delays.

```javascript
async function exec(asyncFunc, delay) {
  try {
    await asyncFunc();
  } catch (e) {
    logger.error('Error executing', e);
  } finally {
    setTimeout(() => {
      exec(asyncFunc, delay);
    }, delay);
  }
}
```

---

## Setup

First thing I did was to install some additional tools on the container to provide more visibility as to what exactly is running (note: you might need to make some additional modifications to pod configurations in order run the following tools as root).
```bash
apt update && apt install -y strace lsof net-tools
```
`strace`: Tool that traces syscalls. Goal is to find out which syscalls are taking large percentage of CPU time.

`lsof`: Tool to list open files. Goal is to find out what connections are there.

`net-tools`: This package contains a variety of tools (e.g `arp`, `hostname`, `netstat` etc). I am installing just for using `netstat`. One can argue that lsof may be able to sufficiently replace use of netstat (check out this [awesome guide on lsof](https://danielmiessler.com/study/lsof/)), but I haven't figure how to use `lsof` to also display the `recv-q` and `send-q` data.

---

## Inspecting connections

I first used `lsof` to find out more information on the connections within pod.
```bash
# lsof -i
COMMAND PID USER   FD   TYPE    DEVICE SIZE/OFF NODE NAME
node     18 root   19u  IPv6 249577828      0t0  TCP *:9999 (LISTEN)
node     18 root   20u  IPv4 249738893      0t0  TCP exporter:52984->some-ip:9243 (ESTABLISHED)
node     18 root   21u  IPv4 249573270      0t0  TCP exporter:55846->some-ip2:9243 (ESTABLISHED)
node     18 root   23u  IPv4 249573271      0t0  TCP exporter:35286->some-ip3:9243 (ESTABLISHED)
node     18 root   24u  IPv4 249734064      0t0  TCP exporter:53960->some-ip4:9243 (ESTABLISHED)
node     18 root   25u  IPv4 249743967      0t0  TCP exporter:57936->some-ip:9243 (ESTABLISHED)
...
..
.

# lsof -i | grep 9243 | wc 
256
```

Excluding the header row and the only listening connection, there's a total of 256 connections, all to a bunch of IP addresses on port 9243. A quick Google search revealed that port 9243 is commonly used by ElasticCloud. Indeed, we do use `winston-elasticsearch` library for establishing transport of logs to ElasticCloud. 

I restarted the application multiple times while varying the duration between scrape and observed the number of connections created. Turns out it did not start with 256 connections but instead increases over time. Increasing the duration between scrape slowed down the rate of increase of connections. It also reduced the amount of logs produced.

{{<zoomable-img src="container-sockets.png" caption="Container sockets">}}
{{<zoomable-img src="container-fd.png" caption="Container FD">}}

Notice that number of connections is capped at 256? Definitely not a coincidence and some code somewhere is somehow limiting the max number of connections.

I also used `netstat` to get information on the `recv-q` and `send-q` on each socket.
```bash
# netstat -ntp
Active Internet connections (w/o servers)
Proto Recv-Q Send-Q Local Address           Foreign Address         State       PID/Program name
tcp     1101      0 10.189.2.170:43536      some-ip:9243      ESTABLISHED       19/node
tcp     1101      0 10.189.2.170:51434      some-ip:9243      ESTABLISHED       19/node
tcp     0       443 10.189.2.170:43534      some-ip:9243      ESTABLISHED       19/node
tcp     1101      0 10.189.2.170:47432      some-ip:9243      ESTABLISHED       19/node
tcp     1101      0 10.189.2.170:47384      some-ip:9243      ESTABLISHED       19/node
tcp     1101      0 10.189.2.170:34586      some-ip:9243      ESTABLISHED       19/node
...
..
.
```

As the name suggests, `recv-q` and `send-q` are the receive and send queues/buffer for a particular socket and indicates the number of bytes in the queue/buffer. Having non-zero value under any of the queue columns indicates that data is not being processed fast enough, which could be due to an abnormally large volume of data or something is slowing down the processing.

I also noticed that `recv-q` bytes is capped at `1101` and `send-q` is capped at `443`.

---

## Inspecting CPU load

Wanting to figure out which syscall is responsible for the bulk of CPU time, I attached `strace` to the node process and passed a `-c` flag to return a summary of syscalls traced. (note: `strace` introduces a significant amount of performance overhead and is not recommended to run in production environment. For that, `perf` will be a better tool)
```
# strace -p 25 -c
strace: Process 25 attached
^Cstrace: Process 25 detached
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 40.31    0.297807           8     39518           clock_gettime
 16.37    0.120910          22      5481         7 write
 12.05    0.089027           9      9968           gettimeofday
  8.51    0.062851         101       624           epoll_wait
  6.71    0.049588          10      5162           read
  5.70    0.042095          13      3280       146 futex
  5.54    0.040911           9      4616           epoll_ctl
  4.58    0.033837           9      3810           getpid
  0.17    0.001259           9       148           mprotect
  0.03    0.000244           9        26           mmap
  0.03    0.000230           9        26           munmap
  0.00    0.000022           6         4         1 writev
------ ----------- ----------- --------- --------- ----------------
100.00    0.738781                 72663       154 total
```

`clock_gettime`, `write`, `gettimeofday`?

I came across an article on [nodejs timers](https://asafdav2.github.io/2017/node-js-timers/), which covers how timers are managed internally and one particular line stood out to me
>  On top of user code and 3rd-party libraries using timers, timers are also used internally by the Node.js platform itself. For example, a dedicated timer is used with each TCP connection to detect a possible connection timeout. 

Timer for connections? Well, this application has create 256 connections to ElasticCloud. And it sure is sending a non-trivial amount of error logs to ElasticCloud, which could explain the high `% time` used by `write`.

At this point, my hypothesis for the root cause of high CPU usage and memory leak: use of `winston-elasticsearch` library coupled with the huge amount of logs being shipped through it.

I could have just removed the use of `winston-elasticsearch` in the application to verify my hypothesis but I wanted to dig deeper.

---

## CPU and memory profiling of application

For debugging purpose, I ran the application locally with `--inspect` flag and managed to replicate the same issue.

When a Nodejs process application is started with `--inspect` flag, the Nodejs process will listen for a debugging client. There are multiple clients available; I used Chrome Devtools. See [debugging guide](https://nodejs.org/en/docs/guides/debugging-getting-started/) for more information.

I then captured the CPU and memory profile.

{{<zoomable-img src="cpu-profile.png" caption="CPU profile">}}
From the CPU profile, we can see large percentage of CPU time used by `EventEmitter.emit`, with some of source files being `_stream_readable.js`, `_http_client.js`, `Transport.js`, `bulk_writer.js`, `Connection.js`.

Aha! These files are related to `winston-elasticsearch` library.
```javascript
const { ElasticsearchTransport } = require('winston-elasticsearch');

ElasticsearchTransport 
-> readable-stream
-> @elastic/elasticsearch
-> winston-elasticsearch
```

After spending some time tracing calls with debugger, I found the answer to the 256 connections limit: https://github.com/elastic/elasticsearch-js/blob/b67d42cb5ff7a39a1836d176266ac32af9e72f07/lib/Connection.js#L63
```javascript
 const agentOptions = Object.assign({}, {
        keepAlive: true,
        keepAliveMsecs: 1000,
        maxSockets: 256, <--------------- !!
        maxFreeSockets: 256,
        scheduling: 'lifo'
      }, opts.agent)
```

Depending on the options (`opts.proxy`) passed, the creation of sockets is handled either by Nodejs `http` or `https` module or `hpagent` (which uses `http`/`https` modules under-the-hood), which reminds me of the [power of Nodejs and event loop](https://medium.com/the-node-js-collection/why-the-hell-would-you-use-node-js-4b053b94ab8e) to support large number of concurrent connections

Now for the memory profile.
{{<zoomable-img src="memory-profile.png" caption="Memory profile">}}

I will not be sharing details of the objects captured due to potentially sensitive information but the bulk of it are these:
```javascript
(array): objects for connections to ElasticCloud
(string): payload for each log (looking closely, we can see theres many references to timers.js. this matches what was mentioned in the nodejs timers article above)
(closure): response objects...perhaps from ElasticCloud
```

---

## Final verification

I removed the use of `winston-elasticsearch` library and wala. Also, this library is no longer needed since we have `fluent-bit` running in our EKS clusters for shipping logs.

Below are diagrams comparing before and after change was made (new pod metrics in TEAL color).
{{<zoomable-img src="new-cpu-usage.png" caption="CPU usage">}}
{{<zoomable-img src="new-memory-usage.png" caption="Memory usage">}}
{{<zoomable-img src="new-network-bandwidth.png" caption="Network bandwidth">}}
{{<zoomable-img src="new-packet-rate.png" caption="Packet rate">}}

---

## Key takeaways

Tools are only as powerful as the wielder.

I have always believed in understanding the fundamentals of various topics/domains and not take the blackbox approach when using libraries/tools/frameworks and this experience has reinforced that belief. 

Honestly, I probably wouldn't even know where to start if I didn't have basic understanding of syscalls, linux networking, nodejs internals and the use of tools such as debugger, `strace`, `lsof`, `netcat`.
