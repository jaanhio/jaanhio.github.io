---
title: "Managing multiple EKS clusters access using Apiservers' private endpoints with AWS VPN"
date: 2021-10-18T08:11:48+08:00
slug: "eks-private-ip-resolution"
description: ""
keywords: ["aws", "eks", "dns"]
draft: false
tags: ["aws", "eks", "dns"]
math: false
toc: false
---

I manage multiple EKS clusters (multi-envs multi-tenants) at work and access to these is via Bastion instances deployed within each VPC of those clusters.

However this approach can become unmaintainable over time as the number of Bastion instances will grow with the number of clusters we manage. This means additional effort required for monitoring and maintenance of each of those Bastion instances.

{{<zoomable-img src="multi-cluster.png">}}

This led to the idea of removing all Bastion instances and configure direct access to Apiservers instead.

There's a few ways we can accomplish this:
* entirely remove Bastion instances and allow users to access all EKS Apiservers via their **publice endpoints**
* entirely remove Bastion instances and allow users to access all EKS Apiservers via their **private endpoints** + AWS VPN servers in each VPC
* entirely remove Bastion instances and allow users to access all EKS Apiservers via their **private endpoints** + single AWS VPN server

---

## Accessing Apiservers via their public endpoints
This is the most straightforward approach, and also the least maintainable one. Let me explain.

#### Increased attack surface

Having a publicly exposed endpoint for the EKS Apiservers is akin to apartments having publicly accessible doors. To control access, we use credentials and keys to authenticate users, similar to how the apartment door can only be unlocked by specific keys given to a few tenants.

BUT just because someone doesn't have valid credentials to access doesn't mean they will not try accessing it.

{{<zoomable-img src="public-access.png">}}

Fortunately, AWS EKS comes with the ability to whitelist IP addresses that can access reach the public endpoints.

This approach works well for a small team but when we are configuring access for potentially hundreds of users, this whitelisting approach can get real messy real quick.

Also considering that most of us are working remotely, we certainly do not want to be updating the whitelist every single time we switched to a different location to do our work.

---

## Access Apiservers via their private endpoints + AWS VPN servers

How can we reduce our attack surface without having to manually whitelist valid users' IP addresses?

Simple: by removing the public endpoints entirely.

{{<zoomable-img src="vpn-access.png">}}

However in a multi-clusters/VPCs environment, it can be a chore to constantly switch between VPN profiles in order to access different Apiservers.

I read that OpenVPN has a paid service that can help with management of multiple VPN servers access but it might not be suitable for us as we are using AWS VPN.

Which brings us to the last option...

---

## Access Apiservers via their private endpoints + a single AWS VPN server

For now, this seems to be the best approach out of the 3 in terms of security and maintainability, with the assumption that availability of AWS VPN service shouldn't be a concern.

Is this entirely bullet-proof? Probably not, since we are still one misconfiguration away from locking us out from all clusters (however unlikely). But it is still something worth exploring.

{{<zoomable-img src="single-vpn.png">}}

### Configuration

For this approach to work, we definitely need some form of network connections between the various VPCs.

This can be accomplished using either [AWS Transit Gateways](https://docs.aws.amazon.com/vpc/latest/tgw/what-is-transit-gateway.html) or [VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html), followed by updating the various subnets' route tables with the appropriate routing rules.

Transit Gateway? :white_check_mark:

Route tables updated? :white_check_mark:

Connected to cluster A's VPN server? :white_check_mark:

Now `dig <external apiserver endpoint>`....returned a public IP address. What am I missing?

After some thorough Googling, I finally found an [AWS blog guide](https://aws.amazon.com/blogs/compute/enabling-dns-resolution-for-amazon-eks-cluster-endpoints/) covering exactly what I wanted to achieve!

Turns out the Route53's `Inbound Endpoints`, `Outbound Endpoints` and `Rules` were missing (TIL moment right here).

{{<zoomable-img src="route53-config.png">}}

With those configurations, I ran `dig` command again and finally managed to resolved the private IP address of Apiserver residing in another VPC!
