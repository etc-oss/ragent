---
type: decision
id: ADR-0020
title: Async review transport as a pluggable adapter, configured per project
description: The async review loop talks to a forge through a small adapter interface (Forgejo/GitLab/GitHub/SSH), chosen and tuned per project; access via Tailscale; auto-merge, poll interval, and bounds are per-project variables; the orchestrator runs per task until resolved.
status: accepted
date: 2026-07-27
tags: [phase-6, review, adapter, forgejo, gitlab, github, orchestrator, config]
timestamp: 2026-07-27
---

# ADR-0020 — Async review transport as a pluggable adapter, configured per project

## Context and problem statement

The [Forgejo transport design](../components/forgejo-transport-design.md) assumed a
single forge (Forgejo). But the review transport is not fundamentally Forgejo: a
team may already run **GitLab** or **GitHub (Enterprise)**, may want an **instance
per project**, or may want a lighter **git-over-SSH** flow. Hard-coding Forgejo
would fork the design per environment. We also need the per-project knobs
(auto-merge? poll cadence?) to actually live *with the project*, since every project
differs.

## Decision

**Make the review transport a pluggable adapter, selected and configured per
project.** The orchestrator (ragent, host-side, outside the jail) is
transport-agnostic and drives a small **adapter interface**; concrete adapters
implement it for each backend.

**Adapter interface (verbs the orchestrator calls):**

| Verb | Meaning |
|---|---|
| `ensure` | Make sure the project has a remote/repo (create if needed — supports instance-per-project). |
| `push <branch>` | Push the agent's branch to the transport (from **outside** the jail). |
| `open-review <branch> <base>` | Open or update the review unit (PR / MR / …); return its id/URL. |
| `status <review>` | `pending` \| `changes-requested` \| `approved`. |
| `comments <review>` | Unresolved review comments (fed back to the agent). |
| `report <review> <text>` | Post the agent's reply/report back into the thread ("addressed X by …") — so you see its response on your phone. |
| `merge <review>` | Merge (only when `autoMerge` and approved). |

> **The interface is provisional.** The *decision* to use adapters is accepted; this
> exact verb set is a hypothesis written before any adapter runs. 6a (the first
> Forgejo adapter, pushing one real PR) is expected to reshape it — that is not an
> amendment to this ADR, it is the interface earning its shape.

**Adapters (initial):** `forgejo` (default, self-hosted), `gitlab`, `github`
(Enterprise or SaaS), and `ssh` (bare git over SSH + patch/notes — the minimal,
forge-less transport). "PR", "MR", and "review" all map to the same interface.

**Privacy boundary — self-hosted vs. SaaS.** Self-hosted adapters (Forgejo,
GitLab-CE, a git-over-SSH remote) run **in the guest, on the Tailscale mesh** — your
code and the whole review stay inside your private boundary. **SaaS adapters
(github.com, gitlab.com) are external**: the agent's branch and the review leave to
a third party. That is a real relaxation of confinement (principle #1); the SaaS
adapters exist for teams already committed to those hosts, and the exposure must be
a conscious per-project choice, not a default.

**Per-project configuration** (in the project's `flake.nix`, alongside
`projectTools`; secrets are runtime-forwarded, never in the flake — ADR-0014):

```nix
reviewConfig = {
  adapter      = "forgejo";              # forgejo | gitlab | github | ssh
  remote       = "http://ragent-vm:3000/me/proj";  # the instance (per-project in enterprise)
  autoMerge    = false;                  # approve auto-merges, or wait for a manual merge
  pollInterval = 20;                     # seconds between review polls
  bounds       = { maxIterations = 8; maxCostUSD = 5; wallClockMin = 60; };
};
```

**Resolved decisions (were open in the design doc):**
- **Access: Tailscale.** The forge/orchestrator sit on a private mesh — reachable
  from a phone without a public port or a per-session tunnel.
- **Auto-merge vs. manual merge: a per-project variable** (`autoMerge`). Default
  `false` (explicit human merge).
- **Trigger: polling**, with a **per-project `pollInterval`**.
- **Orchestrator lifetime: per task**, running the bounded loop **until the task is
  marked resolved** (approved) or a bound trips (→ "needs human").

## Consequences

### Positive
- One orchestrator, many backends — Forgejo today, GitLab/GitHub/SSH without a rewrite.
- Enterprise-friendly: instance-per-project and existing forges are just config.
- Per-project knobs live with the project (ADR-0019); no global one-size setting.
- The jail is untouched: adapters run host-side; the agent still only commits in its clone.

### Negative / trade-offs
- An interface to keep stable as backends differ (GitHub "reviews" ≠ GitLab
  "approvals" ≠ a bare-SSH notes flow); the `ssh` adapter especially is a thinner
  experience.
- More surface to test — each adapter needs its own integration coverage.

## Alternatives considered
- **Forgejo-only** — simplest, but forks per environment and ignores existing forges.
- **A generic "git host" library dependency** — heavier and still not covering the
  SSH/forge-less case; a thin verb interface is smaller and fully in our control.

## Links
- [Forgejo/async review transport design](../components/forgejo-transport-design.md)
- [Phase 6 evaluation](../components/phase6-remote-and-async-review.md)
- [Roadmap & future guidelines](../components/roadmap.md)
- [ADR-0016 — Agent works in a clone](0016-agent-clone-not-worktree.md),
  [ADR-0014 — Runtime env secret forwarding](0014-runtime-env-secret-forwarding.md),
  [ADR-0019 — Per-project forking & deps](0019-per-project-forking-and-dependencies.md)
