-- Wrap a finished biome-scenery sheet PNG into a single-canvas editable .ase
-- (one frame holding every variant left-to-right) — the layout the other biome
-- sheets use (glade_trees, deepwood_blockers). Round-trips bit-identical: the
-- export pipeline re-emits the same PNG.
--
--   aseprite -b \
--     --script-param sheet=/tmp/sheet.png \
--     --script-param out=asset_src/graphics/generation/world/biomes/<biome>/art/<biome>_<prop>.ase \
--     --script .claude/skills/biome-scenery/scripts/make_ase.lua
local sheet = app.params["sheet"]
local out = app.params["out"]
assert(sheet and out, "need --script-param sheet=... and out=...")
local img = Image{ fromFile = sheet }
local spr = Sprite(img.width, img.height, ColorMode.RGB)
spr.cels[1].image:drawImage(img)
spr:saveAs(out)
