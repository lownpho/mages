"""Mechanical validator. Encodes only objective, checkable rules.

Optionally enforces per-project constraints from game.json:
{
  "grid_size": 8,
  "max_colors": 4,            # max non-transparent colors per sprite
  "transparent_margin": 0,    # required transparent border in px
  "transparent_char": "_"
}
"""
import json
import os


def _used_cells(grid, transparent='_'):
    return {(y, x) for y, row in enumerate(grid) for x, ch in enumerate(row) if ch != transparent}


def validate_grid(grid, palette, game_config=None, transparent='_'):
    """Returns list of issue strings. Empty list = mechanically clean."""
    issues = []
    w = len(grid[0])
    # Rectangularity + palette membership
    for y, row in enumerate(grid):
        if len(row) != w:
            issues.append(f"row {y}: length {len(row)} != {w}")
        for x, ch in enumerate(row):
            if ch not in palette:
                issues.append(f"({y},{x}): char '{ch}' not in palette")
    if issues:
        return issues  # structural problems make further checks unreliable

    cells = _used_cells(grid, transparent)
    # Orphan pixels: no 4- or 8-connected neighbor
    for (y, x) in cells:
        if not any((y + dy, x + dx) in cells
                   for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                   if (dy, dx) != (0, 0)):
            issues.append(f"orphan pixel at ({y},{x})")

    if game_config:
        gs = game_config.get('grid_size')
        if gs and (len(grid) != gs or w != gs):
            issues.append(f"grid is {len(grid)}x{w}, game requires {gs}x{gs}")
        mc = game_config.get('max_colors')
        used_colors = {palette[grid[y][x]] for (y, x) in cells}
        if mc and len(used_colors) > mc:
            issues.append(f"{len(used_colors)} colors used, game allows max {mc}")
        margin = game_config.get('transparent_margin', 0)
        for (y, x) in cells:
            if y < margin or x < margin or y >= len(grid) - margin or x >= w - margin:
                issues.append(f"pixel at ({y},{x}) violates {margin}px transparent margin")
    return issues


def find_isolated_new_pixels(base_frame, frame, transparent='_'):
    """Pixels in `frame` that (a) differ from `base_frame` at that cell and
    (b) have no 4-connected neighbor of the same color in `frame`.

    Catches a defect `validate_grid`'s orphan check misses: a pixel that IS
    topologically connected to the body (has non-transparent neighbors) but
    is color-isolated from it — a lone accent dot with no matching-color
    patch around it. At small grid sizes a single-pixel eye or thorn-tip is
    normal and intentional (see references/rules.md #6), so checking a whole
    frame in isolation is too noisy to be useful — nearly every 1px accent
    trips it. Restricting to pixels that are NEW relative to a base frame
    (usually idle) targets the actual failure mode instead: accents freshly
    added for an attack/action telegraph, with nothing establishing them as
    deliberate design. A lone red or pink speck introduced only in an attack
    frame reads exactly like a stray bullet fragment or a punched-out hole,
    not a body detail — this is what that looks like mechanically.
    """
    h, w = len(base_frame), len(base_frame[0])
    found = []
    for y in range(h):
        for x in range(w):
            c = frame[y][x]
            if c == transparent or c == base_frame[y][x]:
                continue
            same = any(
                0 <= y + dy < h and 0 <= x + dx < w and frame[y + dy][x + dx] == c
                for dy, dx in [(-1, 0), (1, 0), (0, -1), (0, 1)]
            )
            if not same:
                found.append((y, x, c))
    return found


def validate_animation(frames, parts=None, static_parts=None, transparent='_'):
    """Cross-frame checks for an animation (list of grids).

    parts: dict name -> list of (y,x) cells (defined on frame 0)
    static_parts: list of part names that must be pixel-identical in every frame
    Also checks all frames share dimensions, flags isolated pixels newly
    introduced relative to frame 0 (see find_isolated_new_pixels), and
    reports pixel churn between consecutive frames (high churn = likely
    flicker).
    """
    issues = []
    h, w = len(frames[0]), len(frames[0][0])
    for i, f in enumerate(frames):
        if len(f) != h or any(len(r) != w for r in f):
            issues.append(f"frame {i}: dimensions differ from frame 0")
    if issues:
        return issues

    if parts and static_parts:
        for name in static_parts:
            for (y, x) in parts.get(name, []):
                ref = frames[0][y][x]
                for i, f in enumerate(frames[1:], start=1):
                    if f[y][x] != ref:
                        issues.append(
                            f"static part '{name}' changed at ({y},{x}) in frame {i} "
                            f"('{ref}' -> '{f[y][x]}')")

    # Isolated pixels newly introduced vs frame 0 — likely fx/bullet-artifact
    # or hole misreads, not deliberate design (see find_isolated_new_pixels).
    for i, f in enumerate(frames[1:], start=1):
        for (y, x, c) in find_isolated_new_pixels(frames[0], f, transparent):
            issues.append(
                f"frame {i}: isolated new pixel at ({y},{x}) color '{c}' — "
                f"no same-color neighbor and absent from frame 0; likely reads "
                f"as a stray artifact rather than body detail, verify visually")

    # Churn report (informational threshold: >50% of used cells changing)
    for i in range(1, len(frames)):
        a, b = frames[i - 1], frames[i]
        changed = sum(1 for y in range(h) for x in range(w) if a[y][x] != b[y][x])
        used = max(1, len(_used_cells(a, transparent)))
        if changed / used > 0.5:
            issues.append(f"frames {i-1}->{i}: {changed} cells changed "
                          f"(> 50% of sprite) — possible flicker, verify visually")
    return issues


def load_game_config(project_dir):
    path = os.path.join(project_dir, 'game.json')
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    return None


def print_validation(grid, palette, game_config=None):
    issues = validate_grid(grid, palette, game_config)
    if not issues:
        print("VALID: mechanically clean")
    else:
        print(f"{len(issues)} ISSUE(S):")
        for i in issues:
            print(f"  - {i}")
    return issues
