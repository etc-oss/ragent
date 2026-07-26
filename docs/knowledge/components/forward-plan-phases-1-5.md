---
type: component
id: COMP-forward-plan
title: Forward plan (Phases 1–5)
description: The phased development plan from the jail through open-source hardening, with concrete tasks, exit criteria, and risks per phase.
tags: [plan, roadmap, phases, planning]
timestamp: 2026-07-26
---

# Forward plan (Phases 1–5)

This plan refines and expands the roadmap sketched in the
[genesis session](../sessions/0001-genesis-architecture-conversation.md) and the
[bootstrap prompt](../sessions/0002-phase0-bootstrap-prompt.md). It is the
"when/how" companion to the [architecture overview](architecture-overview.md).

## Guiding principles

- **Vertical slice first.** Prove one end-to-end loop before adding breadth. The
  multi-agent common-tooling layer is the part most likely to eat weeks, so it is
  validated *last*, after the loop feels good with one agent.
- **Study before building.** Each phase names the prior art to read first.
- **The recursive dogfooding milestone.** Early on, Claude Code runs on the host
  (or in the VM) editing files normally. Once the jail exists (Phase 1), we
  dogfood it by running the agent **inside its own jail**. *That transition is
  the real "it works" moment* and is the exit gate for Phase 1.
- **Model split** per [ADR-0009](../decisions/0009-opus-design-sonnet-execution.md):
  design with Opus, execute volume with Sonnet, mechanical work with Haiku.
- **Checkpoint before anything irreversible** (public remote, push, publishing).

## Status legend

`TODO` not started · `WIP` in progress · `DONE` complete · `BLOCKED` waiting

---

## Phase 1 — The jail, one agent  `WIP`

**Goal:** one coding agent running confined via [jail.nix](../decisions/0002-jail-nix-confinement.md)
inside [Lima](../decisions/0004-lima-vm-layer.md), with a read-write bind mount
scoped to the project directory and nothing else.

**Study first:** `andersonjoseph/jailed-agents` (its `makeJailedAgent` builder
and the crush/opencode/pi jails), the `jail.nix` combinator set, and
`srid/sandnix` (as the weaker native-mac fallback to understand the trade-off).

**Landed (host side, macOS):**
- Studied jailed-agents (it exports `makeJailedClaudeCode`/`makeJailedOpencode`/…)
  and the real jail.nix combinators. Decisions: [ADR-0013](../decisions/0013-jailed-agents-opencode-first.md),
  [ADR-0014](../decisions/0014-runtime-env-secret-forwarding.md),
  [ADR-0015](../decisions/0015-cgroup-caps-systemd-run.md).
- `flake.nix` wires `jailed-agents` + a jail.nix `jailed-probe` (the confinement
  proof), `jailed-opencode`, and `jailed-claude-code`, Linux-guarded; `flake.lock`
  updated.
- `tools/confinement-test.sh` (negative-control gate), `tools/ragent-run.sh`
  (cgroup launcher), and the Lima guest config (now in your-config-repo) with user
  namespaces + cgroup delegation.
- **Verified on macOS (smoke test):** the darwin devshell and the `aarch64-linux`
  `jailed-probe` both evaluate/instantiate. The agent derivations use IFD
  (bun2nix) and must build in the guest — not eval on macOS.

**Verified in a Linux guest (2026-07-26) — the confinement gate PASSES:**
- Fresh Lima VM (`ragent`): Nix + flakes, unprivileged user namespaces on, cgroup
  delegation in place.
- `jailed-probe` builds from the pinned flake (same derivation hash cross-eval'd
  on macOS), and `tools/confinement-test.sh` reports **8/8 controls pass**: cwd is
  real and writable; the real `$HOME` secret, a planted SSH key, an out-of-project
  file, and `/etc/shadow` are all unreadable; writes to `$HOME`/`/etc`/out-of-project
  land on an ephemeral tmpfs and never reach the real filesystem. The jail's
  `$HOME` is a fresh empty tmpfs.
- **cgroup caps enforce** (ADR-0015): controllers `cpu/memory/pids` are delegated
  to the user session, and a `MemoryMax=50M` `systemd-run --user --scope`
  OOM-killed an unbounded allocation instantly (not a timeout). `ragent-run.sh`'s
  mechanism bites.
- **DNS works** inside the jail: `/etc/resolv.conf` is present and the shared net
  namespace resolves and connects — a TCP connect to the LLM API host from inside
  the jail succeeded. (An earlier "DNS fail" reading was a false negative: only
  `bash`+`coreutils` are on the jail PATH, so `getent`/`grep` were "not found".)
- **A real agent builds and launches in its jail:** `jailed-opencode` builds
  (bun2nix; opencode 1.18.5, wrapping the prebuilt linux-arm64 binary,
  `bubblewrap` in the closure) and runs — `opencode --version` → `1.18.5`, rc 0,
  including under `tools/ragent-run.sh` (cgroup scope + jail together, so the caps
  *integration* is confirmed, not just the mechanism).
- **opencode's confinement — established by bind-list inspection** (not by
  re-running the 8 controls against its profile): its bwrap invocation makes only
  `$PWD` and `~/.config/opencode`, `~/.local/share/opencode`,
  `~/.local/state/opencode` real+writable; `~` and `/tmp` are fresh tmpfs and
  everything else is `--ro-bind` (nix store, minimal `/etc`), with
  user/ipc/pid/uts/cgroup unshared and net shared for egress. So opencode is
  confined by construction to the project dir + its own state dirs.
- **Operational + secret notes:** the bound XDG dirs must pre-exist or bwrap
  aborts ("Can't find source path") — `ragent-run.sh` now pre-creates them via
  `RAGENT_PRECREATE_DIRS`. And `~/.local/share/opencode` is bound **read-write**,
  where opencode persists auth — the exact credential-dir case
  [ADR-0014](../decisions/0014-runtime-env-secret-forwarding.md) flags: when
  wiring real auth, decide deliberately (env-forward the key vs. accept the bound
  auth dir).
- **Dogfood — Claude Code in its own jail (the recursive milestone):**
  `jailed-claude-code` builds (claude-code 2.1.220, unfree; `socat`/`bubblewrap`
  in the closure) and runs confined — `--version` → `2.1.220`, rc 0, both directly
  and via `ragent-run.sh`. Bind list inspected: only `$PWD`, `~/.claude` (dir),
  and `~/.claude.json` (file) are real+writable; `~`/`/tmp` tmpfs, all else
  `--ro-bind`. `~/.claude.json` holds Claude Code's credentials and is bound
  **read-write** — the ADR-0014 tension in its sharpest form. Launcher note:
  `~/.claude.json` is a **file** bind source, so `RAGENT_PRECREATE_DIRS`
  (mkdir-only) does not cover it — file bind sources need separate creation.

**Remaining in Phase 1:**
- A full agent-driven edit: run a jailed agent (opencode or Claude Code) on a real
  editing task with runtime-forwarded auth (ADR-0014) and review the diff — needs
  the owner's provider key. This is the last piece of the Phase 1 dogfood.

**Tasks**
1. Stand up the long-lived Lima VM; confirm unprivileged user namespaces work
   (bubblewrap prerequisite).
2. Replace the placeholder inputs in `flake.nix` with real, resolvable ones
   (jail.nix pinned; the chosen agent pinned). Generate `flake.lock`.
3. Define the jail with combinators: `mount-cwd`/scoped `readwrite` to the
   project dir; `network` only as required for the LLM API; **exclude** `$HOME`,
   SSH keys, secrets. Add cgroup CPU/RAM caps.
4. Bind the LLM API key into the jail explicitly; keep push/deploy creds out.
5. Prove negative controls: from inside the jail, reading `~/.ssh` or writing
   outside the project dir must **fail**.
6. Dogfood: run the agent inside its own jail to make a real edit.

**Deliverables:** a working `jail` derivation + devshell; a short "confinement
test" script (positive + negative controls); ADRs for any concrete choices
(which agent first; exact cgroup caps).

**Exit criteria:** the agent edits the project from inside the jail; attempts to
touch `$HOME`/SSH/secrets or escape the project dir fail; the run is reproducible
from `flake.lock`.

**Risks:** user-namespace/cgroup availability in the guest; the GPL-3.0 status of
jail.nix (kept clean by referencing, not vendoring — [ADR-0003](../decisions/0003-consume-upstreams-as-flake-inputs.md));
scoping the bind mount too broadly (the security story lives or dies here).

---

## Phase 2 — The Zellij workspace  `WIP`

**Goal:** the two-side [Zellij](../decisions/0005-zellij-two-pane-layout.md) TUI —
HUMAN (neovim + lazygit) and MACHINE (the jailed agent) — each with a main pane
and a log/observability pane, defined in a KDL layout.

**Study first:** Zellij KDL layout docs; truecolor/clipboard behavior when nested
inside an SSH'd Lima session.

**Landed + verified in the guest (2026-07-26):**
- `flake.nix` adds a Linux `workspace` devshell — zellij 0.44.3, neovim 0.12.4
  **with LSPs** (nixd/basedpyright/bashls via the nvim-0.11 `vim.lsp.enable` API;
  clean startup + verified attach to `.nix`/`.py` — Polish), lazygit 0.63.1, git,
  git-surgeon + rg/fd/jq, and the jailed agents on PATH (all confirmed in-guest).
- `workspace/ragent-workspace.kdl` — two tabs. `dump-layout` on a live session
  confirms the structure: **HUMAN** = editor (`nvim`) + `review (lazygit)` on the
  main tree; **MACHINE** = `agent` shell + `agent log` (`tail -F .ragent/agent.log`)
  in the agent clone. cwds resolve via env the launcher exports.
- `tools/ragent-workspace.sh` — sets up the agent **clone** (ADR-0016), writes a
  per-clone launch helper + log, and starts Zellij with `--new-session-with-layout`
  (caught + fixed a real bug: plain `--session … --layout` adds tabs to an
  *existing* session). The generated `.ragent/launch-agent.sh` is verified end to
  end: `--version` runs opencode 1.18.5 confined + capped and its output reaches
  `.ragent/agent.log`, so the MACHINE log pane will populate.
- **Review boundary verified headlessly** (ADR-0011/0016): the agent commits
  inside its clone, `main` stays untouched until the human `git fetch`es the
  `agent/<task>` branch and merges — nothing lands without that gate. `.ragent/`
  metadata is excluded from the agent's commits (verified).

**Remaining / honest caveats:**
- The launcher's **pieces** are verified (the `-s NAME -n LAYOUT` invocation via
  `dump-layout`; clone/env/metadata via the headless hook; `launch-agent.sh` via
  `--version`), but the launcher → **live-TUI composition** was not run end to end
  headlessly — that final hop is human-verified-later.
- **Interactive usability not verified headless** — truecolor, clipboard
  passthrough, and keybinding collisions (the
  [ADR-0005](../decisions/0005-zellij-two-pane-layout.md) time-sinks) need a human
  at a real terminal. A sanity-check runbook is in the README ("Try the workspace").
- A full loop with a real agent editing in the machine pane needs the owner's API
  key (the [ADR-0014](../decisions/0014-runtime-env-secret-forwarding.md) auth
  decision).

**Tasks**
1. Author the KDL layout: two tabs/sides, each `main` + `log` pane.
2. Wire the HUMAN side: in-guest neovim with LSPs, lazygit.
3. Wire the MACHINE side to launch the Phase 1 jailed agent; its log pane tails
   the agent's output.
4. Implement the [git-worktree review boundary](../decisions/0011-git-worktree-review-boundary.md):
   agent works on `agent/<task>`; human reviews diffs before merge.
5. Tame the nesting papercuts: truecolor, clipboard passthrough, keybinding
   collisions (avoid stacking tmux).

**Deliverables:** a committed KDL layout; a launch command/script; the
propose→review→accept loop working with one agent.

**Exit criteria:** from a single command you get the two-side workspace; the
human can review and accept/reject the agent's proposed diff; clipboard and
colors are usable.

**Risks:** terminal-nesting ergonomics; editing host files over a slow mount
(mitigated by running neovim in-guest, [ADR-0004](../decisions/0004-lima-vm-layer.md)).

---

## Phase 3 — The tooling layer  `WIP`

**Goal:** shared capabilities available to every agent via `PATH`
([ADR-0007](../decisions/0007-shared-clis-on-path.md)), and `ragent` itself
consumable as a pinned flake input by downstream projects.

**Study first:** the exact `git-surgeon` project to adopt (the name collides
across ≥4 repos — see `THIRD_PARTY.md`); each agent's file/prompt extension
points (for the "capabilities as files" path).

**Landed + verified in the guest (2026-07-26):**
- **git-surgeon pinned** (raine, v0.1.17 — [ADR-0017](../decisions/0017-pin-git-surgeon.md)):
  a `flake=false` source built with `buildRustPackage`/`cargoLock` (0 git deps).
  Builds; `git-surgeon 0.1.17` runs.
- **Shared-tools layer** `sharedTools` = git-surgeon, git, ripgrep, fd, jq, placed
  on **every agent's in-jail PATH** via `makeJailed*`'s `extraPkgs` (+ the human
  shell). Verified by inspecting `jailed-opencode`'s bwrap PATH (all five present,
  the *agent* by construction) and by **running them from inside the jail via
  bash** — ADR-0007's thesis, end to end. Confinement re-run against the widened
  profile: still **8/8**.
- **Capabilities-as-files** pattern recorded:
  [agent-capabilities convention](../conventions/agent-capabilities.md).
- **Project template** `templates/default` + a packaged, checkout-free launcher
  (`apps.workspace` → `nix run .#workspace`). Verified: `nix flake new -t .#default`
  scaffolds a downstream project that composes ragent's workspace devshell as a
  pinned input (local-override eval → `nix-shell`), and the packaged app sets up
  the clone/metadata headlessly.

**Done:** the consumable config repo — **your-config-repo** — was extracted after
Phase 5 ([ADR-0018](../decisions/0018-split-your-config-repo.md), realizing
[ADR-0012](../decisions/0012-defer-global-config-split.md)); it consumes ragent as
a pinned input, and the VM/deployment specifics moved there first.

**Tasks**
1. Pin the specific `git-surgeon` and put it (and other shared CLIs) on `PATH`
   via the flake; record which one and why in an ADR.
2. Establish the "capabilities as CLIs or files" pattern; add ADR-as-a-skill and
   commit conventions as plain files + prompt snippets, not per-agent plugins.
3. Provide a `nix flake init` template so a new project can scaffold a ragent
   workspace and consume ragent as an input.
4. Exercise agents calling the shared CLIs through bash (the common denominator).
5. Evaluate the global-vs-workspace boundary that emerged in Phases 1–3 and,
   once it is clear, extract the shared config into a consumable `ragent-config`
   repo ([ADR-0012](../decisions/0012-defer-global-config-split.md)) — preserving
   git history and attribution. (Deferred from Phase 0 by owner decision.)

**Deliverables:** shared CLIs on `PATH`; a project template; an ADR pinning the
git-surgeon identity.

**Exit criteria:** a fresh project can consume ragent as a flake input and its
agent can invoke a shared CLI via bash with no per-agent adapter.

**Risks:** CLIs not behaving well non-interactively; scope creep into a premature
universal-plugin abstraction (deliberately deferred).

---

## Phase 4 — Observability + the 2nd/3rd agent  `WIP`

**Goal:** usable observability, then breadth — add more agents once the loop is
solid with the first.

**Landed:**
- **Four agents, jailed identically.** opencode + Claude Code were verified
  confined in Phase 1; `pi` and `crush` are now wired the same way
  (`makeJailedPi`/`makeJailedCrush` with `extraPkgs = sharedTools`), so all four
  share the confinement profile and the tooling layer. The launcher's
  per-agent config-dir handling covers all four (`RAGENT_AGENT=…`).
- **Observability = the MACHINE log pane** tailing `.ragent/agent.log` (Phase 2),
  with `jq` on PATH for pretty-printing. Deliberately *not* a unified/normalized
  logger — the genesis conversation warned against building that before the loop
  is solid.

> Verification note (precise): opencode + Claude Code are verified running
> confined, with their writable binds inspected (Phase 1). For `pi` and `crush` I
> confirmed they **build, are bwrap-jailed, and carry all five shared tools**
> (git-surgeon/git/ripgrep/fd/jq) on their in-jail PATH — but did **not**
> bind-inspect their configPath writable binds (`~/.pi`, `~/.config/crush`) or run
> per-agent negative controls. Their confinement is therefore **inferred** from
> identical `makeJailed*` wiring + confirmed-jailed + the 8/8 base-profile probe,
> not independently bind-inspected. (crush's llm-agents Go-module build is heavy,
> ~12 min cold.)

**Study first:** each agent's log/session format (pi stores sessions as trees;
others differ) to judge whether a normalizer is worth it.

**Tasks**
1. Start observability as plain panes: `tail -f` + `jq`/`fx` pretty-printing. Do
   **not** build a WASM Zellij plugin unless plain panes genuinely fall short.
2. Add a second agent (pi or opencode) as a pinned input with its own jail
   profile, reusing the Phase 1 pattern.
3. Add the third agent. Confirm all three invoke shared CLIs uniformly via bash.
4. Only if warranted, write a small log normalizer for a unified view.

**Deliverables:** working log panes; second and third jailed agents; a short note
on whether a normalizer/plugin is justified (with evidence).

**Exit criteria:** all three agents run confined and share the tooling layer;
their logs are legible; no premature observability platform was built.

**Risks:** heterogeneous logs tempting an over-built "unified" layer before the
core loop warrants it — explicitly resisted.

---

## Phase 5 — Open-source hardening  `WIP`

**Goal:** make the project safe and pleasant to fork and adopt.

**Landed (pre-publish):**
- **CI prepared (not run).** `flake.nix` `checks` build the jail (`jailed-probe`)
  and `git-surgeon`; **`nix flake check` passed in the guest for `aarch64-linux`**
  (it omitted the other systems). `.github/workflows/ci.yml` is **written but has
  never executed** — there is no remote — and *would* run `nix flake check` + the
  confinement gate + a docs-HTML-sync check on Linux.
- **Governance docs** — `CONTRIBUTING.md`, `CHANGELOG.md`; `NOTICE`/`THIRD_PARTY`
  updated (git-surgeon adopted; agents noted). License audit: still
  reference-don't-vendor; no upstream code copied in.
- **Deployment guide** — [running ragent on a VM](running-on-a-vm.md) (drop Lima;
  run host-independently), which also removes the broad host-home mount.
- The **worked example** is `templates/default` + the README "Try the workspace"
  runbook (both verified: the template composes ragent as a pinned input).

**Still gated on the owner:** publishing (public remote / push / tagged release)
— explicitly not done without confirmation.

**Tasks**
1. `README` polish; a worked **example project** demonstrating the full loop.
2. CI: `nix flake check`; regenerate and verify `docs/html/` is in sync with
   `docs/knowledge/`. **Wire the in-guest scripts into `flake check`s** rather
   than leaving them hand-run — `confinement-test.sh`, `ragent-run.sh`'s cap
   check, the workspace layout/boundary tests, and `okf_render.py` were all
   verified by hand this far and are regression surface; make them checks (Linux
   checks for the jail/workspace, a host check for the renderer).
3. License/attribution audit: re-verify `THIRD_PARTY.md`; confirm no upstream
   code was vendored; confirm the mirror layer is absent from the public repo.
4. Finalize the local-mirror/resilience runbook ([ADR-0010](../decisions/0010-local-mirror-resilience.md));
   confirm an offline rebuild via `nix flake archive` + overrides.
5. **Checkpoint with the owner, then** (only on explicit confirmation) add the
   public remote, push, and tag a release.

**Deliverables:** green CI; an example project; an audited attribution set; a
tagged release — after human sign-off.

**Exit criteria:** a stranger can fork, `nix develop`, and reach a working
confined loop by following the README; the publish gate has explicit human
approval.

**Risks:** publishing prematurely (guardrail: never push/publish without explicit
confirmation); attribution drift (guardrail: the audit step).

---

## Exit-criteria summary

| Phase | The "done" signal |
|---|---|
| 1 | Agent edits from inside its jail; escapes fail; reproducible from lock. |
| 2 | One command → two-side workspace; human review gate works. |
| 3 | Downstream project consumes ragent as an input; agent calls shared CLI via bash. |
| 4 | Three agents confined + sharing tooling; logs legible; nothing over-built. |
| 5 | Stranger forks to a working loop from the README; publish gate approved. |

## Model usage by phase

- **Opus** — Phase 1 jail/security design; any cross-agent abstraction calls in
  Phases 3–4; licensing audit in Phase 5.
- **Sonnet** — the volume: flake, KDL, configs, templates, CI across all phases.
- **Haiku** — boilerplate, log-parsing helpers, mechanical edits.
