# <your project>

Scaffolded from the [ragent](https://github.com/REPLACE-ME/ragent) per-project
template. ragent is an open-source, forkable AI-coding workspace: confined agents
(jail.nix) with human oversight, on Zellij + Lima.

## One-time setup

1. Point `inputs.ragent.url` in `flake.nix` at your ragent repo/fork. Until it is
   published, use a local checkout:
   ```
   ragent.url = "git+file:///absolute/path/to/ragent";
   ```
2. Run inside a Linux guest (bubblewrap needs Linux) — e.g. a Lima VM whose config
   lives in a config repo like your-config-repo. `nix flake lock` to pin.

## Use

```sh
nix develop                 # zellij, nvim, lazygit, git, git-surgeon, rg, fd, jq + jailed agents
nix run .#workspace -- .    # launch the two-side workspace on this project
```

The MACHINE side runs a coding agent confined to a **clone** of this project
(the agent can only touch the clone + its own config; ADR-0016). You review its
proposed commits from the HUMAN side and merge what you accept — nothing lands
without that gate.
