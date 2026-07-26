---
type: session
id: SESSION-0002
title: 'Phase 0 bootstrap prompt (verbatim)'
description: The exact prompt handed to Claude Code (Opus) to execute the Phase 0 bootstrap of ragent.
tags: [session, bootstrap, phase-0, verbatim]
timestamp: 2026-07-26
sources:
  - genesis-transcript.json
---

# Phase 0 bootstrap prompt (verbatim)

This is the prompt that was pasted into Claude Code (Opus) to carry out the
Phase 0 bootstrap — the work that produced this repository.

## Provenance

- It is **byte-identical** to the bootstrap template generated at the end of the
  genesis conversation (the final assistant turn, *Message 5*, in
  [SESSION-0001](0001-genesis-architecture-conversation.md)), with exactly **one**
  deliberate edit by the operator: the canonical transcript reference was changed
  from `genesis-transcript.md` to `genesis-transcript.json`, because the
  conversation was supplied to Claude Code as the JSON export rather than a
  hand-saved Markdown file.
- It is reproduced below inside a fenced block so its exact structure (headings,
  the directory tree, numbered deliverables) is preserved without being
  reinterpreted as Markdown.
- Per the [verbatim-sessions convention](../conventions/verbatim-sessions.md),
  this record is not edited to reflect how the work actually went; that story
  lives in the [ADRs](../decisions/index.md) and the
  [forward plan](../components/forward-plan-phases-1-5.md).

## The prompt

```text
You are taking over as the primary engineer for a new open-source project, working in Claude Code (Opus). This is the Phase 0 bootstrap. Read everything here, scaffold the repository, capture the originating conversation, produce a forward plan, then continue development from there.

## Canonical context: the originating conversation
The full, verbatim transcript of the design conversation that produced this project is in `genesis-transcript.json` at the repo root. It contains the architecture brief, an evaluation, a development-and-open-sourcing roadmap, and the reasoning behind every decision. Treat it as the canonical context and the project's genesis record. When you store it, do NOT paraphrase, summarize over, or "clean up" the text — preserve it exactly.

## What we're building (summary — the transcript has the full rationale)
An open-source, forkable-per-project developer workspace that makes AI-assisted coding efficient while preserving human oversight:
- A Zellij workspace with two sides: a HUMAN pane (neovim + LSPs + lazygit) and a MACHINE pane (coding agents: Claude Code, pi, opencode), each with its own log/observability pane.
- The machine side runs confined via jail.nix (Alex David's Nix-native bubblewrap wrapper, sourcehut:~alexdavid/jail.nix) inside a Lima Linux VM. The jail gets a read-write bind mount to the project directory ONLY; home dir, SSH keys, and secrets are excluded; cgroup caps limit blast radius.
- Shared tools (e.g. git-surgeon) go on PATH via the flake so every agent can call them through bash; a global config repo (ragent) is consumed as a pinned flake input, not forked.
- Records are captured in OKF (Google's Open Knowledge Format): a directory of Markdown files with YAML frontmatter, cross-linked into a graph — plus a rendered HTML view (see below).

Study before writing code: andersonjoseph/jailed-agents (already jails opencode/pi/crush via jail.nix), srid/sandnix, and the OKF spec + its reference implementations.

## Suggested repository structure (adjust as sensible; justify deviations in an ADR)
project/
├─ README.md            # what it is + roadmap
├─ LICENSE              # decide via ADR (default Apache-2.0)
├─ NOTICE               # upstream credits + licenses
├─ AGENTS.md            # cross-harness context entrypoint
├─ CLAUDE.md            # points to AGENTS.md, no duplication
├─ flake.nix / flake.lock
├─ docs/
│  ├─ knowledge/        # OKF bundle (markdown + frontmatter, linked)
│  │  ├─ sessions/      # verbatim chats: genesis transcript, this prompt
│  │  ├─ decisions/     # ADRs (seed decisions from the transcript)
│  │  ├─ components/    # architecture concepts + the forward plan
│  │  └─ conventions/   # standards
│  └─ html/             # generated, self-contained HTML (never hand-edit)
└─ tools/               # md→html generator, graph visualizer, mirror scripts

## Phase 0 deliverables
1. Repository scaffold along the lines above.
2. Governance & attribution: pick a permissive license (default Apache-2.0 for its explicit patent grant and NOTICE mechanism; record the choice as an ADR, MIT acceptable if justified). Add a NOTICE/THIRD_PARTY crediting every upstream with license + URL (jail.nix by Alex David, bubblewrap, Lima, Zellij, OKF, and anything you add). The public repo must REFERENCE upstreams as pinned flake inputs, never vendor their code.
3. AGENTS.md as the entrypoint any coding agent reads, pointing at the knowledge bundle and conventions. CLAUDE.md references it.
4. Knowledge system (OKF + ADR): docs/knowledge/ as an OKF bundle. Typed concepts via frontmatter — decision (ADRs, MADR-style body), session (verbatim chats), component (architecture), convention (standards) — cross-linked with markdown links.
5. Capture the originating conversation two ways:
   a. Store the verbatim transcript as the canonical genesis `session` concept, unaltered.
   b. Distill the conversation into seed `decision` concepts (ADRs) for choices already made — at minimum: jail.nix for confinement; consume upstreams as flake inputs; Lima as the VM layer; Zellij two-pane human/machine layout; one long-lived VM with per-project devshells; shared CLIs on PATH over per-agent plugins; OKF+ADR for knowledge capture; Opus-for-design / Sonnet-for-execution model split; local-mirror resilience strategy. Link each ADR back to the genesis session.
   c. Also preserve THIS bootstrap prompt as a `session` concept.
6. HTML alongside Markdown: Markdown stays the source of truth. Add a small, dependency-light generator in tools/ that renders every record to a self-contained, OFFLINE HTML view (no external CDN) and produces a single-file HTML visualizer of the whole knowledge graph (in the spirit of OKF's reference visualizer). Output to docs/html/. HTML must be regenerable from Markdown at any time; never hand-edit it.
7. Starter flake: flake.nix with jail.nix and other inputs pinned, plus a documented local-resilience path (nix flake archive + a private mirror/override strategy) so the project builds offline if upstreams vanish. Keep the mirror layer OUT of the public repo.
8. Forward plan: using plan mode and thinking deeply, produce a development plan for Phases 1–5 (jail → Zellij workspace → tooling layer → observability + 2nd/3rd agent → open-source hardening), refining and expanding what the transcript sketches. Store it as a `component`/planning concept and surface it in the README roadmap.

## Principles (from the conversation)
- Vertical slice first: scaffolding + plan now; implement incrementally afterward, not all at once.
- Records are plain Markdown + YAML frontmatter (OKF v0.1) — portable and low-risk; don't over-engineer tooling around a v0.1 spec.
- Verbatim means verbatim: never paraphrase session records.
- Reference-don't-redistribute upstream code; credit generously.

## Handoff
Complete Phase 0, commit with clear messages, and show me: the tree, the NOTICE, AGENTS.md, the seed ADRs, and the forward plan. Then continue into Phase 1. CHECKPOINT WITH ME BEFORE ANYTHING IRREVERSIBLE — in particular, do not add a public remote, push, or make the repository public without explicit confirmation. Keep everything in a local git repo until I say otherwise.
```

