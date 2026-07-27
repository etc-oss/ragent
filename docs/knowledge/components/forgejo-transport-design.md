---
type: component
id: COMP-forgejo-transport
title: 'Forgejo-as-transport for async agent review (design, Phase 6a)'
description: A concrete, implementable design for the async review loop using a shared self-hosted Forgejo — the orchestrator pushes the agent's branch as a PR from outside the jail; the user reviews on the go; comments drive a bounded agent revision loop.
tags: [proposal, forgejo, review, orchestrator, phase-6, security]
timestamp: 2026-07-27
---

# Forgejo-as-transport for async agent review (design, Phase 6a)

Concrete design for the async web-review loop from the
[Phase 6 evaluation](phase6-remote-and-async-review.md), using the **buy-not-build**
option it recommended: a self-hosted **Forgejo** provides diff review, line
comments, resolution, auth, a mobile UI, and notifications for free. **Design for
review — not yet built.** Owner decisions taken: **one shared guest forge**;
capture the design first.

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

## Components & where they live (ADR-0018 split)

- **Forgejo service** → the **VM config repo (your-config-repo)**, since it is
  deploy/VM specifics. NixOS ships `services.forgejo`; run it on the guest bound to
  `127.0.0.1:3000`, reached from a phone via SSH tunnel or HTTPS+token. One
  instance, one org, a repo per project.
- **The orchestrator** → **ragent** (the reusable framework), exposed like the
  workspace: a script + a `lib.<system>.mkOrchestrator`/`apps.orchestrate` that a
  project invokes. It reuses the existing clone/boundary logic in
  `tools/ragent-workspace.sh` and the confined-agent launch in
  `tools/ragent-run.sh` + `.ragent/launch-agent.sh`.
- **Per project** → its repo on the forge; the orchestrator run per task. No new
  per-project infra (the shared forge serves all).

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
6. Repeat 4–5 until you **approve** — the human gate. Merge is your action (or
   auto-merge-on-approve, configurable; the gate stays human).

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

- **6a (this design):** Forgejo on the guest + the orchestrator pushes an agent
  branch as a PR you can review read-only on your phone. *No comment loop yet.*
- **6b:** the comment → agent-revision loop (webhook or poll), bounded.
- **6c:** polish — notifications tuning, mobile ergonomics, resolution/labels,
  multiple concurrent tasks.

## Open decisions (for the owner, before 6a code)

1. **Access from the phone:** SSH tunnel to `127.0.0.1:3000` (simplest, most
   secure) vs. Forgejo HTTPS on a LAN/Tailscale address (more convenient, needs a
   cert). Recommend SSH tunnel / Tailscale first.
2. **Auto-merge on approve** vs. approve-then-you-merge. Recommend the latter
   (explicit human merge) initially.
3. **Trigger:** webhook (needs the orchestrator reachable by the forge) vs. the
   orchestrator **polling** the PR API (simpler, no inbound port). Recommend polling
   for 6b's first cut.
4. **Where the orchestrator runs long-term:** a foreground run you start per task,
   vs. a small persistent guest service. Recommend per-task foreground for 6a/6b.

## Links
- [Phase 6 evaluation](phase6-remote-and-async-review.md) (this implements its forge option)
- [ADR-0016 — Agent works in a clone](../decisions/0016-agent-clone-not-worktree.md),
  [ADR-0011 — Git review boundary](../decisions/0011-git-worktree-review-boundary.md)
- [ADR-0014 — Runtime env secret forwarding](../decisions/0014-runtime-env-secret-forwarding.md),
  [ADR-0015 — cgroup caps](../decisions/0015-cgroup-caps-systemd-run.md)
- [ADR-0018 — your-config-repo split](../decisions/0018-split-your-config-repo.md),
  [ADR-0019 — Per-project forking & deps](../decisions/0019-per-project-forking-and-dependencies.md)
