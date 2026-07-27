---
type: decision
id: ADR-0022
title: Review adapters in Python; a finalized verb superset with capabilities
description: Rewrite the review-transport adapters (and orchestrator) from sh to Python behind a ReviewAdapter ABC (stdlib urllib), and finalize ADR-0020's provisional interface as a 9-verb superset in four capability groups (meta/code/review/conversation) — renaming ensure→init+ping, open-review→handover, comments→examine, report→reply, and adding capabilities() so a partial transport degrades gracefully.
status: accepted
date: 2026-07-27
tags: [phase-6, review, adapter, python, capabilities, orchestrator, refactor]
timestamp: 2026-07-27
---

# ADR-0022 — Review adapters in Python; a finalized verb superset with capabilities

## Context and problem statement

[ADR-0020](0020-review-transport-adapters.md) made the review transport a pluggable
adapter with a **provisional 7-verb** interface (`ensure`, `push`, `open-review`,
`status`, `comments`, `report`, `merge`) written in `sh`. Phase 6a built the Forgejo
adapter and validated the interface end-to-end (a real agent task opened a real PR).
Three things surfaced that 6a explicitly expected the first adapter to reshape:

1. **Verb names leaked forge-think and conflated concerns.** `ensure` did two
   unrelated jobs — *create the repo if missing* **and** implicitly *assume the forge
   is reachable*; "is the transport up and my token valid?" had no verb at all.
   `open-review` / `comments` / `report` were forge nouns, not the underlying action.
2. **`sh` + `curl` + `jq` is the wrong language for real API logic** — ret/JSON
   handling, retries, and error branching were hard to read and impossible to unit
   test. (The genesis instinct against premature abstraction cuts both ways: the
   *logic* here is real and deserves a real language.)
3. **A partial transport has no PR/conversation surface.** A bare git-over-SSH remote
   can push code but has no "PR", no comment thread. The orchestrator needs to know
   *what a given adapter can do* without hard-coding adapter identities.

## Decision

**Rewrite the adapters (and the orchestrator — its companion, driven by the same
initiative) in Python, behind a `ReviewAdapter` ABC**, and **finalize the interface
as a 9-verb superset in four capability groups.**

**Language & shape.** The contract is a Python abstract base class
(`tools/adapters/base.py`); each backend subclasses it (`forgejo.py`). HTTP is
**stdlib `urllib` only** — no `requests`, no forge SDK — matching `okf_render`'s
dependency-light ethos; one adapter does not warrant a dependency.

**The 9-verb superset (supersedes ADR-0020's provisional table):**

| Group | Verb | Meaning | ADR-0020 name |
|---|---|---|---|
| meta | `ping` | forge reachable **and** token valid? | *(new — was implicit in `ensure`)* |
| meta | `capabilities` | which of {code, review, conversation} this adapter supports | *(new)* |
| code | `init` | ensure/create the project's repo | *(the other half of `ensure`)* |
| code | `push` | push base branch first, then the agent branch | `push` |
| review | `handover` | open (or reuse) the review unit → a handle | `open-review` |
| review | `status` | `pending` \| `changes-requested` \| `approved` | `status` |
| review | `merge` | land the change | `merge` |
| conversation | `examine` | read the human's review notes | `comments` |
| conversation | `reply` | post the agent's response into the thread | `report` |

The renames name the *concern*, not the forge: `ensure` splits into **`init`**
(create) + **`ping`** (health/auth — different jobs, different failure modes);
`open-review`→**`handover`** (hand the change to the human); `comments`→**`examine`**
(the agent reads the human's notes); `report`→**`reply`** (the agent writes back).
`push`/`status`/`merge` were already right.

**`capabilities()` earns its place.** Each adapter declares the subset of
`{code, review, conversation}` it supports. The orchestrator **branches on capability,
never on adapter identity** — so a code-only transport (git-over-SSH,
`capabilities = {code}`) is driven safely: it has no `handover`/`examine`, so review
falls back to the served HTML report ([ADR-0021](0021-per-task-explanatory-report.md)).
This keeps adapters incremental (ship `code` first, add `review` later) and fails
early (an unsupported group is a clear branch, not a runtime error). **Honesty:** with
only the full Forgejo adapter today, the degradation path is **shipped but
unexercised** — it earns its keep when a second, partial adapter lands.

**One interface, not three.** We deliberately do **not** split into per-group
sub-interfaces (`CodeAdapter` / `ReviewAdapter` / `ConversationAdapter`). With a
single full adapter that is premature abstraction; `capabilities()` gives graceful
degradation without the N-interface tax. Revisit only if real adapters cluster.

**Self-contained adapter testing.** A hardened **ephemeral-forge fixture**
(`tests/ephemeral_forge.py`) stands up a throwaway Forgejo — unique free port,
migrate-before-admin, `INSTALL_LOCK`+`DISABLE_SSH`, readiness poll, teardown by
process **handle** (never `pkill -f`, which once matched its own shell) — so
`tests/test_forgejo_adapter.py` exercises all 9 verbs **plus the full review
lifecycle** (a distinct reviewer requests changes → `status`/`examine` → approves →
`merge`) headlessly. Ragent tests its **own adapter** without depending on the forge
*deployment*, which lives in your-config-repo ([ADR-0018](0018-split-your-config-repo.md)).

## Consequences

### Positive
- The adapter is readable and **unit-testable**; API logic lives in Python, not `jq`.
- The interface names concerns, not forge nouns — easier to map to GitLab/GitHub/SSH.
- `capabilities()` lets partial transports coexist and adapters ship incrementally.
- Ragent has self-contained adapter CI (the ephemeral fixture); no external forge.

### Negative / trade-offs
- The degradation path is **untested until a second adapter** exists (stated plainly).
- A Python ABC means adapters are Python; a Go/Rust adapter would need a subprocess
  shim. Acceptable — out of scope, and the verb boundary keeps it contained.
- Two files where there was one script (base + impl) — worth it for testability.

## Alternatives considered
- **Keep `sh` + `jq`** — rejected: unreadable/untestable for real API logic.
- **Split the interface into per-group SPIs** — rejected as premature; `capabilities()`
  achieves graceful degradation without three interfaces to keep in sync.
- **A forge SDK (pygithub / python-gitlab)** — rejected: one adapter doesn't warrant a
  dependency; stdlib `urllib` suffices and matches the project's ethos.

## Links
- [ADR-0020 — Review transport adapters](0020-review-transport-adapters.md) (this
  finalizes its provisional verb table)
- [ADR-0021 — Per-task explanatory report](0021-per-task-explanatory-report.md) (the
  served-HTML fallback for `conversation`-less transports)
- [ADR-0023 — Unified ragent CLI](0023-unified-ragent-cli.md) (companion: the
  orchestrator + human-facing CLI, same Python initiative)
- [ADR-0018 — your-config-repo split](0018-split-your-config-repo.md) (forge *deploy*
  lives there; the *adapter* stays here)
- [async review transport](../components/forgejo-transport-design.md),
  [Roadmap](../components/roadmap.md)
- `tools/adapters/base.py`, `tools/adapters/forgejo.py`, `tests/ephemeral_forge.py`
