---
type: component
id: COMP-forgejo-transport
title: 'Async agent review transport (adapter-based, Phase 6a)'
description: A concrete design for the async review loop — a transport-agnostic orchestrator drives a pluggable adapter (Forgejo/GitLab/GitHub/SSH), pushes the agent branch from outside the jail, and runs a bounded comment loop until the user marks the task resolved. Configured per project; access via Tailscale.
tags: [proposal, review, adapter, forgejo, gitlab, github, orchestrator, phase-6, security]
timestamp: 2026-07-27
---

# Async agent review transport (adapter-based, Phase 6a)

Concrete design for the async web-review loop from the
[Phase 6 evaluation](phase6-remote-and-async-review.md), using the **buy-not-build**
option it recommended: a self-hosted forge provides diff review, line comments,
resolution, auth, a mobile UI, and notifications for free. Per
[ADR-0020](../decisions/0020-review-transport-adapters.md) the forge is reached
through a **pluggable adapter** — **Forgejo is the default/reference adapter**, with
GitLab, GitHub (Enterprise), and a git-over-SSH adapter following the same
interface. **Design for review — not yet built.**

## Architecture

```
 phone/browser ──HTTPS or SSH tunnel──►  Forgejo  ◄── push + API ── Orchestrator (HOST/guest side, OUTSIDE the jail)
                                        (guest svc)                    │  holds the forge token + git push creds
                                                                       ├─ sets up the agent clone (ADR-0016)
                                                                       ├─ runs the jailed agent (commits in clone)
                                                                       └─ reads PR comments → re-prompts the agent
                                                                          the JAILED agent: only its clone; no forge token
```

The load-bearing boundary: **the jailed agent never pushes and never holds the
forge token.** It only commits in its clone (ADR-0016). A host-side **orchestrator**
does every privileged thing — push, open PR, read/write comments — with credentials
kept out of the jail ([ADR-0011](../decisions/0011-git-worktree-review-boundary.md) /
[ADR-0014](../decisions/0014-runtime-env-secret-forwarding.md)).

## The adapter (ADR-0020)

The orchestrator is **transport-agnostic**; it drives a small adapter interface, so
the same loop works over Forgejo, GitLab, GitHub (Enterprise), or bare git-over-SSH.
*The verb set below is the original 7; it is finalized as a 9-verb superset with a
`capabilities` verb in [ADR-0022](../decisions/0022-python-adapters-verb-superset-capabilities.md)
(`ensure`→`init`+`ping`, `open-review`→`handover`, `comments`→`examine`, `report`→`reply`).*

| Verb | Meaning |
|---|---|
| `ensure` | ensure the project's remote/repo exists (create if needed — supports instance-per-project) |
| `push <branch>` | push the agent branch to the transport (**outside** the jail) |
| `open-review <branch> <base>` | open/update the review unit (PR / MR / …); return id |
| `status <review>` | `pending` \| `changes-requested` \| `approved` |
| `comments <review>` | unresolved review comments (fed back to the agent) |
| `report <review> <text>` | post the agent's reply/report into the thread (you see it on your phone) |
| `merge <review>` | merge (only when `autoMerge` and approved) |

Adapters: `forgejo` (default), `gitlab`, `github`, `ssh`. Each is a small script/
module host-side; "PR", "MR", and "review" all map to these verbs. **The verb set
is provisional** — 6a (the first real adapter) is expected to reshape it.
**Self-hosted adapters (Forgejo, GitLab-CE, SSH) stay in-guest on the mesh; SaaS
(github.com/gitlab.com) sends the review to a third party** — a conscious
per-project relaxation of confinement, not a default.

## Components & where they live (ADR-0018 split)

- **Forge service** → the **VM config repo (your-config-repo)**. NixOS ships
  `services.forgejo` (and `services.gitlab`); run it on the guest, on the
  **Tailscale** mesh so a phone reaches it privately (no public port). Shared
  instance by default; **instance-per-project** is a config option for enterprise.
- **The orchestrator + adapters** → **ragent** (the reusable framework), in Python
  (ADR-0022): `tools/ragent/orchestrator.py` + `tools/ragent/adapters/`, driven by the unified
  `ragent task orchestrate` CLI (ADR-0023). Reuses the clone/boundary logic in
  `tools/ragent-workspace.sh` and the confined-agent launch in
  `tools/ragent-confine.sh` + `.ragent/spawn-agent.sh`.
- **The dev-forge harness** (`forgejo-local`) → **your-config-repo** (ADR-0018) —
  standing up a forge is deployment config. ragent keeps only a throwaway
  **ephemeral-forge fixture** (`tests/ephemeral_forge.py`) to test its own adapter.
- **Per project** → its `reviewConfig` in the project flake (adapter, remote,
  `autoMerge`, `pollInterval`, bounds — ADR-0020), plus its repo on the forge. The
  forge token is runtime-forwarded (like the API key, ADR-0014), never in the repo.

## The loop (one task)

1. Orchestrator ensures a Forgejo repo for the project and a clone on
   `agent/<task>` (existing ADR-0016 setup).
2. Runs the **jailed agent** on the task; the agent edits + commits **in its clone**
   (verified working — the first real loop + `projectTools` self-test).
3. **Outside the jail**, the orchestrator pushes `agent/<task>` to Forgejo and
   opens/updates a **PR** against the base branch.
4. **You review on the go** in Forgejo (mobile): the diff, line comments, approve.
   Forgejo **notifies** you when the PR is ready / updated (the "on-the-go" enabler).
5. A **webhook** (PR review-comment / review-submitted) hits the orchestrator (or it
   polls the API). It collects unresolved comments, re-prompts the confined agent
   ("address these review comments: …"), the agent revises + commits in the clone,
   and the orchestrator pushes again (updates the PR).
6. Repeat 4–5 **until you approve** (the task is *resolved*) — the human gate. On
   approve, the orchestrator merges if `autoMerge = true`, else it stops and you
   merge (per-project `autoMerge`). If a bound trips first, it labels the review
   **needs-human** and stops. The orchestrator lives only for this task.

## Security (the crux — do not undercut confinement)

- **Jail unchanged.** The agent stays confined to its clone; it does not get the
  forge token. Its network need is only the LLM API (already allowed).
- **All forge I/O is outside the jail**, by the orchestrator, holding the forge
  token + push creds (human/host side).
- **Comments are steering data, bounded by the jail.** A comment re-prompts the
  agent, so there *is* a control path web→agent — but the agent acts **only within
  the jail's blast radius**, and **nothing reaches the real tree without your
  approve/merge**. The webhook endpoint and forge both require **auth**; bind
  localhost + tunnel, or HTTPS + token. Never a naked public port.
- **Bound the autonomous loop** ([ADR-0015](../decisions/0015-cgroup-caps-systemd-run.md)
  instinct, applied to the loop): max iterations, a token/cost ceiling, a wall-clock
  cap, and a **"needs-human" escape** (label the PR, stop) when it stalls or loops.

## State

The **PR is the review state** — Forgejo stores the diff, comments, and status. No
bespoke database. The orchestrator tracks only iteration count / caps in the clone's
`.ragent/`. "Resolved" = PR approved.

## Phasing

- **6a — BUILT & verified locally (2026-07-27); rebuilt in Python (ADR-0022/0023),
  re-verified at parity:** `tools/ragent/orchestrator.py` + `tools/ragent/adapters/forgejo.py`,
  driven by `ragent task orchestrate`; the dev forge is `nix run .#forgejo-local` in
  **your-config-repo**. A real confined agent task opened a real mergeable PR on a
  local Forgejo — body = the agent's `EXPLAIN.md` + the served-report link
  (`ragent task review`), diff = the real change. **Remote next:** the same adapter
  against a NixOS `services.forgejo` on Tailscale — a URL swap, no code change.
- **6b:** the bounded `examine` → agent-revision → `reply` → `merge` loop (poll
  `status`, feed new review notes to the agent), per task until resolved.
- **6c:** polish — notifications tuning, mobile ergonomics, resolution/labels,
  multiple concurrent tasks.

## Decisions (resolved — ADR-0020)

1. **Access:** **Tailscale** — the forge/orchestrator on a private mesh, reachable
   from a phone without a public port or a per-session tunnel.
2. **Auto-merge vs. manual merge:** a **per-project variable** (`autoMerge`),
   default `false` (explicit human merge).
3. **Trigger:** **polling**, with a **per-project `pollInterval`** (no inbound port).
4. **Orchestrator lifetime:** **per task**, running the bounded loop **until the
   task is marked resolved** (approved) — or a bound trips (→ "needs human").

## Links
- [ADR-0020 — Review transport as a pluggable adapter](../decisions/0020-review-transport-adapters.md)
- [Roadmap & future guidelines](roadmap.md)
- [Phase 6 evaluation](phase6-remote-and-async-review.md) (this implements its forge option)
- [ADR-0016 — Agent works in a clone](../decisions/0016-agent-clone-not-worktree.md),
  [ADR-0011 — Git review boundary](../decisions/0011-git-worktree-review-boundary.md)
- [ADR-0014 — Runtime env secret forwarding](../decisions/0014-runtime-env-secret-forwarding.md),
  [ADR-0015 — cgroup caps](../decisions/0015-cgroup-caps-systemd-run.md)
- [ADR-0018 — your-config-repo split](../decisions/0018-split-your-config-repo.md),
  [ADR-0019 — Per-project forking & deps](../decisions/0019-per-project-forking-and-dependencies.md)
