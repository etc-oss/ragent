# ragent — backlog

The flat, prioritized task list. Strategic phasing + the "why" live in
[`docs/knowledge/components/roadmap.md`](docs/knowledge/components/roadmap.md); this is the
working checklist. `[x]` = done.

## Priority — security
- [ ] **Network egress allowlist.** The jail grants **full outbound network** (the
  `network` combinator in `flake.nix`, for the LLM API — unfiltered), so a prompt-injected/
  malicious agent can reach any host, fetch + run arbitrary packages (`npx`/`pip`), and
  **exfiltrate the clone's data** — the human merge-gate does *not* stop exfiltration.
  Restrict egress to the LLM endpoint(s) via a filtering proxy or a netns+firewall (cf.
  Cyrus `sandbox.networkPolicy`, Anthropic `sandbox-runtime`). Load-bearing for any
  high-assurance positioning. Documented honestly in `SECURITY.md`.

## Near-term (si-nergy pulls these)
- [ ] `orchestrate --json` — machine-readable result (pr_url/branch/status/outcome/iterations).
- [ ] **SQLite** request/status store — operational source-of-record; doubles as 6c
  resumable-loop state + si-nergy's dispatcher record (+ optional git-notes provenance footnote).
- [ ] `ragent task clean` — GC reused/ephemeral clones (never auto-deleted).
- [ ] 6c: durable/resumable waits + concurrency.

## DX
- [ ] **`ragent shell` auth hint** — when the subscription agent is selected and
  `~/.claude/.credentials.json` is absent, print the one-time `/login` tip (creds persist via
  the bound `~/.claude`) so the interactive login menu isn't a surprise.

## Framework hardening
- [ ] A 2nd review adapter (GitLab / GitHub / SSH) — exercises `capabilities` (untested).
- [ ] Remote forge end-to-end (NixOS `services.forgejo` on Tailscale).
- [ ] 6c polish: notifications · a needs-human forge label · (optional) mobile ergonomics.

## Direction (uncommitted)
- [ ] `agentConfig` — per-agent native MCP/skills (fixes the harness-efficiency gap).
- [ ] Local models — Ollama / LiteLLM (opt-in on-box inference).
- [ ] OTel observability — opt-in, self-hosted.
- [ ] microvm.nix — VM-per-agent isolation beyond bubblewrap.
- [ ] Multi-user / team.

## Ops
- [ ] Turn CI on (the prepared workflow).
- [ ] Exercise the offline mirror path end-to-end.
- [ ] Confirm the interactive-TTY fix in a real terminal.
- [x] Publish to etc-oss — live + in sync.
