# Atlantis

## Story

As a devops engineer I want to have an easy and cheap way to onboard new IaC repositories in github with altlantis pull request automation tool.

I want my atlantis environments isolated from each other (no shared env for tokens or similar).

I want my atlantis pods to be stateless (in the default chart it is a statefullset).

I want a helm release for each tepository, for fine grained permissions.

## Atlantis Helm Chart

[Github](https://github.com/runatlantis/helm-charts)

The default atlantis helm chart is at this time a statefullset. Therefore we dont use it anymore.

## bjw-s app-template Chart

[bjw-s Helm Charts](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)

@bjw-s thank you so much for your work this solves most of my problems and makes it really easy to create new HelmRelease without go templating pain ❤️. Standarized Helm made easy.

## REDIS

Atlantis allow to use REDIS as state backend (this also allow ha mode)
In my case I will use dragonfly-db (redis compatible real ha + multithreading)

## kustomize

With kustomize we are able to define a base layer on how our chart will look in general and build the implementation detail on top with a kustomize patch 💪.

## Flux Kustomization

Well this is maybe a little hacky, as we need more then 1time our base chart and we want to have hem all in the atlantis namespace for now. And metadata.name must match for kustomize patch.
We use a Flux Kustomization postRenderer substitution to replace ${APP} with with the current chart name 🧙.

## Cloudflared

Github Webhook is exposed via cloudflared. Currently config need to be added manual

## local DNS (unbound on opnsense)

Is managed via [techtales-io/terraform-opnsense](https://github.com/techtales-io/terraform-opnsense)
