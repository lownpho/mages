class_name ForestPainter extends BiomePainter
## A forest biome as a stateless per-tile function. Every cell gets walkable ground; then
## independent hash rolls decide cover (trees) or decor. There is no void to seal — the whole
## ground is walkable and trees are sparse cover, so the player can always walk anywhere. Cover
## shape is data: `patch_thickness` (thickness in a patch), `coverage` (how much of the biome is
## wooded), `patch_width` (patch width in tiles) — so one painter makes both Glade's sparse
## tree-lumps and Deepwood's dense-woods-with-clearings. Sub-areas (`ctx.macro.area_at`) override
## those dials per tile, so a thicket reads denser than the surrounding biome.
##
## All rolls come from `Hash(world_seed, x, y, channel)`, so the result is identical whichever
## chunk builds a border cell (no seams) and survives a discard/rebuild unchanged. This painter
## paints ground/cover/decor ONLY — encounter spawning is Group G (it extends this base).

const SPAWN_CLEAR := 8   # tiles around world origin kept free of cover (the spawn pocket)
const PATCH_EDGE := 0.12 # softness of grove/clearing borders (smoothstep width on the noise mask)
const NOISE_GAIN := 2.0  # stretches the noise to fill [0,1] so groves reach full density, not just the noise's narrow mid-band

# Independent hash channels — one per decision so rolls on the same tile don't correlate.
enum { CH_GROUND, CH_COVER, CH_COVER_TILE, CH_DECOR, CH_DECOR_TILE }

# Lazily built when a biome wants clustered cover; pure function of (world_seed, x, y) so it
# agrees across chunk borders. One painter instance per biome (the streamer caches them).
# Frequency is fixed at the BIOME-level patch_width — per-area patch_width overrides are not
# reflected in the clump shape yet (fine-grained tuning is a later task); per-area thickness and
# coverage overrides ARE honoured below.
var _clump_noise: FastNoiseLite


func fill(ctx: GenContext, biome: Resource, cells: Array[Vector2i], world_seed: int) -> void:
	if biome.patch_width > 0:
		_ensure_clump_noise(world_seed, biome.patch_width)

	for cell in cells:
		# Ground: every cell, always — a hash-picked interior-grass variant placed directly
		# (no set_cells_terrain_connect; autotiling would resolve against empty neighbour chunks).
		if not biome.ground_tiles.is_empty():
			ctx.ground.set_cell(cell, biome.ground_source,
				Hash.pick(world_seed, cell.x, cell.y, CH_GROUND, biome.ground_tiles))

		# World-edge wall: overrides trails and cover, sealing the hull. Ground stays underneath.
		if _edge_wall(ctx, biome, cell, world_seed):
			continue

		# Keep the spawn pocket clear of cover so the player spawn isn't buried.
		if cell.x * cell.x + cell.y * cell.y <= SPAWN_CLEAR * SPAWN_CLEAR:
			continue

		# Per-tile area overrides (null area or -1 sentinel → inherit the biome dial).
		var area: Resource = ctx.macro.area_at(cell) if ctx.macro else null
		var thickness: float = area.resolve_patch_thickness(biome.patch_thickness) if area else biome.patch_thickness
		var coverage: float = area.resolve_coverage(biome.coverage) if area else biome.coverage
		var decor_density: float = area.resolve_decor_density(biome.decor_density) if area else biome.decor_density

		# Cover (trees): the sightline dial. A tree owns its cell — no decor on top. Trail cells are
		# forced clear (never a tree) so the walkable network stays connected; they still get decor
		# below, so trails read as planted clearings, not blanks.
		var on_trail: bool = ctx.macro and ctx.macro.is_trail(cell)
		if not on_trail and not biome.blocker_tiles.is_empty() \
				and _cover_roll(cell, thickness, coverage, world_seed):
			ctx.objects.set_cell(cell, biome.blocker_source,
				Hash.pick(world_seed, cell.x, cell.y, CH_COVER_TILE, biome.blocker_tiles))
			continue

		# Decor (cosmetic), at most one per open cell.
		if not biome.decor_tiles.is_empty() and Hash.chance(world_seed, cell.x, cell.y, CH_DECOR, decor_density):
			ctx.decor.set_cell(cell, biome.decor_source,
				Hash.pick(world_seed, cell.x, cell.y, CH_DECOR_TILE, biome.decor_tiles))

	_spawn_encounters(ctx, biome, cells, world_seed)


# The tree-cover coin flip for a cell given its resolved dials — the single source both `fill` and
# `_blocks` use, so encounter placement never disagrees with what's painted.
func _cover_roll(cell: Vector2i, thickness: float, coverage: float, world_seed: int) -> bool:
	return Hash.chance(world_seed, cell.x, cell.y, CH_COVER, _cover_chance(cell, thickness, coverage))


# Whether a tree or the world-edge wall occupies this cell (matches `fill`). Trails are never
# blocked; the edge wall overrides everything. Area dials are resolved per tile like in `fill`.
func _blocks(ctx: GenContext, biome: Resource, cell: Vector2i, world_seed: int) -> bool:
	if biome.blocker_tiles.is_empty():
		return false
	if ctx.macro and ctx.macro.is_world_edge(cell):
		return true
	if ctx.macro and ctx.macro.is_trail(cell):
		return false
	var area: Resource = ctx.macro.area_at(cell) if ctx.macro else null
	var thickness: float = area.resolve_patch_thickness(biome.patch_thickness) if area else biome.patch_thickness
	var coverage: float = area.resolve_coverage(biome.coverage) if area else biome.coverage
	return _cover_roll(cell, thickness, coverage, world_seed)


# Local tree probability. With no groves (patch_width 0 or full coverage) it's a flat field at
# `thickness`. Otherwise a low-frequency noise mask carves the biome into wooded patches: the top
# `coverage` of the noise is "woods" (trees at `thickness`), the rest is open clearing (no trees),
# with soft borders. So low coverage = sparse groves in open ground (Glade lumps); high coverage =
# mostly woods with open clearings/rooms (Deepwood), the gaps stitched by trail corridors.
func _cover_chance(cell: Vector2i, thickness: float, coverage: float) -> float:
	if not _clump_noise or coverage >= 1.0:
		return thickness
	var n01 := clampf(_clump_noise.get_noise_2d(cell.x, cell.y) * NOISE_GAIN * 0.5 + 0.5, 0.0, 1.0)
	var threshold := 1.0 - coverage                        # more woods → lower bar to be "woods"
	var mask := smoothstep(threshold, threshold + PATCH_EDGE, n01)
	return thickness * mask


func _ensure_clump_noise(world_seed: int, patch_width: int) -> void:
	if _clump_noise:
		return
	_clump_noise = FastNoiseLite.new()
	_clump_noise.seed = world_seed
	_clump_noise.frequency = 1.0 / float(patch_width)   # patch width in tiles → noise frequency
	_clump_noise.fractal_octaves = 2   # fewer octaves = smoother, blobbier patches (cleaner groves/rooms)
