---
title: "Building my secondhand camera equipment pricing webapp"
date: 2022-02-19T17:34:57+08:00
slug: ""
description: ""
keywords: []
draft: false
tags: []
math: false
toc: false
---

When I was dabbling with photography a few years back, secondhand camera equipment forum [ClubSNAP](https://www.clubsnap.com/) was where I frequented for my equipment needs. Buying a brand new equipment was simply too expensive for a hobbyist like me.

Finding sellers was the easy part; the difficult part was figuring how much to pay for it. What did I do? Manually scanned all the posts to figure out the "standard" price range of an equipment. 

It was tedious and I thought to myself how great it would be if I can see the price history over time at a glance.

I decided to build it myself.

After spending 1.5 months working on it after work. There are definitely many areas of improvement but 

{{<image src="./sgcameraprice-usage.webp" alt="usage-video" position="center" >}}
[SG secondhand camera equipment pricing](https://sgcameraprice.xyz/)

# Planning

Before building this, I asked myself what did I want to get out of it:
* learn Golang
* deliver a MVP that can showcase the feasibility of this idea
* fully manage the infrastructure while keeping costs as low as possible. ideally the infrastructure can be easily reused for future projects

## Feature

To be able to deliver value as quickly as possible, I narrowed down the available features based on this statement:
> As a user, I want to be able to search for the price history of a particular camera equipment belonging to a particular brand over a specific period of time, with the ability to dynamically zoom in on the data without performing additional queries. I also want to be able to perform more than 1 search at once to compare the results.

## Design

As mentioned above, one the goals was to learn Golang. I have read quite a bit of code written in Golang as my responsibilities at work involve operating EKS clusters built for observability (Prometheus stack) and when you encounter some behaviour that isn't well documented, the best way to have a better understanding is to read the source code, most of which are written in Golang. However I have never written much Golang before so I thought this might be a good chance to get my hands dirty and learn the intricacies of it.

{{<image src="./architecture.png" alt="usage-video" position="center" >}}

I decided to adopt the microservices approach and split the logic into 3 different services:
* Frontend written using React (JavaScript). This is then packaged into static files and served by `nginx`.
* Backend API written using Nodejs (TypeScript)
* Worker performing periodic scraping written in Golang. I found a pretty decent Golang package ([Colly](https://github.com/gocolly/colly))meant for web scraping purpose 

Reasons for doing so: ability to scale and make changes to services without affecting the other services. This is especially true for the scraper worker instance, which is designed to operate only with 1 instance running at all times to reduce the amount of load on the scraped website as much as possible. Redundancy is not necessary since it is not user facing and even in failure cases, data can eventually be recovered.

#### Using Kubernetes
Some of you might be thinking "Kubernetes for such a simple webapp?!".

Kubernetes (or rather containers + orchestrators in general) is amazing and has changed the way we design our systems and manage workloads. One of the main draw to me are the ability to deploy any workload in the form of containers and not worry about messing up the dependencies of each application. 

It also allows us to [pack more within the same VMs](https://kubernetespodcast.com/episode/063-economics-of-kubernetes/), which is what I am looking for as I intend to use this setup for my future projects. Future application deployments can be as simple as: purchasing new domain (if necessary), containerizing the new application, write a helm chart to create an necessary resources, done! 

Of course, nothing in life is free. With the features come complexity. To me, that's a fair tradeoff and isn't much of a deterring factor as I have been managing Kubernetes clusters at work. If anything, it's a great opportunity to learn if I ever encounter any issue.

#### Cloud provider

This took me awhile to decide due too the number of choices available (AWS, GCP, Azure, Digital Ocean, Linode, Heroku etc). Operating cost and ease of operating are what I based my decision on.

In terms of familiarity, AWS comes out top as I have been using their services almost daily for both my current and previous roles. The problem is the complexity and operating cost. Like Kubernetes, it has many knobs, perhaps a little too many for a small project like mine. Also, the operating cost is much higher with the lingering fear that I might have accidentally toggled some costly feature.

I ended up with either Linode or Digital Ocean. Both are rather similar in pricing and both provide managed Kubernetes control plane. However, Digital Ocean do provide managed databases though unlike Linode

Eventually I chose Linode because they happen to have a $100 voucher for new joiners and I figured I can use this opportunity to learn how to operate a database (deployment, backups, upgrades).

# Challenges faced
