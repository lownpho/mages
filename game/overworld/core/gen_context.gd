class_name GenContext extends RefCounted
## The bundle a painter is handed so it never reaches into the scene tree itself: the
## TileMapLayers it may paint into, the node it spawns enemies under, the MacroMap it
## queries, and tile↔world helpers. One container per biome per chunk; it holds no
## generation state — everything a painter draws must be a pure function of (seed, tile).

var ground: TileMapLayer     # walkable floor (grass variants)
var decor: TileMapLayer      # cosmetic overlay, never blocks
var objects: TileMapLayer    # collidable blockers (trees, rocks); y-sorted
var enemies: Node2D          # container spawned creatures are parented to
var macro: Object            # MacroMap: biome_at / area_at / is_trail / in_world (Group C)


## Tile centre in world pixels.
func tile_to_world(tile: Vector2i) -> Vector2:
	var half := GameConstants.PX_PER_TILE / 2.0
	return Vector2(tile * GameConstants.PX_PER_TILE) + Vector2.ONE * half


## Tile that contains a world-space position (floor-divide so negative coords map correctly).
func world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i((pos / GameConstants.PX_PER_TILE).floor())


# Deterministic sub-tile offset for a spawned node. Enemies placed dead-centre share an
# exact y with everything in their row; overlapping y-sorted sprites that tie on y flip
# draw order frame-to-frame (flicker). A hash-keyed nudge breaks the tie, de-grids the look,
# and stays identical on chunk reload (unlike a live RNG draw). Channels keep x/y independent.
func scatter_pos(tile: Vector2i, world_seed: int, ch_x: int, ch_y: int) -> Vector2:
	var jitter := GameConstants.PX_PER_TILE * 0.5 - 1.0
	var off := Vector2(
		(Hash.value(world_seed, tile.x, tile.y, ch_x) * 2.0 - 1.0) * jitter,
		(Hash.value(world_seed, tile.x, tile.y, ch_y) * 2.0 - 1.0) * jitter)
	return tile_to_world(tile) + off
