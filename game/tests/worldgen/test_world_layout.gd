extends Node
## Headless tests for Layer 1: contract symmetry, packer placement invariants
## (in-bounds, non-overlap, grid consistency), adjacency rules, world-unique room placement,
## determinism, and the seed sweep (the authoring-time guarantee that the shipped adjacency
## rules are satisfiable — a failure here is a content bug, never a runtime condition). Run:
##   godot --headless --path game res://tests/worldgen/test_world_layout.tscn


func _ready() -> void:
	var fails: Array[String] = []
	var config: GenConfig = load("res://world_content/gen_config.tres")
	var bs := config.biome_slots

	# 1. Seed sweep: 64 consecutive seeds must all produce a layout (packing is total; only the
	# adjacency check can reject an attempt, bounded by max_layout_retries).
	for seed_v in 64:
		if WorldLayout.build(seed_v, config) == null:
			fails.append("layout failed in the seed sweep at seed %d" % seed_v)
			break
	print("seed sweep: 64 consecutive seeds")

	# 2. Contract symmetry: every differing-biome cell border of a built world, computed from
	# both orderings, must be field-identical; slots ascending/distinct, offsets in range.
	for i in 200:
		var seed_v := 1_000_003 * i + 17
		var spec := WorldLayout.build(seed_v, config)
		for b in _borders(spec):
			var ab: Array = BorderContracts.get_contract(seed_v, config, b[0], b[1])
			var ba: Array = BorderContracts.get_contract(seed_v, config, b[1], b[0])
			if not _crossings_equal(ab, ba):
				fails.append("contract asymmetric at seed %d border %s-%s" % [seed_v, b[0], b[1]])
				break
			for j in range(1, ab.size()):
				if ab[j].slot_index <= ab[j - 1].slot_index:
					fails.append("contract slots not ascending/distinct at seed %d" % seed_v)
					break
			for c in ab:
				if c.tile_offset < 2 or c.tile_offset > config.room_slot_tiles - config.door_width_tiles - 2:
					fails.append("door offset out of range at seed %d: %d" % [seed_v, c.tile_offset])
					break
		if not fails.is_empty():
			break
	print("contract symmetry: 200 seeds")

	# 3. Layout determinism: same seed twice -> identical grid, placements and unique rooms.
	for i in 50:
		var seed_v := 7919 * i + 3
		var a := WorldLayout.build(seed_v, config)
		var b := WorldLayout.build(seed_v, config)
		if a.biome_grid != b.biome_grid or a.grid_h != b.grid_h:
			fails.append("biome_grid differs on rebuild at seed %d" % seed_v)
			break
		if not _placements_equal(a.placements, b.placements):
			fails.append("placements differ on rebuild at seed %d" % seed_v)
			break
		if not _uniques_equal(a.unique_rooms, b.unique_rooms):
			fails.append("unique_rooms differ on rebuild at seed %d" % seed_v)
			break
	print("layout determinism: 50 seeds rebuilt")

	# 4. Over 200 seeds: placements in-bounds and rect == size_cells, no overlap, grid consistent
	# with placements, FORBIDDEN never violated, REQUIRED always satisfied, uniques interior.
	for i in 200:
		var seed_v := 104_729 * i + 41
		var spec := WorldLayout.build(seed_v, config)
		if spec == null:
			fails.append("layout failed at seed %d" % seed_v)
			break
		# Placement rects: authored size, inside the grid, disjoint.
		var claimed: Dictionary = {}
		for p in spec.placements:
			var biome := config.biome_by_id(p.id)
			if p.rect.size != biome.size_cells:
				fails.append("placement %s rect size %s != size_cells %s at seed %d"
						% [p.id, p.rect.size, biome.size_cells, seed_v])
			if p.rect.position.x < 0 or p.rect.position.y < 0 \
					or p.rect.position.x + p.rect.size.x > spec.grid_w \
					or p.rect.position.y + p.rect.size.y > spec.grid_h:
				fails.append("placement %s out of bounds at seed %d" % [p.id, seed_v])
			for cy in range(p.rect.position.y, p.rect.position.y + p.rect.size.y):
				for cx in range(p.rect.position.x, p.rect.position.x + p.rect.size.x):
					var key := cy * spec.grid_w + cx
					if claimed.has(key):
						fails.append("placements overlap at cell %d,%d seed %d" % [cx, cy, seed_v])
					claimed[key] = p.id
					if spec.biome_at(Vector2i(cx, cy)) != p.id:
						fails.append("grid/placement mismatch at %d,%d seed %d" % [cx, cy, seed_v])
		# Every non-&"" grid cell belongs to some placement.
		for cy in spec.grid_h:
			for cx in spec.grid_w:
				var bid := spec.biome_at(Vector2i(cx, cy))
				if bid != &"" and claimed.get(cy * spec.grid_w + cx, &"") != bid:
					fails.append("grid cell %d,%d claims '%s' without a placement at seed %d"
							% [cx, cy, bid, seed_v])
		# Adjacency rules over placement rects.
		for r in config.adjacency.forbidden:
			if _pair_adjacent(spec, r.biome_a, r.biome_b):
				fails.append("FORBIDDEN(%s,%s) violated at seed %d" % [r.biome_a, r.biome_b, seed_v])
		for r in config.adjacency.required:
			if not _pair_adjacent(spec, r.biome_a, r.biome_b):
				fails.append("REQUIRED(%s,%s) unsatisfied at seed %d" % [r.biome_a, r.biome_b, seed_v])
		# Unique rooms: allowed biome, strictly interior to the region's slot rect, distinct.
		var taken: Dictionary = {}
		for ur in spec.unique_rooms:
			var rt := config.room_type_by_id(ur.type_id)
			var host := spec.biome_at_slot(ur.world_slot)
			if not host in rt.unique_allowed_biomes:
				fails.append("unique '%s' outside allowed biomes at seed %d" % [ur.type_id, seed_v])
			var org := spec.region_origin_slot(host)
			var sz := spec.region_size_slots(host)
			var local: Vector2i = ur.world_slot - org
			if local.x < 1 or local.x > sz.x - 2 or local.y < 1 or local.y > sz.y - 2:
				fails.append("unique '%s' on region border at seed %d" % [ur.type_id, seed_v])
			if taken.has(ur.world_slot):
				fails.append("unique rooms collide at seed %d" % seed_v)
			taken[ur.world_slot] = true
		if not fails.is_empty():
			break
	print("packer invariants + rules + uniques: 200 seeds (slots per cell side: %d)" % bs)

	if fails.is_empty():
		print("ALL PASS")
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
	get_tree().quit(0 if fails.is_empty() else 1)


## Adjacent differing-biome cell pairs of a built world (each once, a < b in scan order).
func _borders(spec: WorldSpec) -> Array:
	var out: Array = []
	for y in spec.grid_h:
		for x in spec.grid_w:
			var a := Vector2i(x, y)
			var abid := spec.biome_at(a)
			if abid == &"":
				continue
			for d in [Vector2i(1, 0), Vector2i(0, 1)]:
				var b: Vector2i = a + d
				var bbid := spec.biome_at(b)
				if bbid != &"" and bbid != abid:
					out.append([a, b])
	return out


func _crossings_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].slot_index != b[i].slot_index or a[i].tile_offset != b[i].tile_offset \
				or a[i].width != b[i].width:
			return false
	return true


func _placements_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].id != b[i].id or a[i].rect != b[i].rect:
			return false
	return true


func _uniques_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].type_id != b[i].type_id or a[i].world_slot != b[i].world_slot:
			return false
	return true


## Two biomes are adjacent iff their placement rects share an edge segment >= 1 cell.
func _pair_adjacent(spec: WorldSpec, a: StringName, b: StringName) -> bool:
	var pa: WorldSpec.BiomePlacement = spec.placement_for(a)
	var pb: WorldSpec.BiomePlacement = spec.placement_for(b)
	if pa == null or pb == null:
		return false
	var ra := pa.rect
	var rb := pb.rect
	var x_overlap := mini(ra.position.x + ra.size.x, rb.position.x + rb.size.x) \
			- maxi(ra.position.x, rb.position.x)
	var y_overlap := mini(ra.position.y + ra.size.y, rb.position.y + rb.size.y) \
			- maxi(ra.position.y, rb.position.y)
	var x_flush := ra.position.x + ra.size.x == rb.position.x or rb.position.x + rb.size.x == ra.position.x
	var y_flush := ra.position.y + ra.size.y == rb.position.y or rb.position.y + rb.size.y == ra.position.y
	return (x_flush and y_overlap >= 1) or (y_flush and x_overlap >= 1)
