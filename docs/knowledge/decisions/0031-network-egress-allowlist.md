---
type: decision
id: ADR-0031
title: Network egress allowlist — default-deny, LLM API only, enforced by a system-scope BPF IP filter
description: The jail's `network` combinator gave the agent full open egress (an exfiltration + supply-chain hole). Close it by default — a systemd SYSTEM scope with IPAddressDeny=any + IPAddressAllow=<resolved LLM host + localhost + DNS>, dropped back to the caller with setpriv. --user scopes don't enforce IP filtering, so it needs passwordless sudo. Escape hatch RAGENT_EGRESS_OPEN=1. Honest limits — IP-allowlist not a domain proxy (CDN rotation/sharing), DNS-exfil uncovered.
status: accepted
date: 2026-08-16
tags: [security, network, egress, sandbox, confinement]
timestamp: 2026-08-16
---

# ADR-0031 — Network egress allowlist (default-deny, LLM API only)

## Context and problem statement

The jail's `network` combinator ([flake.nix](../../../flake.nix)) grants the agent **full,
unfiltered outbound network** (present for the LLM API, but not scoped to it). So a
prompt-injected or malicious agent could reach any host, **fetch and run arbitrary
packages** (`npx`/`pip`), and **exfiltrate the clone's own contents** — and the human
merge-gate does *not* stop exfiltration (it happens mid-run, over the wire). `SECURITY.md`
named this the biggest open edge. The filesystem jail is strong; the network side was open.

## Decision

**Default-deny outbound; allow only the LLM API host(s)** (+ localhost + the DNS resolver),
**enforced by a kernel BPF IP filter** on a systemd scope. Implemented in `ragent-confine.sh`:

```
sudo -En systemd-run --scope  -p IPAddressDeny=any \
     -p IPAddressAllow=127.0.0.0/8 -p IPAddressAllow=::1/128 \
     -p IPAddressAllow=<each resolved IP of the allowed host(s) + resolv.conf nameservers> \
     -p MemoryMax=… -p CPUQuota=… -p TasksMax=…            # the ADR-0015 caps, same scope
     -- setpriv --reuid=<uid> --regid=<gid> --clear-groups -- env HOME=<user> <jailed-agent> "$@"
```

- **Why a SYSTEM scope + sudo:** `--user` scopes **do not enforce** `IPAddress*` filtering
  (verified on systemd 255 — the BPF egress program isn't attached for user-manager units).
  The system manager does. So the filtered path uses **passwordless sudo**, then **`setpriv`
  drops back to the caller's uid** so the agent never runs as root, and **`env HOME=…`
  re-pins HOME** for the `~/.claude` bind. The OAuth token rides the inherited env (`sudo -E`)
  — it is **never** put in a `-p Environment=` (which would leak it into the unit/journal).
- **Why BPF-on-cgroup, not a proxy env var:** it's enforced by the kernel on the scope's
  cgroup and applies even though bubblewrap shares the net namespace — an adversarial agent
  can't bypass it (unlike `HTTPS_PROXY`, which it could simply ignore).
- **Knobs:** `RAGENT_EGRESS_ALLOW="host1 host2"` (default `api.anthropic.com`);
  `RAGENT_EGRESS_OPEN=1` restores open network. If sudo/`setpriv` are unavailable it **falls
  back to the old `--user` (open) path and prints a warning** — never silently "secure".

## Consequences

### Positive
- The exfiltration + arbitrary-package-fetch hole is **closed by default** for the common
  (Claude) case — verified by negative control. The high-assurance wedge's *network* half is
  now real (kernel FS jail **and** egress control), not just the filesystem half.
- Reuses the existing `systemd-run` scope (ADR-0015) — no netns/proxy plumbing.

### Negative / trade-offs — stated honestly
- **IP-allowlist, not a domain-aware proxy.** IPs are resolved *at launch*, so (a) **CDN IP
  rotation** can drop connectivity mid-session, and (b) **CDN IP-sharing** means a site on the
  same IP *could* be reachable. A domain-filtering proxy is the tighter future option.
- **DNS-based exfiltration** (encoding data in queries to the allowed resolver) is **not**
  covered.
- **Requires passwordless sudo + `setpriv`** in the guest; without them ragent stays open
  (and warns). Fine for the dedicated single-user VM; a hardened multi-user setup wants the
  firewall provisioned declaratively instead.
- The default allowlist targets `api.anthropic.com`; **non-Claude agents** (opencode/pi/crush,
  other endpoints) need their host added via `RAGENT_EGRESS_ALLOW`.

## Alternatives considered
- **`--user` scope `IPAddress*`** — rejected: does not enforce (verified).
- **nftables cgroup match** — viable but needs root + fiddly matching of a transient scope
  cgroup; the system-scope BPF filter is simpler and reuses the existing scope.
- **`--unshare-net` + a filtering proxy bridged into the netns** — the *tightest* (domain-
  aware) design, but heavy plumbing; deferred as the follow-up when IP-allowlist limits bite.

## Verification
Real `ragent-confine.sh` run in the guest (temp HOME, fake agent): the agent ran **as the
user** (uid, not root), the OAuth token and pinned HOME survived, `api.anthropic.com` was
**reachable**, and `example.com` was **BLOCKED** — the negative control the 8/8 filesystem
probe is to reads, now for the network.

## Links
- [SECURITY.md](../../../SECURITY.md) (the edge this closes) · [ADR-0002 — jail.nix confinement](0002-jail-nix-confinement.md)
- [ADR-0015 — cgroup caps via a systemd scope](0015-cgroup-caps-systemd-run.md) (same scope now carries the IP filter)
- `tools/ragent-confine.sh`, [roadmap](../components/roadmap.md)
