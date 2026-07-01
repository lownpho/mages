extends Node
## Group H (H3 rares/coverage, H5 signs, H6 boss anchors) verify. Over ~30 seeds asserts:
##   1. Signs — ≥1 per biome; each on a trail + in_world; target_id is a real graph-neighbour id;
##      target_tile is that neighbour's centre.
##   2. Coverage — every world-roster member (union of all area rosters) gets ≥1 &"coverage"/&"rare"
##      override; anchor_override(tile) returns that scene; each override tile IS an is_anchor tile.
##   3. Rares — each WorldGraph.rare_enemies member gets 1–2 &"rare" overrides.
##   4. Bosses — count of &"boss" specials == number of &"boss"-tagged area instances (proven with a
##      synthetic in-code graph carrying a &"boss" area, so count > 0; real content stays 0).
##   5. Determinism — H-b specials + overrides identical on an independent same-seed re-setup.
##   6. Integration — a glade painter fill over a region holding a coverage/rare override anchor
##      actually spawns the forced scene into Enemies at that tile (the override path, end-to-end).
## Run: godot --headless --path game overworld/tests/test_specials_hb.tscn

const GRAPH_PATH := "res://overworld/world_graph.tres"
const FLOOR_TS := "res://overworld/biomes/glade/glade_floor_tileset.tres"
const DECOR_TS := "res://overworld/biomes/glade/glade_decor_tileset.tres"


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)
	var roster := _world_roster(graph)

	# Aggregate counts for the log.
	var min_signs_per_biome := 1 << 30
	var covered_members := {}

	var seeds: Array[int] = []
	for i in 30:
		seeds.append(i * 977 + 13)

	for world_seed in seeds:
		var macro := MacroMap.new(); macro.setup(world_seed, graph)
		var macro2 := MacroMap.new(); macro2.setup(world_seed, graph)  # same seed → identical
		var centers: Dictionary = macro.biome_centers()
		var specials: Array[Dictionary] = macro.specials()

		# --- 1. Signs ---
		var signs_per_node := {}
		for node in centers:
			signs_per_node[node] = 0
		for s in specials:
			if s.type != &"sign":
				continue
			if not macro.is_trail(s.tile) or not macro.in_world(s.tile):
				fails.append("s%d: sign at %s not on an in-world trail" % [world_seed, s.tile])
			var src := _nearest_node(centers, s.tile)
			signs_per_node[src] = signs_per_node.get(src, 0) + 1
			var target_id: StringName = s.payload.target_id
			var ok := false
			for m in graph.neighbors(src):
				if centers.has(m) and graph.nodes[m].biome.id == target_id:
					ok = true
					if s.payload.target_tile != centers[m]:
						fails.append("s%d: sign target_tile %s != neighbour centre %s" % [world_seed, s.payload.target_tile, centers[m]])
			if not ok:
				fails.append("s%d: sign target_id %s is not a graph-neighbour of node %d" % [world_seed, target_id, src])
		for node in signs_per_node:
			min_signs_per_biome = mini(min_signs_per_biome, signs_per_node[node])
			if signs_per_node[node] < 1:
				fails.append("s%d: biome node %d has no sign" % [world_seed, node])

		# --- 2 + 3. Coverage / rares ---
		var cov_scenes := {}        # scene -> true (has a coverage/rare override)
		var rare_counts := {}       # rare scene -> count of &"rare" overrides
		for s in specials:
			if s.type != &"coverage" and s.type != &"rare":
				continue
			var scene: PackedScene = s.payload.scene
			cov_scenes[scene] = true
			if not Encounters.is_anchor(world_seed, s.tile.x, s.tile.y):
				fails.append("s%d: %s override at %s is not an is_anchor tile" % [world_seed, s.type, s.tile])
			if macro.anchor_override(s.tile) != scene:
				fails.append("s%d: anchor_override(%s) != its %s scene" % [world_seed, s.tile, s.type])
			if s.type == &"rare":
				rare_counts[scene] = rare_counts.get(scene, 0) + 1
		for member in roster:
			if cov_scenes.has(member):
				covered_members[member] = true
			else:
				fails.append("s%d: world-roster member %s has no coverage override" % [world_seed, _name(member)])
		for rare in graph.rare_enemies:
			var c: int = rare_counts.get(rare, 0)
			if c < 1 or c > 2:
				fails.append("s%d: rare %s has %d overrides (want 1-2)" % [world_seed, _name(rare), c])

		# --- 5. Determinism (H-b specials + override lookups) ---
		var b: Array[Dictionary] = macro2.specials()
		if specials.size() != b.size():
			fails.append("s%d: specials size differs on re-setup" % world_seed)
		else:
			for i in specials.size():
				if specials[i] != b[i]:
					fails.append("s%d: special %d (%s) differs on re-setup" % [world_seed, i, specials[i].type]); break
		for s in specials:
			if (s.type == &"coverage" or s.type == &"rare") and macro2.anchor_override(s.tile) != s.payload.scene:
				fails.append("s%d: override at %s not reproduced on re-setup" % [world_seed, s.tile]); break

	# --- 4. Boss reservation via a synthetic in-code graph with a &"boss"-tagged area ---
	var boss_fails := _check_boss_reservation()
	fails.append_array(boss_fails)

	# --- 6. Integration: a glade override anchor actually spawns its forced scene ---
	var integ_fails := _check_override_spawn(graph)
	fails.append_array(integ_fails)

	print("signs/biome min=%d ; coverage members covered=%d/%d ; boss synthetic OK=%s" % [
		min_signs_per_biome, covered_members.size(), roster.size(), boss_fails.is_empty()])
	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails.slice(0, 8)))
	get_tree().quit(1 if not fails.is_empty() else 0)


# Synthetic 2-node graph: glade + a deepwood clone with an extra &"boss"-tagged required area.
# Proves the reservation fires with count > 0 while real content (no &"boss" tag) stays 0.
func _check_boss_reservation() -> Array[String]:
	var fails: Array[String] = []
	var glade: Resource = load("res://overworld/biomes/glade/glade.tres")
	var biome: Resource = load("res://overworld/biomes/deepwood/deepwood.tres").duplicate(true)
	var boss_area := AreaResource.new()
	boss_area.type_id = &"boss_lair"
	boss_area.required = true
	boss_area.tags = [&"boss"] as Array[StringName]
	var aset: Array[AreaResource] = biome.area_set.duplicate()
	aset.append(boss_area)
	biome.area_set = aset

	var g := WorldGraph.new()
	var n0 := BiomeNode.new(); n0.biome = glade
	var n1 := BiomeNode.new(); n1.biome = biome
	g.nodes = [n0, n1] as Array[BiomeNode]
	g.edges = [Vector2i(0, 1)] as Array[Vector2i]
	g.start_index = 0

	var macro := MacroMap.new(); macro.setup(4242, g)
	var expected := 0
	for node in macro.biome_centers():
		for inst in macro.area_instances(node):
			if inst.type.tags.has(&"boss"):
				expected += 1
	var got := 0
	for s in macro.specials():
		if s.type == &"boss":
			got += 1
			if not s.payload.has("biome_id") or not s.payload.has("area_type"):
				fails.append("boss special payload missing keys: %s" % s.payload)
	if expected <= 0:
		fails.append("synthetic boss: expected boss instances is 0 (test setup broken)")
	if got != expected:
		fails.append("boss specials %d != boss-tagged instances %d" % [got, expected])
	return fails


# End-to-end: fill a glade region containing a coverage/rare override anchor and assert the forced
# scene lands in Enemies at that anchor's scatter position.
func _check_override_spawn(graph: WorldGraph) -> Array[String]:
	var fails: Array[String] = []
	var world_seed := 5551
	var macro := MacroMap.new(); macro.setup(world_seed, graph)
	var glade: Resource = graph.nodes[graph.start_index].biome

	var target := Vector2i(1 << 30, 0)
	var forced: PackedScene = null
	for s in macro.specials():
		if (s.type == &"coverage" or s.type == &"rare") and macro.biome_at(s.tile) == glade:
			target = s.tile
			forced = s.payload.scene
			break
	if forced == null:
		fails.append("integration: no glade coverage/rare override found for seed %d" % world_seed)
		return fails

	var ground := TileMapLayer.new(); ground.tile_set = load(FLOOR_TS)
	var decor := TileMapLayer.new(); decor.tile_set = load(DECOR_TS)
	var objects := TileMapLayer.new(); objects.tile_set = load(DECOR_TS)
	var enemies := Node2D.new(); enemies.y_sort_enabled = true
	add_child(ground); add_child(decor); add_child(objects); add_child(enemies)
	var ctx := GenContext.new()
	ctx.ground = ground; ctx.decor = decor; ctx.objects = objects; ctx.enemies = enemies; ctx.macro = macro
	var painter: BiomePainter = glade.painter.new()
	painter.fill(ctx, glade, _region(target, 40), world_seed)

	var want_pos := ctx.scatter_pos(target, world_seed, Encounters.CH_SCATTER_X, Encounters.CH_SCATTER_Y)
	var hit := false
	for e in enemies.get_children():
		if e.position.distance_to(want_pos) < 0.01:
			hit = true
			if e.scene_file_path != forced.resource_path:
				fails.append("integration: enemy at override tile is %s, expected %s" % [e.scene_file_path, forced.resource_path])
			break
	if not hit:
		fails.append("integration: forced scene did NOT spawn at override tile %s" % target)
	return fails


func _world_roster(graph: WorldGraph) -> Array:
	var out: Array = []
	for node in graph.nodes:
		if node == null or node.biome == null:
			continue
		for area in node.biome.area_set:
			if area == null:
				continue
			for scene in area.roster:
				if scene != null and not out.has(scene):
					out.append(scene)
	return out


func _nearest_node(centers: Dictionary, tile: Vector2i) -> int:
	var best := -1
	var best_d := 1 << 62
	for node in centers:
		var d: int = (centers[node] - tile).length_squared()
		if d < best_d:
			best_d = d
			best = node
	return best


func _name(scene: PackedScene) -> String:
	return scene.resource_path.get_file() if scene else "<null>"


func _region(center: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			out.append(Vector2i(x, y))
	return out
