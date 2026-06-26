class_name ForestPainter extends BiomePainter
## A forest biome: the playable area is what's carved out of an otherwise solid wood. The
## walkable mask comes from the WorldGenerator; this painter owns everything around it.
##   1. ground        — walkable cells = floor; the void = the deep-forest floor (visual only)
##   2. border seal   — every void cell touching walkable gets a tree, walling the walkable
##                      region with tree collision (the trees ARE the wall — no ground collision)
##   3. void fill     — the rest of the void fills with trees at `void_fill_density`
##   4. clumps        — tree clusters dotted through the walkable area as cover
##   5. decor/enemies — scattered on the leftover walkable cells; the spawn pocket stays clear
## Glade and Deepwood share this and differ only in their BiomeResource knobs (Deepwood crams
## a tighter mask and denser fill/clumps).

const SPAWN_CLEAR := 8   # tiles around the map centre kept free of trees (the player's spawn pocket)

const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0),                   Vector2i(1, 0),
	Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1),
]

func fill(ctx: GenContext, biome: BiomeResource, cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	if cells.is_empty():
		return

	var land_set := {}
	for c in cells:
		land_set[c] = true

	# 1. Ground: walkable floor, plus the forest floor under the void. -1 reuses the floor
	# terrain, so the whole map is one seamless field and the trees alone read as the wall.
	var void_cells := _void_cells(ctx, land_set)
	var void_terrain := biome.void_terrain_id if biome.void_terrain_id >= 0 else biome.terrain_id
	ctx.ground.set_cells_terrain_connect(cells, biome.terrain_set, biome.terrain_id, false)
	ctx.ground.set_cells_terrain_connect(void_cells, biome.terrain_set, void_terrain, false)

	if biome.blocker_tiles.is_empty():
		return

	# 2+3. Trees fill the void: every border cell (8-adjacency seals diagonal gaps, so the
	# walkable region is walled by tree collision with no slip-throughs), then the interior.
	for cell in void_cells:
		if _touches_land(cell, land_set) or rng.randf() < biome.void_fill_density:
			ctx.objects.set_cell(cell, biome.blocker_source, _pick(biome.blocker_tiles, rng))

	# 4. Clumps of trees as cover inside the walkable area, away from the spawn pocket. Cells a
	# clump takes are marked so decor/enemies don't land on a tree.
	var centre := ctx.bounds.get_center()
	var occupied := {}
	var clumps := int(round(biome.clump_count_per_1k * cells.size() / 1000.0))
	for _i in clumps:
		var c0: Vector2i = cells[rng.randi() % cells.size()]
		if _within(c0, centre, SPAWN_CLEAR):
			continue
		var r := rng.randi_range(biome.clump_radius.x, biome.clump_radius.y)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := c0 + Vector2i(dx, dy)
				if dx * dx + dy * dy <= r * r and land_set.has(c) and not occupied.has(c) \
						and rng.randf() < biome.clump_density:
					ctx.objects.set_cell(c, biome.blocker_source, _pick(biome.blocker_tiles, rng))
					occupied[c] = true

	# 5. Decor + enemies on the leftover walkable cells (one role per cell, spawn pocket clear).
	var pool := cells.duplicate()
	_shuffle(pool, rng)
	for cell in pool:
		if occupied.has(cell) or _within(cell, centre, SPAWN_CLEAR):
			continue
		var roll := rng.randf()
		if not biome.decor_tiles.is_empty() and roll < biome.decor_density:
			ctx.decor.set_cell(cell, biome.decor_source, _pick(biome.decor_tiles, rng))
		elif not biome.enemy_roster.is_empty() and roll < biome.decor_density + biome.enemy_density:
			var enemy: Node2D = _pick(biome.enemy_roster, rng).instantiate()
			ctx.enemies.add_child(enemy)
			enemy.global_position = _scatter_pos(ctx, cell, rng)


# Every in-bounds cell that isn't walkable land (the coastline margin plus any interior lakes).
func _void_cells(ctx: GenContext, land_set: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var b := ctx.bounds
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var c := Vector2i(x, y)
			if not land_set.has(c):
				out.append(c)
	return out


# True if any 8-neighbour is walkable land (this void cell is on the playable border).
func _touches_land(cell: Vector2i, land_set: Dictionary) -> bool:
	for d in NEIGHBORS_8:
		if land_set.has(cell + d):
			return true
	return false


func _within(cell: Vector2i, centre: Vector2i, radius: int) -> bool:
	var dx := cell.x - centre.x
	var dy := cell.y - centre.y
	return dx * dx + dy * dy <= radius * radius
