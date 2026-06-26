class_name BiomePainter extends RefCounted
## Fills one biome's cells however it likes — but only within `cells`, and only into this
## biome's layers (handed in via GenContext). The streamer calls `fill` once per biome per
## chunk. A painter must be a pure function of (seed, tile): use `Hash` for every roll, never
## per-chunk state, so adjacent chunks agree at their shared edge and a chunk rebuilds
## identically after being discarded.

func fill(_ctx: GenContext, _biome: BiomeResource, _cells: Array[Vector2i], _rng: RandomNumberGenerator) -> void:
	push_error("BiomePainter.fill() is abstract — override it")


# Deterministic sub-tile offset for a spawned node. Enemies placed dead-centre share an
# exact y with everything in their row; overlapping y-sorted sprites that tie on y flip
# draw order frame-to-frame (flicker). A hash-keyed nudge breaks the tie, de-grids the look,
# and stays identical on chunk reload (unlike a live RNG draw). Channels keep x/y independent.
func _scatter_pos(ctx: GenContext, cell: Vector2i, world_seed: int, ch_x: int, ch_y: int) -> Vector2:
	var jitter := GameConstants.PX_PER_TILE * 0.5 - 1.0
	var off := Vector2(
		(Hash.value(world_seed, cell.x, cell.y, ch_x) * 2.0 - 1.0) * jitter,
		(Hash.value(world_seed, cell.x, cell.y, ch_y) * 2.0 - 1.0) * jitter)
	return ctx.tile_to_world(cell) + off
