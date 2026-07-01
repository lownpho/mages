class_name BiomeResource extends Resource
## What a biome IS (data). How it generates lives in its `painter` (a BiomePainter,
## wired in Group F). Every scenery channel is uniform: a tileset `source` + a list of
## atlas `tiles` + shape dials. The whole ground is walkable; blockers are sparse cover.
##
## This is the streamed-rewrite BiomeResource. Enemy spawning is no longer a biome-level
## density — it moves into `area_set` (rosters + encounter templates), so this resource
## carries no roster of its own. Biomes are unique and hand-placed by the WorldGraph, so
## there is no `region_weight` either.

@export var id: StringName                          ## matches the biome's TileMapLayers in world.tscn (floor_<id> etc.)
@export var painter: Script                         ## the BiomePainter subclass that fills this biome (set in Group F)

@export_group("Ground")
@export_range(0, 8, 1, "or_greater") var ground_source: int = 0  ## source id in the floor tileset
@export var ground_tiles: Array[Vector2i] = []      ## interior-grass atlas cells, hash-picked per tile

@export_group("Cover (blockers)")
@export_range(0, 8, 1, "or_greater") var blocker_source: int = 0 ## source id of the objects tileset
@export var blocker_tiles: Array[Vector2i] = []     ## object atlas cells (trees, boulders)
@export_range(0.0, 0.5, 0.001) var patch_thickness: float = 0.0  ## tree thickness inside a wooded patch (0 = none, 0.5 = packed)
@export_range(0.0, 1.0, 0.01) var coverage: float = 1.0          ## how much of the biome is woods vs open
@export_range(0, 128, 1, "or_greater") var patch_width: int = 0  ## typical patch width in tiles (0 = uniform)

@export_group("Decor (cosmetic)")
@export_range(0, 8, 1, "or_greater") var decor_source: int = 0   ## source id of the decor tileset
@export var decor_tiles: Array[Vector2i] = []       ## transparent atlas cells (flowers, tufts)
@export_range(0.0, 0.2, 0.001) var decor_density: float = 0.0    ## per-tile cosmetic-overlay probability

@export_group("Areas & dungeons")
@export var area_set: Array[AreaResource] = []      ## sub-area types placed inside this biome (Group E)
@export var dungeon_types: Array[StringName] = []   ## one door per type is placed here (Group H)

@export_group("Size")
@export_range(200, 6000, 50, "or_greater") var target_radius_tiles: int = 800  ## rough biome half-extent, tuned to the ≈1500-tile target


## The single required-area check the content test relies on.
func has_required_area() -> bool:
	for a in area_set:
		if a != null and a.required:
			return true
	return false
