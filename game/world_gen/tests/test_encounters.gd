extends Node
## Group G verify: encounter anchors → weighted templates → solitary/pack/mixed spawns are a
## pure function of (seed, tile). Asserts, over a few seeds and two regions (glade @ origin,
## deepwood @ its centre):
##   1. Deterministic decisions — rolls_at is identical on a second pass and after re-setup.
##   2. Template bounds — SOLITARY=1; PACK/MIXED size in [count_min,count_max]; PACK all one
##      scene; MIXED members all drawn from the template's entries.
##   3. Placement — no spawn in the spawn-clear pocket; anchors only where in_world.
##   4. Live spawn — running a painter's fill actually adds children to the y-sorted Enemies
##      node (proving the streamer's per-chunk tracking will free them on unload).
## Run: godot --headless --path game world_gen/tests/test_encounters.tscn

const GRAPH_PATH := "res://world_gen/content/world_graph.tres"
const FLOOR_TS := "res://overworld/biomes/glade/glade_floor_tileset.tres"
const DECOR_TS := "res://overworld/biomes/glade/glade_decor_tileset.tres"


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)

	for world_seed in [7, 101, 5551]:
		var macro := MacroMap.new()
		macro.setup(world_seed, graph)
		var macro2 := MacroMap.new()
		macro2.setup(world_seed, graph)  # independent instance, same seed → must decide identically

		# Two regions: glade around origin, deepwood around its centre.
		var regions := {
			"glade": _region(Vector2i.ZERO, 70),
			"deepwood": _region(macro.biome_center(1), 70),
		}
		for label in regions:
			for cell in regions[label]:
				if not Encounters.is_anchor(world_seed, cell.x, cell.y):
					continue
				var area: Resource = macro.area_at(cell)
				var rolls: Array = Encounters.rolls_at(area, cell, world_seed)

				# 1. Deterministic across a repeat call and an independent same-seed macro.
				if _tag(rolls) != _tag(Encounters.rolls_at(area, cell, world_seed)):
					fails.append("s%d %s %s: rolls_at not stable" % [world_seed, label, cell])
				if _tag(rolls) != _tag(Encounters.rolls_at(macro2.area_at(cell), cell, world_seed)):
					fails.append("s%d %s %s: rolls_at differs on re-setup" % [world_seed, label, cell])

				# 2. Template bounds.
				var tmpl: EncounterTemplate = Encounters.picked_template(area, cell, world_seed)
				if tmpl != null and not rolls.is_empty():
					var n := rolls.size()
					match tmpl.kind:
						EncounterTemplate.Kind.SOLITARY:
							if n != 1:
								fails.append("s%d %s: SOLITARY spawned %d" % [world_seed, cell, n])
						EncounterTemplate.Kind.PACK:
							if n < tmpl.count_min or n > tmpl.count_max:
								fails.append("s%d %s: PACK n=%d out of [%d,%d]" % [world_seed, cell, n, tmpl.count_min, tmpl.count_max])
							for r in rolls:
								if r.scene != rolls[0].scene:
									fails.append("s%d %s: PACK not single-scene" % [world_seed, cell]); break
						EncounterTemplate.Kind.MIXED:
							if n < tmpl.count_min or n > tmpl.count_max:
								fails.append("s%d %s: MIXED n=%d out of [%d,%d]" % [world_seed, cell, n, tmpl.count_min, tmpl.count_max])
							for r in rolls:
								if not tmpl.entry_scenes.has(r.scene):
									fails.append("s%d %s: MIXED member not in entries" % [world_seed, cell]); break

	# 3 + 4. Live spawn: a painter's fill adds tracked children — assert none stacked, none on a
	# blocker, none in a sealed pocket. Run BOTH sparse glade (origin) AND dense deepwood (its centre,
	# where the `den` area is coverage 0.9 — the case that used to strand enemies in tree pockets).
	var lseed := 5551
	var macro := MacroMap.new(); macro.setup(lseed, graph)
	_live_spawn_check(macro, graph.nodes[graph.start_index].biome, Vector2i.ZERO, "glade(sparse)", lseed, fails)
	_live_spawn_check(macro, graph.nodes[1].biome, macro.biome_center(1), "deepwood(dense)", lseed, fails)

	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails.slice(0, 8)))
	get_tree().quit(1 if not fails.is_empty() else 0)


# Paint a 141x141 region of `biome` around `center` and assert every spawned enemy is on a distinct,
# unblocked, reachable tile (outside the spawn pocket). Appends any violations to `fails`.
func _live_spawn_check(macro: MacroMap, biome: Resource, center: Vector2i, label: String,
		lseed: int, fails: Array) -> void:
	var ground := TileMapLayer.new(); ground.tile_set = load(FLOOR_TS)
	var decor := TileMapLayer.new(); decor.tile_set = load(DECOR_TS)
	var objects := TileMapLayer.new(); objects.tile_set = load(DECOR_TS)
	var enemies := Node2D.new(); enemies.y_sort_enabled = true
	add_child(ground); add_child(decor); add_child(objects); add_child(enemies)
	var ctx := GenContext.new()
	ctx.ground = ground; ctx.decor = decor; ctx.objects = objects; ctx.enemies = enemies; ctx.macro = macro
	var painter: BiomePainter = biome.painter.new()
	painter.fill(ctx, biome, _region(center, 70), lseed)

	if enemies.get_child_count() == 0:
		fails.append("%s: fill spawned no enemies" % label)
	var per_tile := {}
	for e in enemies.get_children():
		var t := ctx.world_to_tile(e.position)
		if t.x * t.x + t.y * t.y <= Encounters.SPAWN_CLEAR * Encounters.SPAWN_CLEAR:
			fails.append("%s: enemy in spawn-clear pocket at %s" % [label, t]); break
		if objects.get_cell_source_id(t) != -1:
			fails.append("%s: enemy on a blocked (tree/wall) tile %s" % [label, t]); break
		if not painter._flood_reachable(ctx, biome, t, 1, lseed).reachable:
			fails.append("%s: enemy in an unreachable sealed pocket at %s" % [label, t]); break
		# Clearance: no tree/wall in the enemy's Moore neighbourhood — so its body can't wedge on cover.
		# Uses the painter's pure predicate (no painted-region-edge false clears).
		if not painter._has_clearance(ctx, biome, t, lseed):
			fails.append("%s: enemy spawned adjacent to a blocker at %s" % [label, t]); break
		per_tile[t] = per_tile.get(t, 0) + 1
	var max_stack := 0
	for t in per_tile:
		max_stack = maxi(max_stack, per_tile[t])
	if max_stack > 2:
		fails.append("%s: %d enemies stacked on one tile" % [label, max_stack])
	print("live spawn %s: %d enemies over %d distinct tiles (max %d/tile)" % [
		label, enemies.get_child_count(), per_tile.size(), max_stack])
	ground.queue_free(); decor.queue_free(); objects.queue_free(); enemies.queue_free()


# A comparable signature for a rolls list: (scene path, channels) per member, in order.
func _tag(rolls: Array) -> Array:
	var out: Array = []
	for r in rolls:
		out.append([r.scene.resource_path if r.scene else "", r.ch_x, r.ch_y])
	return out


func _region(center: Vector2i, r: int) -> Array:
	var out: Array[Vector2i] = []
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			out.append(Vector2i(x, y))
	return out
