---
type: component
id: COMP-phase6-remote-async-review
title: 'Phase 6 (proposed): remote access & async web review'
description: An evaluation of two forward ideas — remoting the workspace (Zellij sessions) and a server-backed web surface for async diff review/annotation during long, unsupervised agent runs. Options, not decisions.
tags: [proposal, remote, web, review, observability, orchestrator, phase-6]
timestamp: 2026-07-27
---

# Phase 6 (proposed): remote access & async web review

Two forward ideas, **evaluated — not decided**. Both are about *oversight when you
are not sitting at the workspace*: (1) reaching the TUI from another machine, and
(2) a lightweight web surface to review an agent's diffs on the go. They are
complementary layers of the same "async/remote oversight" spectrum, not rivals.

> **Prerequisite (queue-placement honesty).** This is Phase 6+, and its floor has
> not been built: the **synchronous** agent edit → review → merge loop (ADR-0011 /
> [ADR-0016](../decisions/0016-agent-clone-not-worktree.md)) has never actually run
> — every agent has been verified only via `--version`, not a real task with a key.
> An async, unsupervised, web-reviewed loop is the *second story on an unbuilt first
> floor*. Compelling direction; gated on first demonstrating the core loop.

## 1. Remote access — is Zellij "remote sessions" ideal?

**Separate the enabler from the access method.** The property that actually makes
long, unattended runs safe to walk away from is Zellij **session
persistence/resurrection** — the session survives your disconnect *and* a server
restart, so you can re-attach later and nothing is lost. That is the load-bearing
part. *How* you reach it is secondary:

- **SSH + `zellij attach`** — the classic, terminal-native, secured by SSH. This is
  the right default for the **primary-device remote-TUI** path (macOS → SSH → the
  Linux guest → attach), and it is already how ragent is meant to run remotely
  ([running on a VM](running-on-a-vm.md)).
- **Zellij web client** (introduced 0.43.0; remote-over-HTTPS in 0.44.0 — we run
  0.44.3). A built-in web server (default `127.0.0.1:8082`) serves the session in a
  browser; **token auth** is required, **HTTPS is enforced on non-localhost**
  interfaces, and **read-only tokens** let you *watch* a session without being able
  to type into it. That read-only mode is genuinely nice for **observing a
  long-running agent from any device**.

**Two honest limits.**
1. Even remoted, it renders the **full TUI** — nvim, lazygit, btop. That is the
   wrong surface for *fine-grained diff review on a phone* (tiny screen, terminal
   keys, Zellij chords). Great for a glance; poor for line-by-line review. This gap
   is exactly why idea (2) exists.
2. `zellij web` exposes the **privileged HUMAN pane too** — nvim on the *real* tree,
   lazygit holding git credentials — not just the confined machine side. Read-only
   tokens limit *input*, but your code and git state are on the wire. So: bind to
   localhost + SSH tunnel, or HTTPS + tokens; never a naked public bind.

**Verdict:** use it — session persistence is the enabler, SSH-attach the default,
`zellij web` (read-only token) a nice *observation* layer. It is **not** the tool
for casual mobile review; that is idea (2).

## 2. Async web review loop — extend the HTML into a review surface?

The idea: during a long, unsupervised session the flake's orchestrator exposes,
over a lightweight server, not just the static ADRs/docs but the agent's **live
diffs**, which the user can **review, annotate, and comment on** from a browser.
The agent captures that feedback, revises, and regenerates until the user marks the
diff **resolved** — async oversight from a secondary device, with the TUI reserved
for deep work on the primary one.

**Why it fits ragent (this is the appealing part).** It is a natural extension of
pieces that already exist, not a new universe:
- The **git-clone review boundary** ([ADR-0016](../decisions/0016-agent-clone-not-worktree.md))
  already produces exactly the artifact to render: `git diff <base>..agent/<task>`.
- The **OKF/ADR knowledge system** ([ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md))
  already captures decisions and renders them to offline HTML
  ([knowledge-system](knowledge-system.md)); an agent "report" is just another OKF
  `session`/`decision` concept, and a *review* (comments + resolution) can be one too.
- Human oversight of machine work is the project's founding value (the genesis
  session) — this is that value, made **asynchronous**.

**Design shape, if pursued (keep it on-ethos):**
- **Static generator stays the base; add an *optional* server layer** — do not
  replace `tools/okf_render.py`. Offline, dependency-light HTML remains the default;
  the server is a mode you turn on for a session.
- **Persist review state git-natively** — comments, annotations, and resolution
  status as Markdown/OKF under the clone's `.ragent/review/`. It then syncs via git
  (works offline, portable, diffable) and lands in the knowledge graph as a concept.
  No database.
- **Confinement property, stated precisely.** The web surface is *not* "data that
  never executes" — the whole point is that comments **drive the confined agent to
  act**. The defensible property is narrower and is the security crux: web input
  steers the agent **only within the jail's blast radius**, and **nothing reaches
  the real tree without the human merge gate** (ADR-0011 / ADR-0016). So the comment
  endpoint still needs **auth** (an attacker who can post can make the confined agent
  thrash and write into the clone — bounded, not nothing), and "resolve"/merge stay
  explicit human actions.
- **Bound the autonomous loop — the biggest *new* risk.** "Iterate until resolved,"
  unsupervised, can thrash, drift, or burn tokens with no human present. Apply the
  [ADR-0015](../decisions/0015-cgroup-caps-systemd-run.md) blast-radius instinct to
  the *orchestration loop*, not just the process: **max iterations, a token/cost
  ceiling, a wall-clock cap, and a "needs human" escape state** when it stalls.

**Buy vs. build — weigh a self-hosted forge first.** A self-hosted **Forgejo/Gitea**
gives diff review, line comments, resolution state, auth, a mobile-friendly web UI,
**and push notifications** — all battle-tested — for a fraction of a bespoke build.
The orchestrator pushes the agent's `agent/<task>` branch as a PR; the user reviews
from the forge on their phone; a webhook/poll feeds comments back to the agent;
"resolved" = PR approved. Two precise constraints:
1. **The push must run *outside* the jail.** Pushing needs credentials ADR-0011 /
   [ADR-0014](../decisions/0014-runtime-env-secret-forwarding.md) deliberately keep
   out of the jail — so the **orchestrator (host/human side)**, not the jailed agent,
   does the push. That preserves the secret boundary.
2. **Notifications are the "on-the-go" enabler.** Review-on-the-go needs a *push*
   signal ("diff ready" / "agent responded") or the user is left polling — a forge
   gives this free; a bespoke surface must add it.

**Phased vertical slice, if built bespoke** (each step independently useful):
(a) render the current diff to **static** HTML (a small `okf_render` extension);
(b) a **read-only live server** to serve it during a session;
(c) **comments** appended to the `.ragent/review/` markdown sidecar;
(d) the **agent-iterate-until-resolved** orchestration loop — *last*, and bounded.

## Recommendation

- **Q1:** Adopt session persistence + SSH-attach as the remote default now (it's
  nearly free and already implied by [running-on-a-vm](running-on-a-vm.md)); treat
  `zellij web` (read-only token, tunneled/HTTPS) as an optional *observation* layer.
  Do not expect it to serve mobile diff review.
- **Q2:** Strong, on-ethos direction — but **gate it on first demonstrating the
  synchronous core loop** (a real agent edit, reviewed and merged). When that
  exists, prefer **forge-as-transport** (Forgejo) for the first version — it buys
  ~90% of the value, including notifications, at ~10% of the effort — and only build
  the bespoke `.ragent/review/` surface if the forge genuinely does not fit. Whatever
  the transport: bound the autonomous loop, keep the jail + human merge gate intact,
  and never bind a naked public port.

This is a proposal for discussion, recorded per the project's capture-everything
ethos; it is **not** an accepted decision.

## Links
- [Forward plan (Phases 1–5)](forward-plan-phases-1-5.md) — this sits after it.
- [ADR-0011 — Git review boundary](../decisions/0011-git-worktree-review-boundary.md),
  [ADR-0016 — Agent works in a clone](../decisions/0016-agent-clone-not-worktree.md)
- [ADR-0008 — OKF + ADR knowledge capture](../decisions/0008-okf-adr-knowledge-capture.md),
  [knowledge-system](knowledge-system.md)
- [ADR-0014 — Runtime env secret forwarding](../decisions/0014-runtime-env-secret-forwarding.md),
  [ADR-0015 — cgroup caps](../decisions/0015-cgroup-caps-systemd-run.md)
- [ADR-0005 — Zellij two-side layout](../decisions/0005-zellij-two-pane-layout.md),
  [running on a VM](running-on-a-vm.md)
