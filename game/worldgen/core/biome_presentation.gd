class_name BiomePresentation
## How one biome's LOGICAL tile classes (FLOOR/WALL/BLOCKER/DECOR_FLOOR) map to actual tileset
## art. This is a PRESENTATION concern only: per spec §13 tile-art selection lives outside the
## deterministic core, so it is deliberately NOT folded into CONFIG_HASH and never touched by
## generation code — the streamer reads it when blitting rooms into chunks.
##
## One tileset per logical class, one TileMapLayer per class, every slot OPTIONAL (null → that
## class renders nothing). Each tileset is single-source (the streamer uses source index 0) and
## carries its own art + collision; there is no source_id and no curated atlas subset — the
## streamer uses EVERY tile in the source, weighted by the tileset's per-tile `probability`
## (default 1.0). Collision (wall/blocker) is authored as per-tile physics polygons in the
## tileset, not here. Picks are a pure hash of the world tile, so a rebuilt chunk is
## byte-identical (see WorldStreamer._pick_weighted).
##
## Forest biomes (glade, deepwood) point BOTH `wall_tileset` and `blocker_tileset` at their tree
## tileset, so room shells (WALL) and groves (BLOCKER) both render as collidable trees.
extends Resource

@export var floor_tileset: TileSet = null    ## FLOOR layer (no collision)
@export var wall_tileset: TileSet = null     ## WALL layer (collision; forest biomes use tree art)
@export var blocker_tileset: TileSet = null  ## BLOCKER layer (collision; trees/rocks)
@export var decor_tileset: TileSet = null    ## DECOR_FLOOR overlay layer (no collision)
