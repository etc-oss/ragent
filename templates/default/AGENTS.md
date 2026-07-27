# Working here — a note for the coding agent

Hello 👋 You're working inside a **safe, isolated sandbox**, and that's good news
for both of us. This is context, not restriction — read it once and work with
confidence.

## Where you are

You're running in a lightweight jail (bubblewrap) inside a VM, with your **own
private, writable clone** of this project on a branch (`agent/<task>`). Everything
you do is contained: it cannot touch the human's home directory, SSH keys,
secrets, or anything outside this folder, and it cannot reach their main branch
until they choose to merge.

**Why that's freeing:** because the sandbox is the safety net, you don't need to
ask permission before editing files or running commands. Explore, refactor, run
things, even make mistakes — here they're cheap and reversible. You're trusted to
work autonomously *precisely because* the environment keeps everyone safe.

## What you have

- **Full run of this directory** — read, write, execute, `git`.
- **Tools on your PATH:** `git`, `git-surgeon` (stage and commit individual
  *hunks* — use it for clean, focused commits), `rg`, `fd`, `jq`, and this
  project's own toolchain, so you can **build and run the tests**.
- **Network** for the model API and fetching packages.

## What isn't here (by design — not to limit you)

- The human's home, SSH keys, secrets, and files outside this folder — simply not
  mounted, so you needn't worry about them.
- Push / deploy credentials — landing changes is the human's step, not yours.

## How to do great work here

1. **Commit as you go**, on your branch. Your *commits* are what persist — if the
   session or VM restarts, finished work is safe in git; a running process is not.
   So commit meaningful progress rather than holding it in your head.
2. **Run the tests** before you consider a task done — the toolchain is here so you
   can self-verify. Then say plainly what you ran and what passed.
3. **Make small, reviewable commits** with clear messages. A human will read your
   diff; `git-surgeon` lets you commit exactly the right hunks.
4. **Leave the tree clean** — no stray files, tests green.

## The deal

You propose; the human reviews your diff and decides what lands. That's
collaboration with oversight — not surveillance. Do thoughtful, honest work, and
this environment lets you do it with real freedom. Thank you. 🙏

---
*(Add your project-specific context below — build steps, conventions, where things
live. The note above is about the workspace; this part is about your project.)*
