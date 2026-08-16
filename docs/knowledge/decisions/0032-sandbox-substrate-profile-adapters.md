---
type: decision
id: ADR-0032
title: Decouple ragent into a sandbox substrate + adapter-based profiles (ACP/A2A)
description: ragent splits into (a) the sandbox SUBSTRATE (jail + egress allowlist + caps + Nix tools + optional local model + an ACP/A2A endpoint + a profile SPI) and (b) PROFILES — typed agent kinds (code, web, data, reservations, ops, research) where each profile is a thin wrapper with a standard interface over a PLUGGABLE tool adapter (Firecrawl, an MCP data server, a booking API, the review transport). `code` is the reference profile. The sandbox posture + egress allowlist are per-profile. The profiles are a consuming orchestrator's typed agents.
status: accepted
date: 2026-08-16
tags: [architecture, sandbox, profiles, adapters, acp, a2a, refactor]
timestamp: 2026-08-16
---

# ADR-0032 — ragent = a sandbox substrate + adapter-based profiles

## Context and problem statement

ragent conflates two separable things: the **sandbox substrate** (confine *any* agent — jail +
egress allowlist + cgroup caps + Nix-provisioned tools) and a **code workflow** (clone →
orchestrate → PR → review). The substrate is general; the code flow is one application of it.
And per the maintainer's mandate, each purpose-specific agent should be a **wrapper with a
standard interface over a *pluggable* underlying tool** — adapters everywhere — so the tool
under a capability can be swapped in or out without touching the substrate or the orchestrator.

## Decision

**Decouple: `ragent` = the substrate + a profile SPI; every capability is an adapter.**

- **Substrate (`ragent` core):** the sandbox (jail + **per-profile** egress allowlist +
  caps) + Nix tool-provisioning + optional local model + an **ACP/A2A endpoint** + a
  **profile SPI** (a profile declares: capability interface · tool-adapter(s) · scope ·
  sandbox posture + egress · model · the ACP/A2A surface).
- **Profiles** = typed agent kinds. Each is a **thin wrapper with a standard interface**, and
  the underlying tool is a **pluggable adapter**:

  | Profile | Interface (standard) | Pluggable tool-adapter(s) | Sandbox posture |
  |---|---|---|---|
  | **`code`** *(reference, built)* | edit · test · open/revise a PR | the **review transport** (Forgejo/GitLab/GitHub — the existing `ReviewAdapter`, ADR-0022) + a coding agent (Claude Code/opencode/pi/crush) | full FS jail + egress = LLM API |
  | **`web`** | fetch · crawl · extract · ingest | **Firecrawl** (default) — pluggable: Playwright / Tavily / browserless | read-only + egress = the target domains |
  | **`data`** | query · read · expose | an **MCP server over the source** (Postgres / S3 / warehouse / files) — ragent as a *sandboxed MCP gateway* | read-only + egress = the source only |
  | **`reservations`** *(hypothetical)* | search · hold · book · cancel | a provider API (calendar / OTA / OpenTable / …) — one adapter per provider | usually no FS jail; egress = the provider; **hard human gate on any booking** |
  | **`ops` / `comms`** | draft · schedule · file | email/calendar APIs (Gmail/Outlook/CalDAV) | **draft-not-send**; egress-allowlisted; human gate |
  | **`research`** | gather · synthesize | search + `web` + `data` adapters composed | read-only + egress = sources |

  A profile's tool plugs in/out behind its interface — swap Firecrawl for Playwright, or one
  ERP/provider adapter for another, with no change to the substrate or the orchestrator.

- **`code` is the reference profile**, refactored to sit *behind* the SPI. That refactor **is**
  the decoupling — everything else is a profile added later.

## The sandbox posture is per-profile (the critical bit)

The egress allowlist (ADR-0031) defaults to the LLM API only — but `web`/`data`/`reservations`
**must** reach *other* hosts (crawl targets, the DB, the provider). So **each profile declares
its own egress allowlist and sandbox level**; the substrate is *profile-aware*, not
one-size. `code` = full FS jail; `web`/`data` = read-only + egress to the source domains;
`ops`/`reservations` = often unsandboxed API calls + an egress allowlist + a **hard human gate
on any acting output** (a sent email, a booking, a ledger entry). This reuses the ADR-0031
`RAGENT_EGRESS_ALLOW` knob per profile.

## Ties to a consuming orchestrator + interop

- **The ragent profiles *are* a consuming orchestrator's typed agents** (the `web` profile, the
  `data` profile, …). ragent supplies the *sandboxed profile primitives* + an **ACP/A2A** surface;
  **a consuming orchestrator is the conductor** — board, inbound intake, pipelines, governance, source-of-record, and
  the *outbound* adapters (ERP/CRM/…). ragent = the instruments; a consuming orchestrator = the score.
- **ACP** (coding-CLI) + **A2A** (framework-to-framework) is the surface every profile exposes, so
  any orchestrator drives them uniformly. It's the composability linchpin.

## Consequences / discipline
- Extract the **profile SPI + the ACP/A2A endpoint** now; keep `code` as the reference. Add
  `web`/`data`/… **just-in-time** as a consumer pulls them — each a **thin adapter-wrapper around an
  existing tool** (reuse-don't-rebuild; the sandbox layer is *commodity* per the prior-art scan).
  **Do not build the profile fleet upfront** — that's the two-person-team failure mode.
- The substrate gets **leaner and pluggable**, not bigger. Breadth lives in profiles, not the core.

## Alternatives considered
- **Separate binaries** (`cragent`, `web-rag`, `registant`) — rejected: fragments installs,
  sandboxes, and interop; profiles under one `ragent` (with the SPI) are cleaner and map 1:1 to
  a consuming orchestrator's typed agents.
- **Bake tools in directly (no adapter seam)** — rejected: the plug-in/out mandate *requires* the
  adapter interface.

## Links
- [ADR-0022 — Review adapters](0022-python-adapters-verb-superset-capabilities.md) (the adapter
  pattern this generalizes) · [ADR-0031 — Egress allowlist](0031-network-egress-allowlist.md)
  (now per-profile) · [ADR-0007 — Shared CLIs on PATH](0007-shared-clis-on-path.md)
- A consuming orchestrator composes these profiles as its agent catalogue (documented in the
  consumer's own repo, not here). ragent stays consumer-agnostic.
