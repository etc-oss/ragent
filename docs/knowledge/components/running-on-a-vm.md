---
type: component
id: COMP-running-on-a-vm
title: Running ragent on a VM instead of the host
description: How to run ragent in a Linux VM (cloud or local) so it does not depend on the macOS host — which also removes the Lima layer and tightens the mount.
tags: [vm, lima, deployment, cloud, nixos, security]
timestamp: 2026-07-26
---

# Running ragent on a VM instead of the host

## Why this comes up

Today the stack is `macOS host → Lima Linux guest → jail.nix → agent`
([ADR-0004](../decisions/0004-lima-vm-layer.md)). Lima exists for **one reason**:
bubblewrap needs a Linux kernel and macOS isn't Linux. The driver (Claude Code,
or you at the terminal) runs on the *host* and reaches into the guest.

The key realization: **on a Linux VM you don't need Lima at all.** bubblewrap
runs natively, so the whole stack collapses to `Linux VM (Nix) → Zellij → jail →
agent`, and your Mac becomes just an SSH terminal. That is simpler, host-
independent, and **more secure** — the broad "mount all of `~` into the guest"
that the local Lima config uses disappears, because the project lives *in* the
VM.

## Options (recommendation first)

### A. A dedicated Linux VM (cloud or local) — recommended

A persistent Linux box (Hetzner / EC2 / GCE / DigitalOcean, or a local
UTM/Proxmox/VirtualBox VM). One-time provision, then it *is* your ragent
environment; you SSH in from anywhere.

Provisioning is exactly the three steps already encoded in
[`lima/ragent.yaml`](../../../lima/ragent.yaml), portable to cloud-init or a
shell script:

1. **Unprivileged user namespaces on** (bubblewrap): `kernel.apparmor_restrict_unprivileged_userns=0` (Ubuntu 24.04) — persist in `/etc/sysctl.d/`.
2. **cgroup delegation** (the caps, [ADR-0015](../decisions/0015-cgroup-caps-systemd-run.md)): a `Delegate=cpu memory pids` drop-in for `user@.service`.
3. **Nix with flakes** installed for your user.

Then:

```sh
ssh you@your-vm
git clone <ragent> && cd ragent
nix develop .#workspace           # zellij, nvim(+LSP), lazygit, git-surgeon, agents
export ANTHROPIC_API_KEY=...       # forwarded into the jail at runtime (ADR-0014)
./tools/ragent-workspace.sh "$PWD" mytask   # or: nix run .#workspace -- "$PWD" mytask
```

No Lima, no host-home mount. The jail confines the agent to its clone *inside the
VM*; the VM confines everything to itself.

### B. A NixOS / microvm.nix VM — most reproducible

Bake the provisioning (namespaces, delegation, Nix, the workspace) into a
**NixOS configuration** (or a `microvm.nix` guest — the stronger-isolation path
the genesis conversation flagged). The VM becomes declarative and reproducible:
`nixos-rebuild`/`microvm` brings up an identical ragent box every time, and the
three provisioning steps above become a few NixOS options
(`security.unprivilegedUsernsClone`, `systemd.services."user@".serviceConfig.Delegate`,
`nix.settings.experimental-features`). Best long-term home for the project; more
upfront Nix work.

### C. Keep Lima, but drive from *inside* the guest — smallest change

Instead of Claude Code on the host reaching into the guest, run the driver
**inside** the existing Lima guest (`limactl shell ragent`, then work there).
This is the recursive dogfood milestone and needs no new infrastructure — but it
still carries the local Lima config's broad `~` mount, so tighten that
(`mounts: - location: "~/Developer/ragent"` instead of `~`) if you stay here.

## Security note (a real improvement)

The local `lima/ragent.yaml` mounts the **entire host home writable** into the
guest — convenient but broad. Moving to a dedicated VM (A or B) removes that
entirely: nothing of your Mac is exposed; the repo is native to the VM, and the
jail's scoped `mount-cwd` is the only filesystem boundary that matters. If you
keep Lima (C), scope the mount to the project directory.

## Connectivity

- SSH in; run Zellij in the VM. For a good TUI over SSH: a truecolor terminal
  (`TERM=xterm-256color`/`tmux-256color`) and **OSC 52 clipboard** so copy/paste
  works without a shared clipboard. These are the [ADR-0005](../decisions/0005-zellij-two-pane-layout.md)
  ergonomics, now over one SSH hop instead of macOS→Lima→SSH.
- Secrets: the provider key lives in the VM's shell env and is forwarded into the
  jail at runtime (never stored — ADR-0014). Keep git push/deploy creds on the
  human side (an ssh-agent forwarded to the VM, used outside the jail).

## What already ports directly

Everything ragent-specific is host-agnostic: the `flake.nix` (jail, agents,
`sharedTools`, the `workspace` devshell and `nix run .#workspace`), the
`tools/`, the KDL layout, and the provisioning steps in `lima/ragent.yaml`. The
only macOS-coupled piece is Lima itself — which options A and B drop.

## A vs B, head to head

| | **A — dedicated Linux VM** (imperative) | **B — NixOS / microvm.nix** (declarative) |
|---|---|---|
| Time to first run | **Hours.** Reuses the existing provisioning as cloud-init. | **Days.** Write a NixOS module / microvm config first. |
| Reproducibility | Nix reproduces the *toolchain*; the *box* is a mutable pet that drifts. | **The box itself is code** — rebuild an identical one on demand (cattle). |
| Provisioning | Idempotent shell/cloud-init (the same steps that hit the nix-probe bug). | Clean NixOS options — no scripts, no idempotency bugs. |
| Fits ragent's ethos | Partial (Nix inside a non-Nix box). | **Full** — pinned, reproducible, "forkable per project" all the way down. |
| Isolation | bwrap in a shared-kernel VM (today's model). | Can add **VM-per-agent** (microVM) — stronger than bwrap, the [ADR-0002](../decisions/0002-jail-nix-confinement.md) "microvm.nix future" and pi's Gondolin pattern. |
| On a **Mac** | Clean: macOS → one cloud/local Linux VM. | Nests again: macOS → Linux host → microVM, **unless** you use a cloud Linux box or a Linux workstation. |
| Debugging | Familiar Linux ops. | Nix-shaped errors; steeper. |
| Could be a flake output | No (external box). | **Yes** — `nixosConfigurations.ragent` / a microvm, so the flake spins up the *whole* environment. |

## Recommendation

**Start with A, target B.**

- **A now** — least new work, gets you off the host immediately, removes the broad
  home mount, reuses provisioning you already have, and validates the workflow on
  a real VM. Best *first* step, especially to move quickly.
- **B as the endgame** — it is the more *correct* architecture for a Nix-native,
  reproducibility-first project like ragent: the dev box becomes declarative and
  forkable, and **microvm.nix can upgrade confinement itself** (a VM boundary per
  agent, not just bwrap). Worth it once the workflow is proven — and it pays off
  most if you run on a **Linux host or a cloud Linux box** (no re-nesting) and are
  comfortable in Nix.

The tie-breaker is your host and appetite: on a **cloud/Linux box + Nix-comfort**,
you could even skip straight to B (it's the destination). On a **Mac, moving
fast**, A is the pragmatic bridge and B is the thing to grow into.
