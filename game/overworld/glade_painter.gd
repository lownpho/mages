class_name GladePainter extends BiomePainter
## The Glade's bespoke layout. Instead of one flat scatter across the whole landmass, it carves
## zones of interest and scatters at a different rate inside each:
##   - clearings — safe rest spots: enemy-free, flower-rich, almost no trees
##   - thickets  — dense forest pockets: tree-choked and a touch more enemies (ambush cover)
##   - default   — the plain Glade look everywhere else ("zones like it is now")
## Placement stays single-role-per-cell (a cell is a tree, OR decor, OR an enemy, OR empty), so
## nothing overlaps. Zone strength is a multiplier on the biome's base densities.

const CLEARING := {"blocker": 0.1, "decor": 3.0, "enemy": 0.0}
const THICKET := {"blocker": 3.5, "decor": 0.6, "enemy": 1.6}
const DEFAULT := {"blocker": 1.0, "decor": 1.0, "enemy": 1.0}

# Feature discs scale with the landmass area (counts per 1000 land tiles).
const CLEARINGS_PER_1K := 1.1
const THICKETS_PER_1K := 1.4
const FEATURE_RADIUS := Vector2i(5, 11)   # min..max disc radius in tiles
const SPAWN_CLEARING_RADIUS := 8          # the player always starts in a clearing this big

func fill(ctx: GenContext, biome: BiomeResource, cells: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	if cells.is_empty():
		return

	# 1. Ground autotiles; floor edges tile against the wall void already painted.
	ctx.ground.set_cells_terrain_connect(cells, biome.terrain_set, biome.terrain_id, false)

	# 2. Tag cells that fall inside a feature disc; everything else stays DEFAULT.
	var zone := _zone_map(ctx, cells, rng)

	# 3. One shuffled pass, one role per cell, weighted by the cell's zone.
	var pool := cells.duplicate()
	_shuffle(pool, rng)
	for cell in pool:
		var z: Dictionary = zone.get(cell, DEFAULT)
		var roll := rng.randf()
		var bp: float = biome.blocker_density * z["blocker"]
		var dp: float = biome.decor_density * z["decor"]
		var ep: float = biome.enemy_density * z["enemy"]
		if not biome.blocker_tiles.is_empty() and roll < bp:
			ctx.objects.set_cell(cell, biome.blocker_source, _pick(biome.blocker_tiles, rng))
		elif not biome.decor_tiles.is_empty() and roll < bp + dp:
			ctx.decor.set_cell(cell, biome.decor_source, _pick(biome.decor_tiles, rng))
		elif not biome.enemy_roster.is_empty() and roll < bp + dp + ep:
			var enemy: Node2D = _pick(biome.enemy_roster, rng).instantiate()
			ctx.enemies.add_child(enemy)
			enemy.global_position = _scatter_pos(ctx, cell, rng)


# Map cell -> zone multipliers. Stamp clearings, then thickets (later stamps win on overlap),
# and always a clearing at the spawn centre so the player opens in a safe spot.
func _zone_map(ctx: GenContext, cells: Array[Vector2i], rng: RandomNumberGenerator) -> Dictionary:
	var land_set := {}
	for c in cells:
		land_set[c] = true
	var zone := {}
	var k := cells.size() / 1000.0

	_stamp(zone, land_set, ctx.bounds.get_center(), SPAWN_CLEARING_RADIUS, CLEARING)
	for _i in maxi(int(round(CLEARINGS_PER_1K * k)), 1):
		var r := rng.randi_range(FEATURE_RADIUS.x, FEATURE_RADIUS.y)
		_stamp(zone, land_set, cells[rng.randi() % cells.size()], r, CLEARING)
	for _i in int(round(THICKETS_PER_1K * k)):
		var r := rng.randi_range(FEATURE_RADIUS.x, FEATURE_RADIUS.y)
		_stamp(zone, land_set, cells[rng.randi() % cells.size()], r, THICKET)
	return zone


# Tag every land cell within `radius` of `centre` as `z`.
func _stamp(zone: Dictionary, land_set: Dictionary, centre: Vector2i, radius: int, z: Dictionary) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				var c := centre + Vector2i(dx, dy)
				if land_set.has(c):
					zone[c] = z
