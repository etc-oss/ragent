{
  description = "A project using the ragent AI-coding workspace.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ragent is CONSUMED as a pinned flake input — never forked (ADR-0003).
    # Until ragent (or your fork) is published, point this at a local checkout:
    #     ragent.url = "git+file:///absolute/path/to/ragent";
    ragent.url = "github:REPLACE-ME/ragent";
  };

  outputs = { self, nixpkgs, ragent, ... }:
    let
      # The jail and workspace are Linux only (they run inside the Lima guest).
      system = "aarch64-linux";
    in
    {
      # `nix develop` gives this project ragent's workspace toolchain — zellij,
      # neovim, lazygit, git, git-surgeon, rg, fd, jq — plus the jailed agents.
      devShells.${system}.default = ragent.devShells.${system}.workspace;

      # `nix run .#workspace -- .` launches the two-side HUMAN/MACHINE workspace
      # (ADR-0005) with the clone review boundary (ADR-0011/0016) for THIS project.
      apps.${system}.workspace = ragent.apps.${system}.workspace;
    };
}
