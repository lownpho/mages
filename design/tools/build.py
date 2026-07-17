#!/usr/bin/env python3
"""Render the design catalogues from their YAML sources of truth.

Reads the files in  design/data/  and writes the generated regions of the docs
plus a standalone interactive HTML design view per catalogue:
  - spells.yaml   -> design/docs/spells.md   + design/docs/spells.html
  - enemies.yaml  -> design/docs/enemies.md  + design/docs/enemies.html
  - biomes.yaml   -> design/docs/biomes.md   + design/docs/biomes.html
                     (per-enemy drops table and the enemies HTML pull drops from
                      enemies.yaml — one home per fact)

Each Markdown doc has a hand-written preamble and, at the end, a hand-written
"ideas" section; only the region between the GENERATED markers is machine-owned.

Usage:
    python3 design/tools/build.py [--check]

--check exits non-zero if any output is out of date (for CI / pre-commit),
without writing anything.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import yaml
from jinja2 import Environment, FileSystemLoader, select_autoescape

ROOT = Path(__file__).resolve().parents[1]          # design/
DATA = ROOT / "data"
DOCS = ROOT / "docs"
TEMPLATES = Path(__file__).resolve().parent

BEGIN = "<!-- BEGIN GENERATED CATALOGUE -->"
END = "<!-- END GENERATED CATALOGUE -->"


def _gen_note(source: str) -> str:
    return (
        f"<!-- Generated from design/data/{source} by design/tools/build.py "
        "— do not edit by hand. -->"
    )


def load(name: str) -> dict:
    with (DATA / name).open() as fh:
        return yaml.safe_load(fh)


def _clean(text: str) -> str:
    """Collapse a folded-scalar description to a single paragraph line."""
    return " ".join((text or "").split())


def _first_paragraph(text: str) -> str:
    """First paragraph of a literal markdown block, collapsed to one line.

    Enemy descriptions can carry a trailing bullet list (e.g. a boss's phases);
    the card view wants just the lead blurb, the full detail lives in the doc.
    """
    return _clean((text or "").strip().split("\n\n", 1)[0])


def inject(md_path: Path, catalogue: str) -> str:
    """Splice `catalogue` between the GENERATED markers of an existing doc."""
    src = md_path.read_text()
    if BEGIN not in src or END not in src:
        raise SystemExit(
            f"{md_path} is missing the generated-catalogue markers "
            f"({BEGIN!r} / {END!r})."
        )
    head = src[: src.index(BEGIN)]
    tail = src[src.index(END) + len(END):].lstrip("\n")
    # Blank line before any hand-written tail (e.g. the "---" / "# ideas" section)
    # so a bare "---" under the END comment can't read as a setext heading.
    sep = "\n\n" if tail else "\n"
    return head + catalogue.rstrip("\n") + sep + tail


# --- Spells -----------------------------------------------------------------

def spells_by_category(data: dict) -> list[tuple[dict, list[dict]]]:
    """Group the flat spell list under each category, in category order."""
    grouped = []
    for cat in data["categories"]:
        members = [s for s in data["spells"] if s["category"] == cat["id"]]
        grouped.append((cat, members))
    return grouped


def render_spells_md(data: dict) -> str:
    lines: list[str] = [BEGIN, _gen_note("spells.yaml"), ""]
    for cat, members in spells_by_category(data):
        lines.append(f"## {cat['name']}")
        lines.append("")
        lines.append(_clean(cat.get("description", "")))
        lines.append("")
        for sp in members:
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


def render_html(template_name: str, payload: dict) -> str:
    env = Environment(
        loader=FileSystemLoader(str(TEMPLATES)),
        autoescape=select_autoescape(["html"]),
    )
    tpl = env.get_template(template_name)
    # Embed as JSON; </ split so the blob can't close the <script> early.
    blob = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    return tpl.render(data_json=blob)


def render_spells_html(data: dict) -> str:
    cat_by_id = {c["id"]: c for c in data["categories"]}
    spells = []
    for sp in data["spells"]:
        cat = cat_by_id[sp["category"]]
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
    return render_html("spells.html.j2", payload)


# --- Enemies ----------------------------------------------------------------

def _roster_entry(entry) -> tuple[str, str | None]:
    """A roster entry is a bare name or a {name, sub_biome} mapping (bosses)."""
    if isinstance(entry, dict):
        return entry["name"], entry.get("sub_biome")
    return entry, None


def render_fsm(fsm: dict) -> list[str]:
    """Structured {start, transitions} -> mermaid stateDiagram-v2 lines."""
    out = ["stateDiagram-v2", f"    [*] --> {fsm['start']}"]
    for t in fsm["transitions"]:
        line = f"    {t['from']} --> {t['to']}"
        if t.get("when"):
            line += f" : {t['when']}"
        out.append(line)
    return out


def _enemy_suffix(enemy: dict, sub_biome: str | None = None) -> str:
    rarity = enemy.get("rarity", "common")
    if rarity == "rare":
        return " *(rare)*"
    if rarity == "boss":
        return f" *(boss, {sub_biome})*" if sub_biome else " *(boss)*"
    return ""


def render_enemies_md(enemies_data: dict, biomes_data: dict) -> str:
    by_name = {e["name"]: e for e in enemies_data["enemies"]}

    lines: list[str] = [BEGIN, _gen_note("enemies.yaml"), ""]
    for biome in biomes_data["biomes"]:
        lines.append(f"## {biome['name']}")
        lines.append("")
        lines.append(_clean(biome.get("enemies_intro", "")))
        lines.append("")
        for entry in biome.get("roster", []):
            name, sub_biome = _roster_entry(entry)
            e = by_name[name]
            lines.append(f"### {e['name']}{_enemy_suffix(e, sub_biome)}")
            lines.append("")
            lines.append(e["description"].rstrip("\n"))
            lines.append("")
            lines.append(f"**Art:** {e['art']}")
            lines.append("")
            drops = ", ".join(d["spell"] for d in e["drops"])
            rows = [
                ("HP", e["hp"]),
                ("Speed", e["speed"]),
                ("Detection", e["detection"]),
                ("Attack", e["attack"]),
                ("Casts", ", ".join(e["casts"])),
                ("Drops", f"**{drops}**"),
            ]
            lines.append("| Stat | |")
            lines.append("|---|---|")
            for label, value in rows:
                lines.append(f"| {label} | {value} |")
            lines.append("")
            if e.get("notes"):
                lines.append(f"**Notes:** {e['notes']}")
                lines.append("")
            lines.append("```mermaid")
            lines.extend(render_fsm(e["fsm"]))
            lines.append("```")
            lines.append("")
    lines.append(END)
    return "\n".join(lines).rstrip() + "\n"


# --- Biomes -----------------------------------------------------------------

def render_biomes_md(biomes_data: dict, enemies_data: dict) -> str:
    by_name = {e["name"]: e for e in enemies_data["enemies"]}

    lines: list[str] = [BEGIN, _gen_note("biomes.yaml"), ""]
    for biome in biomes_data["biomes"]:
        title = biome["name"]
        if biome.get("tier_label"):
            title += f" ({biome['tier_label']})"
        lines.append(f"## {title}")
        lines.append("")
        lines.append(_clean(biome.get("intro", "")))
        lines.append("")
        if biome.get("spawn_with"):
            spawn = ", ".join(f"**{item}**" for item in biome["spawn_with"])
            lines.append(f"Player spawns with: {spawn}.")
            lines.append("")
        if biome.get("notation"):
            lines.append(_clean(biome["notation"]))
            lines.append("")

        for sub in biome["sub_biomes"]:
            lines.append(f"### {sub['name']}")
            lines.append("")
            lines.append(_clean(sub.get("intro", "")))
            lines.append("")
            if sub.get("roster"):
                lines.append(f"Roster: {sub['roster']}")
                lines.append("")
            lines.append("| Tier | Room | Enemy group variations |")
            lines.append("|---|---|---|")
            for r in sub["rooms"]:
                lines.append(f"| {r['tier']} | {r['room']} | {r['groups']} |")
            lines.append("")
            if sub.get("drops"):
                lines.append(f"Drops: {', '.join(sub['drops'])}.")
                lines.append("")

        # Per-enemy drops table — each enemy looked up in enemies.yaml (its drops
        # live there, one home per fact); this biome's roster gives the rows.
        roster = biome.get("roster")
        if roster:
            lines.append(f"### {biome['name']} drops")
            lines.append("")
            lines.append("| Enemy | Items dropped |")
            lines.append("|---|---|")
            for entry in roster:
                name, _sub = _roster_entry(entry)
                e = by_name[name]
                items = ", ".join(
                    f"{d['spell'].lower()} t{d['tier']}" for d in e["drops"]
                )
                lines.append(f"| {e['name']}{_enemy_suffix_flat(e)} | {items} |")
            lines.append("")
    lines.append(END)
    return "\n".join(lines).rstrip() + "\n"


def _enemy_suffix_flat(enemy: dict) -> str:
    """Rarity suffix without the boss's sub-biome — used in the flat drops table."""
    rarity = enemy.get("rarity", "common")
    if rarity == "rare":
        return " *(rare)*"
    if rarity == "boss":
        return " *(boss)*"
    return ""


# --- HTML design views (enemies, biomes) ------------------------------------

def render_enemies_html(enemies_data: dict, biomes_data: dict) -> str:
    # Which biomes list each enemy (an enemy can belong to several).
    membership: dict[str, list[dict]] = {}
    biome_order = [b["name"] for b in biomes_data["biomes"]]
    for biome in biomes_data["biomes"]:
        for entry in biome.get("roster", []):
            name, sub = _roster_entry(entry)
            membership.setdefault(name, []).append(
                {"biome": biome["name"], "sub_biome": sub}
            )

    enemies = []
    for e in enemies_data["enemies"]:
        mem = membership.get(e["name"], [])
        biomes = sorted({m["biome"] for m in mem}, key=biome_order.index)
        sub = next((m["sub_biome"] for m in mem if m["sub_biome"]), None)
        enemies.append(
            {
                "name": e["name"],
                "rarity": e.get("rarity", "common"),
                "biomes": biomes,
                "sub_biome": sub,
                "description": _first_paragraph(e["description"]),
                "hp": e["hp"],
                "speed": e["speed"],
                "detection": e["detection"],
                "attack": e["attack"],
                "casts": e["casts"],
                "drops": [{"spell": d["spell"], "tier": d["tier"]} for d in e["drops"]],
                "notes": e.get("notes", ""),
            }
        )

    payload = {
        "enemies": enemies,
        "biome_order": biome_order,
        "ordered": {
            "hp": ["very low", "low", "med", "high", "very high"],
            "detection": ["short", "med", "long"],
            "rarity": ["common", "rare", "boss"],
        },
    }
    return render_html("enemies.html.j2", payload)


def render_biomes_html(biomes_data: dict) -> str:
    biome_order = [b["name"] for b in biomes_data["biomes"]]
    tiers: set[str] = set()
    rooms = []
    for biome in biomes_data["biomes"]:
        for sub in biome["sub_biomes"]:
            for r in sub["rooms"]:
                tiers.add(r["tier"])
                variations = [v.strip() for v in r["groups"].split("·")]
                rooms.append(
                    {
                        "biome": biome["name"],
                        "sub_biome": sub["name"],
                        "tier": r["tier"],
                        "room": r["room"],
                        "groups": r["groups"],
                        "variations": variations,
                    }
                )
    payload = {
        "rooms": rooms,
        "biome_order": biome_order,
        "ordered": {"tier": sorted(tiers)},
    }
    return render_html("biomes.html.j2", payload)


# --- Driver -----------------------------------------------------------------

def build() -> dict[Path, str]:
    spells = load("spells.yaml")
    enemies = load("enemies.yaml")
    biomes = load("biomes.yaml")

    spells_md = DOCS / "spells.md"
    spells_html = DOCS / "spells.html"
    enemies_md = DOCS / "enemies.md"
    enemies_html = DOCS / "enemies.html"
    biomes_md = DOCS / "biomes.md"
    biomes_html = DOCS / "biomes.html"

    return {
        spells_md: inject(spells_md, render_spells_md(spells)),
        spells_html: render_spells_html(spells),
        enemies_md: inject(enemies_md, render_enemies_md(enemies, biomes)),
        enemies_html: render_enemies_html(enemies, biomes),
        biomes_md: inject(biomes_md, render_biomes_md(biomes, enemies)),
        biomes_html: render_biomes_html(biomes),
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="fail if outputs are stale")
    args = ap.parse_args()

    outputs = build()

    if args.check:
        stale = [
            str(path.relative_to(ROOT.parent))
            for path, content in outputs.items()
            if not path.exists() or path.read_text() != content
        ]
        if stale:
            print("STALE (run design/tools/build.py):", ", ".join(sorted(stale)))
            return 1
        print("up to date")
        return 0

    for path, content in outputs.items():
        path.write_text(content)
        print(f"wrote {path.relative_to(ROOT.parent)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
