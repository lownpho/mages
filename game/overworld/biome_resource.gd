class_name BiomeResource extends Resource
## What a biome IS (data). How it generates lives in its `painter` (a BiomePainter), or the
## default ScatterPainter when left null. Adding a simple biome is one .tres, no code.

@export var id: StringName                          ## matches the biome's TileMapLayers in the scene

@export_group("Ground")
@export var terrain_set: int = 0                    ## which terrain set in the floor tileset
@export var terrain_id: int = 0                     ## which terrain to paint as walkable ground
@export var wall_terrain_id: int = -1               ## impassable border terrain; -1 = no walls

@export var void_terrain_id: int = -1               ## ground under the unwalkable forest; -1 = reuse floor

@export_group("Blockers (cover)")
@export var blocker_source: int = 0                 ## source id of the objects tileset
@export var blocker_tiles: Array[Vector2i] = []     ## object atlas cells to scatter (trees, boulders)
@export var blocker_density: float = 0.0            ## the sightline/cover dial; per ground tile

@export_group("Forest (ForestPainter)")
@export var void_fill_density: float = 0.9          ## fraction of interior void cells filled with trees
@export var clump_count_per_1k: float = 0.0         ## tree clusters in the walkable area, per 1000 land tiles
@export var clump_radius := Vector2i(2, 4)          ## min..max clump disc radius in tiles
@export var clump_density: float = 0.7              ## fraction of a clump's cells that get a tree (porous)

@export_group("Decor (cosmetic)")
@export var decor_source: int = 0                   ## source id of the decor tileset
@export var decor_tiles: Array[Vector2i] = []       ## transparent atlas cells (flowers, tufts)
@export var decor_density: float = 0.0              ## cosmetic overlay; per ground tile

@export_group("Enemies")
@export var enemy_roster: Array[PackedScene] = []   ## reuses existing enemy scenes
@export var enemy_density: float = 0.0              ## expected enemies per ground tile

@export_group("Generation")
@export var allows_dungeon: bool = false            ## can a dungeon entrance spawn here
@export var painter: Script                         ## null -> ScatterPainter
