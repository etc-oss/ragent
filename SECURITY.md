# Security Policy

ragent's whole purpose is to run AI coding agents you don't fully trust **without**
giving them your machine. The sandbox is a safe haven in both directions — the agent
can work boldly because it cannot reach the host, and you stay safe for the same
reason. This document states what that defends, how, and — just as importantly —
where the edges are. We don't overclaim: the discipline is *verify by behavior, then
be honest*.

## The model: two enforced halves

**1. Confinement (the sandbox).** The agent process runs under
[`jail.nix`](https://git.sr.ht/~alexdavid/jail.nix)/bubblewrap with:

- `--clearenv` and a bind list that is **only the project directory** (read-write).
  No `$HOME`, no `~/.ssh`, no OS keychain, no other path.
- The provider key/token forwarded as a **single env var at runtime** — it never
  enters the Nix store, the repository, or a bound-in file
  ([ADR-0014](docs/knowledge/decisions/0014-runtime-env-secret-forwarding.md)).
- **cgroup caps** (memory / CPU / PIDs, via a transient systemd scope) to bound a
  runaway or fork-bomb ([ADR-0015](docs/knowledge/decisions/0015-cgroup-caps-systemd-run.md)).

**2. The human gate (oversight).**

- The agent works in a **disposable clone** and can only *commit*; it never pushes
  and never holds the forge token — all privileged forge I/O is done by a host-side
  orchestrator **outside** the sandbox
  ([ADR-0011](docs/knowledge/decisions/0011-git-worktree-review-boundary.md),
  [ADR-0016](docs/knowledge/decisions/0016-agent-clone-not-worktree.md)). Nothing
  reaches your tree without your merge/approve.
- Every autonomous loop is **bounded** — the async review loop caps agent revisions
  (the load-bearing runaway guard), wall-clock, and cost, and escalates to
  *needs-human* rather than running away
  ([ADR-0024](docs/knowledge/decisions/0024-human-paced-bounded-review-loop.md)).

**Verified by negative control.** We prove the wall by proving what *doesn't* get
through: an 8/8 confinement probe asserts the agent cannot read outside its bind, and
the subscription-auth change was validated by *unsetting* the API key and confirming
the sandbox fails — i.e. the key demonstrably cannot leak in.

## Secret handling

- Provider credentials (`ANTHROPIC_API_KEY` / `CLAUDE_CODE_OAUTH_TOKEN`) live **only**
  in the guest `~/.config/ragent/env` (mode `0600`) — never in the repo, the Nix
  store, a bound file, or chat.
- The forge token lives in the guest `~/.config/ragent/forge.env` and is used
  **host-side only**; the sandboxed agent never sees it.
- Before any publish, the git **history** (not just the working tree) is scanned for
  leaked secret values, and the private mirror layer (`/mirror/`) is confirmed never
  committed. A leaked-then-deleted secret is public the moment the repo is pushed.

## Known boundaries (in scope vs. not)

**In scope** — what confinement is designed to contain:
- A misbehaving, buggy, or prompt-injected **agent** kept to its clone's blast radius.
- Runaway autonomy (loops, fork-bombs) bounded by caps + loop bounds.

**Out of scope / not yet** — stated plainly, not hidden:
- **Network egress is unrestricted.** The sandbox grants the agent **full outbound
  network** (the `network` combinator in `flake.nix` — present for the LLM API, but *not*
  filtered to it). So a prompt-injected or malicious agent can reach **any** host, **fetch
  and run arbitrary packages** (`npx` / `pip` / …), and **exfiltrate the project clone's own
  contents** — and the human merge-gate does **not** stop exfiltration (it happens over the
  wire, mid-run, without anything landing). The filesystem jail bounds *what the agent can
  read* (its clone only), not *where it can send it*. **The fix — a network egress
  allowlist** (restrict the jail to the LLM endpoint via a filtering proxy or a
  netns+firewall, as Cyrus's `sandbox.networkPolicy` and Anthropic's `sandbox-runtime` do) —
  is a **priority** on the roadmap. Until it lands, treat the agent as *trusted-not-to-
  exfiltrate*, not adversarial.
- **Kernel-level sandbox escapes.** Bubblewrap is namespace isolation, *not* a VM; a
  kernel exploit could in principle escape. VM-per-agent (microvm.nix) is the
  roadmap's stronger boundary ([ADR-0002](docs/knowledge/decisions/0002-jail-nix-confinement.md)).
- **A malicious host / multi-tenant use.** ragent is single-user today.
- **SaaS review transports.** A github.com/gitlab.com adapter would send the branch +
  review off-box — a conscious, non-default relaxation
  ([ADR-0020](docs/knowledge/decisions/0020-review-transport-adapters.md)).
- **Remote review** is verified only against a local forge so far; the subscription
  usage-limit **detector** is best-effort (a real limit can't be triggered to verify —
  [ADR-0026](docs/knowledge/decisions/0026-subscription-usage-limit-wait.md)).

## Reporting a vulnerability

**Please do not open a public issue for a security problem.** Report it privately to
a maintainer — Gourang Abani (`aatman@randomness.life`) or Kunal Sharma
(`k7109021@gmail.com`) — or, once the project is published, via a private security
advisory on the hosting platform. Include repro steps and the affected commit. We practice responsible disclosure and will credit reporters who
want it.

> Status: **pre-release, local-only.** No public deployment exists yet; this policy
> is in place for when it does.
