extends Node
## Group F verify: painting is a pure function of (seed, tile). Instantiates a MacroMap +
## the glade ForestPainter directly (no full world.tscn) and paints a region near the origin
## (all inside the glade start cell) into fresh TileMapLayers, then asserts:
##   1. Determinism — repaint the same region gives byte-identical cells.
##   2. Shared-edge agreement — a tile painted alone equals the same tile painted as part of a
##      larger superset region (no seams: the result never depends on chunk framing).
##   3. Trails stay walkable — no blocker (objects) cell ever lands on an is_trail tile.
##   4. Ground coverage — every in-world tile in the region gets a ground cell.
## Run: godot --headless --path game world_gen/tests/test_painting.tscn

const GRAPH_PATH := "res://world_gen/content/world_graph.tres"
const FLOOR_TS := "res://overworld/biomes/glade/glade_floor_tileset.tres"
const DECOR_TS := "res://overworld/biomes/glade/glade_decor_tileset.tres"

const R := 40        # half-side of the tested region (origin ± R, all glade)
const R_BIG := 60    # larger superset for the shared-edge check


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)
	var glade: Resource = graph.nodes[graph.start_index].biome

	for world_seed in [7, 101, 5551, 90210]:
		var macro := MacroMap.new()
		macro.setup(world_seed, graph)

		var region := _region(-R, R)
		var snap_a := _paint_and_snapshot(macro, glade, world_seed, region, -R, R)
		var snap_b := _paint_and_snapshot(macro, glade, world_seed, region, -R, R)

		# 1. Determinism.
		if snap_a.cells != snap_b.cells:
			fails.append("seed %d: repaint not identical" % world_seed)

		# 2. Shared-edge agreement — paint a bigger superset, compare only the inner region tiles.
		var snap_big := _paint_and_snapshot(macro, glade, world_seed, _region(-R_BIG, R_BIG), -R_BIG, R_BIG)
		for key in snap_a.cells:
			if snap_big.cells.get(key) != snap_a.cells[key]:
				fails.append("seed %d: tile %s differs when painted as part of a superset (seam)" % [world_seed, key])
				break

		# 3. Trails never blocked.
		for c in snap_a.blocker_cells:
			if macro.is_trail(c):
				fails.append("seed %d: blocker placed on trail tile %s" % [world_seed, c])
				break

		# 4. Ground coverage on every in-world tile.
		var missing := 0
		for c in region:
			if macro.in_world(c) and not snap_a.ground_cells.has(c):
				missing += 1
		if missing > 0:
			fails.append("seed %d: %d in-world tiles missing ground" % [world_seed, missing])

		print("seed %d: cells %d  ground %d  blockers %d  trail-tiles-in-region %d" % [
			world_seed, snap_a.cells.size(), snap_a.ground_cells.size(),
			snap_a.blocker_cells.size(), _count_trails(macro, region)])

	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit(1 if not fails.is_empty() else 0)


# Paint `region` with glade's painter into fresh layers, then snapshot every cell of the
# inner [lo,hi] box across all three layers into a stable dict, plus the sets of ground and
# blocker tiles used.
func _paint_and_snapshot(macro: MacroMap, biome: Resource, world_seed: int,
		region: Array, lo: int, hi: int) -> Dictionary:
	var ground := TileMapLayer.new(); ground.tile_set = load(FLOOR_TS)
	var decor := TileMapLayer.new(); decor.tile_set = load(DECOR_TS)
	var objects := TileMapLayer.new(); objects.tile_set = load(DECOR_TS)
	add_child(ground); add_child(decor); add_child(objects)

	var ctx := GenContext.new()
	ctx.ground = ground; ctx.decor = decor; ctx.objects = objects
	ctx.enemies = Node2D.new(); add_child(ctx.enemies)
	ctx.macro = macro

	var painter: BiomePainter = biome.painter.new()
	painter.fill(ctx, biome, region, world_seed)

	var cells := {}
	var ground_cells := {}
	var blocker_cells := {}
	for y in range(lo, hi + 1):
		for x in range(lo, hi + 1):
			var c := Vector2i(x, y)
			cells["g%d,%d" % [x, y]] = _cell_tag(ground, c)
			cells["d%d,%d" % [x, y]] = _cell_tag(decor, c)
			cells["o%d,%d" % [x, y]] = _cell_tag(objects, c)
			if ground.get_cell_source_id(c) != -1:
				ground_cells[c] = true
			if objects.get_cell_source_id(c) != -1:
				blocker_cells[c] = true

	ground.queue_free(); decor.queue_free(); objects.queue_free(); ctx.enemies.queue_free()
	return {"cells": cells, "ground_cells": ground_cells, "blocker_cells": blocker_cells}


func _cell_tag(layer: TileMapLayer, c: Vector2i) -> Vector3i:
	var sid := layer.get_cell_source_id(c)
	if sid == -1:
		return Vector3i(-1, 0, 0)
	var a := layer.get_cell_atlas_coords(c)
	return Vector3i(sid, a.x, a.y)


func _region(lo: int, hi: int) -> Array:
	var out: Array[Vector2i] = []
	for y in range(lo, hi + 1):
		for x in range(lo, hi + 1):
			out.append(Vector2i(x, y))
	return out


func _count_trails(macro: MacroMap, region: Array) -> int:
	var n := 0
	for c in region:
		if macro.is_trail(c):
			n += 1
	return n
