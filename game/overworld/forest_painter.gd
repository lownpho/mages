class_name ForestPainter extends BiomePainter
## A forest biome as a stateless per-tile function. Every cell gets walkable ground; then
## independent hash rolls decide cover (trees), decor, or an enemy. There is no void to seal
## or fill — the whole ground is walkable and trees are sparse cover, so the player can always
## walk anywhere. Cover shape is data: `patch_thickness` (thickness in a patch), `coverage`
## (how much of the biome is wooded), `patch_width` (patch width in tiles) — so one painter makes
## both Glade's sparse tree-lumps and Deepwood's dense-woods-with-clearings.
##
## All rolls come from `Hash(world_seed, x, y, channel)`, so the result is identical whichever
## chunk builds a border cell (no seams) and survives a discard/rebuild unchanged.

const SPAWN_CLEAR := 8   # tiles around world origin kept free of cover/enemies (the spawn pocket)
const PATCH_EDGE := 0.12 # softness of grove/clearing borders (smoothstep width on the noise mask)
const NOISE_GAIN := 2.0  # stretches the noise to fill [0,1] so groves reach full density, not just the noise's narrow mid-band

# Independent hash channels — one per decision so rolls on the same tile don't correlate.
enum { CH_GROUND, CH_COVER, CH_COVER_TILE, CH_DECOR, CH_DECOR_TILE, CH_ENEMY, CH_ENEMY_PICK, CH_JIT_X, CH_JIT_Y }

# Lazily built when a biome wants clustered cover; pure function of (world_seed, x, y) so it
# agrees across chunk borders. One painter instance per biome (the streamer caches them).
var _clump_noise: FastNoiseLite


func fill(ctx: GenContext, biome: BiomeResource, cells: Array[Vector2i], _rng: RandomNumberGenerator) -> void:
	var world_seed := int(ctx.rng.seed)
	if biome.patch_width > 0:
		_ensure_clump_noise(world_seed, biome.patch_width)

	for cell in cells:
		# Ground: every cell, always — a hash-picked interior-grass variant placed directly
		# (no set_cells_terrain_connect; autotiling would resolve against empty neighbour chunks).
		if not biome.ground_tiles.is_empty():
			ctx.ground.set_cell(cell, biome.ground_source, Hash.pick(world_seed, cell.x, cell.y, CH_GROUND, biome.ground_tiles))

		# Keep the spawn pocket clear of cover and enemies.
		if cell.x * cell.x + cell.y * cell.y <= SPAWN_CLEAR * SPAWN_CLEAR:
			continue

		# Cover (trees): the sightline dial. A tree owns its cell — no decor/enemy on top.
		# Trail cells are forced clear (never a tree) so the walkable network stays connected;
		# they still get decor/enemies below, so trails read as planted clearings, not blanks.
		var on_path := ctx.macro and ctx.macro.is_path(cell)
		if not on_path and not biome.blocker_tiles.is_empty() and Hash.chance(world_seed, cell.x, cell.y, CH_COVER, _cover_chance(biome, cell)):
			ctx.objects.set_cell(cell, biome.blocker_source, Hash.pick(world_seed, cell.x, cell.y, CH_COVER_TILE, biome.blocker_tiles))
			continue

		# Decor (cosmetic), else an enemy — at most one per cell.
		if not biome.decor_tiles.is_empty() and Hash.chance(world_seed, cell.x, cell.y, CH_DECOR, biome.decor_density):
			ctx.decor.set_cell(cell, biome.decor_source, Hash.pick(world_seed, cell.x, cell.y, CH_DECOR_TILE, biome.decor_tiles))
		elif not biome.enemy_roster.is_empty() and Hash.chance(world_seed, cell.x, cell.y, CH_ENEMY, biome.enemy_density):
			var enemy: Node2D = Hash.pick(world_seed, cell.x, cell.y, CH_ENEMY_PICK, biome.enemy_roster).instantiate()
			# Position BEFORE add_child: otherwise the node enters the tree at (0,0) — world origin
			# since Enemies sits there — so it flashes at origin for a frame and its _ready reads the
			# wrong global_position. Enemies has an identity transform, so local position == world.
			enemy.position = _scatter_pos(ctx, cell, world_seed, CH_JIT_X, CH_JIT_Y)
			ctx.enemies.add_child(enemy)


# Local tree probability. With no groves (patch_width 0 or full coverage) it's a flat field
# at patch_thickness. Otherwise a low-frequency noise mask carves the biome into wooded patches: the
# top `coverage` of the noise is "woods" (trees at patch_thickness), the rest is open clearing
# (no trees), with soft borders. So low coverage = sparse groves in open ground (Glade
# lumps); high coverage = mostly woods with open clearings/rooms (Deepwood), the gaps
# stitched together by the guaranteed trail corridors.
func _cover_chance(biome: BiomeResource, cell: Vector2i) -> float:
	if not _clump_noise or biome.coverage >= 1.0:
		return biome.patch_thickness
	var n01 := clampf(_clump_noise.get_noise_2d(cell.x, cell.y) * NOISE_GAIN * 0.5 + 0.5, 0.0, 1.0)
	var threshold := 1.0 - biome.coverage                        # more woods → lower bar to be "woods"
	var mask := smoothstep(threshold, threshold + PATCH_EDGE, n01)
	return biome.patch_thickness * mask


func _ensure_clump_noise(world_seed: int, patch_width: int) -> void:
	if _clump_noise:
		return
	_clump_noise = FastNoiseLite.new()
	_clump_noise.seed = world_seed
	_clump_noise.frequency = 1.0 / float(patch_width)   # patch width in tiles → noise frequency
	_clump_noise.fractal_octaves = 2   # fewer octaves = smoother, blobbier patches (cleaner groves/rooms)
