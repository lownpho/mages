---
name: biome-scenery
description: Make flat, outline-free biome scenery props (trees, rocks, bushes, stumps, crystals, mushrooms, any terrain decoration/blocker) that read against their own biome floor by value contrast. Use when the user asks to create/draw/add scenery, props, decor, foliage, trees, rocks, or terrain features for a specific biome (glade, deepwood, mycelium, …), especially when they want them flat-shaded, outline-free, tileable in bunches, or "in that style / like the deepwood trees". Composes a 1:1 PNG sheet in the biome's sub-palette, an editable .ase source, the TileSet that makes the game draw it, and verifies the result composited on the real floor color.
---

# Biome scenery

Flat, low-detail terrain props — trees, rocks, bushes, stumps, crystals, mushrooms, anything
scattered or packed across a biome. They are **world sprites**, so they follow the style doctrine
in the **pixel-art** skill: no outlines, one or two flat tones per material, Zughy 32 only, and
the brightest pixels on screen reserved for danger (projectiles and magic), never scenery.

This skill is the *design grammar* for that kind of asset. It rides on top of **pixel-art** (the
render/view/iterate loop and its scripts) — read that skill's workflow first; this one adds the
biome-specific rules and the project's asset + TileSet pipeline.

The defining problem this skill exists to solve: **a prop must read against the very floor it
sits on, often when the biome's natural material color *is* the floor color.** Everything below
flows from that.

---

## The nine rules

1. **Read the ground first.** Before drawing anything, pull the target biome's actual floor and
   background colors (see *Sampling the biome* below). The design is reactive to what the prop
   sits on — you cannot judge contrast in a vacuum.

2. **Legibility by value contrast, not outlines.** No border ring — outlines are the UI's
   dialect, and the eye learns that outlined means interface, outline-free means world. The
   silhouette separates from the floor because it is a clearly different *value*, usually darker.
   If the shape only reads once you add a dark edge around it, the fill colors are wrong; fix the
   colors, don't add the outline.

3. **The lit highlight may not be the floor color *on the edge*.** The classic trap: the biome's
   natural highlight tone equals its floor tone, so a highlight on the silhouette edge dissolves
   into the ground. Resolution — the outer edge stays the dark mass; the floor-matching tone
   appears only *interior*, surrounded by darker pixels.

4. **One or two flat tones per material, plus a sparse accent.** Body = base + one shadow tone.
   No gradients, no dither, no anti-aliasing. A third tone appears only as tiny single-pixel
   "life" specks (a brighter leaf, a burr, a hairline crack).

5. **Ration saturation.** Scenery is deliberately muted and dark. The few saturated pixels are
   1px specks. Bright, hot color belongs to bullets and spells — spending it on scenery steals it
   from danger.

6. **Shadow is a flat region with a consistent light direction.** Put the shade on one side (a
   lower-right block) as a solid fill — it gives volume. A shadow that wraps the whole silhouette
   is just an outline again; don't.

7. **Use the biome's existing sub-palette, not all of Zughy 32.** Sample the handful of colors
   the rest of the biome already uses so the new prop sits with the old ones. In-game these are
   named in `game/globals/palette.gd`.

8. **Design for packing + variety.** If they cluster (a bunch of trees, a field of rocks): each
   variant fills a full-width band so neighbours merge when tiled, but the *set* has distinct
   silhouettes so a cluster never looks like one stamp repeated. Always test by tiling a 3×N
   bunch and looking at it, not just the single sprite.

9. **Verify by looking, composited on the real floor color.** Render → composite onto the actual
   floor tone → look → iterate (minimum two cycles, like pixel-art). Then the mechanical checks:
   100% on-palette, and the `.ase` round-trips bit-identical through the export pipeline.

The portable summary: **flat, outline-free, two-tone-per-material shapes in the biome's muted
sub-palette, made to read against their own floor by value (never the floor's own hue on the
edge), with rationed saturation and a tileable, varied silhouette set.**

---

## Sizing

Props are authored 1:1 on the 8px tile grid (`GameConstants.PX_PER_TILE`). Pick the box from the
role:

- **Ground decor / small prop** → 8×8 (one tile): pebbles, tufts, mushrooms, small bushes. This
  is what a `DECOR_FLOOR` overlay is made of.
- **Tree / tall prop** → 8×16 (one tile wide, two tall): the deepwood and glade trees are this,
  authored in the TileSet as `size_in_atlas = Vector2i(1, 2)`.
- **Big feature / blocker cluster** → up to ~24 in one dimension; spend the extra tiles only when
  the prop is genuinely a large landmark, the same way size signals threat on enemies.

Frame size is the *prop* box; the sheet is several variants laid out left→right on one canvas
(one row), matching `glade_trees` / `deepwood_trees` / `deepwood_decor`.

---

## Where it goes, and how the game draws it

Source `.ase` and shipped `.png` mirror each other under the biome's `art/` folder:

```
asset_src/graphics/generation/world/biomes/<biome>/art/<biome>_<prop>.ase
game/generation/world/biomes/<biome>/art/<biome>_<prop>.png
```

Biomes with their own art: `glade` (its veggie Zone's tilesets live there too), `deepwood` and
`mycelium`. The placeholder Biomes (`wastelands`, `fruit`, `hive`, `moon`, `hell`) borrow one of
those presentations from their `biome.tres`.

**A sheet is not content until it is a TileSet.** The streamer draws the semantic tile classes
through the Biome's `BiomePresentation` (`art/<biome>_presentation.tres`, referenced by
`biome.tres`; script `game/generation/presentation/biome_presentation.gd`), and each slot points at
a `TileSet` `.tres`:

| Slot | Logical class | What it is |
| --- | --- | --- |
| `floor_tileset` | floor | the ground, no collision |
| `wall_tileset` | wall | Room shells, collidable |
| `rock_tileset` | rock | interior rocks, collidable, **Y-sorted against entities** |
| `decoration_tileset` | decoration | flat overlay on floor tiles behind entities, no collision; the Biome's `decoration_density` sets how many |

A Zone may override only the decoration: `decoration_tileset` and `decoration_density` on its
`zones/<zone>.tres`.

Forest biomes point **both** `wall_tileset` and `rock_tileset` at the same tree tileset, which
is why Room walls and interior rocks there read as trees rather than rock.

So a new prop sheet becomes either a new TileSet `.tres` beside it (copy
`deepwood_trees.tres`) or extra tiles in an existing one. The shape of a tree entry:

```
texture_region_size = Vector2i(8, 8)
0:0/size_in_atlas = Vector2i(1, 2)          # 8 wide, 16 tall
0:0/0/texture_origin = Vector2i(0, 4)       # anchor at the base, for Y-sort
0:0/0/physics_layer_0/polygon_0/points = ...  # collision on the trunk tile only
0:0/0/probability = 0.6                     # scatter weight — see below
```

**`probability` is the scatter dial.** Unless the presentation sets `*_autotile`, the streamer
picks among *every* tile in the source weighted by its per-tile `probability` (a pure hash of the
world tile, so it is deterministic and stable across chunks). A rare variant gets a low
probability; the common one gets the rest. Collision is authored as per-tile physics polygons in
the TileSet, never in code.

Generation never reads presentation — no geometry, encounter or RNG draw depends on it — so art
can change freely without changing any seed's World.

---

## Workflow

1. **Identify the biome and its files** (paths above). If the biome doesn't exist yet, ask.

2. **Sample the biome** (rules 1 & 7). Export the biome's existing tileset art and read its
   colors:
   ```bash
   aseprite -b asset_src/graphics/generation/world/biomes/<biome>/art/<biome>_tileset.ase \
     --sheet /tmp/floor.png --sheet-type horizontal
   python3 .claude/skills/biome-scenery/scripts/preview.py --colors /tmp/floor.png
   ```
   The dominant tone is the floor; note any that collide with your prop's natural material color
   (rule 3). Build the prop palette from this set only. `inspect_sheet.py` from the **pixel-art**
   skill dumps a neighbouring prop sheet as a paste-ready grid, which is the faster start when
   you're adding a variant to an existing set.

3. **Plan silhouettes** for the set (rule 8): N distinct shapes, each filling a full-width band
   where they should merge. Decide the light direction once (rule 6).

4. **Draw the grids** using the pixel-art skill's grid format and `render_grid`. Keep the edge the
   dark mass; put floor-colored highlights interior only (rule 3); shadow as a flat block
   (rule 6); ≤1px sparse accent specks (rules 4–5).

5. **Preview on the real floor + tiled bunch** (rule 9):
   ```bash
   python3 .claude/skills/biome-scenery/scripts/preview.py \
     --sheet /tmp/sheet.png --fw 8 --fh 16 --floor 3c5956 --out /tmp/prev
   ```
   (`--floor` takes the hex you sampled in step 2.) This writes `*_onfloor.png` (the set on the
   floor tone) and `*_bunch.png` (a 3×N tiled cluster). **View both.** Iterate the grids until the
   silhouettes read by value alone and a bunch looks varied, not stamped.

6. **Build the `.ase` and ship** (single-canvas, like the other biome sheets):
   ```bash
   aseprite -b --script-param sheet=/tmp/sheet.png \
     --script-param out=asset_src/graphics/generation/world/biomes/<biome>/art/<biome>_<prop>.ase \
     --script .claude/skills/biome-scenery/scripts/make_ase.lua
   cp /tmp/sheet.png game/generation/world/biomes/<biome>/art/<biome>_<prop>.png
   ```
   Do **not** run the full `asset_src/export_assets.lua` just for one prop — it re-exports every
   in-progress asset in the repo. (If you want to scope it rather than skip it,
   `--script-param paths=generation/world/biomes/<biome>` limits it to that subtree.) Copying the
   single shipped PNG is bit-identical to what the pipeline emits; prove it with the round-trip
   check below.

7. **Wire the TileSet** (see *Where it goes* above): add the tiles to the biome's existing
   `*_tileset.tres`, or copy `deepwood_trees.tres` for a new one and point the right
   `BiomePresentation` slot at it. Set each tile's `probability`, `texture_origin` and collision
   polygon. Godot generates the `.png.import` on next editor open.

8. **Verify** (rule 9): the `.ase` round-trips bit-identical to the sheet, the shipped PNG is
   100% on Zughy 32, and `git status` shows only the files you meant to add.

## Scripts

- `scripts/preview.py` — sample colors from a sheet (`--colors`), and composite a frame sheet onto
  a floor color plus tile a randomized N-wide bunch (`--sheet --fw --fh --floor --out`). The
  biome-specific verification that pixel-art's generic renderer doesn't cover.
- `scripts/make_ase.lua` — wrap a finished sheet PNG into a single-canvas editable `.ase` (one
  frame, all variants), the layout the biome sheets use. Round-trips bit-identical.

## References

- The **pixel-art** skill — the style doctrine these rules implement, the grid format,
  `render_grid`, `inspect_sheet.py`, the validator, the render→view→critique→iterate loop, and
  `scripts/verify_export.sh` for proving the export round-trip.
- `game/generation/presentation/biome_presentation.gd` — the authoritative doc comment on how
  semantic tile classes become art, autotiling vs weighted scatter, and why generation never reads
  presentation.
- `asset_src/export_assets.lua` — the real export pipeline (`asset_src/graphics/<path>/x.ase` →
  `game/<path>/x.png`), including the `paths=` scoping param.
