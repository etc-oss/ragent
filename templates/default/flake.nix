{
  description = "A project using the ragent AI-coding workspace.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # ragent is CONSUMED as a pinned flake input — never forked (ADR-0003).
    # Until ragent (or your fork) is published, point this at a local checkout:
    #     ragent.url = "git+file:///absolute/path/to/ragent";
    ragent.url = "github:etc-oss/ragent";
  };

  outputs = { self, nixpkgs, ragent, ... }:
    let
      # The jail and workspace are Linux only (they run inside the Lima guest).
      system = "aarch64-linux";
      pkgs = import nixpkgs { inherit system; };

      # This project's own tools, added to the confined agent's in-jail PATH (and
      # the workspace) so the agent can build/test THIS project (ADR-0019). Deps
      # are pinned by flake.lock — not a Makefile. Edit this list for your stack:
      #   Go:     [ pkgs.go pkgs.gotools ]
      #   Node:   [ pkgs.nodejs pkgs.nodePackages.pnpm ]
      #   Python: [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ]
      projectTools = [ (pkgs.python3.withPackages (ps: [ ps.pytest ])) ];

      ws = ragent.lib.${system}.mkWorkspace {
        inherit projectTools;
        # defaultAgent = "jailed-claude-code";   # or -subscription (Pro/Max), opencode, pi, crush
      };

      # `nix run .#task-<sub> -- …` drives THIS project's workspace via ragent's
      # unified CLI (ADR-0023). NB: mkWorkspace returns `.cli` (not a `.app`).
      mkTaskAlias = sub: {
        type = "app";
        program = "${pkgs.writeShellApplication {
          name = "task-${sub}";
          text = ''exec ${ws.cli}/bin/ragent task ${sub} "$@"'';
        }}/bin/task-${sub}";
      };
    in
    {
      # `nix develop` gives this project ragent's workspace toolchain (zellij,
      # neovim, lazygit, git-surgeon, …) + the jailed agents + YOUR projectTools.
      devShells.${system}.default = ws.devShell;

      # `nix run .#task-window -- "$PWD" <task>` launches the two-side HUMAN/MACHINE
      # workspace (ADR-0005) with the clone review boundary (ADR-0011/0016) for THIS
      # project. The confined agent has projectTools on its PATH, so it runs your tests.
      apps.${system} = {
        default = { type = "app"; program = "${ws.cli}/bin/ragent"; };
        task-window = mkTaskAlias "window";
        task-orchestrate = mkTaskAlias "orchestrate";
        task-review = mkTaskAlias "review";
      };
    };
}
