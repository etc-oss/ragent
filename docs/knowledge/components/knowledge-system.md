---
type: component
id: COMP-knowledge-system
title: Knowledge system (OKF bundle + HTML view)
description: How the OKF Markdown bundle is authored and how tools/okf_render.py turns it into a self-contained, offline HTML view and a knowledge-graph visualizer.
tags: [knowledge, okf, html, tooling, visualizer]
timestamp: 2026-07-26
---

# Knowledge system (OKF bundle + HTML view)

The knowledge system has two representations of the same content:

1. **Markdown + YAML frontmatter** in `docs/knowledge/` — the **source of
   truth**, an [OKF](../conventions/knowledge-format.md) bundle
   ([ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md)).
2. **Self-contained HTML** in `docs/html/` — a **generated**, offline view.
   Never hand-edited; regenerable from Markdown at any time.

## The generator: `tools/okf_render.py`

A single dependency-light Python script (standard library only — no pip, no
CDN). It:

- Parses each concept's YAML frontmatter (a minimal subset parser — enough for
  our fields) and renders the Markdown body to HTML with a small,
  purpose-built renderer (headings, lists, fenced code, tables, blockquotes,
  inline code/bold/italic, links, rules).
- Rewrites inter-concept Markdown links (`../decisions/0002-….md`) to point at
  the generated `.html`, so the offline view is fully navigable.
- Emits one page per concept, an `index.html` grouped by type, and a
  single-file **graph visualizer** (`graph.html`) whose nodes are concepts
  (colored by `type`) and whose edges are the Markdown links between them —
  in the spirit of OKF's reference visualizer.
- Ships light/dark CSS and the graph's force-directed layout **inline**, so
  every file works offline with no external requests.

### Design constraints (why it is deliberately small)

- **Dependency-light and offline** — the workspace must build and render with no
  network and no third-party Python packages.
- **Not a general Markdown engine** — OKF is v0.1 and will move
  ([ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md)); the renderer
  targets *our* corpus, including the nested case where the genesis session
  embeds a fenced prompt containing `#` headings and a `├─` tree. The Markdown
  remains the source of truth, so a simpler render is an acceptable trade for
  zero dependencies.

## Regenerating

```sh
python3 tools/okf_render.py            # docs/knowledge/  ->  docs/html/
```

Run it after any change to `docs/knowledge/`. In Phase 5 this is enforced in CI
(regenerate and diff, to prove HTML is in sync). Open `docs/html/index.html` or
`docs/html/graph.html` in any browser.

## Authoring flow

See the [knowledge-format convention](../conventions/knowledge-format.md) for the
frontmatter schema and [adr-process](../conventions/adr-process.md) for decisions.
The short version: add a Markdown concept, link it to its neighbors, update the
directory `index.md`, and regenerate the HTML.
