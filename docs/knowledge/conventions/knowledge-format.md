---
type: convention
id: CONV-knowledge-format
title: Knowledge format (OKF bundle conventions)
description: How docs/knowledge/ is structured as an OKF v0.1 bundle, and which frontmatter fields are OKF-standard versus ragent extensions.
tags: [okf, knowledge, convention, frontmatter]
timestamp: 2026-07-26
sources:
  - https://github.com/GoogleCloudPlatform/knowledge-catalog
---

# Knowledge format (OKF bundle conventions)

`docs/knowledge/` is an **[Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog)
(OKF) v0.1** bundle: a directory of Markdown files with YAML frontmatter,
cross-linked with standard Markdown links, forming a knowledge graph. OKF is a
*format*, not a service — "if you can `cat` a file, you can read OKF; if you can
`git clone` a repo, you can ship it." We picked it deliberately; see
[ADR-0008](../decisions/0008-okf-adr-knowledge-capture.md).

## Frontmatter fields

Every concept begins with a YAML frontmatter block. We keep the OKF-standard
fields distinct from our own extensions so we never pass off invented fields as
part of the spec.

### OKF-standard fields

| Field | Spec status | Meaning |
|---|---|---|
| `type` | **required** | Kind of concept. The only always-required key. |
| `title` | recommended | Human-readable display name. |
| `description` | recommended | Single-sentence summary. |
| `tags` | recommended | YAML list for categorization. |
| `timestamp` | optional (provenance) | ISO-8601 creation time. |
| `sources` | optional (provenance) | List of source URIs. |

> OKF v0.1 also defines `resource` (a canonical URI for an underlying asset) and
> notes that v0.2 supersedes `timestamp` with `generated.at`. We stay on v0.1
> naming until the spec settles — the downside of churn is near-zero because it
> all bottoms out in plain Markdown + YAML.

### ragent extension fields (NOT part of OKF)

These are our conventions layered on top. A generic OKF consumer will ignore
them; that is fine.

| Field | Applies to | Meaning |
|---|---|---|
| `id` | all | Stable identifier, e.g. `ADR-0002`, `SESSION-0001`, `COMP-architecture-overview`. |
| `status` | decision | MADR lifecycle: `proposed` \| `accepted` \| `superseded` \| `deprecated`. |
| `date` | decision | The date the decision was made. |
| `supersedes` / `superseded-by` | decision | ADR lineage, by `id`. |

## Concept types

OKF does not register `type` values centrally; producers pick descriptive ones
and consumers tolerate unknown types. Ours:

- **`decision`** — an ADR. MADR-style body. Lives in `decisions/`.
- **`session`** — a verbatim chat or prompt record. Lives in `sessions/`. See
  [verbatim-sessions](verbatim-sessions.md).
- **`component`** — an architecture concept or plan. Lives in `components/`.
- **`convention`** — a standard (like this file). Lives in `conventions/`.

## Linking

Concepts link to each other with **standard Markdown links** using relative
paths, e.g. `[ADR-0002](../decisions/0002-jail-nix-confinement.md)`. This is the
OKF linking mechanism and it is what the HTML graph visualizer walks to draw
edges. Prefer linking a concept over restating it (keep the graph, not copies).

## Directory layout and reserved files

```
docs/knowledge/
├─ index.md            # bundle root listing (OKF reserved name)
├─ sessions/
│  ├─ index.md
│  ├─ genesis-transcript.json   # byte-exact source export (canonical)
│  ├─ 0001-*.md                 # rendered session concept
│  └─ 0002-*.md
├─ decisions/          # ADRs, 0001-.. + index.md
├─ components/         # architecture + plans + index.md
└─ conventions/        # standards + index.md
```

OKF reserves two filenames: `index.md` (a directory listing) and `log.md` (an
update history). We use `index.md` per directory. These indexes are hand-written
today; if the bundle grows, generate them.

## Adding a concept

1. Create `docs/knowledge/<type>/<nnnn-slug>.md` with the frontmatter above.
2. Link it to related concepts (and, for decisions, back to the originating
   session).
3. Add a line to the relevant `index.md`.
4. Regenerate the HTML view: `python3 tools/okf_render.py`. Never hand-edit
   `docs/html/`.
