---
title: "Kubernetes CPU requests and limits"
date: 2021-11-11T19:30:06+08:00
slug: ""
description: "It all started with this alert..."
keywords: ["linux", "cgroups", "namespaces", "kernel", "kubernetes"]
draft: false
tags: ["linux", "cgroups", "namespaces", "kernel", "kubernetes"]
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

Isn't the CPU throttling logic simply:

```
if cpuUsage > cpuLimit {
    throttle()
} else {
    continueWithProcess()
}
```

Well...not so simple...

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

For those who aren't aware, "containers" isn't a first-class concept in Linux. It is made up of Linux features like `cgroups` to control available resources to processes and `namespaces` to isolate processes.

A `cgroup` is basically a grouping of processes and consists of 2 parts - the core and controllers.

Taken from https://www.kernel.org/doc/Documentation/cgroup-v2.txt:
> cgroup is largely composed of two parts - the core and controllers. cgroup core is primarily responsible for hierarchically organizing
processes.  A cgroup controller is usually responsible for distributing a specific type of system resource along the hierarchy
although there are utility controllers which serve purposes other than resource distribution.

Under the hood, `requests.cpu` and `limits.cpu` are implemented using features of [CPU cgroup controller](https://kernel.googlesource.com/pub/scm/linux/kernel/git/glommer/memcg/+/cpu_stat/Documentation/cgroups/cpu.txt) (grouping processes) and CFS scheduler (assigning resource based on groupings)

Though the Kubernetes configuration for both `requests.cpu` & `limits.cpu` look similar, they are actually implemented using different mechanisms.

The related configurations and files are located under the `/sys/fs/cgroup/kubepods` directory.

{{<zoomable-img src="kubepods-dir.png">}}

From the image above, we can see how the `cgroup` directories are structured in order to control the CPU resource for each pod/process.

```
/kubepods
|__...cgroup related files
|__/besteffort
|   |__...cgroup related files
|   |__/pod700d3573-6918-4f34-a802-facd3d7c6228
|   |__/pod7c6497d6-c5c7-497f-8f8f-b54d9010ea49
|   |__/pod90c3c7ed-d488-4e2e-8aaf-edaa935f31b9
|   |__/podb8e4fe2d-6ca9-4ba1-bfc9-a4dfb40e9544
|   |__/podba6a8975-37a7-4c9c-a365-347844d069e6
|__/burstable
    |__...cgroup related files
    |__/podc8b9ed51-a468-46ec-afc8-8d000da6942e
    |__/podd7ee7ff2-9089-4825-ab80-281f59f5487a
    |__/podf8802cf7-4278-4596-b278-ce21f4ab2145
    |__/pod84cc4e4e-beea-4ff4-8700-5d534e266304
    |__/pod1351a523-8320-4bb2-9104-7528fd43e8ae
        |__...cgroup related files
        |__/ce90611f00c776ab1a99ba92c88d972aac6f89bf6fd5b2c4b16a0ba5c83cf28a
        |__/bd2bd6e9d405703ceb140e0a94eb4df02ed0930498459b1faeeba2504c81a7e8
```

We can also see that there's 10 pods (directories prefixed with `pod`) running on this particular node, which matches the output of `kubectl get pod | grep <node name>`.

{{<zoomable-img src="k-get-po.png">}}

Then there's the directories nested under one of the `pod` directories with alphanumeric hashes as their names. These are for the containers within a pod.

This is verified by comparing it with the details of the pods.

{{<zoomable-img src="example-pod.png">}}

---
### CPU requests via cpu.shares

CPU request is implemented using `cpu.shares`. CFS scheduler looks at the `cpu.shares` file configured for different process groupings to determine **how much CPU time a process can use**.

This file can be found at the `/sys/fs/cgroup/cpu,cpuacct` directory of a container:
```
/ $ cd /sys/fs/cgroup/cpu,cpuacct/
/sys/fs/cgroup/cpu,cpuacct $ cat cpu.shares
51
```
The `cpu.shares` should match the container's `resources.requests.cpu` value (in this case, it is `cpu: 50m`).

It is important to note that the value represents the **relative share of CPU time** a container will receive **when there is contention for CPU resources**. It **does not represent the actual CPU time** each container will receive.

In Kubernetes, **one CPU** (1000m) is equivalent to 1 vCPU/Core for cloud providers and 1 hyperthread on bare-metal Intel processors.

#### Assuming we are deploying 2 containers on a single core node and there's contention for CPU resources:
#### Scenario A: containers configured with similar `requests.cpu` values
```
container A:
  requests.cpu: 1000m
container B:
  requests.cpu: 1000m
```
Both containers will receive the same amount of CPU time.
#### Scenario B: containers configured with different `requests.cpu` values
```
container A:
  requests.cpu: 1000m
container B:
  requests.cpu: 2000m
```
In this scenario, container B will receive twice as much CPU time as container A.

#### What happens if only container A is running?
In this case, container A will get all the available CPU time since there's no other processes contending for CPU resources.

That being said, there might be cases where we want to put a hard limit on the amount of CPU time a set of processes have access to (e.g hostile workloads consuming unnecessary CPU time, limit resource usage when performing load test), which brings us to the next section.

---
### CPU limits via CFS quota

CPU limit is implemented using CFS bandwidth controller (a subsystem/extension of CFS scheduler), which will use values specified in `cpu.cfs_period_us` and `cpu.cfs_quota_us` (`us` = `μ`, microseconds) to control how much time is available to each control group.

`cpu.cfs_period_us`: length of the accounting period, also in microseconds. This is **configured to 100,000 in Kubernetes**.

`cpu.cfs_quota_us`: amount of CPU time (in microseconds) available to the group during each accounting period. This value is taken from the `limits.cpu`.

```
1 vCPU == 1000m == 100,000us
0.5vCPU == 500m == 50,000us
```

Similar to `cpu.shares`, the files can be found at `/sys/fs/cgroup/cpu,cpuacct` directory of a container:
```
/sys/fs/cgroup/cpu,cpuacct # cat cpu.cfs_quota_us
50000
/sys/fs/cgroup/cpu,cpuacct # cat cpu.cfs_period_us
100000
```

Let's say a web service container is the only process running and has the following `requests.cpu` set:
```
web service container:
  requests.cpu: 1000m
```
Assuming that it takes 200ms to respond to a request and since there's no contention for CPU time, it will have the full 200ms of CPU time uninterrupted.

What if we now set the `limits.cpu`?
```
web service container:
  requests.cpu: 1000m
  limits.cpu: 500m
```
The same request will now take 350ms to respond!

This is because instead of being able to use 200ms of uninterrupted CPU time, the process now has only a quota of `500m/1000m * 100,000us` **every 100,000us period**. Once the quota is depleted, the process will be throttled.

{{<zoomable-img src="cpu-throttle.png">}}

Throttling metrics can be found in the `cpu.stat` file:
```
/sys/fs/cgroup/cpu,cpuacct $ cat cpu.stat
nr_periods 258700
nr_throttled 107792
throttled_time 8635080132047
```

`nr_periods`: number of periods a process was running WITHOUT throttling

`nr_throttled`: number of periods a process was throttled

`throttled_time`: total time a thread in cgroup was throttled

`throttled_percentage`: (rate of change of `nr_throttled`)/(rate of change of `nr_periods`). This can give you an idea of how badly a process is being throttled.

#### What can you do about throttled applications/processes?

Fix the application OR increase/remove the limits!

## Conclusion
`requests.cpu` and `limits.cpu` seems similar but are implemented using very different mechanisms!

Just because `requests.cpu < limits.cpu` does not mean that the process/application/container will not be throttled.

## References
This was by far one of the most complicated topic I have researched on, bringing me down several rabbit holes, diving into kernel documentations, articles, videos etc.

For those interested, these are the resources that helped me greatly on this topic:

* https://www.kernel.org/doc/html/latest/scheduler/sched-bwc.html
* https://www.kernel.org/doc/html/latest/scheduler/sched-design-CFS.html
* https://engineering.squarespace.com/blog/2017/understanding-linux-container-scheduling
* https://medium.com/omio-engineering/cpu-limits-and-aggressive-throttling-in-kubernetes-c5b20bd8a718
* https://manpages.ubuntu.com/manpages/cosmic/man7/cgroups.7.html
* https://nodramadevops.com/2019/10/docker-cpu-resource-limits/
* https://man7.org/linux/man-pages/man7/cgroups.7.html
* https://kernel.googlesource.com/pub/scm/linux/kernel/git/glommer/memcg/+/cpu_stat/Documentation/cgroups/cgroups.txt
* https://lwn.net/Articles/844976/
* https://github.com/kubernetes/kubernetes/issues/51135#issuecomment-373454012
* https://github.com/kubernetes/kubernetes/issues/67577
* https://kubernetes.io/blog/2018/07/24/feature-highlight-cpu-manager/
* https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#meaning-of-cpu
* https://engineering.indeedblog.com/blog/2019/12/cpu-throttling-regression-fix/
* https://engineering.indeedblog.com/blog/2019/12/unthrottled-fixing-cpu-limits-in-the-cloud/
* [Throttling: New Developments in Application Performance with CPU Limits - Dave Chiluk, Indeed](https://www.youtube.com/watch?v=WB3_sV_EQrQ)
* [Resource Requests and Limits Under the Hood: The Journey of a Pod Spec - Kohei Ota & Kaslin Fields](https://www.youtube.com/watch?v=UE7QX98-kO0)
