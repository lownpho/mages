-- import_spritesheet.lua — slice a sprite-sheet PNG into an animated .ase
--
-- Generic importer for the sheets this skill exports: equal-size frames laid
-- out left-to-right, then top-to-bottom. Each frame becomes one Aseprite frame
-- on a single layer, with frame durations from --fps and an optional loop tag.
--
-- Run headless:
--   aseprite -b \
--     --script-param sheet=path/to/sheet.png \
--     --script-param fw=32 \              # frame width  (px)  [or use frames=N]
--     --script-param fh=32 \              # frame height (px)  [default: sheet height]
--     --script-param fps=8 \              # playback speed     [default: 8]
--     --script-param tag=flow \           # loop tag name      [optional]
--     --script-param out=path/to/out.ase \# output            [default: sheet w/ .ase]
--     --script import_spritesheet.lua
--
-- Instead of fw you may pass frames=N (frame count across one row); fw is then
-- derived as sheetWidth / N.

local p = app.params

local function fail(msg)
  app.alert(msg)            -- visible if a GUI is attached
  print("ERROR: " .. msg)   -- always visible in batch mode
  return nil
end

local sheetPath = p["sheet"]
if not sheetPath then return fail("missing --script-param sheet=<png>") end

local fps = tonumber(p["fps"]) or 8
if fps <= 0 then return fail("fps must be > 0") end

local src = app.open(sheetPath)
if not src then return fail("could not open sheet: " .. sheetPath) end

-- Flatten frame 1 of the source into one full-canvas image, so we don't depend
-- on however the PNG happened to lay out its cels/layers.
local srcImg = Image(src.width, src.height, src.colorMode)
srcImg:drawSprite(src, 1)

-- Resolve frame dimensions.
local fw = tonumber(p["fw"])
local frames = tonumber(p["frames"])
if not fw and frames then fw = src.width // frames end
fw = fw or src.width                         -- single full-width frame fallback
local fh = tonumber(p["fh"]) or src.height
if fw <= 0 or fh <= 0 then return fail("frame size must be > 0") end
if src.width % fw ~= 0 or src.height % fh ~= 0 then
  print(("WARNING: sheet %dx%d not an exact multiple of frame %dx%d; trailing strip ignored")
    :format(src.width, src.height, fw, fh))
end

local cols = src.width // fw
local rows = src.height // fh
local total = cols * rows
if total < 1 then return fail("computed 0 frames — check fw/fh/frames") end

-- Build the destination sprite (frame 1 already exists on layer 1).
local dst = Sprite(fw, fh, src.colorMode)
dst:setPalette(src.palettes[1])
dst.layers[1].name = "frames"
local layer = dst.layers[1]

local n = 0
for row = 0, rows - 1 do
  for col = 0, cols - 1 do
    n = n + 1
    if n > 1 then dst:newEmptyFrame(n) end
    local cel = Image(fw, fh, dst.colorMode)
    -- Blit the sheet offset so region (col*fw,row*fh) lands at (0,0); clipped to cel.
    cel:drawImage(srcImg, Point(-col * fw, -row * fh))
    dst:newCel(layer, n, cel, Point(0, 0))
    dst.frames[n].duration = 1.0 / fps
  end
end

if p["tag"] then
  local tag = dst:newTag(1, total)
  tag.name = p["tag"]
  tag.aniDir = AniDir.FORWARD
end

local outPath = p["out"]
if not outPath then outPath = sheetPath:gsub("%.%w+$", "") .. ".ase" end
dst:saveAs(outPath)

src:close()
dst:close()
print(("imported %d frame(s) [%dx%d] @ %dfps -> %s"):format(total, fw, fh, fps, outPath))
