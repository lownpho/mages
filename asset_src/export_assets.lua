-- Export every .ase under asset_src/graphics to its mirrored path under game/.
-- The folder tree is the mapping: asset_src/graphics/<path>/x.ase -> game/<path>/x.png
--
-- Run from the repo root:
--   aseprite -b --script asset_src/export_assets.lua
--
-- Sheet layout: one row per animation tag, frames left to right. Untagged
-- sprites export all frames as a single row. Multi-frame sprites also get a
-- .json next to their .ase source describing the rows so animations/positions
-- can be mapped: frame i of row r sits at (i * frame_width, r * frame_height).

local SRC = "asset_src/graphics"
local DST = "game"

-- icon.ase is not the project icon (game/icon.png is separate artwork) —
-- keep it out of the pipeline so it doesn't overwrite the real icon.
local function is_excluded(name)
  return name:match("^palette") ~= nil or name == "icon.ase"
end

local function collect(dir, out)
  for _, entry in ipairs(app.fs.listFiles(dir)) do
    local full = app.fs.joinPath(dir, entry)
    if app.fs.isDirectory(full) then
      collect(full, out)
    elseif (entry:match("%.ase$") or entry:match("%.aseprite$"))
        and not is_excluded(entry) then
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

  local animated = #spr.frames > 1 or #spr.tags > 0
  if animated then
    local json_path = app.fs.joinPath(app.fs.filePath(src_path),
                                      app.fs.fileTitle(src_path) .. '.json')
    write_json(json_path, src_path, spr, rows)
  end

  print(string.format('%s -> %s.png  (%dx%d, %d row%s%s)',
    src_path, base, sheet.width, sheet.height,
    #rows, #rows == 1 and '' or 's', animated and ' + json' or ''))
  spr:close()
  return true
end

local files = {}
collect(SRC, files)
table.sort(files)

local failures = 0
for _, src in ipairs(files) do
  if not export_file(src) then failures = failures + 1 end
end
print(string.format('done: %d file(s), %d failure(s)', #files, failures))
if failures > 0 then error('some exports failed') end
