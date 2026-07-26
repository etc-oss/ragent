#!/usr/bin/env bash
# provision.sh — turn a fresh Debian/Ubuntu Linux VM into a ragent dev box
# (Option A of docs/knowledge/components/running-on-a-vm.md). No Lima needed:
# bubblewrap runs natively on the VM's Linux kernel.
#
# Idempotent. Run as a sudo-capable user on the VM:
#   scp -r deploy you@vm:~/  &&  ssh you@vm 'bash ~/deploy/provision.sh'
#
# These are exactly the three steps encoded in lima/ragent.yaml.
set -euo pipefail

echo "==> 1/3 unprivileged user namespaces (bubblewrap prerequisite)"
echo "kernel.apparmor_restrict_unprivileged_userns=0" \
  | sudo tee /etc/sysctl.d/99-ragent-userns.conf >/dev/null
sudo sysctl --system >/dev/null || true

echo "==> 2/3 cgroup delegation for the user session (caps — ADR-0015)"
sudo mkdir -p /etc/systemd/system/user@.service.d
printf '[Service]\nDelegate=cpu cpuset io memory pids\n' \
  | sudo tee /etc/systemd/system/user@.service.d/delegate.conf >/dev/null
sudo systemctl daemon-reload || true

echo "==> 3/3 Nix with flakes (Determinate installer)"
if ! command -v nix >/dev/null 2>&1; then
  curl -fsSL https://install.determinate.systems/nix | sh -s -- install --no-confirm
fi

cat <<'DONE'

==> Done. Log out and back in (to pick up cgroup delegation + the nix profile), then:

    git clone <your-ragent-remote> && cd ragent
    nix run .#workspace -- "$PWD" mytask     # the two-side workspace — no Lima

The jail confines the agent to its clone inside this VM; the VM confines
everything to itself. Nothing of any other machine is exposed.
DONE
