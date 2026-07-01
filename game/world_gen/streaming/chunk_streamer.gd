class_name ChunkStreamer extends Node
## Streams the overworld around the player: builds chunks within `load_radius`, discards them
## beyond `unload_radius`, and rebuilds them identically on return (everything is a pure function
## of the seed, so there is no chunk state to persist). Per chunk it asks MacroMap which biome
## each cell is, buckets cells by biome, and hands each bucket to that biome's cached painter —
## reusing one GenContext pointed at that biome's layers. Off-world cells (biome_at null) paint
## nothing.
##
## Each biome owns a `floor_<id>`/`decor_<id>`/`objects_<id>` layer trio in the scene, wired by
## id at init. Painters spawn no enemies yet (Group G), but the per-chunk enemy-tracking scaffold
## is kept: children a chunk's painters add to the shared y-sorted `Enemies` node are recorded so
## unload frees exactly them.

const _DOOR := preload("res://overworld/door.tscn")
const _PORTAL := preload("res://world_gen/runtime/portal.tscn")
const _SIGN := preload("res://world_gen/runtime/sign.tscn")
const _DUNGEON_PLACEHOLDER := preload("res://world_gen/runtime/dungeon_placeholder.tscn")

@export var world_graph: WorldGraph                    # authored biome graph; embedded per seed
@export_range(8, 128, 1) var chunk_size := 32          # tiles per chunk side
@export_range(1, 8, 1) var load_radius := 2            # chunks kept built around the player (Chebyshev)
@export_range(1, 12, 1) var unload_radius := 3         # chunks beyond this are discarded (must be > load_radius)
@export_range(1, 16, 1) var gen_budget_per_frame := 2  # chunks built per frame from the queue (amortised)

var _macro: MacroMap
var _ctx: GenContext
var _world_seed: int
var _player: Node2D
var _enemies_root: Node2D
var _specials_root: Node2D                 # y-sorted container for doors/portals (Group H)
var _layers := {}                          # biome id -> {ground, decor, objects}
var _all_layers: Array[TileMapLayer] = []  # every layer, for blanket erase on unload
var _painters := {}                        # biome id -> BiomePainter instance (cached: holds clump noise)

var _chunks := {}                          # coord:Vector2i -> Array[Node] (the chunk's spawned enemies)
var _queue: Array[Vector2i] = []
var _last_center := Vector2i(2147483647, 0)  # force a refresh on the first frame


## Called by world.gd after the seed is resolved. Builds the MacroMap, wires each biome's layer
## trio + cached painter, primes the chunks around the player synchronously (so the first frame is
## already populated), then streaming takes over.
func init(world_seed: int) -> void:
	_world_seed = world_seed
	_player = get_tree().get_first_node_in_group("player")
	_enemies_root = _world().get_node("Entities/Enemies")
	_specials_root = _world().get_node("Entities/Specials")

	_macro = MacroMap.new()
	_macro.setup(world_seed, world_graph)

	_ctx = GenContext.new()
	_ctx.macro = _macro
	_ctx.enemies = _enemies_root

	# Derive the biome list from the graph (one region per node), wiring each biome's layer trio
	# by id and caching one painter instance (painters may hold per-biome noise state).
	for node in world_graph.nodes:
		var biome: Resource = node.biome
		if biome == null or _layers.has(biome.id):
			continue
		var id := String(biome.id)
		var trio := {
			"ground": _world().get_node("floor_%s" % id) as TileMapLayer,
			"decor": _world().get_node("decor_%s" % id) as TileMapLayer,
			"objects": _world().get_node("Entities/objects_%s" % id) as TileMapLayer,
		}
		_layers[biome.id] = trio
		_all_layers.append(trio.ground)
		_all_layers.append(trio.decor)
		_all_layers.append(trio.objects)
		_painters[biome.id] = (biome.painter.new() if biome.painter else BiomePainter.new())

	# Position the player at a validated Glade spawn BEFORE priming — the prime radius is centred
	# on the player, so it must sit at its final spot first.
	if _player:
		_player.global_position = spawn_position()

	var center := _player_chunk()
	_last_center = center
	for c in _wanted(center):
		_build_chunk(c)


## The live macro layout, for read-only queries (the debug minimap overlay). Null before `init`.
func macro() -> MacroMap:
	return _macro


## The seed the current world was built from (init or the last reseed) — for the debug HUD.
func current_seed() -> int:
	return _world_seed


## Tear down the current world and rebuild it from `new_seed` (debug reroll). Frees every spawned
## node, wipes all painted cells, re-bakes the MacroMap, rebuilds the cached painters (they hold
## per-seed clump noise), repositions the player at the new spawn, and re-primes. Deterministic: a
## given `new_seed` reproduces exactly the world launching with it would.
func reseed(new_seed: int) -> void:
	for coord in _chunks:
		for e in _chunks[coord]:
			if is_instance_valid(e):
				e.free()
	for layer in _all_layers:
		layer.clear()
	_chunks.clear()
	_queue.clear()
	_last_center = Vector2i(2147483647, 0)

	_world_seed = new_seed
	_macro.setup(new_seed, world_graph)
	_ctx.macro = _macro

	# Painters cache per-seed clump noise, so a stale instance would draw the old seed's patches.
	_painters.clear()
	for node in world_graph.nodes:
		var biome: Resource = node.biome
		if biome == null or _painters.has(biome.id):
			continue
		_painters[biome.id] = (biome.painter.new() if biome.painter else BiomePainter.new())

	if _player:
		_player.global_position = spawn_position()
	var center := _player_chunk()
	_last_center = center
	for c in _wanted(center):
		_build_chunk(c)


## World-centre pixel of a spawn tile that is always valid ground in the Glade start biome: in-world,
## off the edge, inside the cover-clear pocket so nothing is on top of the player. Origin satisfies
## all of this by construction (start biome pinned at lattice (0,0), pocket cleared around origin);
## this verifies it and spirals outward to the nearest valid tile if a seed ever breaks that. Pure
## function of the seed.
func spawn_position() -> Vector2:
	return _ctx.tile_to_world(_spawn_tile())


func _spawn_tile() -> Vector2i:
	var start: Resource = world_graph.nodes[world_graph.start_index].biome
	for r in range(ForestPainter.SPAWN_CLEAR + 1):
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if max(abs(x), abs(y)) != r:   # only the newly reached ring
					continue
				var tile := Vector2i(x, y)
				if _is_valid_spawn(tile, start):
					return tile
	push_warning("ChunkStreamer: no valid spawn near origin; using origin")
	return Vector2i.ZERO


func _is_valid_spawn(tile: Vector2i, start: Resource) -> bool:
	if not _macro.in_world(tile) or _macro.is_world_edge(tile):
		return false
	if _macro.biome_at(tile) != start:
		return false
	# Inside the painter's cover-clear pocket → no tree/wall lands on the spawn tile.
	return tile.x * tile.x + tile.y * tile.y <= ForestPainter.SPAWN_CLEAR * ForestPainter.SPAWN_CLEAR


func _process(_dt: float) -> void:
	if not _player:
		return
	var center := _player_chunk()
	if center != _last_center:
		_last_center = center
		_refresh(center)
	_drain_queue()


# Enqueue missing chunks in range (nearest first) and unload the ones that drifted too far.
func _refresh(center: Vector2i) -> void:
	for c in _wanted(center):
		if not _chunks.has(c) and not _queue.has(c):
			_queue.append(c)
	_queue.sort_custom(func(a, b): return _dist2(a, center) < _dist2(b, center))
	for c in _chunks.keys():
		if _cheby(c, center) > unload_radius:
			_unload_chunk(c)


func _drain_queue() -> void:
	var built := 0
	while built < gen_budget_per_frame and not _queue.is_empty():
		var c: Vector2i = _queue.pop_front()
		if not _chunks.has(c):
			_build_chunk(c)
			built += 1


func _build_chunk(coord: Vector2i) -> void:
	var rect := _chunk_rect(coord)
	# Bucket the chunk's cells by biome so each painter fills its own region. Off-world cells
	# (biome_at null) are skipped — nothing generated beyond the hull.
	var buckets := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var biome := _macro.biome_at(cell)
			if biome == null:
				continue
			if not buckets.has(biome):
				buckets[biome] = [] as Array[Vector2i]
			buckets[biome].append(cell)

	var spawned: Array[Node] = []
	var before := _enemies_root.get_child_count()
	for biome in buckets:
		var trio: Dictionary = _layers[biome.id]
		_ctx.ground = trio.ground
		_ctx.decor = trio.decor
		_ctx.objects = trio.objects
		_painters[biome.id].fill(_ctx, biome, buckets[biome], _world_seed)
	# Enemies are parented flat under the shared (y-sorted) Enemies node so they sort correctly
	# across chunks; track the ones this chunk added so unload frees exactly them. Painters spawn
	# none yet (Group G), but the scaffold stays so enemy spawning drops in with no streamer change.
	for i in range(before, _enemies_root.get_child_count()):
		spawned.append(_enemies_root.get_child(i))
	# Specials (doors/portals) whose tile lands in this chunk. Placement is a pure function of the
	# seed, so a rebuilt chunk re-instantiates them identically. Tracked in the same `spawned` array
	# as enemies so unload frees them.
	_build_specials(rect, spawned)
	_chunks[coord] = spawned


# Instantiate the specials pass's items for the tiles in `rect`, positioned at their tile centre
# and parented under the y-sorted Specials node. Sign/boss (H5/H6) drop into this same match.
func _build_specials(rect: Rect2i, spawned: Array[Node]) -> void:
	for s in _macro.specials_in_rect(rect):
		var node: Node2D
		match s.type:
			&"door":
				var door: Door = _DOOR.instantiate()
				door.style = Door.Style.CAVE
				door.target_scene = _DUNGEON_PLACEHOLDER
				node = door
			&"portal":
				node = _PORTAL.instantiate()
			&"sign":
				node = _SIGN.instantiate()
			# &"coverage"/&"rare" spawn through the encounter override in _spawn_encounters (ONE spawn
			# path), and &"boss" is a dormant reserved tile — none instantiate a node here.
			_:
				continue
		node.position = _ctx.tile_to_world(s.tile)   # before add_child so _ready sees it
		_specials_root.add_child(node)
		if node.has_method("setup"):
			node.setup(s.payload)
		spawned.append(node)


func _unload_chunk(coord: Vector2i) -> void:
	for e in _chunks[coord]:
		if is_instance_valid(e):
			e.free()
	var rect := _chunk_rect(coord)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			for layer in _all_layers:
				layer.erase_cell(cell)
	_chunks.erase(coord)


# --- helpers ---

func _wanted(center: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-load_radius, load_radius + 1):
		for dx in range(-load_radius, load_radius + 1):
			out.append(center + Vector2i(dx, dy))
	return out

func _player_chunk() -> Vector2i:
	var t := _player.global_position / GameConstants.PX_PER_TILE
	return Vector2i(floori(t.x / chunk_size), floori(t.y / chunk_size))

func _chunk_rect(coord: Vector2i) -> Rect2i:
	return Rect2i(coord * chunk_size, Vector2i(chunk_size, chunk_size))

func _world() -> Node:
	return get_parent()

func _cheby(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))

func _dist2(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return d.x * d.x + d.y * d.y
