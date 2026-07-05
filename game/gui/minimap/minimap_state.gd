class_name MinimapState
## Discovered-world model behind the strip minimap: which rooms the player has entered, two
## world-sized images (1 px per world tile — floor silhouette + wall/blocker overlay), and the
## static markers recorded when a room is discovered. Pure presentation over the deterministic
## room cache, so the whole thing rebuilds from {world_seed, discovered slots} — that pair is
## the entire save format (see to_dict/restore).
extends RefCounted

enum { MARKER_BOSS, MARKER_FEATURE }

## Room types whose discovery drops a MARKER_BOSS at the room centre.
const BOSS_TYPE := &"boss"

var world_seed: int = 0
var world_tiles := Vector2i.ZERO      ## image dimensions (1 px per tile)
var discovered: Dictionary = {}       ## origin_slot (Vector2i) -> true
var markers: Array = []               ## of {tile: Vector2i (world), kind: MARKER_*}
var floor_texture: ImageTexture = null
var wall_texture: ImageTexture = null

var _floor_img: Image = null
var _wall_img: Image = null
var _streamer: WorldStreamer = null


func setup(streamer: WorldStreamer) -> void:
	_streamer = streamer
	world_seed = streamer.world_seed
	var s := streamer.config.biome_slots * streamer.config.room_slot_tiles
	world_tiles = Vector2i(streamer.world_spec.grid_w * s, streamer.world_spec.grid_h * s)
	_floor_img = Image.create_empty(world_tiles.x, world_tiles.y, false, Image.FORMAT_RGBA8)
	_wall_img = Image.create_empty(world_tiles.x, world_tiles.y, false, Image.FORMAT_RGBA8)
	floor_texture = ImageTexture.create_from_image(_floor_img)
	wall_texture = ImageTexture.create_from_image(_wall_img)
	discovered.clear()
	markers.clear()


## Reveal the room covering a world tile (no-op on fog-of-war misses: outside the world or
## already discovered). Returns true when a new room was painted.
func discover_at(world_tile: Vector2i) -> bool:
	var spec := _streamer.room_spec_at_tile(world_tile.x, world_tile.y)
	if spec == null or discovered.has(spec.origin_slot):
		return false
	discovered[spec.origin_slot] = true
	_paint_room(_streamer.get_room_output(spec))
	floor_texture.update(_floor_img)
	wall_texture.update(_wall_img)
	return true


## True once the room under a world tile has been revealed. Reads the painted image (any
## discovered pixel is opaque), so callers need no room lookup.
func is_tile_discovered(world_tile: Vector2i) -> bool:
	if world_tile.x < 0 or world_tile.y < 0 \
			or world_tile.x >= world_tiles.x or world_tile.y >= world_tiles.y:
		return false
	return _floor_img.get_pixelv(world_tile).a > 0.0


## Minimal save payload; images and markers are re-derived by restore() through the
## deterministic room cache.
func to_dict() -> Dictionary:
	return {"world_seed": world_seed, "discovered": discovered.keys()}


func restore(dict: Dictionary) -> void:
	var ss: int = _streamer.config.room_slot_tiles
	for slot in dict.get("discovered", []):
		discover_at(slot * ss)   # a room's origin slot's top-left tile is inside the room


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
	if room.type_id == BOSS_TYPE:
		markers.append({"tile": Vector2i(ox + (room.width >> 1), oy + (room.height >> 1)),
				"kind": MARKER_BOSS})
	for sp in room.spawns:
		if sp is Dictionary and sp.has("feature"):
			var t: Vector2i = sp.get("tile", Vector2i.ZERO)
			markers.append({"tile": Vector2i(ox + t.x, oy + t.y), "kind": MARKER_FEATURE})


func _presentation_for(biome_id: StringName) -> BiomePresentation:
	var b := _streamer.config.biome_by_id(biome_id)
	if b != null and b.presentation != null:
		return b.presentation
	var fallback := _streamer.config.biome_by_id(_streamer.config.starting_biome)
	return fallback.presentation if fallback != null else null
