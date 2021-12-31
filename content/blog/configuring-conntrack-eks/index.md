---
title: "Configuring conntrack limits for EKS worker nodes"
date: 2021-12-31T10:56:04+08:00
slug: ""
description: "It's the last week of the year, which means more time to clean up those tech debts..."
keywords: ["kubernetes", "linux", "networking", "iptables", "conntrack"]
draft: false
tags: []
math: false
toc: false
---

It's the last week of the year, which means more time to clean up those tech debts, one of which would be looking at some of our not-so-critical alerts and fixing them for good.

One of the firing alerts caught my eye:
```yaml
name: NodeHighNumberConntrackEntriesUsed
expr: (node_nf_conntrack_entries / node_nf_conntrack_entries_limit) > 0.75
labels:
    severity: warning
annotations:
    description: {{ $value | humanizePercentage }} of conntrack entries are used.
    runbook_url: https://github.com/kubernetes-monitoring/kubernetes-mixin/tree/master/runbook.md#alert-name-nodehighnumberconntrackentriesused
    summary: Number of conntrack are getting close to the limit.
```

I then checked the dashboards and noticed signs of network saturation.

{{<zoomable-img src="network-saturation.png">}}

We can also see kernel logs related to dropped packets using `dmesg`.
```bash
[ 3590.416157] nf_conntrack: nf_conntrack: table full, dropping packet
[ 3591.021991] nf_conntrack: nf_conntrack: table full, dropping packet
[ 3592.882524] net_ratelimit: 4 callbacks suppressed
[ 3592.882525] nf_conntrack: nf_conntrack: table full, dropping packet
[ 3593.302573] nf_conntrack: nf_conntrack: table full, dropping packet
[ 3593.335852] nf_conntrack: nf_conntrack: table full, dropping packet
```

This is worrying since it is potentially affecting the user experience of our tenants accessing our services.

Oddly, it's only affecting 1 out of 6 worker nodes.

Some time spent investigating later, I identified `ingress-nginx-controller` pod (using `container_sockets` metric) as the process occupying much of the `conntrack` table, which is somewhat expected since it is the entrypoint to our cluster.


## What is conntrack?
Conntrack (aka "connection tracking") is a core feature of Linux kernel's networking stack and is built on top of the [netfilter](https://www.netfilter.org/) framework.

It allows the kernel to track all network connections (protocol, source IP, source port, destination IP, destination port, connection state) on a table, thereby granting the kernel the ability to identify all packets which make up each connection and handle these connections consistently (`iptables` rules).

```bash
> sudo conntrack -L
.
..
...
tcp      6 1 TIME_WAIT src=10.189.1.107 dst=10.189.1.6 sport=60055 dport=10901 src=10.189.1.6 dst=10.189.1.107 sport=10901 dport=60055 [ASSURED] mark=0 use=1
udp      17 25 src=10.189.1.6 dst=10.189.1.73 sport=44762 dport=8472 [UNREPLIED] src=10.189.1.73 dst=10.189.1.6 sport=8472 dport=44762 mark=0 use=1
tcp      6 115 TIME_WAIT src=10.189.1.73 dst=10.189.1.6 sport=39640 dport=10901 src=10.189.1.6 dst=10.189.1.73 sport=10901 dport=39640 [ASSURED] mark=0 use=1
```

## How is it used by Kubernetes?
Kubernetes uses [Service](https://kubernetes.io/docs/concepts/services-networking/service/) as an abstract way of exposing application running on pods. This means load can be distributed across the pods via a single DNS name.

There's primarily two ways (excluding CNIs) this is implemented:
* [iptables mode](https://kubernetes.io/docs/concepts/services-networking/service/#proxy-mode-iptables)
* [IPVS mode](https://kubernetes.io/docs/concepts/services-networking/service/#proxy-mode-ipvs)

`iptables` mode is where `conntrack` comes into play.

From the previous section, we know that `iptables` works by interacting with packet filtering hooks provided by `netfilter` to determine what to do with packets belonging to each connection.

## Implementing a fix to this conntrack exhaustion problem

I did some research and seems like there's 2 approaches to this problem:
* increasing `net.netfilter.nf_conntrack_max` value based on this formula `CONNTRACK_MAX = RAMSIZE (in bytes)/16384/(OS-architecture bit)/32` (e.g for server with 16GB RAM running 64-bit OS, formula will be `CONNTRACK_MAX = 16 * 1024 * 1024 * 1024 / 16384 / 64 / 2`)
* decreasing the connection timeout so that stale connections are terminated as soon as possible

I manually tested the first approach and seems like it did solve the problem (for now?). Network saturation dropped to 0, although it came with an increase in CPU and memory utilization.
{{<zoomable-img src="post-fix.png">}}

Now to move this configuration change into IaC (infrastructure-as-code).

### How NOT to do this - the EC2 launch template user data approach

Since I tested this by manually updating the `net.netfilter.nf_conntrack_max` value using `sysctl`, I figured I can simply move those commands into a script under [EC2 launch template user data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html) and let it be executed when new instances boot up.
```bash
# formula is available_ram_in_bytes / 16384 / 2 (https://support.huaweicloud.com/intl/en-us/trouble-ecs/ecs_trouble_0324.html)
AVAILABLE_RAM_IN_BYTES=$(free -b | sed -n '2 p' | awk '{ print $2 }')
RECOMMENDED_MAX_CONNTRACK=$(($AVAILABLE_RAM_IN_BYTES/16384/2))
echo "net.netfilter.nf_conntrack_max = $RECOMMENDED_MAX_CONNTRACK" | sudo tee -a /etc/sysctl.conf
sudo sysctl --system
```

PR created, approved, deployed and I expected the `node_nf_conntrack_entries_limit` to be increased for all new instances.

But nope, `node_nf_conntrack_entries_limit` remained at `131072` (note: t2.xlarge instances were used).

Just to be sure, I SSHed into an instance and ran `sudo sysctl -a | grep conntrack` to check the values. It was indeed unmodified.

I then checked the `/var/log/cloud-init-output.log` and verified that the `sysctl --system` command was executed and even the `net.netfilter.nf_conntrack_max = $MAX` key was added to `/etc/sysctl.conf`.

What. the. hell. is going on.

A full day of reading and researching later, I found this `kube-proxy` documentation: https://kubernetes.io/docs/reference/config-api/kube-proxy-config.v1alpha1/#kubeproxy-config-k8s-io-v1alpha1-KubeProxyConntrackConfiguration

FINALLY.

### How to do this - the modifying kube-proxy configmap approach

At my current work, we access our various EKS clusters using a bastion instance. This means I can automate the updating of kube-proxy configmap using the bastion instance's Terraform init script.

```bash
AVAILABLE_MEM_IN_KB=$(kubectl get nodes -o jsonpath='{.items[*].status.allocatable.memory}' | awk '{ print $1}' | sed 's/Ki.*//') # memory value is given in Ki units
CORES_COUNT=$(kubectl get nodes -o jsonpath='{.items[*].status.capacity.cpu}' | awk '{ print $1}')
RECOMMENDED_MAX_CONNTRACK=$(($AVAILABLE_MEM_IN_KB*1024/16384/2)) # arithmetic operations done using (()) will only return int, thus no need to convert before writing to config file which expects only int
RECOMMENDED_MAX_CONNTRACK_PER_CORE=$(($RECOMMENDED_MAX_CONNTRACK/$CORES_COUNT))
CURRENT_MAX_CONNTRACK_PER_CORE=$(kubectl get cm kube-proxy-config -n kube-system -o jsonpath='{.data.config}' | grep 'maxPerCore:' | sed 's/^.*: //') # this is used to perform sed match and replace later
kubectl get cm kube-proxy-config -n kube-system -o yaml | sed "s/maxPerCore: ${CURRENT_MAX_CONNTRACK_PER_CORE}/maxPerCore: ${RECOMMENDED_MAX_CONNTRACK_PER_CORE}/" | kubectl apply -f -
kubectl rollout restart ds kube-proxy -n kube-system
```

Hope this post helps someone out there (probably future-me)!

## Some great reading materials
* https://blog.cloudflare.com/conntrack-tales-one-thousand-and-one-flows/
* https://www.tigera.io/blog/when-linux-conntrack-is-no-longer-your-friend/
* https://deploy.live/blog/kubernetes-networking-problems-due-to-the-conntrack/
* https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html/kernel_administration_guide/working_with_sysctl_and_kernel_tunables
* https://support.huaweicloud.com/intl/en-us/trouble-ecs/ecs_trouble_0324.html
* https://arthurchiao.art/blog/conntrack-design-and-implementation/
* [Liberating Kubernetes From Kube-proxy and Iptables - Martynas Pumputis, Cilium](https://youtu.be/bIRwSIwNHC0)
