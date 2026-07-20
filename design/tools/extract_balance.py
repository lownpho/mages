#!/usr/bin/env python3
"""Extract shipped spell numbers from the game's `.tres` files into spells.yaml.

`design/data/spells.yaml` is the hand-written design source of truth — the words,
the fuzzy scales (range: med, cooldown: low). This tool adds the other half: the
*actual authored numbers*, read back out of `game/characters/player/spells/`, so
the design doc and the game can be compared without opening Godot.

Each spell in the yaml gains a machine-owned `balance:` block, one entry per
shipped tier, spliced between BEGIN/END markers. Everything else in the file —
comments, folded descriptions, order — is left byte-for-byte alone. Spells with
no `.tres` (design ideas, graveyard content) get no block, so the presence of
`balance:` is exactly the "is this shipped?" signal.

Run before build.py, which renders the numbers into design/docs/spells_balance.html:

    python3 design/tools/extract_balance.py
    python3 design/tools/build.py

--check exits non-zero if the yaml is out of date, without writing.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import yaml

import tres

ROOT = Path(__file__).resolve().parents[2]       # repo root
DATA = ROOT / "design" / "data"
GAME = ROOT / "game"
SPELL_DIR = GAME / "characters" / "player" / "spells"

BEGIN = "# BEGIN GENERATED BALANCE"
END = "# END GENERATED BALANCE"

# Fields carried by every ItemResource, reported as `grants` when non-zero.
STAT_MODIFIERS = ("skill", "speed", "max_health", "defence")


# --- GDScript defaults ------------------------------------------------------
# A `.tres` only stores properties that differ from the script default, so
# reading the numbers back means knowing those defaults. Parse them out of the
# scripts rather than hardcoding a table here, so the tool can't drift.

_CLASS_NAME = re.compile(r"^class_name\s+(\w+)", re.M)
_EXTENDS = re.compile(r"^extends\s+(\w+)", re.M)
_EXPORT = re.compile(
    r"^@export(?:_\w+)?(?:\([^)]*\))?\s+var\s+(\w+)\s*(?::\s*[\w\[\]., ]+?)?\s*"
    r"(?:=\s*(.+?))?\s*$",
    re.M,
)


def _literal(text: str):
    """A GDScript default expression -> Python value, or None if not a literal."""
    text = text.strip()
    if text in ("true", "false"):
        return text == "true"
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?\d*\.\d+", text):
        return float(text)
    if re.fullmatch(r"\[\s*\]", text) or re.fullmatch(r"Array\[\w+\]\(\[\s*\]\)", text):
        return []
    if text.startswith('"') and text.endswith('"'):
        return text[1:-1]
    return None  # null, Vector2(...), preload(...) — nothing a number reads


def scan_script_defaults() -> dict[str, dict]:
    """-> {ClassName: {"parent": str, "defaults": {field: value}}} for all of game/."""
    classes: dict[str, dict] = {}
    for path in GAME.rglob("*.gd"):
        text = path.read_text(errors="replace")
        m = _CLASS_NAME.search(text)
        if not m:
            continue
        parent = _EXTENDS.search(text)
        defaults = {}
        for field, expr in _EXPORT.findall(text):
            defaults[field] = _literal(expr) if expr else None
        classes[m.group(1)] = {
            "parent": parent.group(1) if parent else "",
            "defaults": defaults,
        }
    return classes


class Defaults:
    """Resolves a class's full default set, walking up the `extends` chain."""

    def __init__(self, classes: dict[str, dict]):
        self._classes = classes
        self._cache: dict[str, dict] = {}

    def for_class(self, name: str) -> dict:
        if name in self._cache:
            return self._cache[name]
        entry = self._classes.get(name)
        if not entry:
            return {}
        merged = dict(self.for_class(entry["parent"]))
        merged.update(entry["defaults"])
        self._cache[name] = merged
        return merged

    def get(self, block, field: str, fallback=None):
        """A property off a parsed block, falling back to the script default."""
        if block is None:
            return fallback
        if field in block:
            return block[field]
        value = self.for_class(getattr(block, "script_class", "")).get(field)
        return fallback if value is None else value


# --- shaping ----------------------------------------------------------------

def _num(value):
    """Trim float noise, and drop `.0` so the yaml reads like the .tres does."""
    if isinstance(value, float):
        value = round(value, 4)
        return int(value) if value == int(value) else value
    return value


def _flow(mapping: dict) -> dict:
    """Mark a leaf mapping to be dumped inline (`{a: 1, b: 2}`)."""
    return _Flow((k, _num(v)) for k, v in mapping.items())


class _Flow(dict):
    pass


yaml.add_representer(
    _Flow,
    lambda dumper, data: dumper.represent_mapping(
        "tag:yaml.org,2002:map", data, flow_style=True
    ),
)


def _amount(profile, d: Defaults) -> dict | None:
    """A ScalingProfile -> the four coefficients the damage formula uses."""
    if profile is None:
        return None
    return _flow(
        {
            "base": d.get(profile, "base_damage", 0),
            "skill": d.get(profile, "skill_scaling", 0),
            "speed": d.get(profile, "speed_scaling", 0),
            "defence": d.get(profile, "defence_scaling", 0),
        }
    )


def _pattern(pattern, d: Defaults) -> dict:
    """Fire pattern -> its name and how many bullets one shot puts out."""
    name = getattr(pattern, "script_class", "") or "SinglePattern"
    count = 1
    if pattern is not None:
        if "num_pellets" in pattern or name == "ShotgunPattern":
            count = d.get(pattern, "num_pellets", 1)
        elif "num_bullets" in pattern or name in ("RingPattern", "ParallelPattern"):
            count = d.get(pattern, "num_bullets", 1)
        elif name == "FlankPattern":
            count = 2
    info = {"pattern": name, "per_shot": count}
    if name == "ShotgunPattern":
        info["spread_deg"] = d.get(pattern, "spread_angle", 0)
    return info


def _behaviours(bullet, d: Defaults) -> list:
    """Bullet behaviours -> flat records; the template reads radius/bounces off these."""
    out = []
    for b in (bullet.get("behaviours") or []) if bullet is not None else []:
        name = getattr(b, "script_class", "")
        if name == "HomingBehaviour":
            out.append(_flow({
                "type": "homing",
                "turn_deg": d.get(b, "turn_deg", 0),
                "cone_deg": d.get(b, "cone_deg", 0),
                "range_tiles": d.get(b, "range_tiles", 0),
            }))
        elif name == "BlastPayload":
            out.append(_flow({
                "type": "blast",
                "radius_tiles": d.get(b, "radius_tiles", 0),
                "blast_only": d.get(b, "blast_only", False),
            }))
        elif name == "ChainBehaviour":
            out.append(_flow({
                "type": "chain",
                "bounces": d.get(b, "bounces", 0),
                "bounce_range_tiles": d.get(b, "bounce_range_tiles", 0),
            }))
        elif name:
            out.append(_flow({"type": name}))
    return out


def _cast_block(spell, d: Defaults) -> dict:
    """The bullet-spell half of a cast: pattern, burst, projectile, damage."""
    bullet = spell.get("bullet")
    out = {
        "shots": _flow({
            **_pattern(spell.get("fire_pattern"), d),
            "count": d.get(spell, "max_shots", 1),
            "interval": d.get(spell, "shot_interval", 0),
        }),
        "amount": _amount(spell.get("damage"), d),
    }
    if bullet is not None:
        out["projectile"] = _flow({
            "range_tiles": d.get(bullet, "range_tiles", 0),
            "speed_tiles": d.get(bullet, "speed_tiles", 0),
        })
    behaviours = _behaviours(bullet, d)
    if behaviours:
        out["behaviours"] = behaviours
    return out


def extract_tier(path: Path, d: Defaults) -> dict:
    """One shipped `<spell>N.tres` -> its balance record."""
    spell = tres.load(path)
    kind_by_class = {
        "BulletSpellResource": "bullet",
        "SummonResource": "summon",
        "HealResource": "heal",
        "NopeResource": "nope",
    }
    kind = kind_by_class.get(spell.script_class, "effect")

    entry: dict = {"tier": _tier_of(path.stem), "kind": kind}
    entry["source"] = str(path.relative_to(ROOT))
    entry["cooldown"] = _num(d.get(spell, "cooldown", 0))
    entry["cast_time"] = _num(d.get(spell, "cast_time", 0))
    entry["channeled"] = bool(d.get(spell, "channeled", False))

    grants = {
        stat: spell[f"{stat}_modifier"]
        for stat in STAT_MODIFIERS
        if spell.get(f"{stat}_modifier")
    }
    if grants:
        entry["grants"] = _flow(grants)

    if kind == "bullet":
        entry.update(_cast_block(spell, d))
    elif kind == "heal":
        entry["amount"] = _amount(spell.get("amount"), d)
    elif kind == "summon":
        minion = {
            "count": d.get(spell, "count", 0),
            "health": d.get(spell, "minion_health", 0),
            "lifetime": d.get(spell, "minion_lifetime", 0),
        }
        entry["minion"] = _flow(minion)
        weapon = spell.get("minion_spell")
        if weapon is not None:
            entry["minion_cast"] = {
                "cooldown": _num(d.get(weapon, "cooldown", 0)),
                **_cast_block(weapon, d),
            }
    elif kind == "nope":
        entry["absorb"] = d.get(spell, "absorb_amount", 0)

    return {k: v for k, v in entry.items() if v is not None}


def _tier_of(stem: str) -> int:
    m = re.search(r"(\d+)$", stem)
    return int(m.group(1)) if m else 1


def spell_dir_for(name: str) -> Path:
    return SPELL_DIR / name.lower().replace(" ", "_")


def extract_all(names: list[str], d: Defaults) -> dict[str, list]:
    """-> {spell name: [tier record, ...]} for every name that ships tiers."""
    out: dict[str, list] = {}
    for name in names:
        folder = spell_dir_for(name)
        if not folder.is_dir():
            continue
        stem = folder.name
        tiers = sorted(
            p for p in folder.glob("*.tres")
            if re.fullmatch(rf"{re.escape(stem)}\d*", p.stem)
        )
        records = [extract_tier(p, d) for p in tiers]
        if records:
            out[name] = sorted(records, key=lambda r: r["tier"])
    return out


# --- yaml splice ------------------------------------------------------------
# Surgical, line-based: the yaml is hand-written (comments, folded scalars) and
# must survive a round trip untouched, which a load/dump cycle would not.

def _render_block(records: list) -> list[str]:
    body = yaml.dump(
        records,
        sort_keys=False,
        default_flow_style=False,
        width=100,
        allow_unicode=True,
    )
    lines = [f"    {BEGIN}", "    balance:"]
    lines += [("      " + line).rstrip() for line in body.rstrip("\n").splitlines()]
    lines.append(f"    {END}")
    return lines


def _spell_spans(lines: list[str]) -> list[tuple[str, int, int]]:
    """-> [(spell name, first line, end line)] for entries of the `spells:` list."""
    spans: list[tuple[str, int, int]] = []
    in_spells = False
    start, name = None, None
    for i, line in enumerate(lines):
        if re.match(r"^spells:\s*$", line):
            in_spells = True
            continue
        if not in_spells:
            continue
        if line and not line[0].isspace():        # a new top-level key ends the list
            break
        m = re.match(r"^  - name:\s*(.+?)\s*$", line)
        if m:
            if start is not None:
                spans.append((name, start, i))
            start, name = i, m.group(1)
    if start is not None:
        spans.append((name, start, len(lines)))
    return spans


def splice(text: str, balance: dict[str, list]) -> str:
    lines = text.splitlines()
    # Back to front, so earlier spans keep their indices as we edit.
    for name, start, end in reversed(_spell_spans(lines)):
        body = lines[start:end]

        marked = [i for i, l in enumerate(body) if l.strip() in (BEGIN, END)]
        if len(marked) == 2:
            body = body[: marked[0]] + body[marked[1] + 1:]

        while body and not body[-1].strip():
            body.pop()

        if name in balance:
            body += _render_block(balance[name])
        body.append("")
        lines[start:end] = body

    return "\n".join(lines).rstrip("\n") + "\n"


def build(path: Path | None = None) -> str:
    path = path or (DATA / "spells.yaml")
    text = path.read_text()
    data = yaml.safe_load(text)
    names = [s["name"] for s in data["spells"]]

    d = Defaults(scan_script_defaults())
    balance = extract_all(names, d)

    # Lint: a shipped spell folder the design doesn't list is a doc gap.
    known = {spell_dir_for(n).name for n in names}
    for folder in sorted(SPELL_DIR.iterdir()):
        if folder.is_dir() and folder.name not in known and any(folder.glob("*.tres")):
            print(f"  warning: {folder.name}/ ships .tres but is not in spells.yaml")

    return splice(text, balance), balance


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="fail if spells.yaml is stale")
    args = ap.parse_args()

    path = DATA / "spells.yaml"
    updated, balance = build(path)
    tiers = sum(len(v) for v in balance.values())

    if args.check:
        if path.read_text() != updated:
            print("STALE (run design/tools/extract_balance.py): design/data/spells.yaml")
            return 1
        print("up to date")
        return 0

    path.write_text(updated)
    print(f"wrote design/data/spells.yaml — {tiers} tiers across {len(balance)} spells")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
