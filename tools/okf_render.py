#!/usr/bin/env python3
"""Render the ragent OKF knowledge bundle to a self-contained, offline HTML view.

- Input:  docs/knowledge/   (Markdown + YAML frontmatter, cross-linked)
- Output: docs/html/        (one page per concept + index.html + graph.html)

Design constraints (see docs/knowledge/components/knowledge-system.md):
  * Python standard library only. No third-party packages, no network, no CDN.
  * Not a general Markdown engine — a small renderer that is correct on *our*
    corpus (headings, lists incl. wrapped items, fenced code, tables,
    blockquotes, inline code/bold/italic, links, rules). Markdown stays the
    source of truth; if a construct renders imperfectly, fix the corpus or this
    renderer — never hand-edit the generated HTML.

Usage:  python3 tools/okf_render.py
"""

import html
import json
import posixpath
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "knowledge"
OUT = ROOT / "docs" / "html"

TYPE_ORDER = ["session", "decision", "component", "convention", "index"]
TYPE_COLOR = {
    "session": "#d98c3f",
    "decision": "#4f9d69",
    "component": "#5b8def",
    "convention": "#a970d0",
    "index": "#8a8f98",
}


# --------------------------------------------------------------------------- #
# Frontmatter (minimal YAML subset: scalars, inline [a, b] lists, block lists) #
# --------------------------------------------------------------------------- #
def parse_frontmatter(text):
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---", 3)
    if end == -1:
        return {}, text
    fm = text[4:end]
    rest = text[end + 4:]
    if rest.startswith("\n"):
        rest = rest[1:]
    meta = {}
    lines = fm.split("\n")
    i = 0
    while i < len(lines):
        line = lines[i]
        i += 1
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        m = re.match(r"^([A-Za-z0-9_.-]+):\s?(.*)$", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2).strip()
        if val == "":
            # possible block list on following indented "- " lines
            items = []
            while i < len(lines) and re.match(r"^\s+-\s+", lines[i]):
                items.append(_scalar(lines[i].split("-", 1)[1].strip()))
                i += 1
            meta[key] = items if items else ""
        elif val.startswith("[") and val.endswith("]"):
            inner = val[1:-1].strip()
            meta[key] = [_scalar(x.strip()) for x in inner.split(",")] if inner else []
        else:
            meta[key] = _scalar(val)
    return meta, rest


def _scalar(v):
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v


# --------------------------------------------------------------------------- #
# Inline rendering                                                             #
# --------------------------------------------------------------------------- #
def rewrite_href(href):
    """Point intra-bundle .md links at the generated .html; leave others alone."""
    if re.match(r"^(https?:|mailto:|#)", href):
        return href
    base, sep, anchor = href.partition("#")
    if base.endswith(".md"):
        base = base[:-3] + ".html"
    return base + sep + anchor


def render_inline(text):
    stash = []

    def keep(frag):
        stash.append(frag)
        return "\x00%d\x00" % (len(stash) - 1)

    # inline code
    text = re.sub(r"`([^`]+)`", lambda m: keep("<code>%s</code>" % html.escape(m.group(1))), text)

    # links [label](href)
    def link(m):
        label, href = m.group(1), m.group(2).strip()
        return keep('<a href="%s">%s</a>' % (html.escape(rewrite_href(href), quote=True), html.escape(label)))
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)

    # bare autolinks
    def auto(m):
        u = m.group(1)
        return keep('<a href="%s">%s</a>' % (html.escape(u, quote=True), html.escape(u)))
    text = re.sub(r"(?<![\"'>=(])\b(https?://[^\s<>()\]]+)", auto, text)

    text = html.escape(text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\*\w])\*([^*\n]+)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\x00(\d+)\x00", lambda m: stash[int(m.group(1))], text)
    return text


# --------------------------------------------------------------------------- #
# Block rendering                                                              #
# --------------------------------------------------------------------------- #
LIST_RE = re.compile(r"^(\s*)([-*+]|\d+\.)\s+(.*)$")


def _slug(text):
    return re.sub(r"[^a-z0-9]+", "-", re.sub(r"<[^>]+>", "", text).lower()).strip("-")


def md_to_html(body):
    lines = body.split("\n")
    out = []
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]

        # fenced code
        fence = re.match(r"^```(\w*)\s*$", line)
        if fence:
            lang = fence.group(1)
            buf = []
            i += 1
            while i < n and not re.match(r"^```\s*$", lines[i]):
                buf.append(lines[i])
                i += 1
            i += 1  # closing fence
            cls = ' class="language-%s"' % lang if lang else ""
            out.append("<pre><code%s>%s</code></pre>" % (cls, html.escape("\n".join(buf))))
            continue

        if line.strip() == "":
            i += 1
            continue

        # heading
        h = re.match(r"^(#{1,6})\s+(.*)$", line)
        if h:
            lvl = len(h.group(1))
            inner = render_inline(h.group(2).strip())
            out.append('<h%d id="%s">%s</h%d>' % (lvl, _slug(h.group(2)), inner, lvl))
            i += 1
            continue

        # horizontal rule
        if re.match(r"^(-{3,}|\*{3,}|_{3,})\s*$", line):
            out.append("<hr>")
            i += 1
            continue

        # table (header row + separator row)
        if "|" in line and i + 1 < n and _is_table_sep(lines[i + 1]):
            tbl, i = _parse_table(lines, i)
            out.append(tbl)
            continue

        # blockquote
        if line.lstrip().startswith(">"):
            buf = []
            while i < n and lines[i].lstrip().startswith(">"):
                stripped = re.sub(r"^\s*>\s?", "", lines[i])
                buf.append(stripped)
                i += 1
            out.append("<blockquote>%s</blockquote>" % md_to_html("\n".join(buf)))
            continue

        # list
        if LIST_RE.match(line):
            indent = len(LIST_RE.match(line).group(1))
            lst, i = _parse_list(lines, i, indent)
            out.append(lst)
            continue

        # paragraph
        buf = []
        while i < n and lines[i].strip() != "" and not _starts_block(lines, i):
            buf.append(lines[i].strip())
            i += 1
        out.append("<p>%s</p>" % render_inline(" ".join(buf)))
    return "\n".join(out)


def _starts_block(lines, i):
    line = lines[i]
    if re.match(r"^```", line) or re.match(r"^#{1,6}\s", line):
        return True
    if re.match(r"^(-{3,}|\*{3,}|_{3,})\s*$", line):
        return True
    if line.lstrip().startswith(">"):
        return True
    if LIST_RE.match(line):
        return True
    if "|" in line and i + 1 < len(lines) and _is_table_sep(lines[i + 1]):
        return True
    return False


def _is_table_sep(line):
    s = line.strip()
    return "|" in s and "-" in s and re.match(r"^\|?[\s:|-]+\|?$", s) is not None


def _split_row(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def _parse_table(lines, i):
    header = _split_row(lines[i])
    i += 2  # header + separator
    rows = []
    while i < len(lines) and "|" in lines[i] and lines[i].strip():
        rows.append(_split_row(lines[i]))
        i += 1
    out = ["<table><thead><tr>"]
    out += ["<th>%s</th>" % render_inline(c) for c in header]
    out.append("</tr></thead><tbody>")
    for r in rows:
        out.append("<tr>" + "".join("<td>%s</td>" % render_inline(c) for c in r) + "</tr>")
    out.append("</tbody></table>")
    return "".join(out), i


def _parse_list(lines, i, base_indent):
    items = []
    ordered = None
    while i < len(lines):
        m = LIST_RE.match(lines[i])
        if not m or len(m.group(1)) != base_indent:
            break
        if ordered is None:
            ordered = bool(re.match(r"\d+\.$", m.group(2)))
        parts = [m.group(3)]
        i += 1
        # wrapped continuation lines (indented, not a list marker)
        while (i < len(lines) and lines[i].strip() != "" and not LIST_RE.match(lines[i])
               and (len(lines[i]) - len(lines[i].lstrip())) > base_indent):
            parts.append(lines[i].strip())
            i += 1
        # nested sublist
        sub = ""
        if i < len(lines):
            m2 = LIST_RE.match(lines[i])
            if m2 and len(m2.group(1)) > base_indent:
                sub, i = _parse_list(lines, i, len(m2.group(1)))
        items.append((render_inline(" ".join(parts)), sub))
    tag = "ol" if ordered else "ul"
    body = "".join("<li>%s%s</li>" % (c, s) for c, s in items)
    return "<%s>%s</%s>" % (tag, body, tag), i


# --------------------------------------------------------------------------- #
# Page templates                                                              #
# --------------------------------------------------------------------------- #
CSS = """
:root{--bg:#fff;--fg:#1c1e21;--muted:#6b7280;--border:#e5e7eb;--card:#f7f8fa;
--link:#2563eb;--code-bg:#f2f3f5;--accent:#4f9d69}
@media (prefers-color-scheme:dark){:root{--bg:#16181d;--fg:#e6e8eb;--muted:#9aa0a6;
--border:#2a2e37;--card:#1d2027;--link:#7aa7ff;--code-bg:#22262e;--accent:#5fb67f}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
font:16px/1.62 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif}
.wrap{max-width:820px;margin:0 auto;padding:2rem 1.25rem 5rem}
a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}
h1,h2,h3,h4{line-height:1.25;margin:1.8em 0 .6em}h1{margin-top:.2em;font-size:1.9rem}
h2{font-size:1.4rem;border-bottom:1px solid var(--border);padding-bottom:.3em}
h3{font-size:1.15rem}code{background:var(--code-bg);padding:.12em .4em;border-radius:4px;
font:.88em ui-monospace,SFMono-Regular,Menlo,Consolas,monospace}
pre{background:var(--code-bg);padding:1rem;border-radius:8px;overflow-x:auto;border:1px solid var(--border)}
pre code{background:none;padding:0;font-size:.85rem;line-height:1.5}
blockquote{margin:1em 0;padding:.2em 1em;border-left:3px solid var(--border);color:var(--muted)}
table{border-collapse:collapse;width:100%;margin:1em 0;display:block;overflow-x:auto}
th,td{border:1px solid var(--border);padding:.5em .7em;text-align:left;vertical-align:top}
th{background:var(--card)}hr{border:none;border-top:1px solid var(--border);margin:2em 0}
.nav{font-size:.9rem;color:var(--muted);margin-bottom:1.5rem}
.badge{display:inline-block;font-size:.72rem;font-weight:600;text-transform:uppercase;
letter-spacing:.04em;color:#fff;padding:.15em .6em;border-radius:20px;vertical-align:middle}
.meta{background:var(--card);border:1px solid var(--border);border-radius:8px;
padding:.5rem .9rem;margin:1rem 0 2rem;font-size:.86rem}
.meta div{margin:.25em 0}.meta .k{color:var(--muted);display:inline-block;min-width:6.5em}
.tags span{display:inline-block;background:var(--border);border-radius:12px;
padding:.05em .55em;margin:.1em .2em .1em 0;font-size:.78rem}
.footer{margin-top:3rem;padding-top:1rem;border-top:1px solid var(--border);
font-size:.85rem;color:var(--muted)}
.cards{display:grid;gap:.8rem}.card{background:var(--card);border:1px solid var(--border);
border-radius:8px;padding:.8rem 1rem}.card .t{font-weight:600}.card .d{color:var(--muted);font-size:.9rem}
.gen{color:var(--muted);font-size:.8rem}
"""

GEN_BANNER = "<!-- GENERATED by tools/okf_render.py from docs/knowledge/ — DO NOT EDIT. -->"


def page(title, badge_type, meta_html, body_html, depth):
    up = "../" * depth
    badge = ""
    if badge_type:
        color = TYPE_COLOR.get(badge_type, "#8a8f98")
        badge = '<span class="badge" style="background:%s">%s</span> ' % (color, html.escape(badge_type))
    return "\n".join([
        "<!doctype html><html lang=en><head><meta charset=utf-8>",
        '<meta name=viewport content="width=device-width,initial-scale=1">',
        "<title>%s — ragent</title>" % html.escape(title),
        "<style>%s</style></head><body>" % CSS,
        GEN_BANNER,
        '<div class="wrap">',
        '<div class="nav">%s<a href="%sindex.html">knowledge index</a> · '
        '<a href="%sgraph.html">graph</a></div>' % (badge, up, up),
        meta_html,
        body_html,
        '<div class="footer">Generated from <code>docs/knowledge/</code> by '
        "<code>tools/okf_render.py</code>. Markdown is the source of truth; do not edit this file.</div>",
        "</div></body></html>",
    ])


def meta_block(meta):
    rows = []
    for k in ("id", "type", "status", "date", "timestamp", "description"):
        if meta.get(k):
            rows.append('<div><span class="k">%s</span>%s</div>' % (k, html.escape(str(meta[k]))))
    tags = meta.get("tags") or []
    if tags:
        rows.append('<div class="tags"><span class="k" style="background:none">tags</span>'
                    + "".join("<span>%s</span>" % html.escape(str(t)) for t in tags) + "</div>")
    return '<div class="meta">%s</div>' % "".join(rows) if rows else ""


# --------------------------------------------------------------------------- #
# Build                                                                        #
# --------------------------------------------------------------------------- #
def main():
    if not SRC.exists():
        print("no knowledge bundle at %s" % SRC, file=sys.stderr)
        return 1
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)

    concepts = []          # list of dicts
    by_id = {}             # node_id -> concept
    for path in sorted(SRC.rglob("*.md")):
        rel = path.relative_to(SRC).as_posix()
        node_id = rel[:-3]
        text = path.read_text(encoding="utf-8")
        meta, body = parse_frontmatter(text)
        c = {
            "rel": rel, "node_id": node_id, "meta": meta, "body": body,
            "type": meta.get("type", "concept"),
            "title": meta.get("title") or meta.get("id") or node_id,
            "depth": rel.count("/"),
        }
        concepts.append(c)
        by_id[node_id] = c

    # copy non-markdown assets verbatim (e.g. genesis-transcript.json)
    assets = 0
    for path in sorted(SRC.rglob("*")):
        if path.is_file() and path.suffix != ".md" and not path.name.startswith("."):
            dest = OUT / path.relative_to(SRC)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, dest)
            assets += 1

    # render pages + collect graph edges
    edges = set()
    for c in concepts:
        body_html = md_to_html(c["body"])
        html_doc = page(c["title"], c["type"], meta_block(c["meta"]), body_html, c["depth"])
        dest = OUT / (c["node_id"] + ".html")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(html_doc, encoding="utf-8")
        for href in re.findall(r"\]\(([^)]+)\)", c["body"]):
            tgt = _resolve(href, c["rel"])
            if tgt and tgt in by_id and tgt != c["node_id"]:
                edges.add((c["node_id"], tgt))

    write_index(concepts)
    write_graph(concepts, edges)

    print("Rendered %d concepts, %d assets, %d graph edges -> %s"
          % (len(concepts), assets, len(edges), OUT.relative_to(ROOT)))
    return 0


def _resolve(href, src_rel):
    base = href.split("#")[0]
    if not base or re.match(r"^(https?:|mailto:)", base) or not base.endswith(".md"):
        return None
    src_dir = posixpath.dirname(src_rel)
    return posixpath.normpath(posixpath.join(src_dir, base))[:-3]


def write_index(concepts):
    groups = {}
    for c in concepts:
        groups.setdefault(c["type"], []).append(c)
    parts = ["<h1>ragent knowledge bundle</h1>",
             '<p>Generated view of the <code>docs/knowledge/</code> OKF bundle. '
             '<a href="graph.html">Open the knowledge graph &rarr;</a></p>']
    counts = ", ".join("%d %s" % (len(v), k) for k, v in
                       sorted(groups.items(), key=lambda kv: TYPE_ORDER.index(kv[0]) if kv[0] in TYPE_ORDER else 99))
    parts.append('<p class="gen">%d concepts (%s).</p>' % (len(concepts), counts))
    for t in TYPE_ORDER:
        if t not in groups:
            continue
        parts.append('<h2>%s</h2><div class="cards">' % html.escape(t))
        for c in sorted(groups[t], key=lambda x: x["node_id"]):
            desc = html.escape(c["meta"].get("description", ""))
            parts.append('<div class="card"><div class="t"><a href="%s.html">%s</a></div>'
                         '<div class="d">%s</div></div>' % (c["node_id"], html.escape(c["title"]), desc))
        parts.append("</div>")
    doc = page("Knowledge bundle", None, "", "\n".join(parts), 0)
    (OUT / "index.html").write_text(doc, encoding="utf-8")


def write_graph(concepts, edges):
    nodes = [c for c in concepts if c["type"] != "index"]
    ids = {c["node_id"] for c in nodes}
    node_json = [{"id": c["node_id"], "label": c["meta"].get("id") or c["title"],
                  "type": c["type"], "url": c["node_id"] + ".html"} for c in nodes]
    edge_json = [{"s": s, "t": t} for (s, t) in sorted(edges) if s in ids and t in ids]
    data = json.dumps({"nodes": node_json, "edges": edge_json})
    legend = "".join('<span class="lg"><i style="background:%s"></i>%s</span>'
                     % (TYPE_COLOR.get(t, "#888"), t) for t in TYPE_ORDER if t != "index")
    doc = GRAPH_HTML.replace("__DATA__", data).replace("__CSS__", CSS).replace("__LEGEND__", legend)
    (OUT / "graph.html").write_text(doc, encoding="utf-8")


GRAPH_HTML = """<!doctype html><html lang=en><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Knowledge graph — ragent</title><style>__CSS__
.gwrap{max-width:1100px}.legend{margin:.5rem 0 1rem;font-size:.85rem;color:var(--muted)}
.legend .lg{margin-right:1rem;white-space:nowrap}
.legend i{display:inline-block;width:.8em;height:.8em;border-radius:50%;margin-right:.35em;vertical-align:middle}
#c{width:100%;height:70vh;border:1px solid var(--border);border-radius:10px;background:var(--card);touch-action:none}
</style></head><body>
<!-- GENERATED by tools/okf_render.py — DO NOT EDIT. -->
<div class="wrap gwrap">
<div class="nav"><a href="index.html">knowledge index</a> · graph</div>
<h1>Knowledge graph</h1>
<p class="gen">Nodes are concepts (colored by type); edges are the Markdown links between them. Drag to explore; click a node to open it.</p>
<div class="legend">__LEGEND__</div>
<canvas id="c"></canvas>
<div class="footer">Generated from <code>docs/knowledge/</code> by <code>tools/okf_render.py</code>.</div>
</div>
<script>
var DATA=__DATA__;
var COLOR={session:"#d98c3f",decision:"#4f9d69",component:"#5b8def",convention:"#a970d0",index:"#8a8f98"};
var canvas=document.getElementById("c"),ctx=canvas.getContext("2d");
var N=DATA.nodes,E=DATA.edges,idx={};N.forEach(function(n,i){idx[n.id]=i;n.x=Math.random()*600-300;n.y=Math.random()*400-200;n.vx=0;n.vy=0;});
var links=E.map(function(e){return {s:idx[e.s],t:idx[e.t]};});
var W,H,DPR=window.devicePixelRatio||1;
function resize(){W=canvas.clientWidth;H=canvas.clientHeight;canvas.width=W*DPR;canvas.height=H*DPR;ctx.setTransform(DPR,0,0,DPR,0,0);}
window.addEventListener("resize",resize);resize();
var deg={};links.forEach(function(l){deg[l.s]=(deg[l.s]||0)+1;deg[l.t]=(deg[l.t]||0)+1;});
function radius(i){return 6+Math.min(10,(deg[i]||0)*1.4);}
function step(){
 for(var i=0;i<N.length;i++)for(var j=i+1;j<N.length;j++){
  var a=N[i],b=N[j],dx=a.x-b.x,dy=a.y-b.y,d2=dx*dx+dy*dy+0.01,d=Math.sqrt(d2);
  var f=1600/d2;var fx=dx/d*f,fy=dy/d*f;a.vx+=fx;a.vy+=fy;b.vx-=fx;b.vy-=fy;}
 links.forEach(function(l){var a=N[l.s],b=N[l.t],dx=b.x-a.x,dy=b.y-a.y,d=Math.sqrt(dx*dx+dy*dy)+0.01;
  var f=(d-90)*0.015;var fx=dx/d*f,fy=dy/d*f;a.vx+=fx;a.vy+=fy;b.vx-=fx;b.vy-=fy;});
 for(var k=0;k<N.length;k++){var n=N[k];if(n===drag)continue;n.vx-=n.x*0.002;n.vy-=n.y*0.002;
  n.x+=Math.max(-8,Math.min(8,n.vx));n.y+=Math.max(-8,Math.min(8,n.vy));n.vx*=0.86;n.vy*=0.86;}
}
var ox,oy;function draw(){ox=W/2;oy=H/2;ctx.clearRect(0,0,W,H);
 ctx.strokeStyle=getComputedStyle(document.body).getPropertyValue("--border")||"#ccc";ctx.lineWidth=1;
 links.forEach(function(l){var a=N[l.s],b=N[l.t];ctx.beginPath();ctx.moveTo(a.x+ox,a.y+oy);ctx.lineTo(b.x+ox,b.y+oy);ctx.stroke();});
 ctx.font="11px -apple-system,Segoe UI,Roboto,sans-serif";ctx.textAlign="center";
 var fg=getComputedStyle(document.body).getPropertyValue("--fg")||"#111";
 N.forEach(function(n,i){ctx.beginPath();ctx.fillStyle=COLOR[n.type]||"#888";
  ctx.arc(n.x+ox,n.y+oy,radius(i),0,6.2832);ctx.fill();
  ctx.fillStyle=fg;ctx.fillText(n.label,n.x+ox,n.y+oy-radius(i)-3);});
}
var drag=null;function pos(ev){var r=canvas.getBoundingClientRect();var t=ev.touches?ev.touches[0]:ev;return {x:t.clientX-r.left-W/2,y:t.clientY-r.top-H/2};}
function hit(p){for(var i=N.length-1;i>=0;i--){var n=N[i],dx=n.x-p.x,dy=n.y-p.y;if(dx*dx+dy*dy<Math.pow(radius(i)+4,2))return n;}return null;}
canvas.addEventListener("mousedown",function(e){var n=hit(pos(e));if(n){drag=n;n.dragged=false;}});
window.addEventListener("mousemove",function(e){if(drag){var p=pos(e);drag.x=p.x;drag.y=p.y;drag.vx=drag.vy=0;drag.dragged=true;}});
window.addEventListener("mouseup",function(e){if(drag){if(!drag.dragged)location.href=drag.url;drag=null;}});
canvas.addEventListener("mousemove",function(e){canvas.style.cursor=hit(pos(e))?"pointer":"default";});
(function loop(){for(var s=0;s<2;s++)step();draw();requestAnimationFrame(loop);})();
</script></body></html>"""


if __name__ == "__main__":
    sys.exit(main())
