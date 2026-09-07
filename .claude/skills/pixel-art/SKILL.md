---
name: pixel-art
description: >
  Generate pixel art sprites, icons, and characters as PNG files using a
  vision feedback loop — render, look at the result, critique, refine.
  Use this skill whenever the user asks to create, draw, generate, or make
  pixel art, sprites, pixel icons, retro game art, 8-bit art, 16-bit art,
  pixel characters, pixel patterns, pixel landscapes, or any grid-based
  low-resolution artwork. Also trigger when the user says things like
  "make me a sprite", "draw a pixel version of", "retro-style icon",
  "8-bit character", or mentions a specific pixel grid size like "16x16"
  or "32x32" in the context of creating art. Trigger even if the user
  just says "pixel" or "pixelated" alongside any creative request.
---

# Pixel Art (yarpg)

This skill generates pixel art for this game **with a vision feedback loop**. The single
most important rule: never deliver a sprite without first rendering it, *viewing the
rendered PNG with the Read tool*, critiquing what you actually see, and editing the grid
to fix problems. Pixel art looks nothing like the character grid that produced it —
placing pixels blind produces broken art.

Work in the session scratchpad; deliverables land in the repo (`asset_src/` + `game/`,
see *Ship it* below).

```bash
pip install Pillow --break-system-packages -q   # only dependency
```

---

## Style doctrine (not negotiable)

If a sprite disagrees with a rule here, the sprite is wrong.

- **Palette: Zughy 32, nothing else.** Full list below; canonical file is
  `asset_src/graphics/palette_zughy32.txt` (entries are ARGB `FFrrggbb` — strip the
  leading `FF`). The same 32 are mirrored as named constants in `game/globals/palette.gd`
  (`Palette.GREY_DARK`, `Palette.YELLOW`, …), which is what gameplay code uses for telegraph
  flashes and minimap colours — so a sprite's accent and its in-game flash can be the same
  entry. Verify every delivered pixel is on-palette.
- **A material is one or two flat tones.** No gradients, no dithering, no anti-aliasing.
  If a shape needs a third tone to read, the shape is too complicated.
- **No outlines on world sprites.** Shapes are flat fills separated from the ground by
  value contrast. Outlines (rounded, thick, dark) are the *UI's* dialect — the eye learns
  that outlined means interface, outline-free means world.
- **Saturation is a gameplay channel.** Terrain sits in the muted range, creatures a step
  above it; the hot saturated colors are reserved for projectiles and magic. The
  brightest pixels on screen must be the ones that can kill you.
- **Silhouette first.** An asset must be identifiable from its outline alone at its real
  on-screen size (the game runs at native 320×180 — if it only reads zoomed, it doesn't
  read).
- **Eyes are the face.** A creature's identity is its silhouette plus its eye color, and
  the eyes are the brightest pixels on the body. Big head, small body — the head is the
  only place expression fits at this scale.
- **Native 1:1, no runtime scaling.** What is drawn is what ships.

### Frame tiers — design the *frame* to this, not just the sheet

- **Normal enemy → 8×8** (one tile). The default, and the roster means it: **47 of the 55
  shipped enemy sheets are 8×8 frames**. Start here.
- **Big enemy → 16×16.** Reserved for genuinely big, heavy creatures — the whole shipped list is
  the three golems, the `fae` and the `thornmess`. Being "the heavy sibling" of another enemy is
  **not** a licence to grow the frame: `razorback` is `thornback`'s size and `grimlord` is a
  grimling's, both distinguished by build and colour at the same scale. Only step up a real tier.
- **Huge → up to 24 in one dimension, never more.** Exactly one sprite in the game uses it: the
  `gnarlking`, at 16×24.
- The player is drawn inside a 16×16 frame, standing about 10–12px tall, so an 8×8 enemy reads
  player-sized and a 16×16 one as a clear bigger threat. Drawing a normal enemy at 16×16 makes it
  look like a boss and forces a redo — when unsure, ask which tier before drawing.

### Zughy 32

Each row is one group of 8: darks, mid-tones, lights, saturated accents.

```
#302C2E #39314B #472D3C #564064 #5E3643 #394778 #3C5956 #4F546B
#5A5353 #7D7071 #7A444A #A93B3B #397B44 #3978A8 #8E478C #827094
#A05B53 #BF7958 #EEA160 #F4CCA1 #A0938E #CFC6B8 #DFF6F5 #FFAEB6
#E6482E #F47E1B #F4B41B #B6D53C #71AA34 #28CCDF #8AEBF1 #CD6093
```

Per sprite: 3–4 colors. One base + one shadow per material, one accent (usually the
eyes). Pick the shadow as a hue-shifted darker palette entry, not just "the darker one".

---

## The workflow

```
1. Study siblings — pull exact pixels from an existing sprite of the same tier
2. Plan silhouette, light source, tones (in your head or as comments)
3. Write the character grid
4. Render to PNG at 16x scale
5. ★ VIEW the PNG with the Read tool ★
6. Critique against the checklist
7. Edit the grid, GOTO 4 — minimum 2 render-view-edit cycles
8. Mechanical validator
9. Ship: sheet → .ase → verify the export round-trip
```

Step 5 is the step. The validator catches mechanical errors, not whether the dragon
looks like a dragon — only looking does.

### 1. Study siblings

New art must sit next to what's already shipped. Dump the exact grid of the closest
existing sprite (same tier, same biome if possible) instead of eyeballing a preview:

```bash
python <skill-path>/scripts/inspect_sheet.py game/characters/enemies/<id>/<id>.png \
    --region 0,0,8,8 --keys
```

Prints a ready-to-paste `palette = {...}` and `grid = [...]` for that frame, so
proportions (eye placement, body-to-leg ratio, accent rules) come from actual pixels.

### 2–3. Plan, then write the grid

Plan before placing pixels: silhouette (recognizable as a solid shape?), focal point
(eyes get the contrast), light source (pick one, top-left is convention). Then the grid —
a 2D list of strings, each character mapping to a palette key:

```python
import sys; sys.path.insert(0, '<skill-path>/scripts')

palette = {
    '_': None,         # transparent
    'G': '#5A5353',    # stone base
    'g': '#4F546B',    # stone shadow (hue-shifted dark)
    'A': '#F4B41B',    # amber eyes (the accent)
}
grid = [
    '__GGGG__',
    '_GGGGGG_',  # head
    '_GAGGAG_',  # eyes
    '_GGGGGG_',
    '__GGGG__',  # body
    '__G__G__',  # legs
    '________',
    '________',
]
```

All rows the same length; single-character keys (case pairs like `G`/`g` for
base/shadow); `# section` comments on complex sprites. For pixel-placement grammar
(line stepping, doubles, curves, orphans, shading) read `references/rules.md` first.

### 4–7. Render, view, critique, iterate

```python
from render import render_grid
render_grid(grid, palette, output_path='<scratchpad>/sprite.png', pixel_size=16)
```

The 16x upscale matters — at 1x an 8×8 sprite is 64 pixels and vision can't see it.
**Now Read the PNG.** Critique what you actually see, not the grid text:

- Recognizable as the subject in under a second? (Silhouette, else start over.)
- Eyes/focal point carry the most contrast?
- Flat tones — no accidental third shade, no outline creeping in?
- One light source; no pillow shading, no banding (rules.md §4)?
- Diagonals step consistently; no doubles (rules.md §1–2)?
- No orphan pixels except deliberate ones (an eye, a sparkle)?
- Every color on Zughy 32? Background transparent?
- Sits next to its siblings — same proportions and accent logic as step 1's dump?

Name issues by coordinates ("row 4, cols 2–3: eye gap too wide"), fix, re-render,
view again. **Minimum two cycles** — the first render is almost always wrong. On cycle
5+ the problem is the silhouette, not pixel placement: go back to step 2.

Then the mechanical check:

```python
from validate import print_validation
print_validation(grid, palette)   # orphans, off-palette chars, row lengths
```

---

## Animation

Few frames, big reads: an animation state is **2–4 frames**. Movement is displacement,
squash, and silhouette change — never redrawn interior detail nobody sees at native
size. The idle matters most (it's the bestiary loop and the met-pose): every creature
should be alive standing still. Read `references/rules.md` §7 before starting.

```
1. Start from the final idle grid. Decide static vs moving parts.
2. Frame N+1 = copy of frame N, editing ONLY moving-part cells
   (plus deliberate effects like a 1px body bob).
3. validate.validate_animation(frames, parts=parts, static_parts=[...])
   — static parts pixel-identical, dimensions match, and no isolated NEW
   pixels vs frame 0 (a lone accent added only in an attack frame reads
   as a stray bullet artifact or hole — the #1 animation bug, rules.md §5).
4. animation.preview_animation(frames, palette, out_dir, name, fps=...)
   → strip + looping GIF + onion-skin diffs.
5. ★ VIEW the strip and every onion skin ★ — only intended pixels moved,
   pivot didn't slide, silhouette stays continuous.
6. Iterate — minimum two view cycles, same as statics.
```

`parts` is an optional dict of named cell lists (`{'head': [(0,3),(0,4),...]}`) that
makes the static-part check and later targeted edits possible — define it for anything
animated.

---

## Ship it (.ase → game PNG)

**Source of truth is the `.ase`.** Every shipped sprite has an editable source at
`asset_src/graphics/<same path>/<name>.ase`; the PNG in `game/<path>/` is regenerated
from it by `aseprite -b --script asset_src/export_assets.lua`.

**Sheet layout:** one animation per row, frames left→right, native 1:1, transparent
background. Idle is row 0 and runs slow (≤5 fps); action rows ≤8 fps. Assemble the
rows by stacking each animation's frames with PIL (or `animation.export_raw` per row),
no gaps.

**The export pipeline builds one sheet row per Aseprite *tag*.** A sprite with
idle/move/attack needs three tags, so build the `.ase` with the multi-tag importer —
don't hand-roll it:

```bash
aseprite -b \
  --script-param sheet=<scratchpad>/sheet.png \
  --script-param fw=8 --script-param fh=8 \
  --script-param out=asset_src/graphics/<path>/<name>.ase \
  --script-param tags="idle:4,move:8,attack:6" \    # row order top->bottom, "name:fps"
  --script <skill-path>/scripts/import_multi_tag.lua
```

Row count in `tags` must match `sheet height / fh`; frame count must be equal across
rows. (For a plain single-animation sheet there's `import_spritesheet.lua` with
`fw=`/`fps=`/`tag=` params instead.)

Then prove the round-trip through the *real* pipeline — not just a standalone
re-export:

```bash
<skill-path>/scripts/verify_export.sh <repo_root> <rel_path> <name> <source.ase> <reference.png>
# e.g. verify_export.sh . characters/enemies/thornthrower \
#        thornthrower thornthrower.ase thornthrower.png
```

Exits non-zero with a reason if the export fails or the shipped PNG isn't
pixel-identical to the reference sheet. A sprite isn't done until this passes.

Deliver: the `.ase`, the shipped 1:1 PNG (plus its `.png.import`, see the add-enemy
skill), and show the user a 16x preview/GIF so they can see it.

---

## References

- `references/rules.md` — **required reading**: line stepping, doubles, curves, flat-tone
  shading, orphans (incl. the animation new-pixel rule), 8×8 readability, animation rules.
- `scripts/render.py` — `render_grid` (grid → PNG, nearest-neighbor), `render_strip`.
- `scripts/validate.py` — `print_validation` (orphans, palette, dimensions),
  `validate_animation` (static parts, isolated new pixels vs frame 0).
- `scripts/animation.py` — `preview_animation` (strip/GIF/onion skins), `export_raw`,
  save/load of frame stacks as JSON.
- `scripts/inspect_sheet.py` — dump a shipped PNG (or a region) as a paste-ready
  `palette` + `grid`; how you study siblings before drawing.
- `scripts/import_multi_tag.lua` / `scripts/import_spritesheet.lua` — sheet PNG →
  editable `.ase` (one tag per row / single tag).
- `scripts/verify_export.sh` — install a `.ase`, run the repo's real export filtered to
  it, diff the shipped PNG against the reference sheet.
