class_name BiomePresentation
## A Biome's art: how its semantic tile classes (floor, wall, rock and non-blocking decoration) map
## to tilesets, and its minimap colours. PRESENTATION only: tile-art selection lives outside
## generation, so no generated geometry, encounter or RNG draw ever reads it; streamers read it
## when they turn classes into tiles. A Zone may override only the decoration tileset (and, on
## ZoneResource, the decoration density).
##
## One tileset per layer, one TileMapLayer per layer, every slot OPTIONAL (null -> that layer
## renders nothing; the finite World generator draws rocks with the wall art when rock_tileset is
## null). Each tileset is single-source (source index 0) and carries its own art + collision;
## collision (wall/rock) is authored as per-tile physics polygons in the tileset, not here.
##
## Floor and wall each pick tiles one of two ways (see TilePicks):
##   - scatter (default): EVERY tile in the source, weighted by the tileset's per-tile
##     `probability` — a pure hash of the world tile.
##   - autotile (`*_autotile = true`): tiles are matched by the TERRAIN PEERING BITS authored
##     in the tileset's terrain set (standard Godot terrain painting). The streamer computes
##     each cell's 8-neighbour mask from the class grid — deterministic and seamless across
##     rooms/chunks — and picks among the tiles declaring that mask (weighted by `probability`).
##     Masks with no matching tile fall back to the scatter pick, so partial terrain sets
##     degrade gracefully.
##
## The rock layer (trees, rocks) Y-sorts against entities; decoration is a flat overlay behind
## entities. Forest Biomes point BOTH `wall_tileset` and `rock_tileset` at their tree tileset, so
## Room walls and interior rocks both render as collidable trees.
extends Resource

@export var floor_tileset: TileSet = null       ## FLOOR layer (no collision)
@export var floor_autotile := false             ## FLOOR picks by terrain peering bits
@export var wall_tileset: TileSet = null        ## WALL layer (collision; forest Biomes use tree art)
@export var wall_autotile := false              ## WALL picks by terrain peering bits
@export var rock_tileset: TileSet = null        ## ROCK layer (collision; Y-sorted trees/rocks)
@export var decoration_tileset: TileSet = null  ## decoration layer (flat overlay, no collision)

@export_group("Minimap")
@export var map_floor_color := Palette.GREY_DARK  ## minimap pixel for this biome's discovered room mass (Zughy 32)
@export var map_wall_color := Palette.BLACK       ## minimap pixel for walls and rocks at the closest zoom (Zughy 32)
