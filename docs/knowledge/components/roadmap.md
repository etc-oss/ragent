---
type: component
id: COMP-roadmap
title: Roadmap & future guidelines
description: Where ragent is, what comes next (Phase 6 adapter-based async review), the longer-term direction, and the guiding principles any future work should hold.
tags: [roadmap, planning, future, guidelines, phase-6]
timestamp: 2026-07-27
---

# Roadmap & future guidelines

The long view. The near-term detail for Phases 1–5 lives in the
[forward plan](forward-plan-phases-1-5.md); this is the map beyond it and the
principles to steer by.

## Where we are

- **Phases 0–5: done** — governance + OKF knowledge system; the jail (confinement
  gate 8/8, cgroup caps, four agents confined); the Zellij two-side workspace with
  the git-clone review boundary; the shared-tools layer; observability + all four
  agents; open-source hardening (CI prepared, template, VM guide).
- **The core loop is real** — a jailed agent made an edit confined to its clone, a
  human reviewed the diff and ran the tests, and it merged. Agents self-verify now
  via per-project tools ([ADR-0019](../decisions/0019-per-project-forking-and-dependencies.md)):
  a confined agent ran `pytest` inside its jail.
- **Consumption model settled** — ragent is a parameterized library
  (`lib.<system>.mkWorkspace { projectTools }`); personal config lives in a
  consuming repo (your-config-repo, [ADR-0018](../decisions/0018-split-your-config-repo.md)).

## Next: Phase 6 — async review, on the go

Let a human oversee long, unsupervised runs from a phone, keeping the TUI for deep
work on the primary device. Design in
[async review transport](forgejo-transport-design.md); decision in
[ADR-0020](../decisions/0020-review-transport-adapters.md).

- **6a — done (local), verified:** the Forgejo adapter + orchestrator open a real
  PR from a real agent task (body = the agent's explanation + the served-report
  link, diff = the real change). Remote next: the same adapter against a NixOS
  `services.forgejo` on Tailscale (a URL swap).
- **6b** — the bounded comment → agent-revision loop (polling), per task until
  resolved.
- **6c** — polish: notifications, mobile ergonomics, resolution/labels, concurrency.

The transport is a **pluggable adapter** (Forgejo default; GitLab, GitHub
Enterprise, git-over-SSH), configured per project (`reviewConfig`: adapter, remote,
`autoMerge`, `pollInterval`, bounds).

**Already shipped — the served per-task report** ([ADR-0021](../decisions/0021-per-task-explanatory-report.md)):
alongside every task, the agent's own explanation + the real diff render to a
self-contained HTML report, served (`nix run .#serve`, localhost/Tailscale). This
is the forge-independent oversight channel — universal, reviewable from any device —
and the substrate a forge `report` verb can later post.

## Beyond — future guidelines (direction, not commitments)

- **More adapters** as needed — the `ssh` (forge-less) adapter for minimal setups;
  hardening the GitLab/GitHub Enterprise ones for teams.
- **Stronger isolation** — graduate from bubblewrap to **microvm.nix** for a
  VM-per-agent boundary (the [ADR-0002](../decisions/0002-jail-nix-confinement.md)
  "microvm future"; prototype already in your-config-repo).
- **Supervised standing orchestrator** — only after the per-task bounds
  (max-iters/cost/wall-clock/needs-human) are proven; an always-on loop inherits
  the runaway-autonomy risk continuously, so it must earn the trust first.
- **Multi-user / team** — once single-user is solid: shared forge orgs, per-user
  tokens, per-project instances in enterprise.
- **Richer observability** — only if plain log panes fall short (the genesis
  warning against a premature "unified" logger still stands).
- **Local-resilience** — exercise the offline mirror path ([ADR-0010](../decisions/0010-local-mirror-resilience.md))
  end to end; publish (with explicit human go-ahead) and turn the prepared CI on.

## Guiding principles (hold these)

1. **Confinement is not optional.** New capability must not widen the jail. The
   agent touches only its clone; secrets and the real tree stay outside.
2. **The human gate is sacred.** Nothing lands without a human decision — however
   convenient automation gets. Bound every autonomous loop.
3. **Adapters, not hard-codes.** Where environments differ (forge, VM, provider),
   add a thin adapter/parameter — don't fork the design.
4. **Deps in the flake, per project.** Pinned inputs + `projectTools`; a Makefile
   is only a task-runner ([ADR-0019](../decisions/0019-per-project-forking-and-dependencies.md)).
5. **Reference, don't vendor.** Credit upstreams; consume as pinned inputs
   ([ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md)).
6. **Capture decisions.** Non-trivial choices become ADRs linked to their session;
   the knowledge graph is the project's memory.
7. **Verify by behavior, then be honest.** Prove a change by exercising it (an
   agent *ran* pytest; the loop *merged*), and state precisely what was and wasn't
   verified.
8. **Be kind to the agent.** It's a trusted collaborator in a safe space, not a
   prisoner (see `templates/default/AGENTS.md`). Optimal, respectful context beats
   restriction.

## Links
- [Forward plan (Phases 1–5)](forward-plan-phases-1-5.md),
  [Architecture overview](architecture-overview.md)
- [Phase 6 evaluation](phase6-remote-and-async-review.md),
  [async review transport](forgejo-transport-design.md),
  [ADR-0020](../decisions/0020-review-transport-adapters.md)
- [Running on a VM](running-on-a-vm.md)
