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

## Next: Phase 6 — async review & task orchestration

Let a human oversee long, unsupervised runs **asynchronously** — the agent does the task
and makes the code available for review *when you're ready* — keeping the TUI for deep,
hands-on work. (Review works on any device, phone included; that's a convenience, not the
point — ragent is an async session/task orchestrator, not a mobile-first tool.) Design in
[async review transport](forgejo-transport-design.md); decision in
[ADR-0020](../decisions/0020-review-transport-adapters.md).

- **6a — done, rebuilt in Python (ADR-0022/0023), re-verified at parity:** the
  Forgejo adapter + orchestrator, driven by `ragent task orchestrate`, open a real PR
  from a real confined agent task (body = the agent's explanation + the served-report
  link, diff = the real change). Remote next: the same adapter against a NixOS
  `services.forgejo` on Tailscale (a URL swap).
- **6b — done, verified (ADR-0024):** the bounded, **human-paced**
  `examine`→revise→`reply`→`merge` loop — poll `status`, feed only NEW review notes to
  the confined agent, per task until resolved. `max_iterations` is the load-bearing
  runaway guard; wall-clock is a resource cap (hours); "cost" is cumulative agent
  runtime; a tripped bound posts a **needs-human** reply and stops.
- **6c** — polish: notifications, (optional) mobile-review ergonomics, a needs-human forge label,
  concurrency, and **durable/resumable waits** (persist loop state + subscription
  usage-limit waits, [ADR-0026](../decisions/0026-subscription-usage-limit-wait.md),
  so a VM restart doesn't drop a long pause).

The transport is a **pluggable adapter** (Forgejo default; GitLab, GitHub
Enterprise, git-over-SSH), configured per project (`reviewConfig`: adapter, remote,
`autoMerge`, `pollInterval`, bounds).

**Already shipped — the served per-task report** ([ADR-0021](../decisions/0021-per-task-explanatory-report.md)):
alongside every task, the agent's own explanation + the real diff render to a
self-contained HTML report, served (`nix run .#task-review`, localhost/Tailscale). This
is the forge-independent oversight channel — universal, reviewable from any device —
and the substrate the forge `reply` verb posts back into the thread (6b).

**Also shipped — an out-of-box local dev forge** ([ADR-0029](../decisions/0029-local-dev-forge.md)):
`nix run .#dev-forge` stands up a localhost Forgejo (from nixpkgs) + writes `forge.env`, so
the async loop runs without a personal config repo — **Nix, not docker-compose** (the guest
has no Docker daemon; nixpkgs already ships forgejo). This refines the
[ADR-0018](../decisions/0018-split-your-config-repo.md) boundary: the *deployed/remote* forge
stays in your-config-repo; only the throwaway *dev* forge is framework DX.

## Beyond — future guidelines (direction, not commitments)

- **Per-agent config (`agentConfig`)** — a per-project knob to opt each agent into
  its *native* strengths without breaking the portable core: e.g. "in this repo,
  Claude Code uses the OpenSpec skill / an MCP server; pi uses a prompt convention".
  The lowest-common-denominator (CLIs on PATH + `AGENTS.md`) stays the guaranteed
  floor; `agentConfig` layers native skills / MCP / bound config on top per agent
  (`mkWorkspace { agentConfig = { jailed-claude-code = { skills=…; extraBind=…; }; }; }`),
  so a capable agent runs at full strength while the orchestrator stays
  agent-agnostic (ADR-0007). Deferred — flagged for design later.
- **Adapters in Python — done (ADR-0022).** The transport adapters + orchestrator are
  Python behind a `ReviewAdapter` ABC (stdlib `urllib`); the transport-agnostic verb
  boundary made it a contained change. A Go/Rust adapter would need a subprocess shim
  (out of scope). What remains is *more* adapters ↓.
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
- **Richer observability (opt-in, OpenTelemetry)** — only if the log panes + served
  reports fall short (the genesis warning against a premature "unified" logger still
  stands). When warranted, an **opt-in, self-hosted-first telemetry adapter over
  OpenTelemetry**: Claude Code already emits OTel (`CLAUDE_CODE_ENABLE_TELEMETRY` +
  `OTEL_*` exporters), so **Langfuse or any OTLP backend** is just config — traces,
  token/cost, latency, cross-run evals. Vendor-neutral; **self-hosted on the Tailscale
  mesh** so prompts/traces stay inside the confinement boundary (the SaaS-vs-self-hosted
  stance of [ADR-0020](../decisions/0020-review-transport-adapters.md)). Widening the
  jail's egress to the collector is a conscious per-project opt-in, defaulting off.
- **Local models (opt-in, on-box inference)** — run the agents against a **local LLM**
  (Ollama / llama.cpp / vLLM) instead of a cloud API. A pluggable per-project knob that,
  when opted in, **auto-installs the runtime and pulls the model** (Ollama is in
  nixpkgs) and points each agent at it via its OpenAI-compatible base URL. The model
  runs *outside* the sandbox; the confined agent just connects over localhost/the mesh —
  so **inference stays on-box, nothing leaves the confinement boundary** (the same
  self-hosted-first ethos as the forge and OTel adapters). **Evaluate LiteLLM** as the
  normalization layer: an OpenAI-compatible proxy over 100+ backends (local *and* cloud)
  that gives one endpoint all four agents point at, with provider routing / fallbacks /
  budgets configured centrally (and a natural tie-in to the cost/usage-limit story). For
  a single local model a direct base-URL config is simpler; the LiteLLM proxy earns its
  keep in the multi-provider / routing case. Deferred — design as a `localModels` config
  alongside `reviewConfig` / `agentConfig`.
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
