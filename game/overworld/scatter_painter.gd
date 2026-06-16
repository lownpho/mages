class_name ScatterPainter extends BiomePainter
## Default fill: autotile the ground, then scatter blockers, decor, and enemies at their
## densities. Placement is plain random-without-replacement for now (a shuffled pool sliced
## into disjoint runs, so the three never land on the same cell); blue-noise spacing can
## replace the sampler later without touching anything else.

func fill(ctx: GenContext, biome: BiomeResource, cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	if cells.is_empty():
		return

	# 1. Ground — Godot autotiles the edges from the floor tileset's terrain.
	ctx.ground.set_cells_terrain_connect(cells, biome.terrain_set, biome.terrain_id, false)

	# 2/3/4. One shuffled pool, sliced so blockers/decor/enemies occupy disjoint cells.
	var pool := cells.duplicate()
	_shuffle(pool, rng)
	var i := 0

	for _n in _count(biome.blocker_density, cells.size(), biome.blocker_tiles):
		if i >= pool.size(): break
		ctx.objects.set_cell(pool[i], biome.blocker_source, _pick(biome.blocker_tiles, rng))
		i += 1

	for _n in _count(biome.decor_density, cells.size(), biome.decor_tiles):
		if i >= pool.size(): break
		ctx.decor.set_cell(pool[i], biome.decor_source, _pick(biome.decor_tiles, rng))
		i += 1

	for _n in _count(biome.enemy_density, cells.size(), biome.enemy_roster):
		if i >= pool.size(): break
		var enemy: Node2D = _pick(biome.enemy_roster, rng).instantiate()
		ctx.enemies.add_child(enemy)
		enemy.global_position = ctx.tile_to_world(pool[i])
		i += 1


# expected items per cell -> a count, but only if there's something to place
func _count(density: float, cell_count: int, source: Array) -> int:
	if source.is_empty():
		return 0
	return int(round(density * cell_count))


func _pick(arr: Array, rng: RandomNumberGenerator):
	return arr[rng.randi() % arr.size()]


# deterministic Fisher-Yates (Array.shuffle() uses the global RNG, which isn't reproducible)
func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for n in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, n)
		var tmp = arr[n]
		arr[n] = arr[j]
		arr[j] = tmp
