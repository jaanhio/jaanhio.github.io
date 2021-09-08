---
title: "Nodejs application CPU profile analysis with Flame Graphs"
date: 2021-09-06T22:03:43+08:00
slug: "nodejs-flamegraph-analysis"
description: ""
keywords: ["debug", "performance analysis", "nodejs"]
draft: false
tags: ["debug", "performance analysis", "nodejs"]
math: false
toc: false
---

In my [previous post](/blog/debugging-nodejs-app), I shared about my debugging process using various Linux tools and debugger. During the process, I came across the analysis technique using flame graphs and thought it will be interesting to see what information I can get out of it.

---

## What are flame graphs?
Flame graphs, as the name suggests, are graphs that look like flames because of the shape and color (usually red-yellowish hues). It was invented by Brendan Gregg for the purpose of analyzing performance issue and understand CPU usage quickly.

{{<figure src="https://www.brendangregg.com/FlameGraphs/cpu-mysql-updated.svg" caption="Example flame graph https://www.brendangregg.com/FlameGraphs/cpu-mysql-updated.svg">}}

There are various flame graphs generation tool (e.g `stackvis`, `node-stackvis`) available but the one I will be using is the one built by Brendan Gregg http://github.com/brendangregg/FlameGraph.

As with all tools, it's important that we understand how to use it. Despite looking rather similar to most time-series graphs, the x/y axes do not represent value/time.

Taken from https://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html:
> - Each box represents a function in the stack (a "stack frame").
> - The y-axis shows stack depth (number of frames on the stack). The top box shows the function that was on-CPU. Everything beneath that is ancestry. The function beneath a function is its parent, just like the stack traces shown earlier. (Some flame graph implementations prefer to invert the order and use an "icicle layout", so flames look upside down.)
> - The x-axis spans the sample population. It does not show the passing of time from left to right, as most graphs do. The left to right ordering has no meaning (it's sorted alphabetically to maximize frame merging).
> - The width of the box shows the total time it was on-CPU or part of an ancestry that was on-CPU (based on sample count). Functions with wide boxes may consume more CPU per execution than those with narrow boxes, or, they may simply be called more often. The call count is not shown (or known via sampling).
> - The sample count can exceed elapsed time if multiple threads were running and sampled concurrently.
> - The colors aren't significant, and are usually picked at random to be warm colors (other meaningful palettes are supported).
---

## Capturing perf data

Before we can perform flame graph analysis, we have to first capture the CPU profile data. 

To do that, I will be using Linux [`perf`](https://perf.wiki.kernel.org/index.php/Main_Page) tool.

#### Installing perf
```bash
$ uname -a
Linux vm1 4.15.0-154-generic #161-Ubuntu SMP Fri Jul 30 13:04:17 UTC 2021 x86_64 x86_64 x86_64 GNU/Linux

$ sudo apt install -y linux-tools-4.15.0-154-generic
```

#### Capturing profile
```bash
$ sudo perf record -e cycles:u -g -- npm run watch
...
..
.
^C[ perf record: Woken up 33 times to write data ]
failed to mmap file
Terminated
[ perf record: Captured and wrote 8.227 MB perf.data ]
```
After recording, `perf` will generate a `perf.data` file and also a `perf-*.map` file in the `/tmp` directory. The purpose of `.map` file is to provide `perf` with application-specifc symbol map, with which it will be able to tell which instruction pointers belong to which application functions.

#### Processing the data into flame graph
Currently we only have a raw `perf.data`, which isn't really useful.

We have to use `perf script` to generate a trace record file, do some scrubbing of the data to remove less-than-useful frames and finally generate the flame graph.
```bash
$ sudo perf script > perf.out
$ sed -i '/\[unknown\]/d' perf.out
$ sed -i -e "/( __libc_start| LazyCompile | v8::internal::| Builtin:| Stub:| LoadIC:|\[unknown\]| LoadPolymorphicIC:)/d" -e 's/ LazyCompile:[*~]\?/ /' perf.out
$ git clone --depth 1 http://github.com/brendangregg/FlameGraph
$ cd FlameGraph
$ ./stackcollapse-perf.pl < ../perf.out | ./flamegraph.pl --colors js > ../node-flamegraph.svg
```

#### Accessing the flame graph
You can open the `svg` directly in a browser. For my case, I used a simple Python HTTP server to serve the file as I am using a VM.
```
$ python3 -m http.server
```

---

## Analyzing the flame graph

Let's see what we can find out about Nodejs internals from this.

{{<zoomable-img src="flamegraph-zoomed-out.png" caption="Nodejs application flame graph">}}

Many foreign terms (`__libc_start_main`, `uv_*`, `Builtins_*`) and some a little more familiar ones (`node::*`, `v8::Function::*`).

After some researching, I found this awesome article on [Nodejs internals](https://www.smashingmagazine.com/2020/04/nodejs-internals/). Despite having used Nodejs for a few years, it's always been sort of a blackbox to me. It's really interesting to know what goes on underneath.

A little summary of the [article](https://www.smashingmagazine.com/2020/04/nodejs-internals/):
* Nodejs is a runtime i.e an environment provided for a program to execute successfully. In the case of Nodejs, it is through a combination of [V8](https://v8.dev/) and various C++ libraries to enable Nodejs applications to execute
* Core Nodejs dependencies are V8 and [libuv](http://docs.libuv.org/en/v1.x/index.html). 
* V8 allows Javascript source code (originally designed for browsers) to run outside of browser environment. 
* `libuv` is a library written in C++ that enables low-level (networking, file system, concurrency) access to operating system

Highly recommended to read it yourself and check out the examples in it.

Now the appearance of `__libc_start_main` and `uv_*` frames make sense!

`uv_*` are actually the functions from `libuv` library, which as explained, is required to provide low-level OS access. It is also used to [implement the Nodejs event loop](https://www.atomiccommits.io/event-loop-polling/)!

As for `__libc_start_main`, I found this [stackoverflow answer](https://stackoverflow.com/a/62709108) explaining the role of this function and seems to match the description taken from [Linux standard base specification](https://refspecs.linuxbase.org/LSB_3.1.0/LSB-generic/LSB-generic/baselib---libc-start-main-.html#:~:text=The%20__libc_start_main()%20function,to%20the%20exit()%20function.)
> `__libc_start_main` is an initialization routine and performs necessary initialization of execution environment.

Some further digging down the rabbit hole later, I found this [Linux x86 Program Start Up](http://dbp-consulting.com/tutorials/debugging/linuxProgramStartup.html) post, which explains the steps taken to load and run an application and the role that `__libc_start_main` plays.

---

As the current flame graph still contains Nodejs and V8 internal functions, I filtered it again to make application related functions more visible.
```bash
$ sed -i -E '/( __libc_start| LazyCompile | v8::internal::| Builtin:| Stub:| LoadIC:|\[unknown\]| LoadPolymorphicIC:)/d' perf.out
```

{{<zoomable-img src="filtered-flamegraph.png" caption="Flame graph after filtering non-application frames">}}

Almost immediately, we can see the functions called by `readable-stream`, `winston-transport`, `@elastic/elasticsearch` and would have helped greatly in identify the tranporting of huge amount of logs to ElasticCloud as the root cause behind the high CPU usage.

{{<zoomable-img src="zoomed-in-1.png" caption="Flame graph after filtering non-application frames">}}
{{<zoomable-img src="zoomed-in-2.png" caption="Flame graph after filtering non-application frames">}}
