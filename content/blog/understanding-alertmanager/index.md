---
title: "Understanding the differences between alertmanager's group_wait, group_interval and repeat_interval"
date: 2021-08-27T12:07:56+08:00
slug: ""
description: ""
keywords: []
draft: false
tags: ["alertmanager", "monitoring", "prometheus"]
math: false
toc: false
---

[Alertmanager](https://prometheus.io/docs/alerting/latest/alertmanager/) is an application that handles alerts sent by client applications such as Prometheus. It can also perform alert grouping, deduplication, silencing, inhibition. Definitely a useful addition to any modern monitoring infrastructure.

That being said, configuring it can be a little daunting with the many different [configurations](https://prometheus.io/docs/alerting/latest/configuration/) available and somewhat vague explanations on some of the terms.

While configuring Alertmanager, I came across these 3 confusing terms: `group_wait`, `group_interval` and `repeat_interval`. 

From the [official documentation](https://prometheus.io/docs/alerting/latest/configuration/#route):
```yaml
# How long to initially wait to send a notification for a group
# of alerts. Allows to wait for an inhibiting alert to arrive or collect
# more initial alerts for the same group. (Usually ~0s to few minutes.)
[ group_wait: <duration> | default = 30s ]

# How long to wait before sending a notification about new alerts that
# are added to a group of alerts for which an initial notification has
# already been sent. (Usually ~5m or more.)
[ group_interval: <duration> | default = 5m ]

# How long to wait before sending a notification again if it has already
# been sent successfully for an alert. (Usually ~3h or more).
[ repeat_interval: <duration> | default = 4h ]
```

Thanks to the [blog post from robustperception](https://www.robustperception.io/whats-the-difference-between-group_interval-group_wait-and-repeat_interval) and a much more in-depth explanation from [Prometheus: Up & Running](https://www.oreilly.com/library/view/prometheus-up/9781492034131/) book, I now have a much better understanding of it.

Diagrams help me understand things way better than reading chunks of text, so I created one to better illustrate the differences between the 3 terms and how they work with each other.

{{<zoomable-img src="alertmanager-terms.png" alt="alertmanager-terms-diagram" caption="" >}}