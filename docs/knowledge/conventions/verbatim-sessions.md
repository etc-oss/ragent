---
type: convention
id: CONV-verbatim-sessions
title: Verbatim session capture
description: Session records preserve source chats and prompts byte-faithfully; distillation happens in linked decisions, never by editing the session.
tags: [session, verbatim, provenance, convention]
timestamp: 2026-07-26
---

# Verbatim session capture

`type: session` concepts are the project's primary sources — the actual chats
and prompts that produced it. The founding principle, stated in the genesis
conversation and the bootstrap prompt, is blunt: **verbatim means verbatim.**

## Rules

1. **Never paraphrase, summarize over, or "clean up" a session record.** If the
   source said it, the record says it, exactly.
2. **Keep a byte-exact source artifact** alongside any rendered view. For the
   genesis conversation that artifact is
   [`genesis-transcript.json`](../sessions/genesis-transcript.json) — the raw
   Claude.ai export, unaltered. The rendered
   [`0001` session](../sessions/0001-genesis-architecture-conversation.md) is a
   faithful presentation of it, and says so at the top.
3. **Distill in decisions, not in sessions.** The clean, opinionated version of
   what a conversation concluded lives in linked
   [`decision`](../decisions/index.md) concepts. The session stays messy and
   whole; the ADRs are tidy and cross-linked. You keep both the trail and the
   record.
4. **Note gaps honestly.** If the source is incomplete (e.g. an export that
   omits the model's internal reasoning), say so in the record rather than
   silently presenting a partial transcript as complete.
5. **Append-only in spirit.** Correct a genuine transcription error, but do not
   rewrite history. New understanding goes in a new concept that links back.

## Why

The link graph from **session → decision** is the evolutionary story of the
project, and it is only trustworthy if the session end is a true primary source.
The moment a record is "improved," it stops being evidence and becomes opinion —
and we already have a place for opinion (ADRs). This also serves the
context-loading goal: any future model or harness can reconstruct intent from
untouched sources plus distilled decisions.
