---
title: "Node-exporter setup with Systemd"
date: 2021-08-19T22:22:18+08:00
slug: ""
description: ""
keywords: ["linux", "monitoring", "node-exporter", "systemd"]
draft: false
tags: ["linux", "monitoring", "node-exporter", "systemd"]
math: false
toc: false
---

For those who aren't familiar, [node-exporter](https://github.com/prometheus/node_exporter) is a Prometheus exporter that exposes hardware and OS metrics from *NIX kernels.

To get it up and running, there's a [simple guide](https://prometheus.io/docs/guides/node-exporter/) on Prometheus official docs. The issue with the approach is that running node-exporter by executing binary directly isn't the most reliable approach in a production environment as there's no way to ensure that the node_exporter process will run continuously.

This is where `systemd` comes in. `systemd` is an init system and system maanger and comes with a management tool called `systemctl` meant for managing processes, checking statuses, configuration and changing system states.

Now let's look at how we can use it to set up node-exporter on a Linux machine.

First, download the binary from [release page](https://github.com/prometheus/node_exporter). If you are setting node-exporter as part of your bootstrap script, it may be useful to execute the downloading in a subshell (enclose command in `()`) so that you do not have change directory,

```shell
(cd /tmp && curl -OL https://github.com/prometheus/node_exporter/releases/download/v1.2.2/node_exporter-1.2.2.linux-amd64.tar.gz)
(cd /tmp && tar -xvf /tmp/node_exporter-1.2.2.linux-amd64.tar.gz)
```

Next, create user and group for running node-exporter process. [<u>You do not want to run your process as root.</u>](https://unix.stackexchange.com/questions/52268/why-is-it-a-bad-idea-to-run-as-root)

```shell
sudo useradd -m node_exporter
sudo groupadd node_exporter
sudo usermod -a -G node_exporter node_exporter
```

Then, move binary to `/usr/local/bin` and change owner of file to the user (`node_exporter`) created above.
```shell
sudo mv /tmp/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter
``` 

Now, create a `.service` file to running node-exporter process using systemd.
```shell
sudo bash -c 'cat <<EOF > /etc/systemd/system/node_exporter.service
[Unit]
Description=Node Exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=multi-user.target
EOF'
```

We now perform a reload, start and enable the process. The `enable` call will ensure it will start at boot:
```shell
sudo systemctl daemon-reload
sudo systemctl start node_exporter
sudo systemctl enable node_exporter
```

We can then check to see if process is running properly.
```shell
sudo systemctl status node_exporter
● node_exporter.service - Node Exporter
   Loaded: loaded (/etc/systemd/system/node_exporter.service; disabled; vendor preset: disabled)
   Active: active (running) since Thu 2021-08-19 14:38:14 +08; 23h ago
 Main PID: 66608 (node_exporter)
    Tasks: 6 (limit: 23494)
   Memory: 21.1M
   CGroup: /system.slice/node_exporter.service
           └─66608 /usr/local/bin/node_exporter

Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=thermal_zone
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=time
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=timex
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=udp_queues
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=uname
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=vmstat
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=xfs
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:115 collector=zfs
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=node_exporter.go:199 msg="Listening on" address=:9100
Aug 19 14:38:14 foo-instance node_exporter[66608]: level=info ts=2021-08-19T06:38:14.080Z caller=tls_config.go:191 msg="TLS is disabled." http2=false
```

If you see the following error, it could be due to SELinux being enabled.
```shell
Failed to execute command: Permission denied
```
By default, SELinux doesn't allow execution of scripts from `/tmp` or user's `/home` directory. Even though the binary has been moved to `/usr/local/bin`, the context is still `/tmp`.

Check if SELinux is enabled
```shell
sestatus
```

To fix the permission issue, run the following to update the context and restart the service. Node-exporter process should be able to run after this change.
```shell
sudo restorecon -rv /usr/local/bin/node_exporter
sudo systemctl restart node_exporter
```

If you are installing node-exporter on an instance using CIS Hardened image, you may encounter issue accessing the `/metrics` endpoint. This is due to the iptable rules.

The following snippet will check for existence of required rule that accepts packets from `port: 9100`(default port of node-exporter) and add if rule is missing.
```shell
sudo iptables -C INPUT -p tcp -m tcp --dport 9100 -j ACCEPT 2>/dev/null
NODE_EXPORTER_RULE_EXIST=$(echo $?)
if [[ $NODE_EXPORTER_RULE_EXIST -eq 1 ]]; then
sudo iptables -A INPUT -p tcp -m tcp --dport 9100 -j ACCEPT
fi
```


