{
  description = "ragent — a forkable AI-coding workspace: confined agents (jail.nix) with human oversight, on Zellij + Lima.";

  # ---------------------------------------------------------------------------
  # Phase 1 flake — the jail, one agent.
  #
  # The docs devshell runs anywhere (incl. the macOS host). The jail is Linux
  # only (bubblewrap needs Linux namespaces), so all jail outputs are guarded to
  # Linux systems and are meant to run inside a Lima guest (see lima/ragent.yaml).
  # See docs/knowledge/components/forward-plan-phases-1-5.md and ADRs 0013–0015.
  #
  # Reference, don't vendor (ADR-0003): upstreams are pinned inputs; their source
  # is never copied into this repo. jail.nix is GPL-3.0 — referencing it keeps
  # this repo's Apache-2.0 umbrella clean.
  #
  # Local-resilience path (ADR-0010): nix flake archive + a private mirror +
  # --override-input failover. Keep the mirror OUT of this repo; see
  # tools/mirror-example.sh.
  # ---------------------------------------------------------------------------

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";

    # Machine-side confinement. GPL-3.0; referenced, not vendored.
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";

    # Jails for LLM agents built on jail.nix (exports makeJailedOpencode,
    # makeJailedClaudeCode, makeJailedPi, …). Pins jail.nix transitively; we also
    # pin jail.nix directly for the low-level confinement probe below.
    jailed-agents.url = "github:andersonjoseph/jailed-agents";
  };

  outputs = { self, nixpkgs, flake-utils, jail-nix, jailed-agents, ... }:
    let inherit (nixpkgs) lib; in
    # Enumerate systems explicitly: nixpkgs 26.11 dropped x86_64-darwin.
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          # Claude Code is distributed unfree; needed only for jailed-claude-code.
          config.allowUnfree = true;
        };
        # Decide Linux-ness from the system STRING. Do NOT force `pkgs` for this —
        # merging the outputs attrset would then import nixpkgs for every system
        # (incl. dropped x86_64-darwin) just to branch, which errors at eval time.
        isLinux = lib.hasSuffix "-linux" system;

        # Phase 0 docs devshell — usable on macOS and Linux. Stdlib Python only.
        docsShell = pkgs.mkShell {
          packages = [ pkgs.python3 pkgs.git ];
          shellHook = ''
            echo "ragent devshell."
            echo "  Docs:  python3 tools/okf_render.py   (-> docs/html/)"
            echo "  Jail:  Linux only — run inside the Lima guest (lima/ragent.yaml)."
          '';
        };

        # -------------------------------------------------------------------
        # Phase 1 — the jail (Linux only)
        # -------------------------------------------------------------------
        linuxOutputs =
          let
            jail = jail-nix.lib.init pkgs;
            ja = jailed-agents.lib.${system};

            # The confinement contract, stated once. Bubblewrap exposes the bare
            # minimum by default, so $HOME, SSH keys, and every other secret are
            # DENIED unless explicitly bound — and we bind nothing but the cwd.
            confinementProfile = with jail.combinators; [
              network                              # egress for the LLM API
              time-zone
              no-new-session
              mount-cwd                            # the PROJECT DIRECTORY (cwd) rw — and nothing else
              (try-fwd-env "ANTHROPIC_API_KEY")    # runtime-forwarded key; never enters the Nix store (ADR-0014)
              (add-pkg-deps (with pkgs; [ bashInteractive coreutils ]))
            ];

            # A jailed shell that carries exactly the agent's confinement profile.
            # This is the security proof: the negative-control test drives THIS,
            # so confinement is proven without depending on agent packaging
            # (ADR-0013). tools/confinement-test.sh runs against it.
            jailed-probe = jail "ragent-jail-probe" pkgs.bashInteractive confinementProfile;
          in
          {
            packages = {
              inherit jailed-probe;

              # First real agent — jailed-agents' best-documented example, lowest
              # friction to reach the confinement gate (ADR-0013).
              jailed-opencode = ja.makeJailedOpencode { };

              # Dogfood target: Claude Code inside its own jail — the recursive
              # "it works" milestone. Kept as an explicit output; verified to
              # build in-guest before it is relied on (may need unfree/auth).
              jailed-claude-code = ja.makeJailedClaudeCode { };
            };
          };
      in
      {
        devShells.default = docsShell;
      }
      // lib.optionalAttrs isLinux linuxOutputs
    );
}
