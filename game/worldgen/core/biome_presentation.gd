class_name BiomePresentation
## How one biome's LOGICAL tile classes (FLOOR/WALL/BLOCKER/DECOR_FLOOR) map to actual tileset
## art (Task 8). This is a PRESENTATION concern only: per spec §13 tile-art selection lives
## outside the deterministic core, so it is deliberately NOT folded into CONFIG_HASH and never
## touched by generation code — the streamer reads it when blitting rooms into chunks.
##
## Ground and wall layers share `floor_tileset` (grass tiles carry no collider, wall tiles do);
## blockers and floor decor come from `object_tileset`. All arrays are hash-picked per world tile
## for variation (see WorldStreamer._pick_atlas), so a rebuilt chunk is byte-identical.
extends Resource

@export var floor_tileset: TileSet = null              ## ground + wall layers use this
@export var floor_source_id: int = 0
@export var grass_tiles: Array[Vector2i] = []          ## FLOOR / DECOR_FLOOR ground pick
@export var wall_tiles: Array[Vector2i] = []           ## WALL pick (same source, collider tiles)

@export var object_tileset: TileSet = null             ## decor layer
@export var blocker_source_id: int = 1
@export var blocker_tiles: Array[Vector2i] = []        ## BLOCKER (trees/rocks) pick
@export var decor_source_id: int = 0
@export var decor_tiles: Array[Vector2i] = []          ## DECOR_FLOOR overlay pick (non-blocking)
