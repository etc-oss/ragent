---
type: decision
id: ADR-0025
title: Jailed Claude Code can authenticate via a Pro/Max subscription token
description: Add a second jailed agent, jailed-claude-code-subscription, that authenticates with a Claude subscription OAuth token (minted by `claude setup-token` in a browser OUTSIDE the jail) instead of an API key. It omits CLAUDE_CODE_SIMPLE (which ≡ --bare and ignores the token) and forwards ONLY CLAUDE_CODE_OAUTH_TOKEN — never the API key — so the key can't shadow the subscription. Verified in the jail with a positive + negative control.
status: accepted
date: 2026-08-15
tags: [auth, jail, claude-code, subscription, oauth, secret, confinement]
timestamp: 2026-08-15
---

# ADR-0025 — Jailed Claude Code can authenticate via a Pro/Max subscription token

## Context and problem statement

[ADR-0014](0014-runtime-env-secret-forwarding.md) forwards a provider **API key**
into the jail at runtime (never in the store/repo). `jailed-claude-code` pairs that
with `CLAUDE_CODE_SIMPLE=1` — without it a jailed run reported "Not logged in". But
API usage is billed per token; a user with a Claude **Pro/Max subscription** wants
the jailed agent to draw on that instead. Claude Code supports this via a long-lived
token, but the mechanism interacts with our jail in two non-obvious ways that a naive
change gets wrong.

## Decision

**Add a second agent, `jailed-claude-code-subscription`, authenticated by a Claude
subscription OAuth token** — the same runtime-env-forwarding pattern as ADR-0014,
just a different credential. Keep `jailed-claude-code` (API key) as the default and
the limit-free fallback; pick either at runtime with `RAGENT_AGENT`.

The token is minted **once, in a browser, OUTSIDE the jail** (`claude setup-token` →
a 1-year, "model-requests-only" token) and stashed in the guest
`~/.config/ragent/env` (0600) as `CLAUDE_CODE_OAUTH_TOKEN`, exactly like the API key
— never in the store, the repo, or chat.

Two findings (verified against **claude-code 2.1.220** — the actual binary in the
jail — not assumed) shape the build:

1. **`CLAUDE_CODE_SIMPLE` ≡ `--bare`, and bare mode deliberately ignores the OAuth
   token.** The bundle contains `rm(){return Yt(process.env.CLAUDE_CODE_SIMPLE)||…("--bare")}`
   and the string *"Sets CLAUDE_CODE_SIMPLE=1. Anthropic auth is strictly
   ANTHROPIC_API_KEY or apiKeyHelper… (OAuth … disabled)"*; the docs confirm *"Bare
   mode does not read CLAUDE_CODE_OAUTH_TOKEN."* So the subscription variant **must
   omit `CLAUDE_CODE_SIMPLE`.**
2. **Auth precedence: `ANTHROPIC_API_KEY` (#3) beats `CLAUDE_CODE_OAUTH_TOKEN` (#5).**
   If both are present the API key silently wins — the run succeeds while billing the
   API, not the subscription (a false green). So the subscription variant forwards
   **only** the token (`claudeSubBaseOptions = commonJailOptions ++ try-fwd-env
   "CLAUDE_CODE_OAUTH_TOKEN"`), and **not** the API key. This makes the shadowing
   *structurally impossible*, and also stops a Claude token leaking into the
   opencode/pi/crush jails (which keep the shared, API-key `agentBaseOptions`).

`makeJailedClaudeCode` hardcodes its bin to `jailed-claude-code`, so the variant's
bin is renamed (a symlink — the wrapper uses absolute store paths, not `$0`) to avoid
a PATH collision and let `RAGENT_AGENT=jailed-claude-code-subscription` resolve. The
token is a static credential, so — unlike a bound `~/.claude/.credentials.json` — it
needs no writable creds file; env forwarding suffices and adds **no new jail surface**
beyond ADR-0014.

## Verification (guest, isolated — no false green)

- **Raw** (`env -i`, API key absent, only the token): `claude -p` authenticated
  non-interactively → `OK`. (Confirmed the onboarding path that once caused "Not
  logged in" with a bare API key does not block a valid token.)
- **Jailed positive** (token forwarded; API key present in the caller's shell but
  **not** forwarded by this variant): → `OK`.
- **Jailed negative control** (token unset; API key **still set**): → `Not logged in`.
  Decisive — with the token gone the jail gets no credentials even though the API key
  is right there, proving the key genuinely never reaches the subscription jail.

## Consequences

### Positive
- Use a subscription for jailed runs; the API-key agent stays as default + fallback.
- The precedence trap is prevented structurally, not by documentation.
- No new jail surface (env-forwarded, stateless token; no creds file to bind).

### Negative / trade-offs
- Subscription **weekly limits**: autonomous dogfooding draws them down — the reason
  the API-key variant remains the limit-free fallback.
- A second agent in the list (flows through packages/PATH); one rename shim.
- Dropping `CLAUDE_CODE_SIMPLE` re-enables onboarding/keychain/CLAUDE.md discovery;
  a valid token authenticates non-interactively regardless (verified), but this is
  version-sensitive — re-verify on a Claude Code bump.
- The OAuth token is the same secret-risk class as the API key (already in-jail).

## Alternatives considered
- **Forward both, keep `SIMPLE=1`** — rejected: `SIMPLE`≡bare ignores the token, and
  even without `SIMPLE` the key (#3) shadows the token (#5) → false green.
- **Bind `~/.claude/.credentials.json` from a host `claude login`** — heavier
  (writable creds file, refresh writes); the env token is stateless and simpler.
- **A build-time `mkWorkspace { claudeAuth }` toggle instead of two variants** —
  fine and default-safe, but subscription limits make per-run fallback to the API key
  plausible, so runtime selection via `RAGENT_AGENT` (two variants) wins here.

## Links
- [ADR-0014 — Runtime env secret forwarding](0014-runtime-env-secret-forwarding.md)
  (this is the same pattern, a different credential)
- [ADR-0013 — jailed-agents / opencode first](0013-jailed-agents-opencode-first.md)
- `flake.nix` (`claudeSubBaseOptions`, `jailed-claude-code-subscription`),
  [Roadmap](../components/roadmap.md)
