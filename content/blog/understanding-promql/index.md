---
title: "Debugging a misfiring Prometheus alert"
date: 2021-09-20T11:46:24+08:00
slug: "debugging-prometheus-alert"
description: "Last week at work, I encountered an alert that was misfiring. Or so I thought..."
keywords: ["prometheus", "monitoring"]
draft: false
tags: ["prometheus", "monitoring"]
math: false
toc: false
---

Last week at work, I encountered an alert that was misfiring. Or so I thought.

This was the PromQL used for alerting when HTTP requests error rate exceeds the [SLO](https://sre.google/sre-book/service-level-objectives/) of 5% per hour:
```
(sum(rate(service_foo_http_request_total{status_code!~"2.."}[1h]))
  / sum(rate(service_foo__http_request_total[1h]))) OR vector(0) >= 0.05 
```

Some debugging later, issue was finally resolved and well, the PromQL was behaving exactly how it was supposed to.

The cause can be summarized into these 3 points:
* misunderstanding of how PromQL [vector()](https://prometheus.io/docs/prometheus/latest/querying/functions/#vector) function works
* misunderstanding of how PromQL [comparison](https://prometheus.io/docs/prometheus/latest/querying/operators/#comparison-binary-operators) binary operators work
* misunderstanding of how Prometheus/Thanos-ruler evaluates query result and trigger alerts

In this post, I will share about what I have learned about the 3 points and what are changes made to PromQL to make it behave as intended.

*ps*: [Prometheus documentation](https://prometheus.io/docs/introduction/overview/) isn't the clearest. I highly recommend checking out [Prometheus: Up & Running](https://www.amazon.com/Prometheus-Infrastructure-Application-Performance-Monitoring/dp/1492034142) book for better explanations on the various features & functions provided by Prometheus.

---

## How does `vector()` function work?

Let's check out the function description from [Prometheus docs](https://prometheus.io/docs/prometheus/latest/querying/functions/#vector):
> vector(s scalar) returns the scalar s as a vector with no labels.

I think the description taken from [Prometheus: Up & Running](https://www.amazon.com/Prometheus-Infrastructure-Application-Performance-Monitoring/dp/1492034142) is much clearer:
> Vector function takes a scalar value and converts it into an instant vector with one label-less sample with the given value.

Scalar? Label-less instant vector? What are these?

#### Instant vector data type
> a set of time series containing a single sample for each time series, all sharing the same timestamp 

Example:
```
prometheus_operator_kubernetes_client_http_requests_total
```
The PromQL above returns an instant vector, with each row being a time series at a particular point in time of query. 
{{<zoomable-img src="instant-vector.png" alt="instant-vector" caption="" >}}

#### Scalar data type
> a simple numeric floating point value

It literally is just a value. It cannot have labels (i.e just scalar). 

Example:
```
2
```
The PromQL above returns a scalar. 
{{<zoomable-img src="scalar.png" alt="scalar" caption="" >}}

**NOTE**: "cannot have labels" !== "label-less". "Label-less" only applies to vector (instant & range) data type.
Example of label-less data:
```
year()
```
{{<zoomable-img src="label-less-instant-vector.png" alt="scalar" caption="" >}}

Usually scalar type is used to make a comparison easier.

For example: Checking the year of the time series vector data. Both PromQL examples below can be used to perform the comparison, but scalar comparisons are a little easier to understand as compared to vector matching.

Scalar comparison
```
year(prometheus_operator_kubernetes_client_http_requests_total) == 1971
```

Vector comparison
```
year(prometheus_operator_kubernetes_client_http_requests_total) == on() group_left vector(1970)
```

Another question to answer: **when should we use vector()?**

`vector()` function can be useful if we need to ensure an expression returns a result but can't depend on any particular time series to exist.

For example:
```
sum(some_gauge) or vector(0)
```

---

## How does comparison binary operators work?

[**Comparison binary operators**](https://prometheus.io/docs/prometheus/latest/querying/operators/#comparison-binary-operators):
* `==` (equal)
* `!=` (not-equal)
* `>` (greater-than)
* `<` (less-than)
* `>=` (greater-or-equal)
* `<=` (less-or-equal)

Refering to the PromQL again: 
```
(sum(rate(service_foo_http_request_total{status_code!~"2.."}[1h]))
  / sum(rate(service_foo__http_request_total[1h]))) OR vector(0) >= 0.05 
```
In the PromQL, we used the `>=` operator.

**Expectation 1** (entire `(sum(...)/sum(...))` expression resulting in `no data`):
* if either the numerator expression or denominator expression evaluates to `no data`, the entire expression `(sum(...)/sum(...))` will result in `no data`
* `OR vector(0)` will handle the above and return a fallback value of `{} 0`
* `{} 0 >= 0.1` will evaluate to `false`
* because it evaluates to `false`, we might expect the entire PromQL evaluates to `0` OR `1` (in place of `true` or `false`)

**Reality 1**: expression evaluates to `false`, which means no matching time series found and returns `no data`

**Explanation 1**:

The PromQL above is actually performing a **vector** `(sum(...)/sum(...))` VS **scalar** `(0.1)` comparison. 

Depending on what data types are being compared, there are [variations in behaviour](https://prometheus.io/docs/prometheus/latest/querying/operators/#comparison-binary-operators):
* scalar VS scalar
* scalar VS vector
* vector VS vector

As per Prometheus docs,
> Between an instant vector and a scalar, these operators are applied to the value of every data sample in the vector, and vector elements between which the comparison result is false get dropped from the result vector

This is why `no data` was returned.

If we want it to evaluate to a boolean value (`{} 0` or `{} 1`), we will need to add a `bool` modifier after the operator.

Example:
```
(sum(rate(service_foo_http_request_total{status_code!~"2.."}[1h]))
  / sum(rate(service_foo__http_request_total[1h]))) OR vector(0) >=bool 0.05 
```

What if the entire `(sum(...)/sum(...))` expression evaluated to `{} 0` instead? Based on what we understood so far...

**Expectation 2** (entire `(sum(...)/sum(...))` expression resulting in `{} 0`):
* if either the numerator expression or denominator expression evaluates to `0`, the entire expression `(sum(...)/sum(...))` will result in `0`
* `OR vector(0)` will handle the above and return a fallback value of `0`
* `0 >= 0.1` will evaluate to `false`
* because it evaluates to `false`, it means no matching time series found and it will return `no data`

**Reality 2**: evaluated to a label-less instant vector `{} 0`

**Explanation 2**: 

Missing parenthesis enclosing the `OR vector(0)` portion (i.e `(sum(...) / sum(...) OR vector(0)) >= 0.05`).

Without enclosing the `OR vector(0)` section, the `sum(...) / sum(...)` and `OR vector(0) >= 0.05` will be evaluated seperately, before being compared again.

`sum(...) / sum(...)` returns `0 {}`

`vector(0) >= 0.05` returns `no data`

As per the [logical binary operator](https://prometheus.io/docs/prometheus/latest/querying/operators/#logical-set-binary-operators) description:
> `vector1 or vector2` results in a vector that contains all original elements (label sets + values) of vector1 and additionally all elements of vector2 which do not have matching label sets in vector1

This means the final result will be `{} 0`.

---

## How does Prometheus/Thanos-ruler evaluates PromQL result and trigger alerts?

Intuitively (or not), one might assume that for a PromQL result to trigger an alert, the resulting query must evaluate to a "truthy" value. At least that was what I assumed.

On further testing with PromQLs that returned either `0`, `1` or `no data`, I realized that:
* `no data` means "ALL OK"
* evaluating to ANY data (0, 1, whatever else) will be deemed as "SOMETHING IS WRONG. TRIGGER ALERT"

This is supported by what I found in [Prometheus source code](https://github.com/prometheus/prometheus/blob/03d084f8629477907cab39fc3d314b375eeac010/rules/alerting.go#L300):
```go
func (r *AlertingRule) Eval(ctx context.Context, ts time.Time, query QueryFunc, externalURL *url.URL, limit int) (promql.Vector, error) {
	res, err := query(ctx, r.vector.String(), ts)
	if err != nil {
		return nil, err
	}

	r.mtx.Lock()
	defer r.mtx.Unlock()

	// Create pending alerts for any new vector elements in the alert expression
	// or update the expression value for existing elements.
	resultFPs := map[uint64]struct{}{}

	var vec promql.Vector
	var alerts = make(map[uint64]*Alert, len(res))
	for _, smpl := range res {
		// Provide the alert information to the template.
		l := make(map[string]string, len(smpl.Metric))
		for _, lbl := range smpl.Metric {
			l[lbl.Name] = lbl.Value
		}
    ...
``` 

```go
res, err := query(ctx, r.vector.String(), ts)
```

If PromQL returned any data (i.e not `no data`), an `alerts` mapping will be created.
```go
var alerts = make(map[uint64]*Alert, len(res))
```

---

## Summary

We have a better understanding of `vector()` function, comparison binary operators and how alerts are triggered by Prometheus/Thanos-ruler now. 

So what exactly were the changes made to the PromQL to have it evaluate as intended?

Well, one way is to enclose the entire section before the `>=` operator

```
(sum(rate(service_foo_http_request_total{status_code!~"2.."}[1h]))
  / sum(rate(service_foo__http_request_total[1h]))) OR vector(0) >= 0.05 
```

The alternative is to remove the redundant `OR vector(0)`.
```
sum(rate(service_foo_http_request_total{status_code!~"2.."}[1h]))
  / sum(rate(service_foo__http_request_total[1h])) >= 0.05 
```
