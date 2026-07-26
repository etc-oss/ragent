---
type: component
id: COMP-draft-flake-vision
title: Draft flake (original vision, preserved)
description: The verbatim pre-Phase-0 draft flake.nix, preserved as the aspirational target the incremental starter flake builds toward.
tags: [flake, nix, draft, vision, reference]
timestamp: 2026-07-26
---

# Draft flake (original vision, preserved)

Before this Phase 0 bootstrap, the repository contained a single hand-written
`flake.nix` sketching the **full** intended system: a custom neovim, a jailed
opencode built with `jail.nix` combinators, an autonomous test-and-review
`agent-harness`, and a Zellij-launching devshell. It referenced tools and
repositories that do not resolve yet (`your-org/...`, `fakeHash`, agent packages
not yet pinned), so it is a *vision*, not a buildable starter.

It is preserved **verbatim** here because it captures real design intent from the
project's author and is part of the genesis. The committed
[`flake.nix`](../../../flake.nix) at the repo root is a deliberately smaller,
resolvable **starter** that the [forward plan](forward-plan-phases-1-5.md) grows
toward this vision — Phase 1 fills in the real jail and pinned agent, Phase 2 the
Zellij layout, Phase 3 the shared tooling.

Concepts here that map onto later phases:

- `custom-nvim` → the HUMAN side ([ADR-0005](../decisions/0005-zellij-two-pane-layout.md), Phase 2).
- `jailed-opencode` with `jail.combinators` (`network`, `mount-cwd`, `readwrite`,
  `add-pkg-deps`, `noescape`) → the jail ([ADR-0002](../decisions/0002-jail-nix-confinement.md), Phase 1).
- `agent-harness` (autonomous test loop + human diff review) → the
  propose→review→accept loop and the
  [git-worktree boundary](../decisions/0011-git-worktree-review-boundary.md) (Phase 2).
- `human-tools` on `PATH` (git-surgeon, roborev, openspec, …) → the
  [shared-CLIs tooling layer](../decisions/0007-shared-clis-on-path.md) (Phase 3),
  once each tool's identity is pinned.

> Preserved exactly as it was; do not "fix" it here. Improvements happen in the
> real `flake.nix` and are recorded in ADRs.

```nix
{
  # A brief description of what this flake does. This shows up if someone runs `nix flake metadata`.  
  description = "Agentic TUI Harness based on Zellij + Nvim Workspace with Test-Enabled Sandboxed AI Agents";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    jail-nix.url = "sourcehut:~alexdavid/jail.nix";
    
    # --- SCENARIO A: Repositories that ALREADY have a flake.nix ---
    llm-agents.url = "github:numtide/llm-agents";
    roborev-src.url = "github:your-org/roborev"; # Replace 'your-org'
    
    # --- SCENARIO B: Repositories WITHOUT a flake.nix (Raw Source) ---
    git-surgeon-src = {
      url = "github:your-org/git-surgeon"; # Replace 'your-org'
      flake = false; # Tells Nix to just fetch the code, not evaluate a flake
    };
  };

  outputs = { self, nixpkgs, flake-utils, jail-nix, ... }@inputs:
    flake-utils.lib.eachSystem [ "x86_64-linux" "aarch64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };

        jail = jail-nix.lib.init pkgs;

        # =====================================================================
        # 1. THE HUMAN INTERFACE (IDE & TOOLING)
        # =====================================================================
        
        custom-nvim = pkgs.neovim.override {
          configure = {
            packages.myPlugins = with pkgs.vimPlugins; {
              start = [
                catppuccin-nvim
                nvim-tree-lua
                lualine-nvim
                telescope-nvim
                nvim-web-devicons
                nvim-lspconfig
              ];
            };
            customRC = ''
              set termguicolors
              set number
              set mouse=a
              set shiftwidth=2
              set expandtab

              lua << EOF
              require("catppuccin").setup({ flavour = "mocha" })
              vim.cmd.colorscheme "catppuccin"

              require("nvim-tree").setup({ view = { width = 30, side = "left" } })
              require("lualine").setup()

              vim.keymap.set('n', '<C-b>', ':NvimTreeToggle<CR>', { noremap = true, silent = true })
              vim.keymap.set('n', '<C-p>', require('telescope.builtin').find_files, { noremap = true, silent = true })
              vim.keymap.set('n', '<C-S-f>', require('telescope.builtin').live_grep, { noremap = true, silent = true })
              EOF
            '';
          };
        };

        # =====================================================================
        # 2. IMPORTING AND BUILDING AI TOOLCHAINS
        # =====================================================================
        
        # Extracting pre-built packages from Flake inputs (Scenario A)
        opencode = inputs.llm-agents.packages.${system}.opencode;
        openspec = inputs.llm-agents.packages.${system}.openspec;
        roborev  = inputs.roborev-src.packages.${system}.default;
        
        # Compiling raw source code on the fly (Scenario B - assuming it's a Go project)
        git-surgeon = pkgs.buildGoModule {
          pname = "git-surgeon";
          version = "latest";
          src = inputs.git-surgeon-src;
          # Note: Nix requires a hash to guarantee reproducibility.
          # Leave this as fakeHash on the first run. Nix will fail and give you 
          # the correct hash. Copy it, paste it here, and run it again.
          vendorHash = pkgs.lib.fakeHash; 
        };

        agentToolchains = with pkgs; [ go gopls golangci-lint rustc cargo clippy ];

        # =====================================================================
        # 3. THE AGENT SANDBOX
        # =====================================================================
        
        jailed-opencode = jail "jailed-opencode" opencode (with jail.combinators; [
          network
          time-zone
          no-new-session
          mount-cwd       
          
          (add-pkg-deps (with pkgs; [ git curl bashInteractive jq ripgrep fd ] ++ agentToolchains))
          
          (readwrite (noescape "~/.config/opencode"))
          (readwrite (noescape "~/.cache/go-build"))
          (readwrite (noescape "~/.cargo/registry"))
        ]);

        # =====================================================================
        # 4. THE AUTONOMOUS REPL & HUMAN REVIEW HARNESS
        # =====================================================================
        
        agent-harness = pkgs.writeShellScriptBin "agent-harness" ''
          #!/usr/bin/env bash
          set -e
          
          GREEN='\033[0;32m'
          RED='\033[0;31m'
          YELLOW='\033[1;33m'
          NC='\033[0m' 
          
          if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
             echo -e "''${RED}Error: Run harness inside a Git repository to enable safe rollbacks.''${NC}"
             exit 1
          fi

          echo -e "🛡️  ''${GREEN}Agent running in Secure Nix Sandbox with Test Toolchains''${NC}"
          
          MAX_ATTEMPTS=3
          ATTEMPT=1
          PASSED=false
          AGENT_BIN="${jailed-opencode}/bin/jailed-opencode"

          while [ $ATTEMPT -le $MAX_ATTEMPTS ]; do
            echo -e "\n👉 ''${YELLOW}Loop Attempt $ATTEMPT/$MAX_ATTEMPTS: Agent generating code...''${NC}"
            
            $AGENT_BIN "$1"

            echo -e "🔨 ''${YELLOW}Sandboxed Validation: Running tests & linters...''${NC}"
            
            if go test ./... > test.log 2>&1 && golangci-lint run >> test.log 2>&1; then
              echo -e "✅ ''${GREEN}Tests passed autonomously inside the sandbox!''${NC}"
              PASSED=true
              rm -f test.log
              break
            else
              echo -e "⚠️  ''${RED}Tests failed. Feeding compiler errors back to the agent for self-repair...''${NC}"
              ATTEMPT=$((ATTEMPT+1))
            fi
          done

          if [ "$PASSED" = false ]; then
            echo -e "❌ ''${RED}Agent failed to fix its own test failures after $MAX_ATTEMPTS attempts.''${NC}"
          fi

          echo -e "\n🔍 ''${YELLOW}Human Review Phase''${NC}"
          
          git add -N . 
          git diff --color=always
          
          echo -e "\n-------------------------------------"
          read -p "Approve changes? (y/n/e to edit in Nvim): " choice
          
          case "$choice" in 
            y|Y ) 
              echo -e "✅ ''${GREEN}Changes approved.''${NC}"
              ;;
            n|N ) 
              echo -e "❌ ''${RED}Reverting directory...''${NC}"
              git checkout -- .
              git clean -fd
              ;;
            e|E )
              echo -e "✏️  ''${YELLOW}Opening Neovim...''${NC}"
              nvim $(git diff --name-only)
              ;;
            * ) 
              echo -e "❓ ''${RED}Invalid input. Files left in working tree.''${NC}"
              ;;
          esac
        '';

        # =====================================================================
        # 5. CORE HUMAN TOOLSET EXPORT
        # =====================================================================
        
        human-tools = with pkgs; [
          zellij git gh ripgrep jq fd ast-grep glow bat fzf
          custom-nvim
          roborev git-surgeon openspec jailed-opencode agent-harness
        ];

      in {
        devShells.default = pkgs.mkShell {
          packages = human-tools;
          
          shellHook = ''
            if [[ -z "$ZELLIJ" ]]; then
              exec zellij
            fi
            
            echo "🚀 Human-in-the-loop Workspace Ready."
            echo "IDE: Use 'nvim'. Tools: rg, fd, jq, gh, ast-grep."
            echo "Agent: Type 'agent-harness \"<prompt>\"' to run AI safely."
          '';
        };
      }
    );
}
```
