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

## Recommendation

Start with **A** (a dedicated Linux VM): least new Nix work, immediately removes
the host dependency and the broad mount, and reuses the provisioning you already
have. Graduate to **B** (NixOS/microvm.nix) when you want the dev box itself to
be declarative and reproducible.
