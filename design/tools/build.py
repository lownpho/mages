#!/usr/bin/env python3
"""Render the spell catalogue from its YAML source of truth.

Reads  design/data/spells.yaml  and writes:
  - design/docs/spells.md    (fills the region between the GENERATED markers)
  - design/docs/spells.html  (interactive filter/search/sort design view)

Usage:
    python3 design/tools/build.py [--check]

--check exits non-zero if either output is out of date (for CI / pre-commit),
without writing anything.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, select_autoescape

ROOT = Path(__file__).resolve().parents[1]          # design/
DATA = ROOT / "data" / "spells.yaml"
DOCS = ROOT / "docs"
MD_OUT = DOCS / "spells.md"
HTML_OUT = DOCS / "spells.html"
TEMPLATES = Path(__file__).resolve().parent

BEGIN = "<!-- BEGIN GENERATED CATALOGUE -->"
END = "<!-- END GENERATED CATALOGUE -->"
GEN_NOTE = (
    "<!-- Generated from design/data/spells.yaml by design/tools/build.py "
    "— do not edit by hand. -->"
)


def load() -> dict:
    with DATA.open() as fh:
        return yaml.safe_load(fh)


def _clean(text: str) -> str:
    """Collapse a folded-scalar description to a single paragraph line."""
    return " ".join((text or "").split())


# --- Markdown ---------------------------------------------------------------

def render_markdown(data: dict) -> str:
    lines: list[str] = [BEGIN, GEN_NOTE, ""]
    for cat in data["categories"]:
        lines.append(f"## {cat['name']}")
        lines.append("")
        lines.append(_clean(cat.get("description", "")))
        lines.append("")
        for sp in cat["spells"]:
            lines.append(f"### {sp['name']}")
            lines.append("")
            lines.append(_clean(sp["description"]))
            lines.append("")
            rows = [
                ("Scaling", sp["scaling"]),
                ("Grants", ", ".join(sp["grants"])),
                ("Range", sp["range"]),
                ("Cooldown", sp["cooldown"]),
                ("Cast time", sp["cast_time"]),
                ("Hold", sp["hold"]),
            ]
            if sp.get("per_tier"):
                rows.append(("Per tier", sp["per_tier"]))
            lines.append("| | |")
            lines.append("|---|---|")
            for label, value in rows:
                lines.append(f"| {label} | {value} |")
            lines.append("")
    lines.append(END)
    return "\n".join(lines).rstrip() + "\n"


def inject_markdown(catalogue: str) -> str:
    src = MD_OUT.read_text()
    if BEGIN not in src or END not in src:
        raise SystemExit(
            f"{MD_OUT} is missing the generated-catalogue markers "
            f"({BEGIN!r} / {END!r})."
        )
    head = src[: src.index(BEGIN)]
    tail = src[src.index(END) + len(END):]
    return head + catalogue.rstrip("\n") + "\n" + tail.lstrip("\n")


# --- HTML -------------------------------------------------------------------

def render_html(data: dict) -> str:
    # Flatten to a list of spell dicts carrying their category, for the JS.
    spells = []
    for cat in data["categories"]:
        for sp in cat["spells"]:
            spells.append(
                {
                    "name": sp["name"],
                    "category": cat["name"],
                    "category_id": cat["id"],
                    "description": _clean(sp["description"]),
                    "scaling": sp["scaling"],
                    "grants": sp["grants"],
                    "range": sp["range"],
                    "cooldown": sp["cooldown"],
                    "cast_time": sp["cast_time"],
                    "hold": sp["hold"],
                    "per_tier": sp.get("per_tier") or "",
                }
            )
    payload = {
        "spells": spells,
        "ordered_scales": data["ordered_scales"],
        "holds": data["holds"],
        "categories": [
            {"id": c["id"], "name": c["name"], "description": _clean(c.get("description", ""))}
            for c in data["categories"]
        ],
    }
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES)),
        autoescape=select_autoescape(["html"]),
    )
    tpl = env.get_template("spells.html.j2")
    # Embed as JSON; </ split so the blob can't close the <script> early.
    blob = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    return tpl.render(data_json=blob)


# --- Driver -----------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="fail if outputs are stale")
    args = ap.parse_args()

    data = load()
    new_md = inject_markdown(render_markdown(data))
    new_html = render_html(data)

    if args.check:
        stale = []
        if MD_OUT.read_text() != new_md:
            stale.append(str(MD_OUT.relative_to(ROOT.parent)))
        if not HTML_OUT.exists() or HTML_OUT.read_text() != new_html:
            stale.append(str(HTML_OUT.relative_to(ROOT.parent)))
        if stale:
            print("STALE (run design/tools/build.py):", ", ".join(stale))
            return 1
        print("up to date")
        return 0

    MD_OUT.write_text(new_md)
    HTML_OUT.write_text(new_html)
    print(f"wrote {MD_OUT.relative_to(ROOT.parent)}")
    print(f"wrote {HTML_OUT.relative_to(ROOT.parent)}")
    print(f"  {sum(len(c['spells']) for c in data['categories'])} spells "
          f"in {len(data['categories'])} categories")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
