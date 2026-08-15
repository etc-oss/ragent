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

      # Host-side dev shell (edit/test THIS project on macOS / a non-guest host). The
      # confined agent WORKSPACE is Linux-only (the jail) — run that in the Lima guest;
      # this shell is just your project's own toolchain. Edit `packages` for your stack.
      hostShell = hs: let p = import nixpkgs { system = hs; }; in
        p.mkShell {
          packages = [ (p.python3.withPackages (ps: [ ps.pytest ])) ];
          shellHook = ''
            echo "host dev shell — for editing/testing this project itself."
            echo "The confined agent workspace is Linux-only: use the Lima guest"
            echo "  (limactl shell ragent  ->  cd here  ->  nix develop / nix run .#shell)."
          '';
        };
    in
    {
      # In the Linux guest: `nix develop` gives ragent's workspace toolchain (zellij,
      # neovim, lazygit, git-surgeon, …) + the jailed agents + YOUR projectTools.
      # On a macOS / non-guest HOST: a light shell for hacking on this project itself.
      devShells.${system}.default = ws.devShell;
      devShells.aarch64-darwin.default = hostShell "aarch64-darwin";
      devShells.x86_64-darwin.default = hostShell "x86_64-darwin";

      # `nix run .#task-window -- <task>` launches the two-side HUMAN/MACHINE (dir = CWD)
      # workspace (ADR-0005) with the clone review boundary (ADR-0011/0016) for THIS
      # project. The confined agent has projectTools on its PATH, so it runs your tests.
      apps.${system} = {
        default = { type = "app"; program = "${ws.cli}/bin/ragent"; };
        task-window = mkTaskAlias "window";
        task-orchestrate = mkTaskAlias "orchestrate";
        task-review = mkTaskAlias "review";
        # `nix run .#shell` — quick confined interactive session in a clone of CWD (ragent ADR-0030).
        shell = {
          type = "app";
          program = "${pkgs.writeShellApplication {
            name = "shell";
            text = ''exec ${ws.cli}/bin/ragent shell "$@"'';
          }}/bin/shell";
        };
        # `nix run .#dev-forge` — a local Forgejo for the async loop, re-exported from ragent (ADR-0029).
        dev-forge = ragent.apps.${system}.dev-forge;
      };
    };
}
