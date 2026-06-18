class_name WorldGenerator extends MapGenerator
## Overworld generator: carve an organic landmass out of the bounds, wall off the void around
## it, then hand the land cells to the biome's painter. The shape is a low-frequency noise
## field minus a radial falloff — a lumpy coastline with a guaranteed water margin at the
## bounds — reduced to the single connected component reachable from the centre, so the player
## can always walk to everything. Internal water pockets survive as natural lakes/walls.
##
## Multi-biome partition (tagging cells with different biomes) is still future work; this slice
## paints the whole landmass as biomes[0].

const EDGE_MARGIN := 3          # tiles of guaranteed water (wall) inside the bounds
const COAST_THRESHOLD := 0.04   # noise - falloff above this is land; raise to shrink the land
const NOISE_FREQUENCY := 0.05   # lower = larger, smoother lobes
const SPAWN_LAND_RADIUS := 5    # tiles of forced land at the centre (guarantees a spawn pocket)

func generate(ctx: GenContext) -> void:
	if ctx.biomes.is_empty():
		push_error("WorldGenerator: GenContext.biomes is empty")
		return

	var biome: BiomeResource = ctx.biomes[0]
	var land := _landmass(ctx)
	# Everything in bounds that isn't land becomes impassable wall (coastline + interior lakes).
	if biome.wall_terrain_id >= 0:
		_wall_void(ctx, biome, land)
	var painter: BiomePainter = biome.painter.new() if biome.painter else ScatterPainter.new()
	painter.fill(ctx, biome, land, ctx.rng_for(0))


# An organic blob of walkable cells: noise threshold with a radial falloff, then the connected
# component containing the centre (drops stray islands so the world is one reachable piece).
func _landmass(ctx: GenContext) -> Array[Vector2i]:
	var b := ctx.bounds
	var noise := FastNoiseLite.new()
	noise.seed = ctx.rng.randi()
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_octaves = 4

	var centre := b.get_center()
	var rx := maxf(b.size.x * 0.5 - EDGE_MARGIN, 1.0)
	var ry := maxf(b.size.y * 0.5 - EDGE_MARGIN, 1.0)

	var is_land := {}
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var dx := (x - centre.x) / rx
			var dy := (y - centre.y) / ry
			var falloff := dx * dx + dy * dy           # 0 at centre, 1 at the inset radius
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5   # 0..1
			if n - falloff > COAST_THRESHOLD:
				is_land[Vector2i(x, y)] = true

	# Guarantee a spawn pocket and a seed for the flood fill.
	for dy in range(-SPAWN_LAND_RADIUS, SPAWN_LAND_RADIUS + 1):
		for dx in range(-SPAWN_LAND_RADIUS, SPAWN_LAND_RADIUS + 1):
			if dx * dx + dy * dy <= SPAWN_LAND_RADIUS * SPAWN_LAND_RADIUS:
				is_land[centre + Vector2i(dx, dy)] = true

	return _flood_from(is_land, centre)


# 4-connected flood fill from `start` over the land set — the reachable component only.
func _flood_from(is_land: Dictionary, start: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		out.append(c)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nb: Vector2i = c + d
			if is_land.has(nb) and not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return out


# Paint every in-bounds cell that isn't land as wall terrain (collision comes from the wall
# tiles; the floor/wall border autotiles when the painter floors the land afterwards).
func _wall_void(ctx: GenContext, biome: BiomeResource, land: Array[Vector2i]) -> void:
	var land_set := {}
	for c in land:
		land_set[c] = true
	var b := ctx.bounds
	var wall: Array[Vector2i] = []
	for y in range(b.position.y, b.end.y):
		for x in range(b.position.x, b.end.x):
			var c := Vector2i(x, y)
			if not land_set.has(c):
				wall.append(c)
	ctx.ground.set_cells_terrain_connect(wall, biome.terrain_set, biome.wall_terrain_id, false)
