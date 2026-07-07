class_name WorldStreamer
## Layer 5: the read-through streaming cache view over Layers 2–4. Owns NO generation
## logic — it resolves which rooms a chunk overlaps, pulls their RoomOutputs through an LRU
## cache, and blits the overlapping tile slices into a per-chunk node (WgChunk).
##
## Caches:
##   - BiomeGraph cache: RoomGraph instance, never evicted (a few KB each).
##   - Room cache: LRU keyed by origin_slot, capacity room_cache_capacity. Eviction is always
##     safe — regeneration is byte-identical. Godot Dictionaries preserve insertion order, so
##     erase + reinsert on a hit is an O(1) LRU "touch" and keys()[0] is the LRU entry.
##
## Streaming is driven by an assigned `target` Node2D (the fly camera / player): each frame it
## loads chunks covering the camera's visible rect + prefetch_radius_chunks and unloads chunks
## past a larger hysteresis radius. Chunks outside the finite, sealed world are skipped.
## Single-threaded (WorkerThreadPool is the contingency plan).
extends Node2D

## Floor/wall/object/object_bg variant channels for the pure-hash tile pick (kept distinct so a
## tile's wall variant never correlates with its floor variant).
const _CH_FLOOR := 1
const _CH_WALL := 2
const _CH_OBJECT := 3
const _CH_OBJECT_BG := 4

## The 8 neighbours of the autotile mask, bit i = _NB[i] is same-terrain. Order (N, NE, E, SE, S,
## SW, W, NW) pairs each offset with the TileSet peering bit it corresponds to, so masks computed
## from the logical grid line up with masks read from the tileset's authored terrain data.
const _NB: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const _NB_PEERING: Array[int] = [
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
]
## Which logical classes count as "same terrain" for each autotiled layer.
enum _Terrain { T_FLOOR, T_WALL }

const _MAX_LOADS_PER_FRAME := 3   ## smooth the initial burst; remaining chunks stream next frame
const _UNLOAD_MARGIN := 2         ## chunks; unload radius = load radius + this (hysteresis)
## Ring of solid-wall chunks streamed just OUTSIDE the finite world so the player never sees void
## past the sealed edge. Cells beyond any room are filled with the starting biome's wall tiles
## (see _fill_border). Bounded so a zoomed-out fly cam can't spawn an unbounded wall field.
const _BORDER_CHUNKS := 4

## Emitted right after a chunk enters the tree / right before one is freed. `spawns` carries the
## population entries overlapping the chunk with a `world_tile` field added (the entity spawner
## instantiates/frees enemy scenes from these — "spawn data, not nodes").
signal chunk_loaded(coord: Vector2i, spawns: Array)
signal chunk_unloaded(coord: Vector2i)
## Emitted when the streaming target crosses into a different biome cell, including the
## biome it starts in on the first streamed frame. Pure observation of the target's
## position against the layout — no generation state, so GEN_VERSION is unaffected.
## world.gd relays this onto GlobalEvent for game systems (bestiary).
signal biome_entered(biome_id: StringName)

@export var config: GenConfig
@export var debug_spawn_markers := true   ## debug scene only; the game scene turns these off

## What streaming follows (usually the player). Assigned in code after build_world().
var target: Node2D = null

var world_seed: int = 0
var world_spec: WorldSpec = null

## Pause/resume the per-frame streaming loop (debug views 1–3 pause it; loaded chunks stay put).
var streaming: bool = true:
	set(on):
		streaming = on
		set_process(on)

var cache_hits: int = 0
var cache_misses: int = 0
var last_assembly_usec: int = 0

var _room_graphs: RoomGraph = null            # never-evicted BiomeGraph cache
var _room_cache: Dictionary = {}              # Vector2i origin_slot -> RoomOutput, LRU by insertion order
var _chunks: Dictionary = {}                  # Vector2i chunk_coord -> WgChunk
var _fallback_pres: BiomePresentation = null  # starting biome's mapping; fallback for biomes without one
var _world_chunks := Vector2i.ZERO            # world size in chunks (finite bounds)
var _last_biome: StringName = &""             # target's biome cell on the previous streamed frame
var _tile_tables: Dictionary = {}             # TileSet -> weighted pick table (built once, see _tile_table)
var _terrain_tables: Dictionary = {}          # TileSet -> { canonical mask -> pick table } (see _terrain_table)


## (Re)build the world for a seed and reset all caches/chunks.
func build_world(seed_value: int) -> void:
	world_seed = seed_value
	_clear_chunks()
	_room_cache.clear()
	_last_biome = &""
	cache_hits = 0
	cache_misses = 0
	world_spec = WorldLayout.build(seed_value, config)
	_room_graphs = RoomGraph.new()
	if world_spec != null:
		var s := config.biome_slots * config.room_slot_tiles
		_world_chunks = Vector2i(
			_ceil_div(world_spec.grid_w * s, config.chunk_tiles),
			_ceil_div(world_spec.grid_h * s, config.chunk_tiles))
	var start_biome := config.biome_by_id(config.starting_biome)
	_fallback_pres = start_biome.presentation if start_biome != null else null
	if _fallback_pres == null:
		push_error("WorldStreamer: starting biome '%s' has no presentation — chunks cannot render"
				% config.starting_biome)


func loaded_chunks() -> int:
	return _chunks.size()


func room_cache_size() -> int:
	return _room_cache.size()


## Test hook. Dropping every cached room forces regeneration,
## which must reproduce byte-identical chunks.
func clear_room_cache() -> void:
	_room_cache.clear()


func _process(_dt: float) -> void:
	if not streaming or world_spec == null or target == null:
		return
	_update_streaming()


# --- Streaming loop -----------------------------------------------------------------------------

func _update_streaming() -> void:
	var chunk_px := config.chunk_tiles * GameConstants.PX_PER_TILE
	var gp := target.global_position
	var cc := Vector2i(floori(gp.x / chunk_px), floori(gp.y / chunk_px))

	var biome_px := config.biome_slots * config.room_slot_tiles * GameConstants.PX_PER_TILE
	var biome := world_spec.biome_at(Vector2i(floori(gp.x / biome_px), floori(gp.y / biome_px)))
	if biome != &"" and biome != _last_biome:
		_last_biome = biome
		biome_entered.emit(biome)

	# Visible half-extent in chunks (from the active camera's zoom), padded by the prefetch radius.
	var half_chunks := Vector2(config.prefetch_radius_chunks, config.prefetch_radius_chunks)
	var cam := get_viewport().get_camera_2d()
	if cam != null and cam.zoom.x > 0.0 and cam.zoom.y > 0.0:
		half_chunks = (get_viewport_rect().size * 0.5 / cam.zoom) / float(chunk_px)
	var rx := int(ceil(half_chunks.x)) + config.prefetch_radius_chunks
	var ry := int(ceil(half_chunks.y)) + config.prefetch_radius_chunks

	var loads := 0
	for gy in range(cc.y - ry, cc.y + ry + 1):
		for gx in range(cc.x - rx, cc.x + rx + 1):
			if gx < -_BORDER_CHUNKS or gy < -_BORDER_CHUNKS \
					or gx >= _world_chunks.x + _BORDER_CHUNKS or gy >= _world_chunks.y + _BORDER_CHUNKS:
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

## Build one chunk node fully populated. Not added to the tree here.
func assemble_chunk(cx: int, cy: int) -> WgChunk:
	var t0 := Time.get_ticks_usec()
	var cs := config.chunk_tiles
	var px := GameConstants.PX_PER_TILE
	var chunk := WgChunk.new()
	chunk.setup(Vector2i(cx, cy), Vector2(cx * cs, cy * cs) * px, cs)

	if world_spec != null and _fallback_pres != null:
		_blit_chunk(chunk, cx, cy)

	last_assembly_usec = Time.get_ticks_usec() - t0
	return chunk


func _blit_chunk(chunk: WgChunk, cx: int, cy: int) -> void:
	var cs := config.chunk_tiles
	var ss := config.room_slot_tiles
	var bs := config.biome_slots
	var tx0 := cx * cs
	var ty0 := cy * cs
	@warning_ignore_start("integer_division")
	var slot_x0 := tx0 / ss
	var slot_x1 := (tx0 + cs - 1) / ss
	var slot_y0 := ty0 / ss
	var slot_y1 := (ty0 + cs - 1) / ss
	@warning_ignore_restore("integer_division")

	# Coverage mask: which chunk cells a room wrote. Cells left uncovered (out past the sealed
	# world edge) are walled by _fill_border so the player never sees void.
	var covered := PackedByteArray()
	covered.resize(cs * cs)

	# ≤ 4 overlapped slots; merged rooms span 2 slots, so dedupe rooms by origin_slot.
	var world_slots_w := world_spec.grid_w * bs
	var world_slots_h := world_spec.grid_h * bs
	var done: Dictionary = {}
	for sy in range(slot_y0, slot_y1 + 1):
		for sx in range(slot_x0, slot_x1 + 1):
			# Skip slots outside the finite world (border chunks straddle the edge). Explicit —
			# integer division truncates toward zero, so slightly-negative coords would otherwise
			# alias to slot 0 / a negative modulo into room_at.
			if sx < 0 or sy < 0 or sx >= world_slots_w or sy >= world_slots_h:
				continue
			@warning_ignore("integer_division")
			var bc := Vector2i(sx / bs, sy / bs)
			if world_spec.biome_at(bc) == &"":
				continue
			var graph := _room_graphs.get_biome_graph(world_spec, bc, config)
			var spec := graph.room_at(Vector2i(sx % bs, sy % bs))
			if done.has(spec.origin_slot):
				continue
			done[spec.origin_slot] = true
			_blit_room(chunk, get_room_output(spec), tx0, ty0, covered)

	_fill_border(chunk, covered, tx0, ty0)


func _blit_room(chunk: WgChunk, room: RoomOutput, tx0: int, ty0: int, covered: PackedByteArray) -> void:
	var cs := config.chunk_tiles
	var ss := config.room_slot_tiles
	var utx0 := room.origin_slot.x * ss   # room's world-tile origin
	var uty0 := room.origin_slot.y * ss
	var rx0 := maxi(tx0, utx0)
	var ry0 := maxi(ty0, uty0)
	var rx1 := mini(tx0 + cs, utx0 + room.width)
	var ry1 := mini(ty0 + cs, uty0 + room.height)
	var pres := _presentation_for(room.biome_id)
	var lyr := chunk.layers_for(room.biome_id, pres)
	# Resolve the per-layer pick tables once per room (each is cached; keeps the per-cell loop lean).
	var t_floor := _tile_table(pres.floor_tileset)
	var t_wall := _tile_table(pres.wall_tileset)
	var t_object := _tile_table(pres.object_tileset)
	var t_object_bg := _tile_table(pres.object_bg_tileset)
	var tt_floor := _terrain_table(pres.floor_tileset) if pres.floor_autotile else {}
	var tt_wall := _terrain_table(pres.wall_tileset) if pres.wall_autotile else {}

	for wy in range(ry0, ry1):
		for wx in range(rx0, rx1):
			var cls := room.tile_grid[(wy - uty0) * room.width + (wx - utx0)]
			var cell := Vector2i(wx - tx0, wy - ty0)
			covered[cell.y * cs + cell.x] = 1
			# Every non-floor object (wall/blocker/decor) also lays a floor tile beneath it, so
			# tree-walls and blockers — which are transparent around the trunk — never sit on void.
			_place_floor(lyr.floor, cell, room, wx, wy, t_floor, tt_floor)
			match cls:
				RoomBuilder.WALL:
					if tt_wall.is_empty():
						_place(lyr.wall, cell, wx, wy, _CH_WALL, t_wall)
					else:
						_place_auto(lyr.wall, cell, wx, wy, _CH_WALL,
								_mask_for(room, wx, wy, _Terrain.T_WALL), tt_wall, t_wall)
				RoomBuilder.BLOCKER:
					_place(lyr.object, cell, wx, wy, _CH_OBJECT, t_object)
				RoomBuilder.DECOR_FLOOR:
					_place(lyr.object_bg, cell, wx, wy, _CH_OBJECT_BG, t_object_bg)
				_:
					pass   # FLOOR: already laid above

	# Spawn data for this chunk: entries overlapping it, with the world tile resolved.
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
			chunk.add_spawn_marker(Vector2i(wx - tx0, wy - ty0), GameConstants.PX_PER_TILE, false)


## Fill every chunk cell no room wrote (out past the sealed world edge) with the starting biome's
## solid wall tiles, so a player standing at the edge sees a wall of terrain instead of void. Uses
## the same deterministic per-tile variant pick as rooms, on the shared starting-biome layers.
func _fill_border(chunk: WgChunk, covered: PackedByteArray, tx0: int, ty0: int) -> void:
	var cs := config.chunk_tiles
	var lyr := chunk.layers_for(config.starting_biome, _fallback_pres)
	var t_floor := _tile_table(_fallback_pres.floor_tileset)
	var t_wall := _tile_table(_fallback_pres.wall_tileset)
	var tt_wall := _terrain_table(_fallback_pres.wall_tileset) if _fallback_pres.wall_autotile else {}
	for cy in cs:
		for cx in cs:
			if covered[cy * cs + cx] == 1:
				continue
			var cell := Vector2i(cx, cy)
			var wx := tx0 + cx
			var wy := ty0 + cy
			# Floor beneath the wall so transparent-around-trunk wall art never shows void.
			_place(lyr.floor, cell, wx, wy, _CH_FLOOR, t_floor)
			if tt_wall.is_empty():
				_place(lyr.wall, cell, wx, wy, _CH_WALL, t_wall)
			else:
				_place_auto(lyr.wall, cell, wx, wy, _CH_WALL,
						_mask_world(wx, wy, _Terrain.T_WALL), tt_wall, t_wall)


# --- Room cache (LRU) ---------------------------------------------------------------------------

## Fetch a room's RoomOutput, generating on miss. LRU touch = erase + reinsert.
func get_room_output(spec: RoomSpec) -> RoomOutput:
	var key := spec.origin_slot
	if _room_cache.has(key):
		cache_hits += 1
		var hit: RoomOutput = _room_cache[key]
		_room_cache.erase(key)
		_room_cache[key] = hit
		return hit
	cache_misses += 1
	var out := RoomBuilder.build(spec, config, world_seed)
	_room_cache[key] = out
	if _room_cache.size() > config.room_cache_capacity:
		_room_cache.erase(_room_cache.keys()[0])   # evict least-recently-used
	return out


# --- Presentation helpers -----------------------------------------------------------------------

func _presentation_for(biome_id: StringName) -> BiomePresentation:
	var b := config.biome_by_id(biome_id)
	if b != null and b.presentation != null:
		return b.presentation
	return _fallback_pres   # biomes without their own art render in the starting biome's tiles


func _place(layer: TileMapLayer, cell: Vector2i, wx: int, wy: int,
		channel: int, t: Dictionary) -> void:
	if layer == null:
		return
	var total: int = t.total
	if total <= 0:
		return   # empty/unset tileset — nothing to place
	var source_id: int = t.source_id
	layer.set_cell(cell, source_id, _pick_weighted(wx, wy, channel, t))


## Per-tileset pick table, built once and cached: EVERY tile of the tileset's first source, with
## integer cumulative weights from each tile's `probability` (— art picks read the
## tileset, not a curated subset). Probability is scaled ×1000 (min 1 for any non-zero tile) so
## selection stays pure-integer and cross-platform deterministic. Fields: source_id, coords
## (Array[Vector2i]), cum (PackedInt64Array cumulative weights), total (int).
func _tile_table(tileset: TileSet) -> Dictionary:
	if _tile_tables.has(tileset):
		return _tile_tables[tileset]
	var coords: Array[Vector2i] = []
	var cum := PackedInt64Array()
	var acc := 0
	var source_id := -1
	if tileset != null and tileset.get_source_count() > 0:
		source_id = tileset.get_source_id(0)
		var src := tileset.get_source(source_id) as TileSetAtlasSource
		if src != null:
			for i in src.get_tiles_count():
				var coord := src.get_tile_id(i)
				var td := src.get_tile_data(coord, 0)
				var w := 1000
				if td != null:
					w = maxi(1, roundi(td.probability * 1000.0))
					if td.probability <= 0.0:
						continue   # probability 0 → never placed
				acc += w
				coords.append(coord)
				cum.append(acc)
	var t := {"source_id": source_id, "coords": coords, "cum": cum, "total": acc}
	_tile_tables[tileset] = t
	return t


## Deterministic per-tile variant pick — pure function of (world_seed, tile, channel), so a
## rebuilt chunk is byte-identical and neighbouring chunks agree at their seam.
## Hashes to a value in [0, total) then binary-searches the cumulative weight table.
func _pick_weighted(wx: int, wy: int, channel: int, t: Dictionary) -> Vector2i:
	var coords: Array[Vector2i] = t.coords
	if coords.size() <= 1:
		return coords[0]
	var total: int = t.total
	var m := WgHash.splitmix64(WgHash.splitmix64(wx) ^ WgHash.splitmix64(wy))
	m = WgHash.splitmix64(m ^ channel)
	var h := WgHash.splitmix64(world_seed ^ m)
	var r := (h & 0x7fffffffffffffff) % total
	var cum: PackedInt64Array = t.cum
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if cum[mid] <= r:
			lo = mid + 1
		else:
			hi = mid
	return coords[lo]


# --- Autotile ------------------------------------------------------------------------------------

## Scatter-pick floor unless the presentation autotiles it (then the neighbour mask picks the tile).
func _place_floor(layer: TileMapLayer, cell: Vector2i, room: RoomOutput, wx: int, wy: int,
		t: Dictionary, tt: Dictionary) -> void:
	if tt.is_empty():
		_place(layer, cell, wx, wy, _CH_FLOOR, t)
	else:
		_place_auto(layer, cell, wx, wy, _CH_FLOOR,
				_mask_for(room, wx, wy, _Terrain.T_FLOOR), tt, t)


## Set one autotiled cell: the canonical neighbour mask selects the terrain pick table; masks the
## tileset doesn't author fall back to the scatter pick, so partial terrain sets degrade gracefully.
func _place_auto(layer: TileMapLayer, cell: Vector2i, wx: int, wy: int, channel: int,
		mask: int, tt: Dictionary, fallback: Dictionary) -> void:
	if layer == null:
		return
	var t: Dictionary = tt.get(mask, {})
	if t.is_empty():
		_place(layer, cell, wx, wy, channel, fallback)
		return
	layer.set_cell(cell, t.source_id, _pick_weighted(wx, wy, channel, t))


## 8-neighbour same-terrain mask for a tile inside `room` — neighbours still inside the room read
## its grid directly; neighbours past the room edge resolve through the room cache. Pure function
## of the deterministic class grids, so seams agree no matter which chunk/room computes them.
func _mask_for(room: RoomOutput, wx: int, wy: int, kind: int) -> int:
	var ss := config.room_slot_tiles
	var lx := wx - room.origin_slot.x * ss
	var ly := wy - room.origin_slot.y * ss
	var m := 0
	for i in 8:
		var nx := lx + _NB[i].x
		var ny := ly + _NB[i].y
		var cls: int
		if nx >= 0 and ny >= 0 and nx < room.width and ny < room.height:
			cls = room.tile_grid[ny * room.width + nx]
		else:
			cls = _class_at(wx + _NB[i].x, wy + _NB[i].y)
		if _same_terrain(cls, kind):
			m |= 1 << i
	return _canonical_mask(m)


## Mask for a tile with no room context (border fill outside the sealed world).
func _mask_world(wx: int, wy: int, kind: int) -> int:
	var m := 0
	for i in 8:
		if _same_terrain(_class_at(wx + _NB[i].x, wy + _NB[i].y), kind):
			m |= 1 << i
	return _canonical_mask(m)


## Whether a logical class continues a layer's terrain. Walls connect to walls and to the sealed
## void past the world edge; floors connect to walkable ground only, so floor terrain sets get
## edge tiles against walls/blockers (the floor laid BENEATH those solids reads as edge too, which
## is fine — it is covered by the solid's art).
func _same_terrain(cls: int, kind: int) -> bool:
	if kind == _Terrain.T_WALL:
		return cls == RoomBuilder.WALL or cls == -1
	return cls == RoomBuilder.FLOOR or cls == RoomBuilder.DECOR_FLOOR


## RoomSpec covering a world tile, resolved through the graph cache; null outside the world.
## Public read-through — the minimap uses it to map the player's tile to a discoverable room.
func room_spec_at_tile(wx: int, wy: int) -> RoomSpec:
	if world_spec == null or wx < 0 or wy < 0:
		return null
	var ss := config.room_slot_tiles
	var bs := config.biome_slots
	@warning_ignore_start("integer_division")
	var sx := wx / ss
	var sy := wy / ss
	var bc := Vector2i(sx / bs, sy / bs)
	@warning_ignore_restore("integer_division")
	if sx >= world_spec.grid_w * bs or sy >= world_spec.grid_h * bs:
		return null
	if world_spec.biome_at(bc) == &"":
		return null
	var graph := _room_graphs.get_biome_graph(world_spec, bc, config)
	return graph.room_at(Vector2i(sx % bs, sy % bs))


## Logical tile class at any world tile, resolved through the room cache; -1 outside the world.
func _class_at(wx: int, wy: int) -> int:
	var spec := room_spec_at_tile(wx, wy)
	if spec == null:
		return -1
	var room := get_room_output(spec)
	var lx := wx - room.origin_slot.x * config.room_slot_tiles
	var ly := wy - room.origin_slot.y * config.room_slot_tiles
	return room.tile_grid[ly * room.width + lx]


## Corner bits only matter when both adjacent sides are set (the standard 47-blob rule) — clearing
## the meaningless ones collapses the 256 raw masks onto the ones tilesets actually author.
static func _canonical_mask(m: int) -> int:
	if (m & 0b0000_0101) != 0b0000_0101:
		m &= ~0b0000_0010   # NE needs N+E
	if (m & 0b0001_0100) != 0b0001_0100:
		m &= ~0b0000_1000   # SE needs E+S
	if (m & 0b0101_0000) != 0b0101_0000:
		m &= ~0b0010_0000   # SW needs S+W
	if (m & 0b0100_0001) != 0b0100_0001:
		m &= ~0b1000_0000   # NW needs W+N
	return m


## Per-tileset autotile table, built once and cached: canonical mask -> weighted pick table over
## the tiles of source 0 that declare that mask via terrain peering bits (standard Godot terrain
## painting; any terrain set/index counts). Tiles with no terrain are ignored here — they stay
## available to the scatter table. Empty dict when the tileset authors no terrain at all.
func _terrain_table(tileset: TileSet) -> Dictionary:
	if _terrain_tables.has(tileset):
		return _terrain_tables[tileset]
	var groups: Dictionary = {}   # mask -> Array of [coord, weight]
	var source_id := -1
	if tileset != null and tileset.get_source_count() > 0:
		source_id = tileset.get_source_id(0)
		var src := tileset.get_source(source_id) as TileSetAtlasSource
		if src != null:
			for i in src.get_tiles_count():
				var coord := src.get_tile_id(i)
				var td := src.get_tile_data(coord, 0)
				if td == null or td.terrain_set < 0 or td.terrain < 0 or td.probability <= 0.0:
					continue
				var mask := 0
				for b in 8:
					if td.is_valid_terrain_peering_bit(_NB_PEERING[b]) \
							and td.get_terrain_peering_bit(_NB_PEERING[b]) == td.terrain:
						mask |= 1 << b
				mask = _canonical_mask(mask)
				if not groups.has(mask):
					groups[mask] = []
				groups[mask].append([coord, maxi(1, roundi(td.probability * 1000.0))])
	var by_mask: Dictionary = {}
	for mask in groups:
		var coords: Array[Vector2i] = []
		var cum := PackedInt64Array()
		var acc := 0
		for pair in groups[mask]:
			acc += pair[1]
			coords.append(pair[0])
			cum.append(acc)
		by_mask[mask] = {"source_id": source_id, "coords": coords, "cum": cum, "total": acc}
	_terrain_tables[tileset] = by_mask
	return by_mask


## Deterministic player spawn: the lowest-difficulty room, ties broken by entrance depth then by
## distance to the starting biome's center — so the spawn sits at the easy end of the difficulty
## ramp. Validated against the room's reachability map (never a BLOCKER, never
## a sealed pocket — falls back to the nearest reachable tile). Returns a world pixel position.
func find_spawn_position() -> Vector2:
	var bc := Vector2i(-1, -1)
	for y in world_spec.grid_h:
		for x in world_spec.grid_w:
			if world_spec.biome_at(Vector2i(x, y)) == config.starting_biome:
				bc = Vector2i(x, y)
	if bc.x < 0:
		bc = Vector2i.ZERO
	var graph := _room_graphs.get_biome_graph(world_spec, bc, config)
	var bs := config.biome_slots
	var center_slot := Vector2(bc * bs) + Vector2(bs, bs) * 0.5
	var best: RoomSpec = null
	var best_diff := 99
	var best_d := INF
	for u in graph.rooms:
		var rt := config.room_type_by_id(u.type_id)
		var diff: int = rt.difficulty if rt != null else 0
		var d := (Vector2(u.origin_slot) + Vector2(u.size_slots) * 0.5).distance_squared_to(center_slot)
		if best == null or diff < best_diff or (diff == best_diff \
				and (u.depth < best.depth or (u.depth == best.depth and d < best_d))):
			best_diff = diff
			best_d = d
			best = u
	if best == null:
		best = graph.rooms[0]   # unreachable: every biome has at least one room
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
	var wt := best.origin_slot * config.room_slot_tiles + tile
	return (Vector2(wt) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE


func _clear_chunks() -> void:
	for key in _chunks:
		chunk_unloaded.emit(key)
		_chunks[key].queue_free()
	_chunks.clear()


static func _ceil_div(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	return (a + b - 1) / b
