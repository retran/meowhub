---
id: 0002
title: Docker Compose on a cheap VPS, portable to a home server
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0002 - Docker Compose on a cheap VPS, portable to a home server

## Context

The system has to run somewhere cheap now and on the household's own hardware
later, and we don't want to rewrite it in between. The Telegram bot needs a
reachable HTTPS endpoint for its webhooks.

Reaching a home server from the internet is a solved problem, because an
outbound tunnel such as Cloudflare Tunnel or Tailscale Funnel gives a public
HTTPS endpoint with no port forwarding, no static IP and no inbound firewall
holes. Inbound connectivity is therefore *not* why we start on a VPS. We start
on a VPS because the home server does not exist yet, and because a household
machine's uptime depends on nobody unplugging it while we are still building the
system.

The vision makes portability a product principle, so it constrains the topology
from the first container. Retrofitting it would mean rebuilding a deployment the
household already depends on.

## Decision

One `docker-compose.yml` defines the whole system: n8n, PostgreSQL, a reverse
proxy that terminates TLS, and backups. It runs unchanged on a small VPS and on
the home server, and the only difference between the two environments is a
`.env` file and DNS.

Four rules keep that true:

- We run no managed services. No provider-hosted database, queue or secret
  store: everything the system needs is a container in the Compose file.
- We keep all state in named volumes and cover every volume with the backup job,
  so a migration is stop, dump, copy, start.
- We use no provider-specific features, which rules out cloud load balancers,
  vendor DNS APIs beyond ordinary ACME, and provider metadata services.
- We pass configuration through environment variables only, and never bake it
  into images or workflow JSON.

Ingress sits outside the system and can be swapped, because Telegram only needs
a public HTTPS endpoint and how that endpoint reaches n8n is environment
configuration. On the VPS it is the reverse proxy on a public IP. At home it is
an outbound tunnel, and **Cloudflare Tunnel** is the default choice, because it
is free, needs only a domain on Cloudflare, and opens no inbound port. Nothing
inside the Compose file knows which of the two is in use.

A tunnel has a price we should state: Cloudflare terminates TLS, so the tunnel
provider can see the traffic. That is acceptable for webhook plumbing, and for
the admin surfaces it is why we keep authentication at the application edge
(ADR 0032) instead of trusting the network. If that trade stops being
acceptable, we move to Tailscale Funnel, or we keep a small VPS purely as a
WireGuard relay and reverse proxy into the house, which is the same topology
with the household owning the relay.

Moving to the home server gets its own slice and its own spec, and the move
itself is the verification: we run it end to end once before we call the system
portable.

## Alternatives

| Option | Why rejected |
|---|---|
| n8n Cloud | Removes the portability path entirely, and household financial data would sit on someone else's infrastructure. Contradicts two product principles |
| Kubernetes (k3s) from the start | The right answer for a fleet, absurd for one household and four containers. It costs operational work and returns nothing at this size |
| Straight to the home server, no VPS | Tempting, and technically fine now that tunnels remove the connectivity obstacle. We rejected it only because the home server does not exist yet and household hardware makes an unreliable host for a system we are still building, and not because it is hard to reach |
| Port forwarding with dynamic DNS at home | Works, but it puts an inbound hole in the household network and makes TLS renewal depend on the router. A tunnel does the same job with no inbound exposure |
| Bare-metal install without containers | Turns the move to the home server into a manual re-installation instead of a copy |

## Consequences

We gain three things:

- Migrating is a rehearsed copy of the volumes onto the new host.
- The system is cheap: a small VPS covers all of it, and the LLM is the only
  usage-based cost.
- The same Compose file runs on the owner's laptop for development.

We accept four costs in return:

- Nobody manages backups or failover for us, so the household owns uptime. That
  is acceptable for a bookkeeping bot, where an hour of downtime costs nothing.
- Compose gives no horizontal scaling, which is irrelevant at three users and
  becomes a real ceiling if that ever changes.
- We manage TLS, patching and backup verification ourselves, and those chores
  never end.
- In the home phase a third party sits in the request path unless we own the
  relay, which is why the decision above states that trade in full.

Reversing this decision stays cheap. Compose is the low-commitment end of the
spectrum, and if the system ever outgrows it the containers themselves carry
over.
