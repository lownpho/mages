extends Node
## Headless config-sanity test. Loads the starter GenConfig and asserts the
## content invariants plus CONFIG_HASH stability/sensitivity — including the hash DIET: runtime
## dials and presentation fields must NOT move the hash. Run:
##   godot --headless --path game res://tests/worldgen/test_config.tscn

const CONFIG_PATH := "res://world_content/gen_config.tres"


func _ready() -> void:
	var fails: Array[String] = []

	var cfg: GenConfig = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	if cfg == null:
		print("FAILED: 1")
		print("  FAIL: could not load ", CONFIG_PATH)
		get_tree().quit(1)
		return

	# --- summary ---
	var biome_ids: Array[StringName] = []
	for b in cfg.biomes:
		biome_ids.append(b.id)
	var room_type_ids: Array[StringName] = []
	for rt in cfg.room_types:
		room_type_ids.append(rt.id)
	print("=== GenConfig summary ===")
	print("  room_slot_tiles=%d  biome_slots=%d  world_width_cells=%d  chunk_tiles=%d  door_width_tiles=%d"
		% [cfg.room_slot_tiles, cfg.biome_slots, cfg.world_width_cells, cfg.chunk_tiles, cfg.door_width_tiles])
	print("  extra_connection_chance=%.2f  bsp_stop_chance=%.2f  bsp_max_leaf_slots=%s  doors_per_biome_border=%d"
		% [cfg.extra_connection_chance, cfg.bsp_stop_chance, cfg.bsp_max_leaf_slots, cfg.doors_per_biome_border])
	print("  pocket_seal_max_tiles=%d  max_layout_retries=%d  min_reachable_floor_ratio=%.2f"
		% [cfg.pocket_seal_max_tiles, cfg.max_layout_retries, cfg.min_reachable_floor_ratio])
	print("  room_cache_capacity=%d  prefetch_radius_chunks=%d  gen_version=%d"
		% [cfg.room_cache_capacity, cfg.prefetch_radius_chunks, cfg.gen_version])
	print("  biomes: ", biome_ids)
	print("  room types: ", room_type_ids)

	# 1. The shipped config must validate cleanly.
	if not cfg.validate():
		fails.append("validate() rejected the shipped config")

	# 2. Every biome's fallback room type exists, is its own, has no generator (empty interior
	# by construction), and accepts any size. NONE-scope room types must name an existing owner.
	for b in cfg.biomes:
		var fallback := cfg.room_type_by_id(b.fallback_room_type)
		if fallback == null or fallback.biome != b.id:
			fails.append("biome %s: fallback room type '%s' missing or not owned" % [b.id, b.fallback_room_type])
		else:
			if fallback.generator != null:
				fails.append("biome %s: fallback room type '%s' has a generator — must be empty" % [b.id, b.fallback_room_type])
			if fallback.min_size_slots != Vector2i.ONE:
				fails.append("biome %s: fallback room type '%s' must accept any size" % [b.id, b.fallback_room_type])
	for rt in cfg.room_types:
		if rt.unique_scope == RoomTypeDef.UniqueScope.NONE and cfg.biome_by_id(rt.biome) == null:
			fails.append("room type '%s' names unknown biome '%s'" % [rt.id, rt.biome])
	# The starting biome must exist too (player spawn + presentation fallback).
	if cfg.biome_by_id(cfg.starting_biome) == null:
		fails.append("starting biome '%s' missing" % cfg.starting_biome)

	# 3. Every biome fits the world (validate() is the loud gate, but assert the shipped content
	# actually exercises multi-cell regions so the packer path isn't dead code in tests).
	var any_multi_cell := false
	for b in cfg.biomes:
		if b.size_cells.x < 1 or b.size_cells.y < 1:
			fails.append("biome %s: size_cells must be >= 1x1" % b.id)
		if b.size_cells.x > cfg.world_width_cells:
			fails.append("biome %s: size_cells.x %d exceeds world_width_cells %d" % [b.id, b.size_cells.x, cfg.world_width_cells])
		if b.size_cells.x > 1 or b.size_cells.y > 1:
			any_multi_cell = true
	if not any_multi_cell:
		fails.append("no biome exercises a multi-cell size_cells region (packer path untested by content)")

	# 4. Adjacency rule ids reference existing biomes.
	if cfg.adjacency == null:
		fails.append("adjacency rules missing")
	else:
		for r in cfg.adjacency.required + cfg.adjacency.forbidden:
			if cfg.biome_by_id(r.biome_a) == null:
				fails.append("adjacency references unknown biome '%s'" % r.biome_a)
			if cfg.biome_by_id(r.biome_b) == null:
				fails.append("adjacency references unknown biome '%s'" % r.biome_b)

	# 5. CONFIG_HASH: stable across two independent loads, and cached (second call identical).
	var h1 := cfg.compute_hash()
	if cfg.compute_hash() != h1:
		fails.append("compute_hash not stable across calls (cache broken)")
	var cfg2: GenConfig = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)
	var h2 := cfg2.compute_hash()
	if h1 != h2:
		fails.append("compute_hash unstable across loads: %s vs %s" % [_hex(h1), _hex(h2)])
	# Deep duplicate reproduces the hash (duplicates start uncached — plain vars don't copy).
	if cfg.duplicate(true).compute_hash() != h1:
		fails.append("duplicate(true) hash mismatch")

	# 6. Hash SENSITIVITY: world-affecting fields must move the hash. Top-level probes mutate
	# a duplicate (the hash is cached on first use, so a hashed config must never be mutated);
	# nested probes mutate-and-revert on cfg — duplicate(true) SHARES the external biome/room-
	# type .tres subresources, so mutating them on a duplicate would leak into cfg — and
	# compare the uncached fold directly to bypass cfg's cache.
	var dup: GenConfig = cfg.duplicate(true)
	dup.room_slot_tiles += 1
	_expect_changed(fails, h1, dup.compute_hash(), "room_slot_tiles")
	dup = cfg.duplicate(true)
	dup.world_width_cells += 1
	_expect_changed(fails, h1, dup.compute_hash(), "world_width_cells")
	dup = cfg.duplicate(true)
	dup.extra_connection_chance += 0.1
	_expect_changed(fails, h1, dup.compute_hash(), "extra_connection_chance")
	dup = cfg.duplicate(true)
	dup.bsp_stop_chance += 0.1
	_expect_changed(fails, h1, dup.compute_hash(), "bsp_stop_chance")
	dup = cfg.duplicate(true)
	dup.bsp_max_leaf_slots += Vector2i(1, 0)
	_expect_changed(fails, h1, dup.compute_hash(), "bsp_max_leaf_slots")
	dup = cfg.duplicate(true)
	dup.pocket_seal_max_tiles += 1
	_expect_changed(fails, h1, dup.compute_hash(), "pocket_seal_max_tiles")
	dup = cfg.duplicate(true)
	dup.starting_biome = &"elsewhere"
	_expect_changed(fails, h1, dup.compute_hash(), "starting_biome")
	dup = cfg.duplicate(true)
	dup.wall_extra_depth += 1
	_expect_changed(fails, h1, dup.compute_hash(), "wall_extra_depth")
	dup = cfg.duplicate(true)
	dup.corner_radius += 1
	_expect_changed(fails, h1, dup.compute_hash(), "corner_radius")
	dup = cfg.duplicate(true)
	dup.wall_inset_max += 1
	_expect_changed(fails, h1, dup.compute_hash(), "wall_inset_max")

	cfg.biomes[0].open_passage_chance += 0.1
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "biome open_passage_chance")
	cfg.biomes[0].open_passage_chance -= 0.1
	var orig_size_cells: Vector2i = cfg.biomes[0].size_cells
	cfg.biomes[0].size_cells = orig_size_cells + Vector2i(1, 0)
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "biome size_cells")
	cfg.biomes[0].size_cells = orig_size_cells
	var orig_biome_bsp: float = cfg.biomes[0].bsp_stop_chance
	cfg.biomes[0].bsp_stop_chance = 0.9 if orig_biome_bsp != 0.9 else 0.1
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "biome bsp_stop_chance")
	cfg.biomes[0].bsp_stop_chance = orig_biome_bsp
	# Five shell overrides on BiomeDef — same -1-inherit dial as GenConfig's, all hashed.
	for field in ["wall_extra_depth", "wall_outer_erode", "wall_noise_period", "corner_radius", "wall_inset_max"]:
		var orig: int = cfg.biomes[0].get(field)
		cfg.biomes[0].set(field, orig + 1)
		_expect_changed(fails, h1, cfg._compute_hash_uncached(), "biome %s" % field)
		cfg.biomes[0].set(field, orig)

	cfg.room_types[0].enemy_groups_max += 1
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "room type budget")
	cfg.room_types[0].enemy_groups_max -= 1
	cfg.room_types[0].min_per_biome += 1
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "room type min_per_biome")
	cfg.room_types[0].min_per_biome -= 1
	cfg.room_types[0].difficulty = (cfg.room_types[0].difficulty + 1) % 4
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "room type difficulty")
	cfg.room_types[0].difficulty = (cfg.room_types[0].difficulty + 3) % 4
	var orig_min_size: Vector2i = cfg.room_types[0].min_size_slots
	cfg.room_types[0].min_size_slots = orig_min_size + Vector2i(1, 0)
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "room type min_size_slots")
	cfg.room_types[0].min_size_slots = orig_min_size
	var orig_max_size: Vector2i = cfg.room_types[0].max_size_slots
	cfg.room_types[0].max_size_slots = orig_max_size + Vector2i(1, 0)
	_expect_changed(fails, h1, cfg._compute_hash_uncached(), "room type max_size_slots")
	cfg.room_types[0].max_size_slots = orig_max_size

	var scatter: RoomGenScatter = null
	for rt in cfg.room_types:
		if rt.generator is RoomGenScatter:
			scatter = rt.generator
			break
	if scatter == null:
		fails.append("no scatter generator in config to probe")
	else:
		scatter.count_per_slot += 1
		_expect_changed(fails, h1, cfg._compute_hash_uncached(), "generator field")
		scatter.count_per_slot -= 1
	if cfg._compute_hash_uncached() != h1:
		fails.append("hash did not restore after reverting nested probes")

	# 7. Hash DIET: runtime/presentation fields must NOT move the hash (tuning them can't
	# re-roll saved worlds).
	dup = cfg.duplicate(true)
	dup.chunk_tiles *= 2
	_expect_same(fails, h1, dup.compute_hash(), "chunk_tiles")
	dup = cfg.duplicate(true)
	dup.max_layout_retries += 100
	_expect_same(fails, h1, dup.compute_hash(), "max_layout_retries")
	dup = cfg.duplicate(true)
	dup.room_cache_capacity += 16
	_expect_same(fails, h1, dup.compute_hash(), "room_cache_capacity")
	dup = cfg.duplicate(true)
	dup.prefetch_radius_chunks += 1
	_expect_same(fails, h1, dup.compute_hash(), "prefetch_radius_chunks")

	var orig_color: Color = cfg.biomes[0].display_color
	cfg.biomes[0].display_color = Color.MAGENTA
	_expect_same(fails, h1, cfg._compute_hash_uncached(), "biome display_color")
	cfg.biomes[0].display_color = orig_color
	var orig_family: StringName = cfg.biomes[0].family
	cfg.biomes[0].family = &"some_new_family"
	_expect_same(fails, h1, cfg._compute_hash_uncached(), "biome family")
	cfg.biomes[0].family = orig_family
	var orig_pres: BiomePresentation = cfg.biomes[0].presentation
	cfg.biomes[0].presentation = null
	_expect_same(fails, h1, cfg._compute_hash_uncached(), "biome presentation")
	cfg.biomes[0].presentation = orig_pres

	var orig_features: Array[RoomFeature] = cfg.room_types[0].features
	var rf := RoomFeature.new()
	rf.placement = RoomFeature.Placement.NEAR_WALL
	rf.count_min = 2
	rf.count_max = 3
	cfg.room_types[0].features = [rf] as Array[RoomFeature]
	_expect_same(fails, h1, cfg._compute_hash_uncached(), "room type features")
	cfg.room_types[0].features = orig_features

	if cfg._compute_hash_uncached() != h1:
		fails.append("hash did not restore after reverting DIET probes")

	print("CONFIG_HASH = 0x%s" % _hex(h1))

	# 8. validate() rejection cases — each mutates a fresh duplicate(true) (never the cached cfg)
	# and must flip validate() to false.
	_expect_invalid(fails, "duplicate biome id", func(c: GenConfig):
		c.biomes[1].id = c.biomes[0].id)
	_expect_invalid(fails, "duplicate room type id", func(c: GenConfig):
		c.room_types[1].id = c.room_types[0].id)
	_expect_invalid(fails, "room type names unknown biome", func(c: GenConfig):
		for rt in c.room_types:
			if rt.unique_scope == RoomTypeDef.UniqueScope.NONE:
				rt.biome = &"no_such_biome"
				break)
	_expect_invalid(fails, "min_size_slots > max_size_slots", func(c: GenConfig):
		c.room_types[0].min_size_slots = Vector2i(5, 5)
		c.room_types[0].max_size_slots = Vector2i(2, 2))
	_expect_invalid(fails, "quota demand exceeds region area", func(c: GenConfig):
		for rt in c.room_types:
			if rt.min_per_biome > 0 and rt.unique_scope == RoomTypeDef.UniqueScope.NONE:
				rt.min_per_biome = 1000
				break)
	_expect_invalid(fails, "fallback room requires non-1x1 size", func(c: GenConfig):
		var fb := c.room_type_by_id(c.biomes[0].fallback_room_type)
		fb.min_size_slots = Vector2i(2, 2))
	_expect_invalid(fails, "biome wider than world_width_cells", func(c: GenConfig):
		c.biomes[0].size_cells = Vector2i(c.world_width_cells + 1, 1))
	_expect_invalid(fails, "door_width_tiles + 4 > room_slot_tiles", func(c: GenConfig):
		c.door_width_tiles = c.room_slot_tiles)

	if fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for f in fails:
			print("  FAIL: ", f)
		print("FAILED: %d" % fails.size())
		get_tree().quit(1)


## Applies `mutate` to a DEEP-fresh load of the shipped config and requires validate() to
## reject it — every rejection case starts from a known-valid config and breaks exactly one
## rule. CACHE_MODE_IGNORE_DEEP matters: plain IGNORE (or duplicate(true)) still SHARES the
## external biome/room-type .tres subresources, so mutating them would corrupt every later
## load in this same run.
func _expect_invalid(fails: Array[String], what: String, mutate: Callable) -> void:
	var dup: GenConfig = ResourceLoader.load(CONFIG_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	mutate.call(dup)
	if dup.validate():
		fails.append("validate() accepted an invalid config: %s" % what)


func _expect_changed(fails: Array[String], h1: int, h: int, what: String) -> void:
	if h == h1:
		fails.append("hash unchanged after mutating %s" % what)


func _expect_same(fails: Array[String], h1: int, h: int, what: String) -> void:
	if h != h1:
		fails.append("hash CHANGED after mutating %s (should be outside CONFIG_HASH)" % what)


func _hex(v: int) -> String:
	var s := String.num_uint64(v, 16).to_upper()
	while s.length() < 16:
		s = "0" + s
	return s
