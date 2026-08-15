# ragent guides

Task-focused how-tos. Pick your use-case:

- **[Run a sandbox agent](sandbox-agent.md)** — a confined agent on your project; you
  review the diff and merge. No forge, no async loop. The simplest way in.
- **[Async review with Forgejo](async-review-forgejo.md)** — agent → PR → review when
  you're ready → it revises → you merge. The async review loop.
- **[Run ragent on a remote VM](remote-vm.md)** — the workspace on a remote Linux box,
  reached privately over Tailscale; review from anywhere.
- **[Fork ragent into your project](../../README.md#forking-ragent-into-another-project)**
  — consume ragent as a pinned flake input and add your own tools.
- **[Troubleshooting](troubleshooting.md)** — the gotchas this build actually hit, with fixes.

> These guides are plain Markdown on purpose. ragent's *own* knowledge bundle uses
> OKF + ADRs, but **your** project (and these guides) can use any format you like —
> ragent doesn't impose one ([ADR-0027](../knowledge/decisions/0027-knowledge-format-is-the-consumers-choice.md)).
