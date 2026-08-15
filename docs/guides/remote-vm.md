# Guide: run ragent on a remote VM

Run the workspace on a **remote Linux box** and reach it **privately** — so long agent
runs live on the VM and you review from wherever you are. This is the "review when you're
ready" setup; the sandbox is the same, just not on your laptop.

The deploy specifics (a declarative NixOS box, cloud-init) live in a **consuming config
repo** ([ADR-0018](../knowledge/decisions/0018-split-your-config-repo.md)); this guide is
the generic path. Conceptual background: [running on a VM](../knowledge/components/running-on-a-vm.md).

## Prerequisites

- A **Linux VM** you can SSH into (any cloud instance, or a NixOS box from your config
  repo). x86-64 or aarch64; 2+ cores, 4+ GB RAM.
- A **[Tailscale](https://tailscale.com)** account (free tier is fine) — for private
  access with no public ports.
- Your provider credential, **on the VM only, never in a repo** (ADR-0014).

## 1. Get Nix on the VM (flakes enabled)

Install Nix and turn on flakes:

```sh
sh <(curl -L https://nixos.org/nix/install) --daemon
mkdir -p ~/.config/nix && echo 'experimental-features = nix-command flakes' >> ~/.config/nix/nix.conf
```

(On a NixOS box from your config repo, Nix + flakes are already there — skip this.)

## 2. Join your private network

Put the VM on your tailnet so only your devices can reach it:

```sh
tailscale up                       # authenticate once; note the VM's 100.x.y.z address
```

## 3. Get the workspace

Clone your **ragent-consuming config** (recommended — it carries your agent, tools, and
theme) or ragent itself:

```sh
git clone <your-config-repo> && cd <your-config-repo>
```

## 4. Enter the workspace and set a credential

```sh
nix develop .#workspace            # tools + the confined agents + the `ragent` CLI
```
```sh
export CLAUDE_CODE_OAUTH_TOKEN=... # a Pro/Max subscription (or ANTHROPIC_API_KEY)
export RAGENT_AGENT=jailed-claude-code-subscription
```

## 5. Run work on the VM

Pick a use-case — the directory defaults to the current one:

*Quick confined interactive session (a live agent, right on the VM):*
```sh
ragent shell
```

*A task that opens a PR you review asynchronously:*
```sh
nix run .#dev-forge &                       # a local forge on the VM (localhost)
source ~/.config/ragent/forge.env
ragent task orchestrate "add a subtract() to calc.py with a test"
```

## 6. Review from anywhere — privately

Everything binds to `127.0.0.1` on the VM; reach it over the tailnet, **never a public
port**.

*The served HTML report (agent's explanation + the real diff), from your laptop/phone:*
```sh
RAGENT_SERVE_HOST=<vm-tailscale-ip> ragent task review    # on the VM
# then open http://<vm-tailscale-ip>:8099/ on any device on your tailnet
```

*The forge UI (diff, comments, approve), over the tailnet or an SSH tunnel:*
```sh
ssh -L 3000:127.0.0.1:3000 user@<vm-tailscale-ip>          # from your laptop
# then open http://127.0.0.1:3000
```

For a persistent remote forge, run a NixOS `services.forgejo` on the tailnet (deploy
config in your config repo) — the client side is identical, just a `RAGENT_FORGE_URL`
swap. See [async review with Forgejo](async-review-forgejo.md).

## What stays true on a remote VM

- **The confinement is unchanged** — the agent still gets the project clone only; the VM's
  `$HOME`, keys, and secrets sit outside the bind ([SECURITY.md](../../SECURITY.md)).
- **No public ports** — Tailscale (or an SSH tunnel) is the access path; the forge and the
  report server bind localhost.
- **Credentials live on the VM only** (ADR-0014) — never commit them.

Snag? → **[Troubleshooting](troubleshooting.md)**.
