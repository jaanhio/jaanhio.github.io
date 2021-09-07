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
$ git clone --depth 1 http://github.com/brendangregg/FlameGraph
$ cd FlameGraph
$ ./stackcollapse-perf.pl < ../perf | ./flamegraph.pl --colors js > ../node-flamegraph.svg
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

Many foreign terms (`__libc_start_main`, `uv_*`, `Builtins_*`) and some a little for familiar ones (`node::*`, `v8::Function::*`). Well, I say familiar because i see the word `node` (as in nodejs) and `v8` (as in V8 engine); I still have no idea what they actually do. 

Let's dive a little deeper.

#### __libc_start_main

#### uv_*


- uv_run
- uv__io_poll

