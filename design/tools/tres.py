"""Minimal reader for Godot `.tres` resource files.

Enough of the format to read authored data back out of the game: the header,
`[ext_resource]` / `[sub_resource]` blocks, the `[resource]` body, and the
value grammar those use (numbers, bools, strings, `SubResource("id")`,
`ExtResource("id")`, `Rect2(...)`, `Array[T]([...])`).

Pure Python on purpose — the design tooling stays runnable without Godot, so it
works in worktrees and while the editor holds the asset-import lock.

    res = load(Path("game/characters/player/spells/pew/pew1.tres"))
    res.script_class        # "BulletSpellResource"
    res["cooldown"]         # 1.2
    res["bullet"]["range_tiles"]   # 8 — sub-resources resolve inline
"""

from __future__ import annotations

import re
from pathlib import Path

_SECTION = re.compile(r"^\[(\w+)([^\]]*)\]\s*$")
_ATTR = re.compile(r'(\w+)="([^"]*)"')
_IDENT = re.compile(r"[A-Za-z_]\w*")
_NUMBER = re.compile(r"-?\d+\.?\d*(?:e-?\d+)?")


class Ref:
    """An unresolved `SubResource`/`ExtResource` pointer."""

    __slots__ = ("kind", "id")

    def __init__(self, kind: str, id_: str):
        self.kind = kind
        self.id = id_


class Call:
    """A constructor-shaped value, e.g. `Rect2(0, 8, 8, 8)`."""

    __slots__ = ("name", "args")

    def __init__(self, name: str, args: list):
        self.name = name
        self.args = args


class Block(dict):
    """One `[...]` block's properties, plus the class it was authored as."""

    def __init__(self, script_class: str = "", **kw):
        super().__init__(**kw)
        self.script_class = script_class


# --- value grammar ----------------------------------------------------------

def _skip_ws(s: str, i: int) -> int:
    while i < len(s) and s[i] in " \t\r\n":
        i += 1
    return i


def _parse_value(s: str, i: int):
    i = _skip_ws(s, i)
    if i >= len(s):
        return None, i

    c = s[i]
    if c == '"':
        j = i + 1
        out = []
        while j < len(s) and s[j] != '"':
            if s[j] == "\\":
                j += 1
            out.append(s[j])
            j += 1
        return "".join(out), j + 1

    if c == "[":
        return _parse_list(s, i + 1, "]")

    if c == "{":  # dictionaries are rare here, but cheap to support
        i += 1
        out = {}
        while True:
            i = _skip_ws(s, i)
            if i >= len(s) or s[i] == "}":
                return out, i + 1
            key, i = _parse_value(s, i)
            i = _skip_ws(s, i)
            if i < len(s) and s[i] == ":":
                i += 1
            val, i = _parse_value(s, i)
            out[key] = val
            i = _skip_ws(s, i)
            if i < len(s) and s[i] == ",":
                i += 1

    if c == "&":  # StringName literal
        return _parse_value(s, i + 1)

    m = _IDENT.match(s, i)
    if m:
        name = m.group(0)
        i = m.end()
        if name == "true":
            return True, i
        if name == "false":
            return False, i
        if name in ("null", "nan"):
            return None, i

        # Typed array: `Array[ExtResource("x")]([ ... ])` — the element type is
        # bookkeeping, the payload is the parenthesised list.
        if i < len(s) and s[i] == "[":
            depth, j = 1, i + 1
            while j < len(s) and depth:
                depth += (s[j] == "[") - (s[j] == "]")
                j += 1
            i = j

        if i < len(s) and s[i] == "(":
            args, i = _parse_list(s, i + 1, ")")
            if name == "SubResource":
                return Ref("sub", args[0]), i
            if name == "ExtResource":
                return Ref("ext", args[0]), i
            if name == "Array" and len(args) == 1 and isinstance(args[0], list):
                return args[0], i
            return Call(name, args), i
        return name, i

    m = _NUMBER.match(s, i)
    if m:
        text = m.group(0)
        num = float(text) if ("." in text or "e" in text) else int(text)
        return num, m.end()

    return None, i + 1  # unrecognised byte — skip it rather than blow up


def _parse_list(s: str, i: int, close: str):
    out = []
    while True:
        i = _skip_ws(s, i)
        if i >= len(s):
            return out, i
        if s[i] == close:
            return out, i + 1
        if s[i] == ",":
            i += 1
            continue
        val, i = _parse_value(s, i)
        out.append(val)


# --- file structure ---------------------------------------------------------

def _split_sections(text: str) -> list[tuple[str, dict, str]]:
    """-> [(section_kind, header_attrs, body_text)] in file order."""
    sections: list[tuple[str, dict, str]] = []
    kind, attrs, body = "", {}, []
    for line in text.splitlines():
        m = _SECTION.match(line)
        if m:
            if kind:
                sections.append((kind, attrs, "\n".join(body)))
            kind = m.group(1)
            attrs = dict(_ATTR.findall(m.group(2)))
            body = []
        elif kind:
            body.append(line)
    if kind:
        sections.append((kind, attrs, "\n".join(body)))
    return sections


def _parse_body(body: str) -> dict:
    props: dict = {}
    for stmt in re.finditer(r"^(\w+)\s*=\s*", body, re.M):
        value, _ = _parse_value(body, stmt.end())
        props[stmt.group(1)] = value
    return props


def _class_of(props: dict, ext: dict[str, dict]) -> str:
    """A sub-resource's class, taken from the script it points at.

    `res://items/bullets/bullet_resource.gd` -> `BulletResource`, which matches
    the project's convention of one class per snake_case file.
    """
    script = props.get("script")
    if not isinstance(script, Ref) or script.kind != "ext":
        return ""
    path = ext.get(script.id, {}).get("path", "")
    stem = Path(path).stem
    return "".join(part.title() for part in stem.split("_"))


def load(path: Path) -> Block:
    """Parse a `.tres` into its `[resource]` block, sub-resources resolved inline."""
    sections = _split_sections(path.read_text())

    ext: dict[str, dict] = {}
    raw_subs: dict[str, tuple[str, dict]] = {}
    root_class, root_props = "", {}

    for kind, attrs, body in sections:
        if kind == "gd_resource":
            root_class = attrs.get("script_class", "")
        elif kind == "ext_resource":
            ext[attrs["id"]] = attrs
        elif kind == "sub_resource":
            props = _parse_body(body)
            raw_subs[attrs["id"]] = (attrs.get("type", ""), props)
        elif kind == "resource":
            root_props = _parse_body(body)

    resolved: dict[str, Block] = {}
    resolving: set[str] = set()

    def resolve(value):
        if isinstance(value, list):
            return [resolve(v) for v in value]
        if isinstance(value, Call):
            return Call(value.name, [resolve(a) for a in value.args])
        if not isinstance(value, Ref):
            return value
        if value.kind == "ext":
            return ext.get(value.id, {}).get("path", "")
        if value.id in resolved:
            return resolved[value.id]
        if value.id in resolving or value.id not in raw_subs:
            return None  # cycle, or a reference into another file
        resolving.add(value.id)
        type_name, props = raw_subs[value.id]
        block = Block(_class_of(props, ext) or type_name)
        for key, val in props.items():
            if key != "script":
                block[key] = resolve(val)
        resolving.discard(value.id)
        resolved[value.id] = block
        return block

    out = Block(root_class or _class_of(root_props, ext))
    for key, val in root_props.items():
        if key != "script":
            out[key] = resolve(val)
    return out
