# Changelog

All notable changes to ragent. **Pre-release — nothing has been published;** the
repository is local-only. Everything below was verified locally (macOS host + a
Lima Linux guest) and is **not yet wired into CI**.

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
