class_name BiomePresentation
## How one biome's LOGICAL tile classes (FLOOR/WALL/BLOCKER/DECOR_FLOOR) map to actual tileset
## art. This is a PRESENTATION concern only: tile-art selection lives outside the
## deterministic core, so it is deliberately NOT folded into CONFIG_HASH and never touched by
## generation code — the streamer reads it when blitting rooms into chunks.
##
## One tileset per layer, one TileMapLayer per layer, every slot OPTIONAL (null → that layer
## renders nothing). Each tileset is single-source (the streamer uses source index 0) and
## carries its own art + collision; collision (wall/object) is authored as per-tile physics
## polygons in the tileset, not here.
##
## Floor and wall each pick tiles one of two ways:
##   - scatter (default): EVERY tile in the source, weighted by the tileset's per-tile
##     `probability` — a pure hash of the world tile (see WorldStreamer._pick_weighted).
##   - autotile (`*_autotile = true`): tiles are matched by the TERRAIN PEERING BITS authored
##     in the tileset's terrain set (standard Godot terrain painting). The streamer computes
##     each cell's 8-neighbour mask from the logical class grid — deterministic and seamless
##     across rooms/chunks — and picks among the tiles declaring that mask (weighted by
##     `probability`). Masks with no matching tile fall back to the scatter pick, so partial
##     terrain sets degrade gracefully.
##
## The object layer (BLOCKER: trees, rocks) Y-sorts against entities; object_bg (DECOR_FLOOR)
## is a flat overlay behind entities. Forest biomes point BOTH `wall_tileset` and
## `object_tileset` at their tree tileset, so room shells (WALL) and groves (BLOCKER) both
## render as collidable trees.
extends Resource

@export var floor_tileset: TileSet = null      ## FLOOR layer (no collision)
@export var floor_autotile := false            ## FLOOR picks by terrain peering bits
@export var wall_tileset: TileSet = null       ## WALL layer (collision; forest biomes use tree art)
@export var wall_autotile := false             ## WALL picks by terrain peering bits
@export var object_tileset: TileSet = null     ## BLOCKER layer (collision; Y-sorted trees/rocks)
@export var object_bg_tileset: TileSet = null  ## DECOR_FLOOR layer (flat overlay, no collision)
