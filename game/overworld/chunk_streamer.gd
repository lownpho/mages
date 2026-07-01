class_name ChunkStreamer extends Node
## Streams the overworld around the player: builds chunks within `load_radius`, discards them
## beyond `unload_radius`, and rebuilds them identically on return (everything is a pure
## function of the seed, so there's no chunk state to persist). Replaces the old run-once
## WorldGenerator. Per chunk it asks MacroMap which biome each cell is, buckets cells by biome,
## and hands each bucket to that biome's painter — reusing one GenContext pointed at the
## biome's layers.

@export_range(8, 128, 1) var chunk_size := 32          # tiles per chunk side
@export_range(1, 8, 1) var load_radius := 2            # chunks kept built around the player (Chebyshev)
@export_range(1, 12, 1) var unload_radius := 3         # chunks beyond this are discarded (must be > load_radius)
@export_range(1, 16, 1) var gen_budget_per_frame := 2  # chunks built per frame from the queue (amortised)
@export var biomes: Array[BiomeResource] = []          # registry; [0] is the spawn biome
@export var world_regions := Vector2i(3, 3)            # finite world size, in region cells (W x H)

var _macro := MacroMap.new()
var _ctx := GenContext.new()
var _player: Node2D
var _enemies_root: Node2D
var _layers := {}                         # biome id -> {ground, decor, objects}
var _all_layers: Array[TileMapLayer] = [] # every layer, for blanket erase on unload
var _painters := {}                       # biome id -> BiomePainter instance (cached: holds clump noise)

var _chunks := {}                         # coord:Vector2i -> Array[Node] (the chunk's spawned enemies)
var _queue: Array[Vector2i] = []
var _last_center := Vector2i(2147483647, 0)  # force a refresh on the first frame


## Called by world.gd after the seed is resolved. Wires layers, primes the chunks around the
## player synchronously (so the first frame is already populated), then streaming takes over.
func init(world_seed: int) -> void:
	_player = get_tree().get_first_node_in_group("player")
	_enemies_root = _world().get_node("Entities/Enemies")
	_macro.setup(world_seed, biomes, world_regions)
	_ctx.rng = RandomNumberGenerator.new()
	_ctx.rng.seed = world_seed
	_ctx.biomes = biomes
	_ctx.macro = _macro

	for biome in biomes:
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
		_painters[biome.id] = (biome.painter.new() if biome.painter else BiomePainter.new()) as BiomePainter

	var center := _player_chunk()
	_last_center = center
	for c in _wanted(center):
		_build_chunk(c)


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
	# Bucket the chunk's cells by biome so each painter fills its own region.
	var buckets := {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			var biome := _macro.biome_at(cell)
			if biome == null:   # off-world: nothing generated beyond the finite grid
				continue
			if not buckets.has(biome):
				buckets[biome] = [] as Array[Vector2i]
			buckets[biome].append(cell)

	var spawned: Array[Node] = []
	_ctx.enemies = _enemies_root
	var before := _enemies_root.get_child_count()
	for biome in buckets:
		var trio: Dictionary = _layers[biome.id]
		_ctx.ground = trio.ground
		_ctx.decor = trio.decor
		_ctx.objects = trio.objects
		_painters[biome.id].fill(_ctx, biome, buckets[biome], _ctx.rng)
	# Enemies are parented flat under the shared (y-sorted) Enemies node so they sort correctly
	# across chunks; track the ones this chunk added so unload can free exactly them.
	for i in range(before, _enemies_root.get_child_count()):
		spawned.append(_enemies_root.get_child(i))
	_chunks[coord] = spawned


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
