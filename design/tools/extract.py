#!/usr/bin/env python3
"""Read the game's authored numbers out of its `.tres` / `.tscn` files.

Every number in the design docs comes from here, never from the yaml: HP, drop
chances, cast damage, spell tiers, room spawn tables, the starter kit. The yaml
holds only what no resource can tell us — the words and the judgement calls.

`build.py` imports this module; there is no intermediate file and no ordering
rule. Run it directly to eyeball what it sees:

    python3 design/tools/extract.py            # a summary
    python3 design/tools/extract.py --json     # the whole payload

Pure Python (via tres.py) on purpose — it stays runnable without Godot, so it
works in worktrees and while the editor holds the asset-import lock.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import tres

ROOT = Path(__file__).resolve().parents[2]       # repo root
GAME = ROOT / "game"
SPELL_DIR = GAME / "characters" / "player" / "spells"
ENEMY_DIR = GAME / "characters" / "enemies"
CONTENT_DIR = GAME / "world_content"
WORLD_SCENE = GAME / "scenes" / "world.gd"

PX_PER_TILE = 8      # globals/game_constants.gd — everything authored in px converts

# Fields carried by every ItemResource, reported as `grants` when non-zero.
STAT_MODIFIERS = ("skill", "speed", "max_health", "defence")

RARITIES = ("common", "rare", "boss")            # CreatureResource.Rarity order


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
    """-> {ClassName: {"parent": str, "defaults": {field: value}}} for all of game/.

    Also keyed by `res://` path, so a scene node's `script = ExtResource(...)`
    resolves even when the script declares no `class_name` (the behaviours).
    """
    classes: dict[str, dict] = {}
    for path in GAME.rglob("*.gd"):
        text = path.read_text(errors="replace")
        parent = _EXTENDS.search(text)
        defaults = {}
        for field, expr in _EXPORT.findall(text):
            defaults[field] = _literal(expr) if expr else None
        entry = {"parent": parent.group(1) if parent else "", "defaults": defaults}

        m = _CLASS_NAME.search(text)
        if m:
            classes[m.group(1)] = entry
        classes["res://" + str(path.relative_to(GAME))] = entry
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
    """Trim float noise, and drop `.0` so a number reads the way it was authored."""
    if isinstance(value, float):
        value = round(value, 4)
        return int(value) if value == int(value) else value
    return value


def _amount(profile, d: Defaults) -> dict | None:
    """A ScalingProfile -> the four coefficients the damage formula uses."""
    if profile is None:
        return None
    return {
        "base": _num(d.get(profile, "base_damage", 0)),
        "skill": _num(d.get(profile, "skill_scaling", 0)),
        "speed": _num(d.get(profile, "speed_scaling", 0)),
        "defence": _num(d.get(profile, "defence_scaling", 0)),
    }


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
        info["spread_deg"] = _num(d.get(pattern, "spread_angle", 0))
    return info


def _behaviours(bullet, d: Defaults) -> list:
    """Bullet behaviours -> flat records; the pages read radius/bounces off these."""
    out = []
    for b in (bullet.get("behaviours") or []) if bullet is not None else []:
        name = getattr(b, "script_class", "")
        if name == "HomingBehaviour":
            out.append({
                "type": "homing",
                "turn_deg": _num(d.get(b, "turn_deg", 0)),
                "cone_deg": _num(d.get(b, "cone_deg", 0)),
                "range_tiles": _num(d.get(b, "range_tiles", 0)),
            })
        elif name == "BlastPayload":
            out.append({
                "type": "blast",
                "radius_tiles": _num(d.get(b, "radius_tiles", 0)),
                "blast_only": bool(d.get(b, "blast_only", False)),
            })
        elif name == "ChainBehaviour":
            out.append({
                "type": "chain",
                "bounces": _num(d.get(b, "bounces", 0)),
                "bounce_range_tiles": _num(d.get(b, "bounce_range_tiles", 0)),
            })
        elif name:
            out.append({"type": name})
    return out


def _cast_block(spell, d: Defaults) -> dict:
    """The bullet-spell half of a cast: pattern, burst, projectile, damage."""
    bullet = spell.get("bullet")
    out = {
        "shots": {
            **_pattern(spell.get("fire_pattern"), d),
            "count": _num(d.get(spell, "max_shots", 1)),
            "interval": _num(d.get(spell, "shot_interval", 0)),
        },
        "amount": _amount(spell.get("damage"), d),
    }
    if bullet is not None:
        out["projectile"] = {
            "range_tiles": _num(d.get(bullet, "range_tiles", 0)),
            "speed_tiles": _num(d.get(bullet, "speed_tiles", 0)),
            "pierce": bool(d.get(bullet, "pierce", False)),
        }
    behaviours = _behaviours(bullet, d)
    if behaviours:
        out["behaviours"] = behaviours
    return out


KIND_BY_CLASS = {
    "BulletSpellResource": "bullet",
    "ChargeDashResource": "bullet",     # extends BulletSpellResource — same fields
    "SummonResource": "summon",
    "HealResource": "heal",
    "NopeResource": "nope",
}


def _spell_record(spell, d: Defaults) -> dict:
    """Any cast `.tres` -> its numbers. Shared by player tiers and enemy casts."""
    kind = KIND_BY_CLASS.get(spell.script_class, "effect")

    entry: dict = {
        "kind": kind,
        "cooldown": _num(d.get(spell, "cooldown", 0)),
        "cast_time": _num(d.get(spell, "cast_time", 0)),
        "channeled": bool(d.get(spell, "channeled", False)),
    }

    grants = {
        stat: spell[f"{stat}_modifier"]
        for stat in STAT_MODIFIERS
        if spell.get(f"{stat}_modifier")
    }
    if grants:
        entry["grants"] = grants

    if kind == "bullet":
        entry.update(_cast_block(spell, d))
        if spell.script_class == "ChargeDashResource":
            entry["dash"] = {
                "speed_px": _num(d.get(spell, "dash_speed", 0)),
                "duration": _num(d.get(spell, "dash_duration", 0)),
            }
    elif kind == "heal":
        entry["amount"] = _amount(spell.get("amount"), d)
    elif kind == "summon":
        entry["minion"] = {
            "count": _num(d.get(spell, "count", 0)),
            "health": _num(d.get(spell, "minion_health", 0)),
            "lifetime": _num(d.get(spell, "minion_lifetime", 0)),
        }
        weapon = spell.get("minion_spell")
        if weapon is not None:
            entry["minion_cast"] = {
                "cooldown": _num(d.get(weapon, "cooldown", 0)),
                **_cast_block(weapon, d),
            }
    elif kind == "nope":
        entry["absorb"] = _num(d.get(spell, "absorb_amount", 0))
    elif spell.get("damage") is not None:
        # Bespoke families (Bwoom, Thwomp) hold a plain ScalingProfile.
        entry["amount"] = _amount(spell.get("damage"), d)

    return {k: v for k, v in entry.items() if v is not None}


# --- spells -----------------------------------------------------------------

def _tier_of(stem: str) -> int:
    m = re.search(r"(\d+)$", stem)
    return int(m.group(1)) if m else 1


def spell_tiers(d: Defaults) -> dict[str, list]:
    """-> {spell id: [tier record, ...]} for every shipped spell folder."""
    out: dict[str, list] = {}
    for folder in sorted(SPELL_DIR.iterdir()):
        if not folder.is_dir():
            continue
        stem = folder.name
        tiers = sorted(
            p for p in folder.glob("*.tres")
            if re.fullmatch(rf"{re.escape(stem)}\d*", p.stem)
        )
        records = [
            {
                "tier": _tier_of(p.stem),
                "source": str(p.relative_to(ROOT)),
                **_spell_record(tres.load(p), d),
            }
            for p in tiers
        ]
        if records:
            out[stem] = sorted(records, key=lambda r: r["tier"])
    return out


# --- enemies ----------------------------------------------------------------
# An enemy's numbers are split across its folder: scalars and loot in
# `<id>_data.tres`, and one bespoke spell `.tres` per attack beside it.

def _scene_numbers(path: Path, d: Defaults) -> dict:
    """The scene's own balance dials: how fast it moves, how far it sees."""
    if not path.is_file():
        return {}
    nodes = tres.load_scene(path)

    # Movement speed is per-behaviour (wander dawdles, flee bolts); the fastest
    # beat is the one the player has to outrun.
    speeds = [
        n.get("speed", d.for_class(n.script).get("speed"))
        for n in nodes
        if n.script and "speed" in d.for_class(n.script)
    ]
    speeds = [s for s in speeds if s]

    # Probes are RayCast2Ds pointing along +x; their length is the range in tiles.
    probes = {}
    for n in nodes:
        reach = n.get("target_position")
        if n.script_class == "RayCast2D" and reach is not None:
            key = n.name[: -len("Probe")] if n.name.endswith("Probe") else n.name
            probes[key.lower()] = _num(reach.args[0] / PX_PER_TILE)

    out: dict = {}
    if speeds:
        out["speed_px"] = _num(max(speeds))      # authored in px/s, reported as authored
    if probes:
        out["probes"] = probes
    return out


def _drop(drop, d: Defaults) -> dict:
    """A LootDrop -> the spell tier it hands out. `pew1` -> pew t1, `nope` -> nope."""
    stem = Path(drop.get("item") or "").stem
    spell = re.sub(r"\d+$", "", stem)
    return {
        "item": stem,
        "spell": spell,
        "tier": _tier_of(stem) if spell != stem else None,
        "chance": _num(d.get(drop, "chance", 1)),
    }


def _icon(icon) -> dict | None:
    """A Texture2D export -> what a page needs to draw it.

    Icons are usually an AtlasTexture cut out of a shared sheet, so the region
    travels with the path; a plain texture reference has no region.
    """
    if icon is None:
        return None
    if isinstance(icon, str):
        return {"path": icon}
    region = icon.get("region")
    return {
        "path": icon.get("atlas") or "",
        "region": [_num(a) for a in region.args] if region is not None else None,
    }


def enemies(d: Defaults) -> dict[str, dict]:
    """-> {enemy id: record} for every built `characters/enemies/<id>/`."""
    out: dict[str, dict] = {}
    for folder in sorted(ENEMY_DIR.iterdir()):
        data_path = folder / f"{folder.name}_data.tres"
        if not folder.is_dir() or not data_path.is_file():
            continue
        data = tres.load(data_path)

        entry: dict = {
            "source": str(data_path.relative_to(ROOT)),
            "name": d.get(data, "display_name", "") or folder.name.replace("_", " "),
            "rarity": RARITIES[_num(d.get(data, "rarity", 0))],
            "max_health": _num(d.get(data, "max_health", 0)),
            "icon": _icon(data.get("icon")),
            **_scene_numbers(folder / f"{folder.name}.tscn", d),
        }
        entry["drops"] = [_drop(x, d) for x in (data.get("drops") or [])]
        entry["attacks"] = [
            {"cast": p.stem, **_spell_record(tres.load(p), d)}
            for p in sorted(folder.glob("*.tres"))
            if p != data_path
        ]
        out[folder.name] = entry
    return out


# --- biomes & rooms ---------------------------------------------------------
# The room table the design doc shows IS the shipped spawn pool: one entry per
# weighted variation the generator may roll, each a list of {enemy, min, max}.
# Single-type entries and mixed packs collapse to that one shape here, so no
# consumer has to know the difference.

GENERATORS = {
    "GeneratorScatter": "scatter",
    "GeneratorCave": "cave",
    "GeneratorArena": "arena",
}


def _variation(entry, d: Defaults) -> dict:
    members = entry.get("members") or []
    if members:
        picks = [
            {
                "enemy": str(m.get("enemy_id") or ""),
                "min": _num(d.get(m, "count_min", 1)),
                "max": _num(d.get(m, "count_max", 1)),
            }
            for m in members
        ]
    else:
        picks = [{
            "enemy": str(entry.get("enemy_id") or ""),
            "min": _num(d.get(entry, "group_min", 1)),
            "max": _num(d.get(entry, "group_max", 1)),
        }]
    return {"weight": _num(d.get(entry, "weight", 1)), "members": picks}


def _room(path: Path, d: Defaults) -> dict:
    r = tres.load(path)
    gen = r.get("generator")
    return {
        "id": str(r.get("id") or path.stem),
        "biome": str(r.get("biome") or ""),
        "source": str(path.relative_to(ROOT)),
        "difficulty": _num(d.get(r, "difficulty", 0)),
        "generator": GENERATORS.get(getattr(gen, "script_class", ""), "empty"),
        "footprint_blob": bool(d.get(r, "footprint_blob", False)),
        "weight": _num(d.get(r, "weight", 1)),
        "min_per_biome": _num(d.get(r, "min_per_biome", 0)),
        "max_per_biome": _num(d.get(r, "max_per_biome", 99)),
        "groups_min": _num(d.get(r, "enemy_groups_min", 0)),
        "groups_max": _num(d.get(r, "enemy_groups_max", 0)),
        "scale_with_size": bool(d.get(r, "scale_groups_with_size", True)),
        "features": [
            Path(f.get("scene") or "").stem for f in (r.get("features") or [])
        ],
        # Empty stays empty: a room with no pool spawns nothing, and the docs say so.
        "variations": [_variation(e, d) for e in (r.get("enemies") or [])],
    }


def biomes(d: Defaults) -> dict[str, dict]:
    """-> {biome id: def + its room types}, rooms ordered by difficulty then id."""
    out: dict[str, dict] = {}
    rooms: list[dict] = []
    for path in sorted(CONTENT_DIR.rglob("*.tres")):
        block = tres.load(path)
        if block.script_class == "BiomeDef":
            out[str(block.get("id"))] = {
                "id": str(block.get("id")),
                "source": str(path.relative_to(ROOT)),
                "family": str(block.get("family") or ""),
                "size_cells": list(block["size_cells"].args) if block.get("size_cells") else [1, 1],
                "fallback_room_type": str(block.get("fallback_room_type") or ""),
                "rooms": [],
            }
        elif block.script_class == "RoomTypeDef":
            rooms.append(_room(path, d))

    for room in sorted(rooms, key=lambda r: (r["difficulty"], r["id"])):
        if room["biome"] in out:
            out[room["biome"]]["rooms"].append(room)
    return out


# --- the starter kit --------------------------------------------------------

def starter_kit() -> list[str]:
    """world.gd's STARTER_SPELLS -> the tier stems the player begins with."""
    text = WORLD_SCENE.read_text()
    block = re.search(r"STARTER_SPELLS[^=]*=\s*\[(.*?)\n\]", text, re.S)
    return re.findall(r'preload\("res://.*?/(\w+)\.tres"\)', block.group(1)) if block else []


# --- driver -----------------------------------------------------------------

def extract() -> dict:
    """Everything the game knows about itself, keyed on game ids."""
    d = Defaults(scan_script_defaults())
    return {
        "spells": spell_tiers(d),
        "enemies": enemies(d),
        "biomes": biomes(d),
        "starter_kit": starter_kit(),
    }


def main() -> int:
    import argparse

    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true", help="dump the whole payload")
    args = ap.parse_args()

    data = extract()
    if args.json:
        print(json.dumps(data, indent=2))
        return 0

    tiers = sum(len(v) for v in data["spells"].values())
    casts = sum(len(e["attacks"]) for e in data["enemies"].values())
    rooms = sum(len(b["rooms"]) for b in data["biomes"].values())
    print(f"{len(data['spells'])} spells ({tiers} tiers), "
          f"{len(data['enemies'])} enemies ({casts} casts), "
          f"{len(data['biomes'])} biomes ({rooms} room types)")
    print(f"starter kit: {', '.join(data['starter_kit'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
