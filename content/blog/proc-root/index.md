---
title: "A little trick I learned for copying files out of a (somewhat) locked down EC2 worker node for EKS"
date: 2023-09-16T14:54:10+08:00
slug: ""
description: "Disclaimer: you should have also have access to EKS cluster via `kubectl`"
keywords: ["eks", "kubectl", "proc", "pseudo-filesystem", "linux", "containers", "namespaces", "cgroups"]
draft: false
tags: ["eks", "kubectl", "proc", "pseudo-filesystem", "linux", "containers", "namespaces", "cgroups"]
math: false
toc: false
---

Scenario:

You encountered some weird networking issue with one of the pods running on EKS cluster and decided to perform some packet analysis using Wireshark. 

Due to security reasons, the only way to access an EC2 worker node is via the AWS Session Manager. Once inside, you ran `tcpdump` and generated a `.pcap` file, all ready to be analyzed. Except for one problem - how can you get that file out?

`SSH` access from local machine isn't available so forget about using `scp`.

Then you remembered you have access to EKS cluster pods via `kubectl`, which has a `kubectl cp` [command](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#cp). This means you can copy a file out of or into a pod from your machine.

But wait, how is that useful for copying a file out of the EC2 node? The file isn't even on any of the container.

Before going to the implementation of the trick, here are 3 things to know:
1. Containers aren't really a thing - they are constructed out of [`namespaces`](https://man7.org/linux/man-pages/man7/namespaces.7.html) and [`cgroups`](https://man7.org/linux/man-pages/man7/cgroups.7.html) by isolating processes running on a machine. Each of the containers that are running are just processes.

2. There's a `/proc` directory, which is a pseudo-filesystem that serves as an interface to kernel data structure. Each of the numbers from the `ls /proc` output are the PIDs of processes. They are also directories and contains information about the process.
```bash
vagrant@ubuntu-focal64:~$ ls /proc
1       137146  18     21      27      280985  283    483    62160  67759  807  94         consoles     interrupts   kpageflags  pagetypeinfo  sys                zoneinfo
10      137147  183    22      271412  281280  29     484    624    694    81   95         cpuinfo      iomem        loadavg     partitions    sysrq-trigger
100     137148  189    23      279367  281294  3      485    626    70634  82   96         crypto       ioports      locks       pressure      sysvipc
10348   137150  19251  24      279484  281322  30     486    632    709    83   960        devices      irq          mdstat      sched_debug   thread-self
105913  137151  19254  242     279485  281851  32236  496    635    76507  84   97         diskstats    kallsyms     meminfo     schedstat     timer_list
109     137152  2      243144  28      281859  373    498    640    77     85   99         dma          kcore        misc        scsi          tty
11      14      20     243145  280697  281967  38034  499    643    77326  89   acpi       driver       key-users    modules     self          uptime
112     15      202    25      280805  282     39342  56658  649    77541  9    buddyinfo  execdomains  keys         mounts      slabinfo      version
12      16      203    257814  280883  282266  4      56677  651    78     90   bus        fb           kmsg         mpt         softirqs      version_signature
125     17      205    257849  280884  282883  404    56683  666    79     92   cgroups    filesystems  kpagecgroup  mtrr        stat          vmallocinfo
13      170     206    26      280963  282947  42712  6      676    80     93   cmdline    fs           kpagecount   net         swaps         vmstat
```

```bash
vagrant@ubuntu-focal64:/proc/21$ sudo ls
arch_status  cgroup	 coredump_filter  exe	   io	      maps	 mountstats  oom_adj	    patch_state  sched	    smaps	  statm    timers
attr	     clear_refs  cpuset		  fd	   limits     mem	 net	     oom_score	    personality  schedstat  smaps_rollup  status   timerslack_ns
autogroup    cmdline	 cwd		  fdinfo   loginuid   mountinfo  ns	     oom_score_adj  projid_map	 sessionid  stack	  syscall  uid_map
auxv	     comm	 environ	  gid_map  map_files  mounts	 numa_maps   pagemap	    root	 setgroups  stat	  task	   wchan
```

3. The `/proc/<PID>/root` directory serves as not just a symbolic link to the process' root directory, it also provides the same view of the filesystem as the process itself. That means if you copy a file into the `/proc/<PID>/root` directory, it will be visible on the process' filesystem.

---

Now here are the steps:

1. Identify a pod you have access to. You should be able to execute `kubectl cp` on this pod.
2. Identify the node on which the pod is running on. `kubectl get po -o wide`
3. Access node using Session Manager and identify the PID of that pod. You can locate this by `ps aux | grep <container run command>`.
4. Copy the file from VM into the `/proc/<PID>/root` directory of the PID you identified in step 2.
5. Copy the file from pod to your local machine via `kubectl cp <some-namespace>/<some-pod>:/somefile.pcap ~/Desktop/somefile.pcap`

You have now successfully copied the file onto your local machine.

Useful references:
-  https://www.andrew.cmu.edu/course/14-712-s20/applications/ln/Namespaces_Cgroups_Conatiners.pdf
- https://man7.org/linux/man-pages/man5/proc.5.html