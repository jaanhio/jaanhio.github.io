---
title: "Kubernetes CPU requests and limits"
date: 2021-11-11T19:30:06+08:00
slug: ""
description: ""
keywords: []
draft: false
tags: []
math: false
toc: false
---

It all started with this alert.

```
Processes experience elevated CPU throttling.
25.91% throttling of CPU in namespace vault for container consul in pod consul-server-2.
```

I checked the dashboards and see that CPU usage was periodically peaking above the `resources.requests.cpu` (red line). Perhaps I should increase the CPU requests a little.

{{<zoomable-img src="consul-cpu-stats.png">}}

But throttling? Why was the process facing CPU throttling when there's still quite a bit more to go before hitting the `resources.limits.cpu` (orange line)?

Isn't the "CPU throttling logic" simply:

```
if cpuUsage > cpuLimit {
    throttle()
} else {
    continueWithProcess()
}
```

---

# Container requests and limits

Pods are the smallest deployable units of computing that one can create and manage in Kubernetes.

Within pods are containers. There can be one or more containers, which we specify using a container specs list under [PodSpec](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#PodSpec).

Under the [container specs](https://kubernetes.io/docs/reference/kubernetes-api/workload-resources/pod-v1/#Container), we can specify the CPU and memory resources of the container(s) that will be running within a pod.

## Setting the requests and limits
```
apiVersion: v1
kind: Pod
.
.
spec:
  containers:
  - .
    .
    .
    resources:
      limits:
        cpu: "1"
        memory: 400Mi
      requests:
        cpu: 500m
        memory: 200Mi
```
These `spec.containers[].resources` specifications are then used by Kubernetes for workload scheduling and resource limiting.
> `requests` are used by [kube-scheduler](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/#scheduling) to decide which worker node to assign a pod to.

> `limits ` are used by [kubelet](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet/#synopsis) to limit how much resources a container can use

Put simply, we can view them as soft limits (requests) and hard limits (limits).



## How are these CPU requests and limits mechanisms implemented by Kubernetes?

For those who aren't aware, "containers" isn't a first-class concept in Linux. It is made up of Linux features like `cgroups` and `namespaces` to isolate processes and control their available resources.

Similarly for `requests` and `limits`. Under the hood, they are using Linux features too.

### CPU requests

CPU request is implemented using `cpu.shares`, which is a feature of `cgroups`. CPU shares dictates how much CPU time a process can use.

We can confirm this by navigating to the `/sys/fs/cgroup/cpu,cpuacct` directory within a pod and printing the `cpu.shares` file.
```
/ $ cd /sys/fs/cgroup/cpu,cpuacct/
/sys/fs/cgroup/cpu,cpuacct $ cat cpu.shares
51
```
The `cpu.shares` should match the container's `resources.requests.cpu` value (in this case, it is `cpu: 50m`)

Note: the value represents the **relative share of CPU** a container will receive **when there is contention for CPU resources**.


Let's assume we are deploying containers/pods on a single core node.


# References:
https://www.kernel.org/doc/html/latest/scheduler/sched-bwc.html
https://engineering.squarespace.com/blog/2017/understanding-linux-container-scheduling
https://medium.com/omio-engineering/cpu-limits-and-aggressive-throttling-in-kubernetes-c5b20bd8a718
https://engineering.indeedblog.com/blog/2019/12/cpu-throttling-regression-fix/
https://www.kernel.org/doc/html/latest/scheduler/sched-bwc.html
https://manpages.ubuntu.com/manpages/cosmic/man7/cgroups.7.html
