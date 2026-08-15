---
type: decision
id: ADR-0029
title: A first-class local dev forge (Nix app), not docker-compose
description: Ship `nix run .#dev-forge` — a persistent localhost Forgejo (from nixpkgs) that writes forge.env — so the async review loop runs out of the box, without standing a forge up yourself. Deliberately not docker-compose (the guest has no Docker daemon; nixpkgs already ships forgejo). Refines ADR-0018 — the deployed/remote forge stays in your-config-repo; only the throwaway dev forge is framework DX.
status: accepted
date: 2026-08-15
tags: [forge, forgejo, dev-experience, async-review, nix, phase-6]
timestamp: 2026-08-15
---

# ADR-0029 — A first-class local dev forge (Nix app), not docker-compose

## Context and problem statement

The async review loop ([ADR-0020](0020-review-transport-adapters.md)) is ragent's
"review on the go" feature, but a fresh consumer can't *try* it without a forge — and
per [ADR-0018](0018-split-your-config-repo.md) the dev forge (`forgejo-local`) lives in
**your-config-repo** (personal deployment config). So "clone ragent, run the async loop"
doesn't work out of the box — a real onboarding gap for the flagship feature. The
question that surfaced it: *should ragent ship a docker-compose so the loop runs locally?*

## Decision

**Ship a first-class local dev forge as a Nix app — `nix run .#dev-forge` — and
explicitly not docker-compose.**

- **`tools/ragent-dev-forge.py`** (stdlib) stands up **Forgejo from nixpkgs** on
  `127.0.0.1`, seeds an admin user + a fresh API token, writes
  `~/.config/ragent/forge.env` (the `RAGENT_ADAPTER` + `RAGENT_FORGE_URL/USER/TOKEN` the
  adapter reads), then `exec`s `forgejo web` in the **foreground**. The flake app
  `apps.dev-forge` puts `forgejo` on its PATH. Then: `source ~/.config/ragent/forge.env`
  in another shell and `ragent task orchestrate` just works.
- **Not docker-compose**, for concrete reasons — not taste: the Lima guest **has no
  Docker daemon**, so compose means adding a heavyweight new dependency and a **second
  packaging paradigm** beside Nix; and **nixpkgs already ships `forgejo`** — the exact
  substrate `tests/ephemeral_forge.py` already proves (nixpkgs + SQLite + localhost, zero
  external deps). The Nix path reuses what's there; Docker bolts on what isn't.
- **Foreground, not a daemon.** `exec forgejo web` ties the forge to the terminal —
  Ctrl-C stops it cleanly and **no daemon lingers to leveldb-lock the data dir** on the
  next run (the trap `ephemeral_forge.py` was written to dodge). A port-in-use precheck
  catches an already-running instance.
- **A standalone app, not a `ragent task` subcommand** — standing up a forge is *infra*,
  not an agent task; the CLI stays focused on agent tasks (ADR-0023).

## This refines ADR-0018 — three tiers of forge

[ADR-0018](0018-split-your-config-repo.md) put "the dev forge" in your-config-repo
because *standing up a forge is deployment config*. That holds for a **deployed** forge;
it over-reached to the **out-of-box dev** case. The clean cut is three tiers:

| Tier | What | Where |
|---|---|---|
| **Test fixture** | throwaway, per-run, two users, for the adapter suite | ragent `tests/ephemeral_forge.py` |
| **Dev forge** (this ADR) | persistent-localhost, one admin, human-facing, out-of-box | **ragent `nix run .#dev-forge`** |
| **Deployed forge** | real, persistent, remote (NixOS `services.forgejo` on Tailscale) | your-config-repo (ADR-0018 holds) |

The deployed/personal forge still lives in your-config-repo; only the throwaway dev forge
is framework DX. ADR-0018's split is intact — refined, not reversed.

## Consequences

### Positive
- **Out-of-box async review**: `nix run .#dev-forge` → `ragent task orchestrate` with no
  personal config repo. The flagship feature is demoable in one command.
- Reuses the hard-won `ephemeral_forge.py` lessons (migrate-before-create, readiness
  poll, `INSTALL_LOCK`/`DISABLE_SSH`) without importing test code into the runtime.
- localhost-only, never a public port ([ADR-0020](0020-review-transport-adapters.md)); a
  remote forge is still just a `RAGENT_FORGE_URL` swap.

### Negative / trade-offs
- A small maintained artifact in the framework (one stdlib script + one flake app).
- Consumers who want `.#dev-forge` in *their* flake re-export it (a one-liner); it isn't
  auto-exposed by `mkWorkspace` (wire consumer access when a consumer needs it).
- A fresh token is minted per run (old tokens accrue in the dev DB — harmless for a
  throwaway forge).

## Alternatives considered
- **docker-compose** — rejected: no Docker daemon in the guest; a second packaging
  paradigm; nixpkgs already provides forgejo. (A compose file could be a *documented
  recipe* for non-Nix users, but not the first-class path.)
- **Leave the dev forge in your-config-repo** (status quo) — rejected: blocks out-of-box
  async review for every consumer; the flagship feature shouldn't need personal config.
- **A `ragent task dev-forge` subcommand** — rejected: it's infra, not an agent task.
- **A long-running daemon / systemd service** — rejected for the dev case: the lingering
  instance leveldb-locks the data dir; foreground is simpler and safer.

## Verification
Real run in the Lima guest (throwaway dir + port, torn down): `nix run .#dev-forge` built
+ started Forgejo 16.0.1 on `127.0.0.1`, wrote `forge.env` (0600); the Forgejo adapter,
loaded from that `forge.env`, `ping()`ed (GET /user, token auth → true) and `init()`ed
(created a private repo — write scope). Eval-green was not assumed; the adapter path was
exercised (per roadmap principle #7).

## Links
- [ADR-0018 — Split personal config into your-config-repo](0018-split-your-config-repo.md)
  (this refines it — the deployed forge stays there)
- [ADR-0020 — Review transport adapters](0020-review-transport-adapters.md)
  (localhost/Tailscale, never a public port),
  [ADR-0023 — Unified ragent CLI](0023-unified-ragent-cli.md) (why a standalone app, not a task)
- [async review transport](../components/forgejo-transport-design.md),
  [guide: async review with Forgejo](../../guides/async-review-forgejo.md),
  `tools/ragent-dev-forge.py`, `tests/ephemeral_forge.py`
