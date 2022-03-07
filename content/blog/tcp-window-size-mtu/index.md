---
title: "Difference between TCP window size & MTU"
date: 2022-03-06T21:56:44+08:00
slug: ""
description: "A brief explanation on the differences between TCP window size & MTU."
keywords: ["networking", "tcp", "mtu"]
draft: false
tags: ["networking", "tcp", "mtu"]
math: false
toc: false
---

I was reading up on TCP recently when I came across the term "Window size", which also reminded me of another term I came across earlier, "MTU". 

I briefly understood that these 2 terms dictate how quickly data can be transferred between 2 machines, but what exactly are the differences?

Here is a very brief explanation on it.

# What is window size?

Window size is a TCP header value which controls the flow of data. The header space for this value is 2 bytes long, which translates to a maximum value of 65535 bytes. This value is OS/TCP stack dependent.

{{<zoomable-img src="window-size.png" alt="window-size" position="center" >}}

# What does it do?

Imagine you own a brewery and is currently tasked with transferring a huge tank of beer to your customer's own beer tank. 

Instead of being able to pump the beer directly into the other tank, your customer can only receive it with a pail before transferring it to the main tank.

The size of this pail is the `window size`. 

I used pail as an example but you can imagine it being a cup if the window size is even smaller.

Now think about the amount of round trips required to completely transfer the beer over. Throw in the latency between each transfer and we can easily see how this can become a bottleneck.

{{<zoomable-img src="small-cup.png" alt="small-cup" position="center" >}}

# Window scaling (optional)

For modern client-server communications, 65535 bytes wouldn't cut it.

Thankfully, there's the `window scale` option and is only sent with `SYN` packet. 

{{<zoomable-img src="window-scale.png" alt="window-scale" position="center" >}}

This serves as a multiplier for the `window size`, which means a much larger buffer to hold the data.

Using the beer transfer analogy again, it's like upgrading the pail to a cement truck.

{{<zoomable-img src="big-truck.png" alt="big-truck" position="center" >}}

Caveat: both server and client have to support this option, else it wouldn't be available for use.

# How does this differ from MTU?

MTU stands for Maximum Transmission Unit.

We can view the entire data transfer process as a combination of a few entities: server, client and the pipe connecting them.

The MTU determines the size of the pipe whereas `window size` determines the size of buffer at both ends.

{{<zoomable-img src="mtu.png" alt="mtu" position="center" >}}

Assuming MTU is 1500 bytes and the entire payload is 15000 bytes, there will be a total of 10 exchanges needed for entire transfer to complete.

Using Wireshark, we can see how MTU (1500 bytes) limits the `TCP segment len`, and also how these segments are finally assembled.

{{<zoomable-img src="assembled-segments.png" alt="big-truck" position="center" >}}

---

When performing analysis using Wireshark, do note that because `window scale` option is only sent with `SYN` packet, failing to capture this packet will result in Wireshark being unable to determine the "actual" `window size` and thus affect the analysis.

More info: https://networkengineering.stackexchange.com/questions/54107/how-can-a-tcp-window-size-be-allowed-to-be-larger-than-the-maximum-size-of-an-et