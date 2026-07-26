---
type: decision
id: ADR-0015
title: cgroup resource caps via an external systemd-run scope
description: Impose CPU/memory/PID caps on the jailed agent with a transient systemd scope, since jail.nix isolates the cgroup namespace but does not set resource limits.
status: accepted
date: 2026-07-26
tags: [phase-1, cgroups, resource-limits, systemd, security]
timestamp: 2026-07-26
---

# ADR-0015 — cgroup resource caps via an external systemd-run scope

## Context and problem statement

The design calls for cgroup caps to bound blast radius — cheap fork-bomb / runaway
insurance. But **jail.nix isolates the cgroup *namespace* and does not impose
resource *limits*** (confirmed from source: it can unshare the `cgroup`
namespace, but sets no `MemoryMax`/`CPUQuota`), and jailed-agents adds none. So
the caps must come from outside the jail.

## Decision

Wrap the jailed agent in a **transient systemd scope** with caps:

```sh
systemd-run --user --scope -p MemoryMax=4G -p CPUQuota=200% -p TasksMax=512 -- <jailed-agent>
```

Implemented in `tools/ragent-run.sh` (caps overridable via env). The guest enables
**user cgroup delegation** (a `Delegate=cpu cpuset io memory pids` drop-in in the
VM config — now in your-config-repo's `lima/ragent.yaml`) so `--user` scopes can
actually enforce the limits.

## Consequences

### Positive
- A cheap guard against fork bombs and memory/CPU runaways, independent of the
  agent.
- Caps are declarative and tunable per project via env.

### Negative / trade-offs
- **`--user` scopes silently no-op unless the controllers are delegated** to the
  user session. The launcher falls back to running *uncapped with a warning* if
  `systemd-run` is unavailable — so caps must be **verified in-guest** (force an
  over-limit process and confirm `MemoryMax` kills it) before being trusted. This
  verification is owed; until then, treat the caps as unproven.
- Adds a launcher wrapper around the raw jailed binary.

## Alternatives considered
- **Rely on jail.nix** — it does namespace isolation, not resource limits.
- **A persistent systemd slice/unit** — heavier than a transient scope for a
  per-run agent.
- **Skip caps** — loses the insurance the design explicitly asked for.

## Links
- [Genesis session](../sessions/0001-genesis-architecture-conversation.md)
- [ADR-0002 — jail.nix for confinement](0002-jail-nix-confinement.md)
- [ADR-0013 — Build the jail on jailed-agents](0013-jailed-agents-opencode-first.md)
- `tools/ragent-run.sh`; the VM config now lives in your-config-repo (ADR-0018)
