-- import_multi_tag.lua — slice a grid-sheet PNG into an .ase with one tag per row.
--
-- import_spritesheet.lua only supports a single tag for the whole sheet. Use
-- this instead whenever the target pipeline expects "one row = one named
-- animation" (e.g. this project's asset_src/export_assets.lua, which builds
-- the shipped sheet from Aseprite tags). Frame count must be equal across
-- rows.
--
-- aseprite -b \
--   --script-param sheet=path.png --script-param fw=8 --script-param fh=8 \
--   --script-param out=path.ase \
--   --script-param tags="idle:6,move:8,attack:6" \   -- row order top->bottom, "name:fps"
--   --script import_multi_tag.lua
--
-- Gotcha this script exists to dodge: Aseprite auto-extends a tag to cover
-- newly appended frames when the tag's toFrame sits at the sprite's current
-- last frame. Creating tags row-by-row *while* appending later rows silently
-- grows earlier tags to swallow everything after them. Fix: create every
-- frame first, then add all tags in a second pass.

local p = app.params

local function fail(msg)
  app.alert(msg)
  print("ERROR: " .. msg)
  return nil
end

local sheetPath = p["sheet"]
if not sheetPath then return fail("missing sheet=") end
local fw = tonumber(p["fw"])
local fh = tonumber(p["fh"])
if not fw or not fh then return fail("missing fw=/fh=") end

local src = app.open(sheetPath)
if not src then return fail("could not open sheet: " .. sheetPath) end
local srcImg = Image(src.width, src.height, src.colorMode)
srcImg:drawSprite(src, 1)

local cols = src.width // fw
local rows = src.height // fh

local rowSpecs = {}
for spec in (p["tags"] or ""):gmatch("[^,]+") do
  local name, fps = spec:match("^(.-):(%d+)$")
  if not name then return fail("bad tag spec: " .. spec) end
  table.insert(rowSpecs, { name = name, fps = tonumber(fps) })
end
if #rowSpecs ~= rows then
  return fail(("tags list has %d entries but sheet has %d rows"):format(#rowSpecs, rows))
end

local dst = Sprite(fw, fh, src.colorMode)
dst:setPalette(src.palettes[1])
dst.layers[1].name = "frames"
local layer = dst.layers[1]

-- Pass 1: create every frame across every row.
local n = 0
local rowBounds = {}
for row = 0, rows - 1 do
  local fromFrame = n + 1
  for col = 0, cols - 1 do
    n = n + 1
    if n > 1 then dst:newEmptyFrame(n) end
    local cel = Image(fw, fh, dst.colorMode)
    cel:drawImage(srcImg, Point(-col * fw, -row * fh))
    dst:newCel(layer, n, cel, Point(0, 0))
    dst.frames[n].duration = 1.0 / rowSpecs[row + 1].fps
  end
  table.insert(rowBounds, { from = fromFrame, to = n })
end

-- Pass 2: tag, now that no more frames will be appended.
for row = 0, rows - 1 do
  local b = rowBounds[row + 1]
  local tag = dst:newTag(b.from, b.to)
  tag.name = rowSpecs[row + 1].name
  tag.aniDir = AniDir.FORWARD
end

local outPath = p["out"] or (sheetPath:gsub("%.%w+$", "") .. ".ase")
dst:saveAs(outPath)
src:close()
dst:close()
print(("imported %d frame(s) across %d row(s) -> %s"):format(n, rows, outPath))
