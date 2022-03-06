---
title: "Tcp Dive"
date: 2022-03-06T21:56:44+08:00
slug: ""
description: ""
keywords: ["networking", "tcp"]
draft: true
tags: ["networking", "tcp"]
math: false
toc: false
---

Client - Server

Client: hey this is my starting sequence. start with 1
Server: ok cool. this is mine too, start with 1
Client: nice.
Client: i want to send you something. this payload is 440bytes. the sequence is now at 440+1 = 441. to prove that i received your last msg, i will ack with sequence 1
Server: ok cool. i got your request. the payload is 1500bytes. the sequence is now at 1500+1 = 1501. to prove that i received your last msg, i will ack with sequence 441
Client: ok i got the first chunk. ack with sequence 1501
Server: ok you got the first chunk. sending next chunk with 1500bytes. the sequence is not at 1501+1500=3001. i will ack with sequence 441 (no change since the last time, which is expected since the client is making a request and is receiving it)

Client: ok i got the first file. i need another file also. this is the 340bytes payload. the sequence is now at 341 + 441 = 782. i will ack with 3001.


For most of the software engineers/developers out there, daily work is mostly on the application layer and networking layer isn't a domain that one usually ventures into. Thanks to the countless libraries and tools available, there's probably isn't a need to as most of the nitty gritty networking implementations have been abstracted away, which is great as it allows us to focus on the business logic.

That being said, it's always beneficial to understand the inner workings of technologies and tools that are working with daily. You never know when you might encounter an issue like the [40ms of latency that just would not go away](https://rachelbythebay.com/w/2020/10/14/lag/).

# What is window size?

Window size is a TCP header value which controls the flow of data. The header space for this value is 2 bytes long, which translates to a maximum value of 65535 bytes. This value is OS/TCP stack dependent.

<insert screenshots showing the different window size>

So how exactly does this work?

# What does it do?

Imagine you own a brewery and is currently tasked with transferring a huge tank of beer to your customer's own beer tank. 

Instead of being able to pump the beer directly into the other tank, your customer can only receive it with a pail before transferring it to the main tank.

The size of this pail is the window size. 

I used pail as an example but you can imagine it being a cup if the window size is even smaller.

Now think about the amount of round trips required to completely transfer the beer over. Throw in the latency between each transfer and we can easily see how this can become a bottleneck.

# Window scaling (optionally)

For modern client-server communications, 65535 bytes wouldn't cut it.

Thankfully, there's the `Window scale` option.

This serves as a multiplier for the `Window size`, which means a much larger buffer to hold the data.

Using the beer transfer analogy again, it's like upgrading the pail to a cement truck.

Caveat: both server and client have to support this option, else it wouldn't be available for use.

# How does this differ from MTU?

MTU stands for Maximum Transmission Unit.

We can view the entire data transfer process as a combination of a few entities: server, client and the pipe connecting them.

The MTU determines the size of the pipe whereas Window size determines the buffer at both ends.

Assuming MTU is 1500 bytes and the entire payload is 15000 bytes, there will be a total of 10 exchanges needed for 

A small MTU coupled with small Window size can significantly impact the time taken for communications between client and server. 

https://networkengineering.stackexchange.com/questions/54107/how-can-a-tcp-window-size-be-allowed-to-be-larger-than-the-maximum-size-of-an-et