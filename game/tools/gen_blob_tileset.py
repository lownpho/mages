#!/usr/bin/env python3
"""Generate a Godot 4 TileSet .tres with terrain peering bits already filled in,
for a 47-tile blob atlas laid out like overworld/tileset_template.png.

LAYOUT below is the single source of truth: which atlas cell = which set of
peering bits. It was hand-tuned in overworld/tileset_template.tres and baked here.
Any real art drawn in the SAME cell order gets a correct "Match Corners and Sides"
terrain with zero hand-painting in the editor.

Usage:
    python3 tools/gen_blob_tileset.py [ART_PNG] [OUT_TRES]
Defaults to the template png itself -> overworld/tileset_template.tres.
Run from the `game/` directory (paths are res:// relative to it).
"""
import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.normpath(os.path.join(HERE, ".."))
TEMPLATE = os.path.join(GAME, "overworld", "tileset_template.png")
TILE = 8                      # px per cell

# property write order Godot uses (clockwise from right)
ORDER = ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner",
         "left_side", "top_left_corner", "top_side", "top_right_corner"]

# (col, row) -> peering bits. Source of truth, baked from tileset_template.tres.
# (3, 3) is the isolated tile (no peers); every other cell is a distinct blob piece.
LAYOUT = {
    (0, 0): ["right_side", "bottom_right_corner", "bottom_side"],
    (1, 0): ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner", "left_side"],
    (2, 0): ["bottom_side", "bottom_left_corner", "left_side"],
    (3, 0): ["bottom_side"],
    (4, 0): ["right_side", "bottom_side"],
    (5, 0): ["bottom_side", "left_side"],
    (6, 0): ["right_side", "bottom_side", "left_side"],
    (7, 0): ["right_side", "left_side", "top_side"],
    (0, 1): ["right_side", "bottom_right_corner", "bottom_side", "top_side", "top_right_corner"],
    (1, 1): ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner", "left_side", "top_left_corner", "top_side", "top_right_corner"],
    (2, 1): ["bottom_side", "bottom_left_corner", "left_side", "top_left_corner", "top_side"],
    (3, 1): ["bottom_side", "top_side"],
    (4, 1): ["right_side", "top_side"],
    (5, 1): ["left_side", "top_side"],
    (6, 1): ["right_side", "bottom_side", "top_side"],
    (7, 1): ["bottom_side", "left_side", "top_side"],
    (0, 2): ["right_side", "top_side", "top_right_corner"],
    (1, 2): ["right_side", "left_side", "top_left_corner", "top_side", "top_right_corner"],
    (2, 2): ["left_side", "top_left_corner", "top_side"],
    (3, 2): ["top_side"],
    (4, 2): ["right_side", "bottom_side", "bottom_left_corner", "left_side", "top_left_corner", "top_side", "top_right_corner"],
    (5, 2): ["right_side", "bottom_right_corner", "bottom_side", "left_side", "top_left_corner", "top_side", "top_right_corner"],
    (6, 2): ["right_side", "bottom_side", "left_side", "top_left_corner", "top_side", "top_right_corner"],
    (7, 2): ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner", "left_side", "top_side"],
    (0, 3): ["right_side"],
    (1, 3): ["right_side", "left_side"],
    (2, 3): ["left_side"],
    (3, 3): [],
    (4, 3): ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner", "left_side", "top_left_corner", "top_side"],
    (5, 3): ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner", "left_side", "top_side", "top_right_corner"],
    (6, 3): ["right_side", "bottom_side", "bottom_left_corner", "left_side", "top_left_corner", "top_side"],
    (7, 3): ["right_side", "bottom_right_corner", "bottom_side", "left_side", "top_side", "top_right_corner"],
    (0, 4): ["right_side", "bottom_right_corner", "bottom_side", "top_side"],
    (1, 4): ["bottom_side", "bottom_left_corner", "left_side", "top_side"],
    (2, 4): ["right_side", "bottom_right_corner", "bottom_side", "left_side"],
    (3, 4): ["right_side", "bottom_side", "bottom_left_corner", "left_side"],
    (4, 4): ["right_side", "bottom_right_corner", "bottom_side", "left_side", "top_side"],
    (5, 4): ["right_side", "bottom_side", "bottom_left_corner", "left_side", "top_side"],
    (6, 4): ["right_side", "bottom_right_corner", "bottom_side", "left_side", "top_left_corner", "top_side"],
    (7, 4): ["right_side", "bottom_side", "left_side", "top_side"],
    (0, 5): ["right_side", "bottom_side", "top_side", "top_right_corner"],
    (1, 5): ["bottom_side", "left_side", "top_left_corner", "top_side"],
    (2, 5): ["right_side", "left_side", "top_side", "top_right_corner"],
    (3, 5): ["right_side", "left_side", "top_left_corner", "top_side"],
    (4, 5): ["right_side", "bottom_side", "left_side", "top_side", "top_right_corner"],
    (5, 5): ["right_side", "bottom_side", "left_side", "top_left_corner", "top_side"],
    (6, 5): ["right_side", "bottom_side", "bottom_left_corner", "left_side", "top_side", "top_right_corner"],
    (7, 5): ["right_side", "bottom_right_corner", "bottom_side", "bottom_left_corner", "left_side", "top_left_corner", "top_side", "top_right_corner"],
}


def res_path(abspath):
    rel = os.path.relpath(os.path.abspath(abspath), GAME).replace(os.sep, "/")
    return "res://" + rel


def import_uid(png_abspath):
    imp = png_abspath + ".import"
    if os.path.exists(imp):
        for line in open(imp):
            if line.startswith("uid="):
                return line.split('"')[1]
    return None


def existing_resource_uid(tres_path):
    """Preserve the TileSet's own uid on regeneration so references don't break."""
    if os.path.exists(tres_path):
        first = open(tres_path).readline()
        if 'uid="' in first:
            return first.split('uid="')[1].split('"')[0]
    return None


def main():
    art = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else TEMPLATE
    out = os.path.abspath(sys.argv[2]) if len(sys.argv) > 2 else \
        os.path.join(GAME, "overworld", "tileset_template.tres")

    uid = import_uid(art)
    tex_uid = f' uid="{uid}"' if uid else ""
    res_uid = existing_resource_uid(out)
    res_uid_attr = f' uid="{res_uid}"' if res_uid else ""
    src = "TileSetAtlasSource_blob"

    L = []
    L.append(f'[gd_resource type="TileSet" format=3{res_uid_attr}]')
    L.append("")
    L.append(f'[ext_resource type="Texture2D"{tex_uid} path="{res_path(art)}" id="1_blob"]')
    L.append("")
    L.append(f'[sub_resource type="TileSetAtlasSource" id="{src}"]')
    L.append('texture = ExtResource("1_blob")')
    L.append(f"texture_region_size = Vector2i({TILE}, {TILE})")
    for (rx, ry) in sorted(LAYOUT, key=lambda k: (k[1], k[0])):
        bits = set(LAYOUT[(rx, ry)])
        key = f"{rx}:{ry}/0"
        L.append(f"{key} = 0")
        L.append(f"{key}/terrain_set = 0")
        L.append(f"{key}/terrain = 0")
        for prop in ORDER:
            if prop in bits:
                L.append(f"{key}/terrains_peering_bit/{prop} = 0")
    L.append("")
    L.append("[resource]")
    L.append(f"tile_size = Vector2i({TILE}, {TILE})")
    L.append("terrain_set_0/mode = 0")
    L.append('terrain_set_0/terrain_0/name = "blob"')
    L.append("terrain_set_0/terrain_0/color = Color(0.5, 0.5, 0.5, 1)")
    L.append(f'sources/0 = SubResource("{src}")')
    L.append("")

    with open(out, "w") as f:
        f.write("\n".join(L))
    print(f"wrote {res_path(out)}  ({len(LAYOUT)} terrain tiles, texture {res_path(art)})")


if __name__ == "__main__":
    main()
