-- Export every .ase under asset_src/graphics to its mirrored path under game/.
-- The folder tree is the mapping: asset_src/graphics/<path>/x.ase -> game/<path>/x.png
--
-- Run from the repo root:
--   aseprite -b --script asset_src/export_assets.lua
--
-- Export only certain paths with the `paths` script param — a comma-separated
-- list of path prefixes (relative to asset_src/graphics). A prefix matches a
-- whole subtree or a single file; omit the param to export everything:
--   aseprite -b --script-param paths=worldgen --script asset_src/export_assets.lua
--   aseprite -b --script-param paths=characters --script asset_src/export_assets.lua
--   aseprite -b --script-param paths=characters/enemies/golem,worldgen \
--     --script asset_src/export_assets.lua
--
-- Sheet layout: one row per animation tag, frames left to right. Untagged
-- sprites export all frames as a single row: frame i of row r sits at
-- (i * frame_width, r * frame_height).
--
-- Multi-frame sprites also emit a .json describing the rows/durations into the
-- gitignored META dir (mirroring the source tree). It is build *metadata* only —
-- a regenerable record of the sheet layout — NOT shipped game data: SpriteFrames
-- are authored in the .tscn that uses each sheet, the same as every other sprite.

local SRC = "asset_src/graphics"
local DST = "game"
local META = "asset_src/meta"  -- gitignored; see asset_src/.gitignore

-- icon.ase is not the project icon (game/icon.png is separate artwork) —
-- keep it out of the pipeline so it doesn't overwrite the real icon.
local function is_excluded(name)
  return name:match("^palette") ~= nil or name == "icon.ase"
end

-- `paths` param -> list of prefixes (relative to SRC, forward slashes, no
-- trailing slash). Empty list means "export everything".
local function parse_filters(raw)
  local filters = {}
  if raw then
    for part in raw:gmatch("[^,]+") do
      local p = part:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/+$", "")
      if p ~= "" then table.insert(filters, p) end
    end
  end
  return filters
end

-- A prefix matches a file whose relative path equals it (a single file) or
-- starts with it followed by "/" (a whole subtree) — never a partial segment,
-- so "golem" won't match "golem_king".
local function matches_filters(rel, filters)
  if #filters == 0 then return true end
  for _, p in ipairs(filters) do
    if rel == p or rel:sub(1, #p + 1) == p .. "/" then return true end
  end
  return false
end

local function collect(dir, out, filters)
  for _, entry in ipairs(app.fs.listFiles(dir)) do
    local full = app.fs.joinPath(dir, entry)
    if app.fs.isDirectory(full) then
      collect(full, out, filters)
    elseif (entry:match("%.ase$") or entry:match("%.aseprite$"))
        and not is_excluded(entry)
        and matches_filters(full:sub(#SRC + 2), filters) then
      table.insert(out, full)
    end
  end
end

local function dir_name(aniDir)
  if aniDir == AniDir.REVERSE then return "reverse" end
  if aniDir == AniDir.PING_PONG then return "pingpong" end
  if AniDir.PING_PONG_REVERSE and aniDir == AniDir.PING_PONG_REVERSE then
    return "pingpong_reverse"
  end
  return "forward"
end

-- One row per tag; a tagless sprite is a single anonymous row of all frames.
local function build_rows(spr)
  local rows = {}
  if #spr.tags > 0 then
    for _, tag in ipairs(spr.tags) do
      local frames = {}
      for f = tag.fromFrame.frameNumber, tag.toFrame.frameNumber do
        table.insert(frames, f)
      end
      table.insert(rows, { name = tag.name, frames = frames,
                           direction = dir_name(tag.aniDir) })
    end
  else
    local frames = {}
    for f = 1, #spr.frames do table.insert(frames, f) end
    table.insert(rows, { name = "default", frames = frames,
                         direction = "forward" })
  end
  return rows
end

local function json_escape(s)
  return (s:gsub('\\', '\\\\'):gsub('"', '\\"'))
end

local function write_json(json_path, src_rel, spr, rows)
  local lines = {
    '{',
    string.format('  "source": "%s",', json_escape(src_rel)),
    string.format('  "frame_width": %d,', spr.width),
    string.format('  "frame_height": %d,', spr.height),
    '  "animations": [',
  }
  for ri, row in ipairs(rows) do
    local durations = {}
    for _, f in ipairs(row.frames) do
      table.insert(durations,
        string.format('%d', math.floor(spr.frames[f].duration * 1000 + 0.5)))
    end
    table.insert(lines, string.format(
      '    { "name": "%s", "row": %d, "frames": %d, "direction": "%s", "durations_ms": [%s] }%s',
      json_escape(row.name), ri - 1, #row.frames, row.direction,
      table.concat(durations, ', '), ri < #rows and ',' or ''))
  end
  table.insert(lines, '  ],')
  table.insert(lines, '  "slices": [')
  -- The Lua API exposes one bounds/center/pivot per Slice (not keyframed), so each
  -- slice emits a single-element "keys" array at frame 0 — keeping the JSON shape
  -- stable for readers regardless of how many frames the sprite has.
  for si, slice in ipairs(spr.slices) do
    local b = slice.bounds
    local entry = string.format(
      '        { "frame": 0, "x": %d, "y": %d, "w": %d, "h": %d',
      b.x, b.y, b.width, b.height)
    if slice.center then
      local c = slice.center
      entry = entry .. string.format(
        ', "center": { "x": %d, "y": %d, "w": %d, "h": %d }', c.x, c.y, c.width, c.height)
    end
    if slice.pivot then
      entry = entry .. string.format(', "pivot": { "x": %d, "y": %d }', slice.pivot.x, slice.pivot.y)
    end
    entry = entry .. ' }'
    table.insert(lines, string.format(
      '    { "name": "%s", "keys": [\n%s\n      ] }%s',
      json_escape(slice.name), entry, si < #spr.slices and ',' or ''))
  end
  table.insert(lines, '  ]')
  table.insert(lines, '}')
  local f = assert(io.open(json_path, 'w'))
  f:write(table.concat(lines, '\n'), '\n')
  f:close()
end

local function export_file(src_path)
  local spr = app.open(src_path)
  if not spr then
    print('FAILED to open ' .. src_path)
    return false
  end

  local rel = src_path:sub(#SRC + 2)
  local out_dir = app.fs.joinPath(DST, app.fs.filePath(rel))
  local base = app.fs.joinPath(out_dir, app.fs.fileTitle(src_path))
  app.fs.makeAllDirectories(out_dir)

  local rows = build_rows(spr)
  local cols = 0
  for _, row in ipairs(rows) do cols = math.max(cols, #row.frames) end

  local spec = ImageSpec{
    width = spr.width * cols,
    height = spr.height * #rows,
    colorMode = spr.colorMode,
    transparentColor = spr.transparentColor,
  }
  local sheet = Image(spec)
  for ri, row in ipairs(rows) do
    for ci, frame in ipairs(row.frames) do
      sheet:drawSprite(spr, frame, Point((ci - 1) * spr.width,
                                         (ri - 1) * spr.height))
    end
  end
  sheet:saveAs{ filename = base .. '.png', palette = spr.palettes[1] }

  -- A static sprite still gets metadata if it carries slices (e.g. an icon
  -- atlas), since the slice rects are the only way to map them back out. The
  -- .json mirrors the source tree under META (gitignored), not next to the PNG.
  local wants_json = #spr.frames > 1 or #spr.tags > 0 or #spr.slices > 0
  if wants_json then
    local meta_path = app.fs.joinPath(META, rel):gsub('%.aseprite$', '.json'):gsub('%.ase$', '.json')
    app.fs.makeAllDirectories(app.fs.filePath(meta_path))
    write_json(meta_path, rel, spr, rows)
  end

  print(string.format('%s -> %s.png  (%dx%d, %d row%s%s)',
    src_path, base, sheet.width, sheet.height,
    #rows, #rows == 1 and '' or 's', wants_json and ' + json' or ''))
  spr:close()
  return true
end

local filters = parse_filters(app.params["paths"])
if #filters > 0 then
  print("exporting only: " .. table.concat(filters, ", "))
end

local files = {}
collect(SRC, files, filters)
table.sort(files)

if #files == 0 then
  print("no matching .ase files" ..
    (#filters > 0 and " for: " .. table.concat(filters, ", ") or ""))
  return
end

local failures = 0
for _, src in ipairs(files) do
  if not export_file(src) then failures = failures + 1 end
end
print(string.format('done: %d file(s), %d failure(s)', #files, failures))
if failures > 0 then error('some exports failed') end
