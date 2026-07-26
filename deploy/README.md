# deploy/ — running ragent on a VM (no host dependency)

Two ways to stand up a ragent dev box on a Linux VM, per
[running-on-a-vm.md](../docs/knowledge/components/running-on-a-vm.md). On a Linux
VM you do **not** need Lima — bubblewrap runs natively.

## Option A — a stock Linux VM (imperative)

Cloud VM (Hetzner / EC2 / GCE / DigitalOcean), pass the cloud-config as user-data:

```sh
# most providers: paste deploy/cloud-init.yaml as the instance "user data"
```

Or provision an existing Debian/Ubuntu box:

```sh
scp -r deploy you@vm:~/ && ssh you@vm 'bash ~/deploy/provision.sh'
```

Then on the VM:

```sh
git clone <your-ragent-remote> && cd ragent
nix run .#workspace -- "$PWD" mytask
```

Both apply the same three steps as `lima/ragent.yaml` (user namespaces, cgroup
delegation, Nix + flakes). Verified by `shellcheck`; the end-to-end cloud run is
yours to execute (I have no cloud VM here).

## Option B — a declarative NixOS box

The flake exposes `nixosConfigurations.ragent` — the box itself as code (the
three steps become NixOS options, plus a `ragent` user, SSH, and the workspace
tools). See [`../nixos/ragent-box.nix`](../nixos/ragent-box.nix).

```sh
# on/for an x86_64-linux target:
nix build .#nixosConfigurations.ragent.config.system.build.toplevel
# deploy it (nixos-rebuild switch --flake .#ragent, an image via nixos-generators,
# or nixos-anywhere), or wrap it as a microvm.nix guest for VM-per-agent isolation.
```

Recommendation: **A now, B as the reproducible endgame** — see the
[head-to-head](../docs/knowledge/components/running-on-a-vm.md#a-vs-b-head-to-head).
