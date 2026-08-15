# Guide: troubleshooting

The gotchas this project actually hit, with fixes — grouped by symptom.

## The TUI is frozen or garbled
Almost always a bad `TERM` (e.g. `dumb`, which `limactl shell` can pass through). The
launcher forces `xterm-256color`, but use a truecolor terminal (iTerm2 / kitty /
WezTerm) and don't nest inside tmux. A session stuck on an exit prompt: recreate it —
`RAGENT_FRESH=1 ragent task window …`, or `nix run . -- task kill mytask`.

## Claude Code says "Not logged in"
The credential has to be in the *right mode*:
- **API key** — the `jailed-claude-code` agent bakes `CLAUDE_CODE_SIMPLE=1` (strict
  API-key auth) and forwards `ANTHROPIC_API_KEY`. Export the key before running.
- **Subscription** — use `RAGENT_AGENT=jailed-claude-code-subscription` and export
  `CLAUDE_CODE_OAUTH_TOKEN` (from `claude setup-token`). That variant forwards *only*
  the token and omits `CLAUDE_CODE_SIMPLE` — because the flag is `--bare`, which
  ignores the OAuth token. Don't set both: the API key (higher precedence) would
  shadow the subscription. See
  [ADR-0025](../knowledge/decisions/0025-jailed-claude-subscription-auth.md).

## The agent can't run my project's tests/tools
Tools exist inside the sandbox only if you put them there. Add them to `projectTools`
(`mkWorkspace { projectTools = [ pkgs.python3 … ]; }`); they join the agent's
in-sandbox PATH — [ADR-0019](../knowledge/decisions/0019-per-project-forking-and-dependencies.md).

## bubblewrap: "Can't find source path"
A bind-source dir doesn't exist yet. The launcher pre-creates the agent's state dirs
(`RAGENT_PRECREATE_DIRS`); if you invoke the sandbox directly, create those dirs first.

## Confinement / cgroup caps don't seem to enforce
`--user` systemd scopes only enforce CPU/memory if the controllers are delegated to
your user session (a `Delegate=cpu memory pids` drop-in), and bubblewrap needs
unprivileged user namespaces enabled. Verify with `systemd-cgls`; the confinement probe
(`tools/confinement-test.sh`, 8/8) is the ground truth.

## Forge: "credentials incorrect", or a leveldb lock error
Usually a **stale Forgejo** holding the port with an old DB/token. Stop it cleanly with
`pkill -x forgejo` (exact name — `pkill -f forgejo` can match, and kill, its own shell)
and restart. For ragent's own tests, prefer the ephemeral fixture
(`tests/ephemeral_forge.py`): unique port + fresh dir per run.

## The subscription hit a usage limit
On the autonomous path ragent **waits it out and retries** — it does *not* fall back to
the API. A short (5-hour) limit is waited automatically; a long (weekly) one surfaces
`needs-human` past `RAGENT_LIMIT_MAX_WAIT_HOURS` (default 6h — raise it to wait longer).
See [ADR-0026](../knowledge/decisions/0026-subscription-usage-limit-wait.md).

## `nix run` / `nix build` doesn't see my new file
Nix flakes only see **git-tracked** files. `git add` the new file (staging is enough) —
no commit required.

## CI's confinement step fails on GitHub
GitHub runners sometimes restrict unprivileged user namespaces (bubblewrap). If the
`confinement` gate fails there it's a runner limitation, not a code bug — mark that step
`continue-on-error` (the sandbox is proven in the guest). The other CI jobs
(flake-build, the Python suites, docs-sync) don't need the sandbox.

## `git worktree` fails inside the sandbox
Expected — a worktree's `.git` points outside the bind. ragent uses a self-contained
**clone** instead — [ADR-0016](../knowledge/decisions/0016-agent-clone-not-worktree.md).

---
Still stuck? Open a discussion/issue on the repo, or check the
[decision records](../knowledge/decisions/index.md) for the *why* behind a behavior.
