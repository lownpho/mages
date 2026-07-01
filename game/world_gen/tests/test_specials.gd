extends Node
## Group H (H1/H2/H4) verify: the specials pass places, deterministically, exactly one portal per
## biome (on its centre, on a trail) and exactly one door per (biome, dungeon_type) (off the main
## trail but 4-adjacent to it). Over ~30 seeds asserts:
##   1. Portals — one per occupied biome, tile == biome_center(node), on a trail.
##   2. Doors — one per (biome, dungeon_type); in_world, reachable (4-adj to a trail), NOT on trail.
##   3. Every special tile is in_world and reachable.
##   4. Determinism — specials() identical on an independent same-seed re-setup.
##   5. specials_in_rect returns exactly the specials whose tile is inside a rect.
## Run: godot --headless --path game world_gen/tests/test_specials.tscn

const GRAPH_PATH := "res://world_gen/content/world_graph.tres"


func _ready() -> void:
	var fails: Array[String] = []
	var graph: WorldGraph = load(GRAPH_PATH)

	var seeds: Array[int] = []
	for i in 30:
		seeds.append(i * 977 + 13)

	for world_seed in seeds:
		var macro := MacroMap.new()
		macro.setup(world_seed, graph)
		var macro2 := MacroMap.new()
		macro2.setup(world_seed, graph)   # independent, same seed → must be identical

		var centers: Dictionary = macro.biome_centers()
		var expected_portals := centers.size()
		var expected_doors := 0
		for node in centers:
			expected_doors += graph.nodes[node].biome.dungeon_types.size()

		var specials: Array[Dictionary] = macro.specials()
		var portals: Array = []
		var doors: Array = []
		for s in specials:
			# 3. Every special in-world. Trail-based specials (portal/door/sign) must also be
			# reachable; anchor-based ones (coverage/rare/boss) sit on encounter anchors, not trails.
			if not macro.in_world(s.tile):
				fails.append("s%d: %s at %s not in_world" % [world_seed, s.type, s.tile])
			if s.type in [&"portal", &"door", &"sign"] and not _reachable(macro, s.tile):
				fails.append("s%d: %s at %s not reachable" % [world_seed, s.type, s.tile])
			if s.type == &"portal":
				portals.append(s)
			elif s.type == &"door":
				doors.append(s)

		# 1. Portals: one per biome, on its centre, on a trail.
		if portals.size() != expected_portals:
			fails.append("s%d: %d portals, expected %d" % [world_seed, portals.size(), expected_portals])
		var seen_nodes := {}
		for p in portals:
			var node: int = p.payload.node
			if seen_nodes.has(node):
				fails.append("s%d: two portals for node %d" % [world_seed, node])
			seen_nodes[node] = true
			if p.tile != macro.biome_center(node):
				fails.append("s%d: portal node %d tile %s != center %s" % [world_seed, node, p.tile, macro.biome_center(node)])
			if not macro.is_trail(p.tile):
				fails.append("s%d: portal node %d not on a trail" % [world_seed, node])

		# 2. Doors: one per (biome, dungeon_type), off the trail but adjacent to it.
		if doors.size() != expected_doors:
			fails.append("s%d: %d doors, expected %d" % [world_seed, doors.size(), expected_doors])
		for d in doors:
			if macro.is_trail(d.tile):
				fails.append("s%d: door at %s is ON the main trail" % [world_seed, d.tile])
			if not _adjacent_to_trail(macro, d.tile):
				fails.append("s%d: door at %s not 4-adjacent to a trail" % [world_seed, d.tile])
			if not d.payload.has("dungeon_type") or not d.payload.has("biome_id"):
				fails.append("s%d: door payload missing keys: %s" % [world_seed, d.payload])

		# 4. Determinism: an independent same-seed macro produces the identical list.
		var b: Array[Dictionary] = macro2.specials()
		if specials.size() != b.size():
			fails.append("s%d: specials size differs on re-setup (%d vs %d)" % [world_seed, specials.size(), b.size()])
		else:
			for i in specials.size():
				if specials[i] != b[i]:
					fails.append("s%d: special %d differs on re-setup" % [world_seed, i]); break

		# 5. specials_in_rect == the specials whose tile is inside the rect.
		if not portals.is_empty():
			var c: Vector2i = portals[0].tile
			var rect := Rect2i(c - Vector2i(200, 200), Vector2i(400, 400))
			var got := macro.specials_in_rect(rect)
			var want: Array[Dictionary] = []
			for s in specials:
				if rect.has_point(s.tile):
					want.append(s)
			if got.size() != want.size():
				fails.append("s%d: specials_in_rect size %d != expected %d" % [world_seed, got.size(), want.size()])
			for s in got:
				if not rect.has_point(s.tile):
					fails.append("s%d: specials_in_rect returned %s outside rect" % [world_seed, s.tile])
			# far-away rect must be empty
			var far := Rect2i(Vector2i(9_000_000, 9_000_000), Vector2i(10, 10))
			if not macro.specials_in_rect(far).is_empty():
				fails.append("s%d: specials_in_rect(far) not empty" % world_seed)

	# One representative count print for the log.
	var m := MacroMap.new(); m.setup(seeds[0], graph)
	var np := 0; var nd := 0
	for s in m.specials():
		if s.type == &"portal": np += 1
		elif s.type == &"door": nd += 1
	print("seed %d: %d portals, %d doors, %d specials total" % [seeds[0], np, nd, m.specials().size()])

	print("RESULT: ", "PASS" if fails.is_empty() else "FAIL " + str(fails.slice(0, 8)))
	get_tree().quit(1 if not fails.is_empty() else 0)


func _reachable(macro, tile: Vector2i) -> bool:
	return macro.is_trail(tile) or _adjacent_to_trail(macro, tile)


func _adjacent_to_trail(macro, tile: Vector2i) -> bool:
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if macro.is_trail(tile + d):
			return true
	return false
