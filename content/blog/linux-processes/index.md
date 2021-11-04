---
title: "Orphan vs Zombie vs Daemon processes"
date: 2021-11-03T08:53:15+08:00
slug: "understanding-linux-processes"
description: ""
keywords: ["linux"]
draft: false
tags: ["linux"]
math: false
toc: false
---

https://www.gmarik.info/blog/2012/orphan-vs-zombie-vs-daemon-processes/
https://unix.stackexchange.com/questions/264522/how-can-i-show-a-terminal-shells-process-tree-including-children

https://askubuntu.com/questions/30891/is-there-any-way-to-kill-a-zombie-process-without-reboot?lq=1

https://gist.github.com/apbarrero/6338709
https://stackoverflow.com/questions/4880555/what-is-the-linux-process-table-what-does-it-consist-of
https://ostoday.org/linux/what-is-the-impact-of-zombie-process-in-linux.html


# What are processes?
A process is basically a program in execution and a program is a piece of code which may be a single line or millions of lines long written in a programming language.

When a UNIX machine gets powered up, the kernel will be loaded and complete its initialization process. Once initialization is completed, the kernel creates a set of processes in the user space, including the scheduling of the system management daemon process (usually named `init`) which has `PID 1` and is responsible for running the right complement of services and daemons at any given time.

One of the important responsibilities of `init` is the reaping of zombie processes, which I will cover below.

We can see the list of process by using the `ps aux` command.

---

# Parent, child, orphan, daemon, zombie processes

Now we know what processes are, what are the differences between these different kinds of processes then?

## Parent & child processes

### Process creation
In UNIX, every process, except the first process (`PID 0` swapper process), is created by another process by executing the [fork()](https://man7.org/linux/man-pages/man2/fork.2.html) syscall.

The process that creates other processes is known as the **Parent process**. The processes that were created by the Parent process are known as **Child processes**.

The child process is largely identical to the parent process, only with its distinct PID and own accounting information.

After a `fork()`, a child process often uses one of the [exec()](https://man7.org/linux/man-pages/man3/exec.3.html) syscall to begin execution of a new program

When we run `ps` command with the `-aef` flag, we can see 2 columns that are of interest to us: `PID` & `PPID`.

`PID`: process ID
`PPID`: parent process ID

```bash
$ ps -aef
UID        PID  PPID  C STIME TTY          TIME CMD
root         1     0  0 13:39 ?        00:00:04 /usr/lib/systemd/systemd --switched-root --system --deserialize 21
root         2     0  0 13:39 ?        00:00:00 [kthreadd]
root         4     2  0 13:39 ?        00:00:00 [kworker/0:0H]
root         6     2  0 13:39 ?        00:00:00 [ksoftirqd/0]
root         7     2  0 13:39 ?        00:00:00 [migration/0]
```

Now run it again with the `--forest` flag. This will display the processes in a tree structure, clearly depicting the relationship between processes.

```bash
$ ps -aef --forest
UID        PID  PPID  C STIME TTY          TIME CMD
.
.
root     17368     1  0 13:43 ?        00:00:02 /usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
root     17612     1  0 13:43 ?        00:00:01 /usr/bin/amazon-ssm-agent
root     17697 17612  0 13:43 ?        00:00:14  \_ /usr/bin/ssm-agent-worker
root     32548 17697  0 19:41 ?        00:00:05      \_ /usr/bin/ssm-session-worker svc_123456 i-123456
ec2-user 32560 32548  0 19:41 pts/0    00:00:00          \_ sh
root     32561 32560  0 19:41 pts/0    00:00:00              \_ sudo su - ec2-user
```

We can visualize this using a tree diagram.
{{<zoomable-img src="process-tree.png">}}

### Process termination
When a process completes, it calls a routine named `_exit` to notify the kernel that is is ready to die (sounds dark). It supplies an exit code (an integer) which provides information on why it is exiting.

Before the completed process is allowed to be removed, the process's parent has to acknowledge by calling the [wait()](https://man7.org/linux/man-pages/man2/wait.2.html) syscall to remove its entry (PID) in the process table for reuse.

---
## Orphan processes

As the name suggests, an orphan process is one where the parent process terminates before the child process.

When this happens, the kernel will adjust the orphan processes and make them children of the `init` process and call the `wait()` syscall on these newly adopted child processes.

{{<zoomable-img src="orphan-process.png">}}

There are 2 kinds of orphan processes: **unintentional orphan** & **intentional orphan**

### Unintentional orphan

This happens when the parent process terminates or crashes unexpectedly.

The process group mechanism can be used in such cases to coordinate and terminate all child processes using the `SIGHUP` process signal instead of letting them continue to run as orphans.

### Intentional orphan aka Daemon processes

An intentional orphan process is one that is expected to continue running in the background. Typically daemon process names end with letter "d" (e.g `systemd-journald`).

Example will be the use of `nohup` to run a job in indefinitely.
```bash
$ nohup sh custom-script.sh &
```
---

## Zombie processes

We covered the process termination routine earlier on how `wait()` syscall is called by the parent process to clean up a process entry (PID) in process table after a child process is completed.

A zombie process is one that has completed but isn't "waited()" by its parent process and hence continues to hold a process entry in the process table (`ps -axf -o pid,ppid,tty,stat,cmd`). Because the parent process is still running, the zombie process cannot be adopted by the `init` process and reaped (aka `wait()`). ()

This can potentially result in memory leak due to unreleased kernel resources.

That being said, there are some situations where zombie processes are desirable, such as when we want to ensure parent process creates a child process with a different PID or to obtain information about the child processes at a later time.

NOTE:
* a zombie process cannot be killed since it is technically already "dead"
* processes are never responsible for cleaning up their grandchildren processes. this task is always handled by PID 1, which is usually the `init` process

{{<zoomable-img src="zombie-process.png">}}

---

# References
* [Docker and the PID 1 zombie reaping problem](https://blog.phusion.nl/2015/01/20/docker-and-the-pid-1-zombie-reaping-problem/)
* [Tini and how it helps with zombie reaping problem in Docker container](https://github.com/krallin/tini/issues/8#issuecomment-146135930)
* [My process became PID 1 and now signals behave strangely](https://hackernoon.com/my-process-became-pid-1-and-now-signals-behave-strangely-b05c52cc551c)
* [Why you need an init system](https://github.com/Yelp/dumb-init#why-you-need-an-init-system)
