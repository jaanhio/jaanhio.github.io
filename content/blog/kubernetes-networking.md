---
title: "Deep dive into Kubernetes Networking"
date: 2021-08-29T14:34:34+08:00
slug: ""
description: ""
keywords: []
draft: true
tags: []
math: false
toc: false
---

Topics to cover:
- packet capture tools to analyse traffic (tshark, tcpdump)
- understanding the routing setup via kernel routing (e.g `route` or `ip route`) and iptables (linux netfilter) what is the difference between iptables and `ip route`?
- check routes before Weave CNI plugin is installed
- podCIDR on nodes are 10.244.x.x/12 but running pods have IP address matching the CIDR range given by Weave CNI. is that why pods are not able to communicate with each other without a plugin?
- TC (traffic control)? how does it work with iptables and ip route?
- https://www.youtube.com/watch?v=GgCA2USI5iQ&t=1368s&ab_channel=CNCF%5BCloudNativeComputingFoundation%5D
- https://www.youtube.com/watch?v=InZVNuKY5GY&ab_channel=CNCF%5BCloudNativeComputingFoundation%5D
- https://www.redhat.com/sysadmin/telnet-netcat-troubleshooting