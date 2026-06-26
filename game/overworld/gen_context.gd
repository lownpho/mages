class_name GenContext extends RefCounted
## Everything a generator is allowed to touch, handed in as one bundle so generators
## never reach into the scene tree themselves. Shared by the overworld and dungeons.

var rng: RandomNumberGenerator           # seeded once for the whole map
var ground: TileMapLayer                 # grass terrain (autotiled)
var decor: TileMapLayer                  # cosmetic overlay
var objects: TileMapLayer                # collidable blockers (y-sorted); may equal `decor`
var enemies: Node2D                      # container for spawned enemy nodes
var bounds: Rect2i                       # tile-space region to fill
var biomes: Array[BiomeResource] = []    # biome registry (the slice uses biomes[0] everywhere)
var macro: MacroMap                      # global overview: biome_at(tile), is_path(tile)

## An independent RNG for a sub-region, derived from the master seed + an id, so the order
## regions are generated in can't leak into their output (a region is reproducible alone).
func rng_for(id: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([rng.seed, id])
	return r

## Tile centre in world pixels.
func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile * GameConstants.PX_PER_TILE) + Vector2.ONE * (GameConstants.PX_PER_TILE / 2.0)
