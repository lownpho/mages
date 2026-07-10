class_name MapState
## Discovered-world model shared by the strip minimap and the full-screen map: which rooms the
## player has entered, two
## world-sized images (1 px per world tile — floor silhouette + wall/blocker overlay) plus one
## majority-downsampled wall image per coarser zoom level, and the
## static markers recorded when a room is discovered. Pure presentation over the deterministic
## room cache, so the whole thing rebuilds from {world_seed, discovered slots} — that pair is
## the entire save format (see to_dict/restore).
extends RefCounted

enum { MARKER_BOSS, MARKER_FEATURE }

## Canonical tiles-per-pixel zoom steps. A downsampled wall image is pre-built for every level
## > 1 (see setup), so both the minimap and the full map read walls legibly at any zoom from the
## same state. Views step through this array for their own zoom index.
const ZOOM_TILES_PER_PX: Array[int] = [1, 2, 4, 8, 16, 32]

## Room types whose discovery drops a MARKER_BOSS at the room centre — each biome's summit
## encounter (room ids are per-biome, so this is an explicit list).
const BOSS_TYPES: Array[StringName] = [&"glade_boss_d3", &"deepwood_arena"]

var world_seed: int = 0
var world_tiles := Vector2i.ZERO      ## image dimensions (1 px per tile)
var discovered: Dictionary = {}       ## origin_slot (Vector2i) -> true
var markers: Array = []               ## of {tile: Vector2i (world), kind: MARKER_*} — auto, from rooms
var pins: Array = []                  ## of Vector2i (world tile) — player-dropped, saved
var floor_texture: ImageTexture = null
var wall_texture: ImageTexture = null

var _floor_img: Image = null
var _wall_img: Image = null
var _wall_levels: Dictionary = {}    # tpp (int > 1) -> {"img": Image, "tex": ImageTexture}
var _streamer: WorldStreamer = null


## `zoom_levels` are the view's tiles-per-pixel steps; each level > 1 gets its own downsampled
## wall image so walls stay legible (and stable) at every zoom instead of being nearest-sampled.
func setup(streamer: WorldStreamer, zoom_levels: Array[int]) -> void:
	_streamer = streamer
	world_seed = streamer.world_seed
	var s := streamer.config.biome_slots * streamer.config.room_slot_tiles
	world_tiles = Vector2i(streamer.world_spec.grid_w * s, streamer.world_spec.grid_h * s)
	_floor_img = Image.create_empty(world_tiles.x, world_tiles.y, false, Image.FORMAT_RGBA8)
	_wall_img = Image.create_empty(world_tiles.x, world_tiles.y, false, Image.FORMAT_RGBA8)
	floor_texture = ImageTexture.create_from_image(_floor_img)
	wall_texture = ImageTexture.create_from_image(_wall_img)
	_wall_levels.clear()
	for tpp in zoom_levels:
		if tpp <= 1:
			continue
		var img := Image.create_empty(_ceil_div(world_tiles.x, tpp), _ceil_div(world_tiles.y, tpp),
				false, Image.FORMAT_RGBA8)
		_wall_levels[tpp] = {"img": img, "tex": ImageTexture.create_from_image(img)}
	discovered.clear()
	markers.clear()
	pins.clear()


## Drop a pin at a world tile (dedup). Player-placed markers, unlike the auto room markers,
## are free-standing and can sit anywhere — including undiscovered tiles (a pin at a goal you
## haven't reached yet).
func add_pin(world_tile: Vector2i) -> void:
	if world_tile not in pins:
		pins.append(world_tile)


## Remove the pin nearest `world_tile` within `radius_tiles`; true if one was removed. Lets a
## click near an existing pin clear it instead of stacking a second one on top.
func remove_pin_near(world_tile: Vector2i, radius_tiles: int) -> bool:
	var best := -1
	var best_d := radius_tiles * radius_tiles + 1
	for i in pins.size():
		var d: int = (pins[i] - world_tile).length_squared()
		if d <= radius_tiles * radius_tiles and d < best_d:
			best_d = d
			best = i
	if best >= 0:
		pins.remove_at(best)
		return true
	return false


## Wall overlay texture for a zoom level (1 px per `tpp` tiles); the full-res image at tpp 1.
func wall_texture_for(tpp: int) -> ImageTexture:
	if _wall_levels.has(tpp):
		return _wall_levels[tpp]["tex"]
	return wall_texture


## Reveal the room covering a world tile (no-op on fog-of-war misses: outside the world or
## already discovered). Returns true when a new room was painted.
func discover_at(world_tile: Vector2i) -> bool:
	var spec := _streamer.room_spec_at_tile(world_tile.x, world_tile.y)
	if spec == null or discovered.has(spec.origin_slot):
		return false
	discovered[spec.origin_slot] = true
	var room := _streamer.get_room_output(spec)
	_paint_room(room)
	var ss := _streamer.config.room_slot_tiles
	_update_wall_levels(room.origin_slot.x * ss, room.origin_slot.y * ss, room.width, room.height)
	floor_texture.update(_floor_img)
	wall_texture.update(_wall_img)
	for tpp in _wall_levels:
		_wall_levels[tpp]["tex"].update(_wall_levels[tpp]["img"])
	return true


## True once the room under a world tile has been revealed. Reads the painted image (any
## discovered pixel is opaque), so callers need no room lookup.
func is_tile_discovered(world_tile: Vector2i) -> bool:
	if world_tile.x < 0 or world_tile.y < 0 \
			or world_tile.x >= world_tiles.x or world_tile.y >= world_tiles.y:
		return false
	return _floor_img.get_pixelv(world_tile).a > 0.0


## Minimal save payload; images and markers are re-derived by restore() through the
## deterministic room cache. Only discovery and the player's pins are stored — the pins are the
## one thing that can't be re-derived (auto room markers come back with the rooms).
func to_dict() -> Dictionary:
	return {"world_seed": world_seed, "discovered": discovered.keys(), "pins": pins}


func restore(dict: Dictionary) -> void:
	var ss: int = _streamer.config.room_slot_tiles
	for slot in dict.get("discovered", []):
		discover_at(slot * ss)   # a room's origin slot's top-left tile is inside the room
	pins.clear()
	for p in dict.get("pins", []):
		pins.append(p)   # stored as Vector2i; copy into our own array


## Blit one room's tile classes into the images and record its static markers. The floor image
## gets the full room rectangle (a solid silhouette for far zooms where walls are hidden); the
## wall image overlays WALL/BLOCKER pixels for the close zoom.
func _paint_room(room: RoomOutput) -> void:
	var pres := _presentation_for(room.biome_id)
	var fc := pres.map_floor_color
	var wc := pres.map_wall_color
	var ss := _streamer.config.room_slot_tiles
	var ox := room.origin_slot.x * ss
	var oy := room.origin_slot.y * ss
	for y in room.height:
		for x in room.width:
			var cls := room.tile_grid[y * room.width + x]
			_floor_img.set_pixel(ox + x, oy + y, fc)
			if cls == RoomBuilder.WALL or cls == RoomBuilder.BLOCKER:
				_wall_img.set_pixel(ox + x, oy + y, wc)
	if room.type_id in BOSS_TYPES:
		markers.append({"tile": Vector2i(ox + (room.width >> 1), oy + (room.height >> 1)),
				"kind": MARKER_BOSS})
	for sp in room.spawns:
		if sp is Dictionary and sp.has("feature"):
			var t: Vector2i = sp.get("tile", Vector2i.ZERO)
			markers.append({"tile": Vector2i(ox + t.x, oy + t.y), "kind": MARKER_FEATURE})


## Recompute the downsampled wall images for the blocks overlapping one room rectangle.
## A block is wall-colored when at least half of its DISCOVERED tiles are wall — thick wall
## masses survive every zoom, door/corridor openings (locally low wall fraction) always punch
## through, and blocks that are mostly unexplored frontier read as wall until proven open.
func _update_wall_levels(rx: int, ry: int, rw: int, rh: int) -> void:
	for tpp: int in _wall_levels:
		var img: Image = _wall_levels[tpp]["img"]
		@warning_ignore_start("integer_division")
		var bx0: int = rx / tpp
		var by0: int = ry / tpp
		@warning_ignore_restore("integer_division")
		var bx1 := _ceil_div(rx + rw, tpp)
		var by1 := _ceil_div(ry + rh, tpp)
		for by in range(by0, by1):
			for bx in range(bx0, bx1):
				var known := 0
				var walls := 0
				var wall_color := Color(0, 0, 0, 0)
				for ty in range(by * tpp, mini((by + 1) * tpp, world_tiles.y)):
					for tx in range(bx * tpp, mini((bx + 1) * tpp, world_tiles.x)):
						if _floor_img.get_pixel(tx, ty).a > 0.0:
							known += 1
							var w := _wall_img.get_pixel(tx, ty)
							if w.a > 0.0:
								walls += 1
								wall_color = w
				if known > 0 and walls * 2 >= known:
					img.set_pixel(bx, by, wall_color)
				else:
					img.set_pixel(bx, by, Color(0, 0, 0, 0))


static func _ceil_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return (a + b - 1) / b


func _presentation_for(biome_id: StringName) -> BiomePresentation:
	var b := _streamer.config.biome_by_id(biome_id)
	if b != null and b.presentation != null:
		return b.presentation
	var fallback := _streamer.config.biome_by_id(_streamer.config.starting_biome)
	return fallback.presentation if fallback != null else null
