---
title: "Visualizing alerts metrics on Grafana"
date: 2021-09-26T13:44:24+08:00
slug: "visualizing-alerts-metrics-grafana"
description: ""
keywords: ["prometheus", "monitoring", "grafana"]
draft: false
tags: ["prometheus", "monitoring", "grafana"]
math: false
toc: false
---

When it comes to Prometheus and alerts, the typical use case is to send alerts to Alertmanager for handling (deduplication, grouping) and routing them to the various services such Slack, PagerDuty etc.

However, there might be situations where we might need to perform analysis on alert patterns and being able to visualize how often the alerts are firing can be very useful.

In this post, I will share how we can visualize the alert metrics on Grafana using the various [PromQL operators and functions](https://prometheus.io/docs/prometheus/latest/querying/basics/).

---

## Choosing the metrics

Prometheus exposes 2 alert metrics: `ALERTS` and `ALERTS_FOR_STATE`.

`ALERTS` time series provide information on the state of a triggered alert via the `alertstate` label. An alert can be either in a "firing" or "pending" state. When an alert is first triggered (i.e alert rule PromQL returns matching time series), it will transitioned into "pending" state. If an alert stays in the "pending" state for the specified duration set in `for` key in alert rule (i.e alert rule PromQL consistently returns matching time series), it will transition to "firing" state. This is when an alert gets fired to Alertmanager for handling. See [docs](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/#defining-alerting-rules) for more information.

Example:
```
ALERTS{alertname="Watchdog", alertstate="firing", severity="none"}   1
```

`ALERTS_FOR_STATE` time series provide information on the start time (Unix epoch time format) of triggered alerts that are in either "firing" or "pending" state.

Example:
```
ALERTS_FOR_STATE{alertname="Watchdog", severity="none"}    1632807871
```

## Breaking down the PromQL

This is PromQL used:
```
(sum by (alertname) (changes(ALERTS_FOR_STATE[48h]) AND ignoring(alertstate) max_over_time(ALERTS{alertstate="firing"}[48h])) + (count by (alertname) (changes(ALERTS_FOR_STATE[48h]) AND ignoring(alertstate) max_over_time(ALERTS{alertstate="firing"}[48h])) * 1))
```

Looks confusing eh? Let's break it down a little.

`changes(ALERTS_FOR_STATE[48h])` returns an instant vector telling us how many times a triggered alert's timestamp has changed. Each change indicates an alert being triggered to either "pending" or "firing" state.

`max_over_time(ALERTS{alertstate="firing"}[48h]` returns an instant vector containing time series of alerts that have been in the "firing" state. `max_over_time` can technically be replaced with other functions that can return the same instant vector. 

Combining it with the `AND` [binary operator](https://prometheus.io/docs/prometheus/latest/querying/operators/#logical-set-binary-operators), we can match labels and filter to get a count of how many times a "firing" alert has been triggered (i.e firing throughout the threshold duration).

Now we want to sum the alert counts computed above by the `alertname`, hence the `sum by (alertname)`.

The latter portion of PromQL (`count by (alertname) (changes(ALERTS_FOR_STATE[48h]) AND ignoring(alertstate) max_over_time(ALERTS{alertstate="firing"}[48h])) * 1)`) is a trick to ensure that the count of each of the time series (alert) computed is incremented by 1. This is because an alert going from not existing (no `ALERTS_FOR_STATE` metric available) to existing is not counted as a change in value, thus the need to increment by 1.


Combining them together:
{{<zoomable-img src="alert-metrics-bar.png" alt="alert-metrics-bar">}}
