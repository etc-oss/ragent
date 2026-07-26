# nixos/ragent-box.nix — a declarative ragent dev box (Option B of
# docs/knowledge/components/running-on-a-vm.md). The three imperative provisioning
# steps from lima/ragent.yaml become NixOS options — no scripts, no idempotency
# bugs. Exposed as `nixosConfigurations.ragent` in the flake.
{ config, pkgs, lib, ... }:
{
  # 1) unprivileged user namespaces (bubblewrap prerequisite)
  boot.kernel.sysctl."kernel.apparmor_restrict_unprivileged_userns" = 0;

  # 2) cgroup delegation so `systemd-run --user --scope` enforces caps (ADR-0015)
  systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";

  # 3) Nix with flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.settings.trusted-users = [ "root" "ragent" ];

  # A dev user. Set an SSH key / password out of band (an overlay module or
  # `users.users.ragent.openssh.authorizedKeys.keys`).
  users.users.ragent = {
    isNormalUser = true;
    description = "ragent workspace user";
    extraGroups = [ "wheel" ];
  };

  # Remote access + the human-side tools. The jail/agents themselves come from the
  # ragent flake's `.#workspace` devshell / `nix run .#workspace` inside the box.
  services.openssh.enable = true;
  environment.systemPackages = with pkgs; [ git zellij neovim lazygit ];

  # Claude Code (unfree) is only pulled in if you build jailed-claude-code here.
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "ragent";

  # Track the release this box was created on.
  system.stateVersion = config.system.nixos.release;

  # Minimal generic-VM boot base so this evaluates to a complete, image-able
  # system. Override these for your real target — or let nixos-generators /
  # nixos-anywhere supply the disk layout (they typically use /dev/vda).
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/vda";
  fileSystems."/" = { device = "/dev/vda1"; fsType = "ext4"; };

  # microvm.nix note: to get a VM-per-agent isolation boundary (stronger than
  # bubblewrap; the ADR-0002 "microvm.nix future"), add the `microvm` flake input
  # and import its module here, then define `microvm.vms` per project. This module
  # is the declarative base that a microVM would run.
}
