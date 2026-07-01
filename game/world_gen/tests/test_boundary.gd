extends Node
## Group I verify: the impassable outer hull + a valid Glade spawn, both pure functions of the seed.
## Over several seeds it asserts:
##   1. Edge wall — locate the hull boundary (scan an axis until in_world flips false), paint the
##      region around it with each owning biome's painter into fresh layers, and assert EVERY
##      is_world_edge tile there carries an objects blocker (walls override trails). A just-outside
##      tile (in_world false) gets nothing.
##   2. Spawn validity — ChunkStreamer's derived spawn tile is the Glade start biome, in_world, NOT
##      is_world_edge, and carries no blocker when painted (it sits in the cover-clear pocket).
##   3. Determinism — edge-wall cell set + spawn tile are identical after re-setup.
## Run: godot --headless --path game world_gen/tests/test_boundary.tscn

const GRAPH_PATH := "res://world_gen/content/world_graph.tres"
const FLOOR_TS := "res://overworld/biomes/glade/glade_floor_tileset.tres"
const DECOR_TS := "res://overworld/biomes/glade/glade_decor_tileset.tres"  # source 1 = blockers, shared by every biome

const M := 12          # half-side of the rect examined around the boundary point
const SPAWN_R := 20    # half-side of the region painted around the spawn tile


# A macro that reports a chosen tile as BOTH edge and trail — proves the wall overrides trails
# (which never happens naturally: trails stay interior, so no real seed exercises this path).
class _EdgeTrailMacro extends RefCounted:
	var edge: Vector2i
	func in_world(_t: Vector2i) -> bool: return true
	func is_world_edge(t: Vector2i) -> bool: return t == edge
	func is_trail(_t: Vector2i) -> bool: return true
	func area_at(_t: Vector2i) -> Resource: return null
	func anchor_override(_t: Vector2i) -> PackedScene: return null


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)
	var glade: Resource = graph.nodes[graph.start_index].biome

	if not _trail_override_walls(glade):
		fails.append("wall does NOT override a trail tile (ordering bug in painter.fill)")

	for world_seed in [7, 101, 5551, 90210]:
		var macro := MacroMap.new()
		macro.setup(world_seed, graph)

		# --- 1. Edge wall ---
		var boundary := _boundary_tile(macro)
		var rect := _rect(boundary, M)
		var painted := _paint_region(macro, world_seed, rect)

		var edge_cells := _edge_cells(macro, rect)
		if edge_cells.is_empty():
			fails.append("seed %d: found no is_world_edge tiles near boundary %s" % [world_seed, boundary])
		var unwalled := 0
		var walled_trails := 0
		for c in edge_cells:
			if not painted.blockers.has(c):
				unwalled += 1
			elif macro.is_trail(c):
				walled_trails += 1   # a walled trail tile — proves the wall overrides trails
		if unwalled > 0:
			fails.append("seed %d: %d/%d edge tiles NOT walled" % [world_seed, unwalled, edge_cells.size()])

		# A just-outside tile gets nothing painted.
		var outside := boundary + Vector2i(MacroMap.BORDER + 1, 0)
		if macro.in_world(outside):
			outside = _first_outside(macro, boundary)
		if painted.any.has(outside):
			fails.append("seed %d: off-world tile %s was painted" % [world_seed, outside])

		# --- 2. Spawn validity ---
		var streamer := ChunkStreamer.new()
		streamer.world_graph = graph
		streamer._macro = macro
		streamer._ctx = GenContext.new()
		streamer._ctx.macro = macro
		var spawn := streamer._spawn_tile()

		if macro.biome_at(spawn) != glade:
			fails.append("seed %d: spawn %s not in Glade start biome" % [world_seed, spawn])
		if not macro.in_world(spawn):
			fails.append("seed %d: spawn %s off-world" % [world_seed, spawn])
		if macro.is_world_edge(spawn):
			fails.append("seed %d: spawn %s on world edge" % [world_seed, spawn])
		var spawn_paint := _paint_region(macro, world_seed, _rect(spawn, SPAWN_R))
		if spawn_paint.blockers.has(spawn):
			fails.append("seed %d: spawn %s has a blocker on it" % [world_seed, spawn])
		streamer.free()

		# --- 3. Determinism ---
		var macro2 := MacroMap.new()
		macro2.setup(world_seed, graph)
		var edge_cells2 := _edge_cells(macro2, rect)
		if edge_cells != edge_cells2:
			fails.append("seed %d: edge cell set differs on re-setup" % world_seed)
		var streamer2 := ChunkStreamer.new()
		streamer2.world_graph = graph
		streamer2._macro = macro2
		streamer2._ctx = GenContext.new()
		streamer2._ctx.macro = macro2
		if streamer2._spawn_tile() != spawn:
			fails.append("seed %d: spawn tile differs on re-setup" % world_seed)
		streamer2.free()

		print("seed %d: boundary %s  edge-tiles %d  walled-trails %d  spawn %s" % [
			world_seed, boundary, edge_cells.size(), walled_trails, spawn])

	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


# Last in-world tile along +x from origin — a point on the hull boundary.
func _boundary_tile(macro: MacroMap) -> Vector2i:
	var last := Vector2i.ZERO
	for x in range(1, 8 * MacroMap.CELL):
		var t := Vector2i(x, 0)
		if not macro.in_world(t):
			break
		last = t
	return last


func _first_outside(macro: MacroMap, from: Vector2i) -> Vector2i:
	for x in range(from.x, from.x + 4 * MacroMap.CELL):
		var t := Vector2i(x, from.y)
		if not macro.in_world(t):
			return t
	return from + Vector2i(10 * MacroMap.CELL, 0)


func _edge_cells(macro: MacroMap, rect: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in rect:
		if macro.is_world_edge(c):
			out.append(c)
	return out


# Paint `rect`, bucketed by owning biome, into fresh layers. Off-world cells are skipped (mirrors
# the streamer). Returns the sets of tiles with a blocker (objects), and every tile with any cell.
func _paint_region(macro: MacroMap, world_seed: int, rect: Array[Vector2i]) -> Dictionary:
	var ground := TileMapLayer.new(); ground.tile_set = load(FLOOR_TS)
	var decor := TileMapLayer.new(); decor.tile_set = load(DECOR_TS)
	var objects := TileMapLayer.new(); objects.tile_set = load(DECOR_TS)
	add_child(ground); add_child(decor); add_child(objects)

	var ctx := GenContext.new()
	ctx.ground = ground; ctx.decor = decor; ctx.objects = objects
	ctx.enemies = Node2D.new(); add_child(ctx.enemies)
	ctx.macro = macro

	var buckets := {}
	for c in rect:
		var biome := macro.biome_at(c)
		if biome == null:
			continue
		if not buckets.has(biome):
			buckets[biome] = [] as Array[Vector2i]
		buckets[biome].append(c)
	for biome in buckets:
		var painter: BiomePainter = biome.painter.new()
		painter.fill(ctx, biome, buckets[biome], world_seed)

	var blockers := {}
	var any := {}
	for c in rect:
		if objects.get_cell_source_id(c) != -1:
			blockers[c] = true
		if ground.get_cell_source_id(c) != -1 or decor.get_cell_source_id(c) != -1 \
				or objects.get_cell_source_id(c) != -1:
			any[c] = true

	ground.queue_free(); decor.queue_free(); objects.queue_free(); ctx.enemies.queue_free()
	return {"blockers": blockers, "any": any}


# Run the glade painter over a single cell that a stub macro reports as edge AND trail; the wall
# must win (a blocker is placed) even though the tile is a trail. Encounter pass is disabled by a
# null enemies node so the stub needs no roster wiring.
func _trail_override_walls(glade: Resource) -> bool:
	var stub := _EdgeTrailMacro.new()
	stub.edge = Vector2i(500, 500)   # far from origin: outside the spawn pocket

	var ground := TileMapLayer.new(); ground.tile_set = load(FLOOR_TS)
	var objects := TileMapLayer.new(); objects.tile_set = load(DECOR_TS)
	add_child(ground); add_child(objects)

	var ctx := GenContext.new()
	ctx.ground = ground; ctx.decor = objects; ctx.objects = objects
	ctx.enemies = null   # disables the encounter pass
	ctx.macro = stub

	(glade.painter.new() as BiomePainter).fill(ctx, glade, [stub.edge] as Array[Vector2i], 7)
	var walled := objects.get_cell_source_id(stub.edge) != -1
	ground.queue_free(); objects.queue_free()
	return walled


func _rect(center: Vector2i, half: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(center.y - half, center.y + half + 1):
		for x in range(center.x - half, center.x + half + 1):
			out.append(Vector2i(x, y))
	return out
