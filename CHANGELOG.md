# Changelog

All notable changes to ragent. **Pre-release — nothing has been published;** the
repository is local-only. Everything below was verified locally (macOS host + a
Lima Linux guest) and is **not yet wired into CI**.

## Unreleased — Phase 6 + subscription auth (2026-07 → 2026-08)

### Phase 6 — async review (agent → PR → bounded human-paced loop → merge)
- Pluggable review-transport **adapter** (ADR-0020); transport-agnostic orchestrator,
  **Forgejo** reference. Finalized as a Python **9-verb superset + `capabilities`**
  (ADR-0022): `ping`/`capabilities` · `init`/`push` · `handover`/`status`/`merge` ·
  `examine`/`reply`.
- **Unified `ragent` CLI** (ADR-0023) — `task window | orchestrate | review | list |
  attach | kill`; `apps.default = ragent` + thin `task-*` aliases (replaces the flat
  `#workspace` / `#serve` / `#orchestrate` / `#zellij` apps).
- Python **orchestrator** — a real jailed agent opens a real PR (body = the agent's
  explanation + the real diff), verified at parity on a local Forgejo.
- **6b: bounded, human-paced loop** (ADR-0024) — poll `status`, feed only *new* review
  notes to the confined agent, revise/reply/merge; `max_iterations` is the
  load-bearing runaway guard, wall-clock a resource cap, with a needs-human escape.
- **Per-task served HTML report** (ADR-0021) — the agent's `EXPLAIN.md` + real diff, a
  forge-independent oversight channel (`ragent task review`).
- Dev-forge harness (`forgejo-local`) moved to the config repo; ragent keeps only an
  ephemeral-forge **test fixture** for its own adapter tests.

### Claude Code authentication
- **Subscription auth** (ADR-0025) — `jailed-claude-code-subscription` authenticates
  with a Pro/Max token (`claude setup-token`, browser, outside the jail). Forwards
  **only** the token, never the API key, so the key can't shadow the subscription;
  verified with a positive + negative control against the real binary.
- **Usage-limit wait layer** (ADR-0026) — on the autonomous path, wait out a
  subscription usage limit and retry rather than fall back to the API; fail-safe
  detection, bounded wait, idle time excluded from the loop's cost bound.

### Docs / release prep
- `SECURITY.md` (confinement model + disclosure); README rewritten for the full
  feature set + an honest "how it's airtight" section; an opt-in OpenTelemetry
  observability item added to the roadmap; git-**history** secrets audit — clean; CI
  now runs the Python test suites (adapter / 6b loop / rate-limit) alongside the jail
  build.

## Unreleased — Phases 0–5 (2026-07-26)

### Phase 0 — scaffold + governance
- Apache-2.0 (ADR-0001); `NOTICE` + `THIRD_PARTY.md` with verified upstream
  licenses; `AGENTS.md` / `CLAUDE.md` entrypoints.
- OKF knowledge bundle (sessions / decisions / components / conventions) and a
  dependency-light Markdown→HTML generator with a knowledge-graph visualizer.
- Genesis conversation captured verbatim; 11 seed ADRs distilled from it.

### Phase 1 — the jail, one agent
- Confinement via `jail.nix` / bubblewrap (jailed-agents). Negative-control test
  **8/8**; cgroup caps enforce; DNS works. opencode + Claude Code run confined.
  ADRs 0013–0015.

### Phase 2 — the Zellij workspace
- Two-side HUMAN / MACHINE KDL layout; git **clone** review boundary (ADR-0016 —
  a clone, not a worktree, so in-jail git works); launcher + packaged app.

### Phase 3 — the tooling layer
- `git-surgeon` (raine, ADR-0017) plus a shared-tools layer on every agent's
  in-jail PATH; a per-project template; the agent-capabilities convention.

### Phase 4 — observability + more agents
- `pi` and `crush` added — four agents total, all confined and sharing the
  tooling layer; the MACHINE pane tails per-agent logs.

### Phase 5 — open-source hardening
- `nix flake check` builds the jail + git-surgeon; a CI workflow
  (`.github/workflows/ci.yml`) prepared; `CONTRIBUTING.md`; license audit; a
  VM-native deployment guide.

### Deferred / not done
- A real agent **edit** with a provider key (ADR-0014 auth decision).
- Interactive TUI ergonomics (truecolor / clipboard / keybindings) — human-verified.
- The consumable `ragent-config` split (ADR-0012).
- **Publishing** (public remote / push / tag) — awaits explicit owner go-ahead.
