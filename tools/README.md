# tools/

Small, dependency-light utilities for the repo. Nothing here requires
third-party packages.

## `okf_render.py` — knowledge → HTML

Renders the OKF knowledge bundle to a self-contained, **offline** HTML view.

```sh
python3 tools/okf_render.py        # docs/knowledge/  ->  docs/html/
```

- Python **standard library only** (no pip, no network, no CDN).
- Produces one page per concept, `index.html`, and a single-file force-directed
  `graph.html` visualizer. All CSS/JS is inlined; every file works offline.
- Rewrites intra-bundle `.md` links to `.html` and copies non-Markdown assets
  (e.g. `genesis-transcript.json`) verbatim.

`docs/html/` is **generated** — never hand-edit it. Markdown in `docs/knowledge/`
is the source of truth. See
[knowledge-system](../docs/knowledge/components/knowledge-system.md) for design
notes and the deliberately-small-renderer rationale.

## `mirror-example.sh` — local-resilience template

A **publishable template** for the offline/local-mirror strategy in
[ADR-0010](../docs/knowledge/decisions/0010-local-mirror-resilience.md). It shows
the `nix flake archive` + private-mirror + `--override-input` failover approach.

It is a template only: the **actual** private mirror is deliberately kept out of
the public repo (`.gitignore` excludes `/mirror/`). Copy it, point it at your own
storage, and run it outside version control.
