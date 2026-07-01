class_name CavePainter extends BiomePainter
## A minimal second painter family, proving a biome can point its `painter` at something other
## than ForestPainter and plug in with no streamer changes. It paints hash-picked ground and a
## sparse scatter of blockers (never on a trail), nothing else. A real cave biome (lava, walls,
## carved rooms) is future art/logic; this only needs to run deterministically without error.

const BLOCKER_CHANCE := 0.06   # flat sparse scatter — no clump noise, no area overrides (stub)

enum { CH_GROUND, CH_COVER, CH_COVER_TILE }


func fill(ctx: GenContext, biome: Resource, cells: Array[Vector2i], world_seed: int) -> void:
	for cell in cells:
		if not biome.ground_tiles.is_empty():
			ctx.ground.set_cell(cell, biome.ground_source,
				Hash.pick(world_seed, cell.x, cell.y, CH_GROUND, biome.ground_tiles))

		# World-edge wall: overrides trails and cover, sealing the hull. Ground stays underneath.
		if _edge_wall(ctx, biome, cell, world_seed):
			continue

		var on_trail: bool = ctx.macro and ctx.macro.is_trail(cell)
		if not on_trail and not biome.blocker_tiles.is_empty() \
				and Hash.chance(world_seed, cell.x, cell.y, CH_COVER, BLOCKER_CHANCE):
			ctx.objects.set_cell(cell, biome.blocker_source,
				Hash.pick(world_seed, cell.x, cell.y, CH_COVER_TILE, biome.blocker_tiles))

	_spawn_encounters(ctx, biome, cells, world_seed)


# Whether a blocker or the world-edge wall occupies this cell (matches `fill`) — the predicate the
# encounter pass uses to avoid spawning enemies inside cover.
func _blocks(ctx: GenContext, biome: Resource, cell: Vector2i, world_seed: int) -> bool:
	if biome.blocker_tiles.is_empty():
		return false
	if ctx.macro and ctx.macro.is_world_edge(cell):
		return true
	if ctx.macro and ctx.macro.is_trail(cell):
		return false
	return Hash.chance(world_seed, cell.x, cell.y, CH_COVER, BLOCKER_CHANCE)
