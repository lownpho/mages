extends Node
## Headless tests for Layer 1: contract symmetry (T4), layout determinism,
## adjacency rules, and world-unique room placement. Run:
##   godot --headless --path game res://tests/worldgen/test_world_layout.tscn


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")
	var w := config.world_width_biomes
	var h := config.world_height_biomes()

	# 1. T4 contract symmetry over 1000 seeds: every internal border computed from both
	# orderings must be field-identical.
	var borders: Array = []
	for y in h:
		for x in w:
			if x + 1 < w:
				borders.append([Vector2i(x, y), Vector2i(x + 1, y)])
			if y + 1 < h:
				borders.append([Vector2i(x, y), Vector2i(x, y + 1)])
	for i in 1000:
		var seed := 1_000_003 * i + 17
		for b in borders:
			var ab: Array = BorderContracts.get_contract(seed, config, b[0], b[1])
			var ba: Array = BorderContracts.get_contract(seed, config, b[1], b[0])
			if not _crossings_equal(ab, ba):
				fails.append("contract asymmetric at seed %d border %s-%s" % [seed, b[0], b[1]])
				break
			for j in range(1, ab.size()):
				if ab[j].slot_index <= ab[j - 1].slot_index:
					fails.append("contract slots not ascending/distinct at seed %d" % seed)
					break
			for c in ab:
				if c.tile_offset < 2 or c.tile_offset > config.room_slot_tiles - config.door_width_tiles - 2:
					fails.append("door offset out of range at seed %d: %d" % [seed, c.tile_offset])
					break
		if not fails.is_empty():
			break
	print("contract symmetry: 1000 seeds x %d borders checked" % borders.size())

	# 2. Layout determinism: same seed twice -> identical grid and unique rooms.
	for i in 50:
		var seed := 7919 * i + 3
		var a := WorldLayout.build(seed, config)
		var b := WorldLayout.build(seed, config)
		if a.biome_grid != b.biome_grid:
			fails.append("biome_grid differs on rebuild at seed %d" % seed)
			break
		if not _uniques_equal(a.unique_rooms, b.unique_rooms):
			fails.append("unique_rooms differ on rebuild at seed %d" % seed)
			break
	print("layout determinism: 50 seeds rebuilt")

	# 3. Over 200 seeds: FORBIDDEN never violated, REQUIRED always satisfied, unique rooms
	# in allowed biomes / interior slots / no collisions.
	var s := config.biome_slots
	for i in 200:
		var seed := 104_729 * i + 41
		var spec := WorldLayout.build(seed, config)
		if spec == null:
			fails.append("layout failed at seed %d" % seed)
			break
		for r in config.adjacency.forbidden:
			if _pair_adjacent(spec, r.biome_a, r.biome_b):
				fails.append("FORBIDDEN(%s,%s) violated at seed %d" % [r.biome_a, r.biome_b, seed])
		for r in config.adjacency.required:
			if not _pair_adjacent(spec, r.biome_a, r.biome_b):
				fails.append("REQUIRED(%s,%s) unsatisfied at seed %d" % [r.biome_a, r.biome_b, seed])
		var taken := {}
		for ur in spec.unique_rooms:
			var rt := config.room_type_by_id(ur.type_id)
			if not spec.biome_at(ur.biome_coord) in rt.unique_allowed_biomes:
				fails.append("unique '%s' outside allowed biomes at seed %d" % [ur.type_id, seed])
			if ur.local_slot.x < 1 or ur.local_slot.x > s - 2 \
					or ur.local_slot.y < 1 or ur.local_slot.y > s - 2:
				fails.append("unique '%s' on biome border at seed %d" % [ur.type_id, seed])
			var key := "%s|%s" % [ur.biome_coord, ur.local_slot]
			if taken.has(key):
				fails.append("unique rooms collide at seed %d" % seed)
			taken[key] = true
		if not fails.is_empty():
			break
	print("layout rules + unique rooms: 200 seeds")

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


func _crossings_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].slot_index != b[i].slot_index or a[i].tile_offset != b[i].tile_offset \
				or a[i].width != b[i].width:
			return false
	return true


func _uniques_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].type_id != b[i].type_id or a[i].biome_coord != b[i].biome_coord \
				or a[i].local_slot != b[i].local_slot:
			return false
	return true


func _pair_adjacent(spec: WorldSpec, a: StringName, b: StringName) -> bool:
	for y in spec.grid_h:
		for x in spec.grid_w:
			var here := spec.biome_at(Vector2i(x, y))
			if here != a and here != b:
				continue
			var other := b if here == a else a
			if spec.biome_at(Vector2i(x + 1, y)) == other or spec.biome_at(Vector2i(x, y + 1)) == other:
				return true
	return false
