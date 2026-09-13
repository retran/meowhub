---
id: 0002
title: Docker Compose on a cheap VPS, portable to a home server
status: accepted
date: 2026-09-12
deciders: owner
supersedes: []
superseded-by: []
---

# ADR 0002 — Docker Compose on a cheap VPS, portable to a home server

## Context

The system has to run somewhere cheap now, and on the household's own hardware
later, without being rewritten in between. The Telegram bot needs a reachable
HTTPS endpoint for webhooks.

Reaching a home server from the internet is a solved problem: an outbound tunnel
(Cloudflare Tunnel, Tailscale Funnel) gives a public HTTPS endpoint with no port
forwarding, no static IP and no inbound firewall holes. So inbound connectivity
is *not* the reason to start on a VPS. The reasons to start on a VPS are that the
home server does not exist yet, and that a household machine's uptime depends on
someone not unplugging it while the system is still being built.

Portability is a stated product principle, not a later project. It therefore
constrains the topology from the start rather than being retrofitted.

## Decision

One `docker-compose.yml` defines the whole system: n8n, PostgreSQL, a reverse
proxy terminating TLS, and backups. It runs unchanged on a small VPS and on the
home server; the only difference between environments is a `.env` file and DNS.

Rules that keep that true:

- **No managed services.** No provider-hosted database, queue or secret store.
  Everything the system needs is a container in the Compose file.
- **All state in named volumes**, and every volume covered by the backup job.
  A migration is: stop, dump, copy, start.
- **No provider-specific features** — no cloud load balancers, no vendor DNS
  APIs beyond ordinary ACME, no provider metadata services.
- **Configuration through environment variables only**, never baked into images
  or workflow JSON.

**Ingress is a swappable edge, not part of the system.** Telegram talks to a
public HTTPS endpoint; how that endpoint reaches n8n is environment
configuration. On the VPS it is the reverse proxy on a public IP. At home it is
an outbound tunnel — **Cloudflare Tunnel** is the default choice, because it is
free, needs only a domain on Cloudflare, and opens no inbound port. Nothing
inside the Compose file knows which of the two is in use.

The price of a tunnel is honest and worth stating: Cloudflare terminates TLS, so
the tunnel provider can see the traffic. For webhook plumbing that is acceptable;
for the admin surfaces it is a reason to keep authentication at the application
edge (ADR 0032) rather than trusting the network. If that trade stops being
acceptable, the alternatives in order are Tailscale Funnel, or keeping a small
VPS purely as a WireGuard relay and reverse proxy into the house — which is the
same topology, with the household owning the relay.

Migrating to the home server is spec'd as its own slice and verified by doing
it, not assumed.

## Alternatives

| Option | Why rejected |
|---|---|
| n8n Cloud | Removes the portability path entirely, and household financial data would sit on someone else's infrastructure. Contradicts two product principles |
| Kubernetes (k3s) from the start | The right answer for a fleet, absurd for one household and four containers. Operational cost with no return at this size |
| Straight to the home server, no VPS | Tempting, and technically fine now that tunnels remove the connectivity obstacle. Rejected only because the home server does not exist yet and household hardware makes an unreliable host for a system still being built — not because it is hard to reach |
| Port forwarding with dynamic DNS at home | Works, but puts an inbound hole in the household network and makes TLS renewal depend on the router. A tunnel achieves the same with no inbound exposure |
| Bare-metal install without containers | Makes the move to the home server a manual re-installation instead of a copy |

## Consequences

**Good:**
- The migration is a rehearsed copy of volumes, not a redesign.
- Cheap: a small VPS covers the whole system, with the LLM the only usage-based
  cost.
- The same Compose file runs on the owner's laptop for development.

**Bad, and the price we accept:**
- No managed backups, no managed failover: the household owns uptime. Acceptable
  for a bookkeeping bot where an hour of downtime costs nothing.
- Compose gives no horizontal scaling. Irrelevant at three users, and a real
  ceiling if that ever changes.
- Self-managed TLS, patching and backup verification are ongoing chores.
- In the home phase, a third party sits in the request path unless the relay is
  self-owned. Stated explicitly above rather than discovered later.

**What becomes harder to change later:**
- Nothing significant. Compose is the low-commitment end of the spectrum; if the
  system ever outgrows it, the containers themselves carry over.
