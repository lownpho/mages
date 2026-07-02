class_name WorldStreamer
## Layer 5: the read-through streaming cache view over Layers 2–4 (spec §11). Owns NO generation
## logic — it resolves which room units a chunk overlaps, pulls their RoomOutputs through an LRU
## cache, and blits the overlapping tile slices into a per-chunk node (WgChunk). Named
## `WorldStreamer` (not `ChunkStreamer`) to keep the read-through streamer distinct from a chunk.
##
## Caches (spec §11):
##   - BiomeGraph cache: RoomGraph instance, never evicted (a few KB each).
##   - Room cache: LRU keyed by unit_id, capacity ROOM_CACHE_CAPACITY. Eviction is always safe —
##     regeneration is byte-identical. Godot Dictionaries preserve insertion order, so erase +
##     reinsert on a hit is an O(1) LRU "touch" and keys()[0] is the least-recently-used entry.
##
## Streaming is driven by an assigned `target` Node2D (the fly camera / player): each frame it
## loads chunks covering the camera's visible rect + PREFETCH_RADIUS and unloads chunks past a
## larger hysteresis radius. Chunks outside the finite, sealed world are skipped. Single-threaded
## (WorkerThreadPool is Task 10's contingency).
extends Node2D

## Grass/wall/blocker/decor variant channels for the pure-hash tile pick (kept distinct so a
## tile's wall variant never correlates with its grass variant).
const _CH_GRASS := 1
const _CH_WALL := 2
const _CH_BLOCKER := 3
const _CH_DECOR := 4

const _MAX_LOADS_PER_FRAME := 3   ## smooth the initial burst; remaining chunks stream next frame
const _UNLOAD_MARGIN := 2         ## chunks; unload radius = load radius + this (hysteresis)

## Emitted right after a chunk enters the tree / right before one is freed. `spawns` carries the
## population entries overlapping the chunk with a `world_tile` field added (Task 9: the entity
## spawner instantiates/frees enemy scenes from these — spec §11 "spawn data, not nodes").
signal chunk_loaded(coord: Vector2i, spawns: Array)
signal chunk_unloaded(coord: Vector2i)

@export var config: GenConfig
@export var debug_spawn_markers := true   ## debug scene only; the game scene turns these off

var target: Node2D = null

var world_seed: int = 0
var world_spec: WorldSpec = null

var streaming: bool = true
var cache_hits: int = 0
var cache_misses: int = 0
var last_assembly_usec: int = 0

var _room_graphs: RoomGraph = null            # never-evicted BiomeGraph cache (spec §11)
var _room_cache: Dictionary = {}              # Vector2i unit_id -> RoomOutput, LRU by insertion order
var _chunks: Dictionary = {}                  # Vector2i chunk_coord -> WgChunk
var _fallback_pres: BiomePresentation = null  # glade's mapping; used for every biome for now
var _world_chunks := Vector2i.ZERO            # world size in chunks (finite bounds)


## (Re)build the world for a seed and reset all caches/chunks (spec §5 recompute-not-save).
func init(seed_value: int) -> void:
	world_seed = seed_value
	_clear_chunks()
	_room_cache.clear()
	cache_hits = 0
	cache_misses = 0
	world_spec = WorldLayout.build(seed_value, config)
	_room_graphs = RoomGraph.new()
	if world_spec != null:
		var s := config.BIOME_SIZE_SLOTS * config.ROOM_SLOT_SIZE
		_world_chunks = Vector2i(
			_ceil_div(world_spec.grid_w * s, config.CHUNK_SIZE),
			_ceil_div(world_spec.grid_h * s, config.CHUNK_SIZE))
	var glade := config.biome_by_id(&"glade")
	_fallback_pres = glade.presentation if glade != null else null
	if _fallback_pres == null:
		push_error("WorldStreamer: no glade presentation — chunks cannot render")


func reseed(seed_value: int) -> void:
	init(seed_value)


## Pause/resume the per-frame streaming loop (views 1–3 pause it; loaded chunks stay put).
func set_streaming(on: bool) -> void:
	streaming = on
	set_process(on)


func loaded_chunks() -> int:
	return _chunks.size()


func room_cache_size() -> int:
	return _room_cache.size()


## Test hook (spec §11: eviction is always safe). Dropping every cached room forces regeneration,
## which must reproduce byte-identical chunks.
func clear_room_cache() -> void:
	_room_cache.clear()


func _process(_dt: float) -> void:
	if not streaming or world_spec == null or target == null:
		return
	_update_streaming()


# --- Streaming loop -----------------------------------------------------------------------------

func _update_streaming() -> void:
	var chunk_px := config.CHUNK_SIZE * GameConstants.PX_PER_TILE
	var gp := target.global_position
	var cc := Vector2i(floori(gp.x / chunk_px), floori(gp.y / chunk_px))

	# Visible half-extent in chunks (from the active camera's zoom), padded by PREFETCH_RADIUS.
	var half_chunks := Vector2(config.PREFETCH_RADIUS, config.PREFETCH_RADIUS)
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.zoom.x > 0.0 and cam.zoom.y > 0.0:
		half_chunks = (get_viewport_rect().size * 0.5 / cam.zoom) / float(chunk_px)
	var rx := int(ceil(half_chunks.x)) + config.PREFETCH_RADIUS
	var ry := int(ceil(half_chunks.y)) + config.PREFETCH_RADIUS

	var loads := 0
	for gy in range(cc.y - ry, cc.y + ry + 1):
		for gx in range(cc.x - rx, cc.x + rx + 1):
			if gx < 0 or gy < 0 or gx >= _world_chunks.x or gy >= _world_chunks.y:
				continue
			var key := Vector2i(gx, gy)
			if _chunks.has(key):
				continue
			if loads >= _MAX_LOADS_PER_FRAME:
				continue
			var chunk := assemble_chunk(gx, gy)
			_chunks[key] = chunk
			add_child(chunk)
			chunk_loaded.emit(key, chunk.spawn_data)
			loads += 1

	var ux := rx + _UNLOAD_MARGIN
	var uy := ry + _UNLOAD_MARGIN
	var to_free: Array[Vector2i] = []
	for key in _chunks:
		var k: Vector2i = key
		if absi(k.x - cc.x) > ux or absi(k.y - cc.y) > uy:
			to_free.append(k)
	for k in to_free:
		chunk_unloaded.emit(k)
		_chunks[k].queue_free()
		_chunks.erase(k)


# --- Chunk assembly -----------------------------------------------------------------------------

## Build one chunk node fully populated (spec §11 pseudocode). Not added to the tree here.
func assemble_chunk(cx: int, cy: int) -> WgChunk:
	var t0 := Time.get_ticks_usec()
	var cs := config.CHUNK_SIZE
	var px := GameConstants.PX_PER_TILE
	var chunk := WgChunk.new()
	chunk.setup(Vector2i(cx, cy), Vector2(cx * cs, cy * cs) * px,
			_fallback_pres.floor_tileset, _fallback_pres.object_tileset, cs)

	if world_spec != null and _fallback_pres != null:
		_blit_chunk(chunk, cx, cy)

	last_assembly_usec = Time.get_ticks_usec() - t0
	return chunk


func _blit_chunk(chunk: WgChunk, cx: int, cy: int) -> void:
	var cs := config.CHUNK_SIZE
	var ss := config.ROOM_SLOT_SIZE
	var bs := config.BIOME_SIZE_SLOTS
	var tx0 := cx * cs
	var ty0 := cy * cs
	var slot_x0 := tx0 / ss
	var slot_x1 := (tx0 + cs - 1) / ss
	var slot_y0 := ty0 / ss
	var slot_y1 := (ty0 + cs - 1) / ss

	# ≤ 4 overlapped slots; merged units span 2 slots, so dedupe rooms by unit_id.
	var done: Dictionary = {}
	for sy in range(slot_y0, slot_y1 + 1):
		for sx in range(slot_x0, slot_x1 + 1):
			var bc := Vector2i(sx / bs, sy / bs)
			if world_spec.biome_at(bc) == &"":
				continue
			var graph := _room_graphs.get_biome_graph(world_spec, bc, config)
			var spec := graph.unit_at(Vector2i(sx % bs, sy % bs))
			if done.has(spec.unit_id):
				continue
			done[spec.unit_id] = true
			_blit_room(chunk, get_room_output(spec), tx0, ty0)


func _blit_room(chunk: WgChunk, room: RoomOutput, tx0: int, ty0: int) -> void:
	var cs := config.CHUNK_SIZE
	var ss := config.ROOM_SLOT_SIZE
	var utx0 := room.unit_id.x * ss   # room's world-tile origin
	var uty0 := room.unit_id.y * ss
	var rx0 := maxi(tx0, utx0)
	var ry0 := maxi(ty0, uty0)
	var rx1 := mini(tx0 + cs, utx0 + room.width)
	var ry1 := mini(ty0 + cs, uty0 + room.height)
	var pres := _presentation_for(room.biome_id)

	for wy in range(ry0, ry1):
		for wx in range(rx0, rx1):
			var cls := room.tile_grid[(wy - uty0) * room.width + (wx - utx0)]
			var cell := Vector2i(wx - tx0, wy - ty0)
			match cls:
				RoomBuilder.WALL:
					_place(chunk.wall, cell, pres.floor_source_id, wx, wy, _CH_WALL, pres.wall_tiles)
				RoomBuilder.BLOCKER:
					_place(chunk.ground, cell, pres.floor_source_id, wx, wy, _CH_GRASS, pres.grass_tiles)
					_place(chunk.decor, cell, pres.blocker_source_id, wx, wy, _CH_BLOCKER, pres.blocker_tiles)
				RoomBuilder.DECOR_FLOOR:
					_place(chunk.ground, cell, pres.floor_source_id, wx, wy, _CH_GRASS, pres.grass_tiles)
					_place(chunk.decor, cell, pres.decor_source_id, wx, wy, _CH_DECOR, pres.decor_tiles)
				_:   # FLOOR
					_place(chunk.ground, cell, pres.floor_source_id, wx, wy, _CH_GRASS, pres.grass_tiles)

	# Spawn data for this chunk (spec §9): entries overlapping it, with the world tile resolved.
	# Debug markers only in the debug scene; the game spawns real entities via chunk_loaded.
	for sp in room.spawns:
		if not (sp is Dictionary):
			continue
		var stile: Vector2i = sp.get("tile", Vector2i.ZERO)
		var wx: int = utx0 + stile.x
		var wy: int = uty0 + stile.y
		if wx < tx0 or wy < ty0 or wx >= tx0 + cs or wy >= ty0 + cs:
			continue
		var entry: Dictionary = sp.duplicate()
		entry["world_tile"] = Vector2i(wx, wy)
		chunk.spawn_data.append(entry)
		if debug_spawn_markers:
			chunk.add_spawn_marker(Vector2i(wx - tx0, wy - ty0), GameConstants.PX_PER_TILE, sp.has("item_id"))


# --- Room cache (LRU) ---------------------------------------------------------------------------

## Fetch a room's RoomOutput, generating on miss (spec §11). LRU touch = erase + reinsert.
func get_room_output(spec: RoomSpec) -> RoomOutput:
	var key := spec.unit_id
	if _room_cache.has(key):
		cache_hits += 1
		var hit: RoomOutput = _room_cache[key]
		_room_cache.erase(key)
		_room_cache[key] = hit
		return hit
	cache_misses += 1
	var out := RoomBuilder.build(spec, config, world_seed)
	_room_cache[key] = out
	if _room_cache.size() > config.ROOM_CACHE_CAPACITY:
		_room_cache.erase(_room_cache.keys()[0])   # evict least-recently-used
	return out


# --- Presentation helpers -----------------------------------------------------------------------

func _presentation_for(biome_id: StringName) -> BiomePresentation:
	var b := config.biome_by_id(biome_id)
	if b != null and b.presentation != null:
		return b.presentation
	return _fallback_pres   # placeholder: non-glade biomes render in glade tiles until Task 10


func _place(layer: TileMapLayer, cell: Vector2i, source: int, wx: int, wy: int,
		channel: int, arr: Array[Vector2i]) -> void:
	if arr.is_empty():
		return
	layer.set_cell(cell, source, _pick_atlas(wx, wy, channel, arr))


## Deterministic per-tile variant pick — pure function of (world_seed, tile, channel), so a
## rebuilt chunk is byte-identical and neighbouring chunks agree at their seam (gotcha 7).
## Formula: m = splitmix64(splitmix64(splitmix64(x) ^ splitmix64(y)) ^ channel);
##          index = (splitmix64(world_seed ^ m) & INT64_MAX) % n. No per-tile RNG object.
func _pick_atlas(wx: int, wy: int, channel: int, arr: Array[Vector2i]) -> Vector2i:
	if arr.size() <= 1:
		return arr[0]
	var m := WgHash.splitmix64(WgHash.splitmix64(wx) ^ WgHash.splitmix64(wy))
	m = WgHash.splitmix64(m ^ channel)
	var h := WgHash.splitmix64(world_seed ^ m)
	return arr[(h & 0x7fffffffffffffff) % arr.size()]


## Deterministic player spawn (Task 9): the center of the `traversal` unit nearest the center
## of the glade biome, validated against the room's reachability map (never a BLOCKER, never a
## sealed pocket — falls back to the nearest reachable tile). Returns a world pixel position.
func find_spawn_position() -> Vector2:
	var bc := Vector2i(-1, -1)
	for y in world_spec.grid_h:
		for x in world_spec.grid_w:
			if world_spec.biome_at(Vector2i(x, y)) == &"glade":
				bc = Vector2i(x, y)
	if bc.x < 0:
		bc = Vector2i.ZERO
	var graph := _room_graphs.get_biome_graph(world_spec, bc, config)
	var bs := config.BIOME_SIZE_SLOTS
	var center_slot := Vector2(bc * bs) + Vector2(bs, bs) * 0.5
	var best: RoomSpec = null
	var best_d := INF
	for u in graph.units:
		if u.type_id != &"traversal":
			continue
		var d := (Vector2(u.unit_id) + Vector2(u.size_slots) * 0.5).distance_squared_to(center_slot)
		if d < best_d:
			best_d = d
			best = u
	if best == null:
		best = graph.units[0]   # a biome with zero traversal units — config would have to force it
	var out := get_room_output(best)
	var cx := out.width >> 1
	var cy := out.height >> 1
	var tile := Vector2i(cx, cy)
	if out.reachability_map[cy * out.width + cx] == 0:
		var nearest := 0x7fffffffffffffff
		for ty in out.height:
			for tx in out.width:
				if out.reachability_map[ty * out.width + tx] == 1:
					var dd := (tx - cx) * (tx - cx) + (ty - cy) * (ty - cy)
					if dd < nearest:
						nearest = dd
						tile = Vector2i(tx, ty)
	var wt := best.unit_id * config.ROOM_SLOT_SIZE + tile
	return (Vector2(wt) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE


func _clear_chunks() -> void:
	for key in _chunks:
		chunk_unloaded.emit(key)
		_chunks[key].queue_free()
	_chunks.clear()


static func _ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b
