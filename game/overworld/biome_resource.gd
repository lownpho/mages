class_name BiomeResource extends Resource
## What a biome IS (data). How it generates lives in its `painter` (a BiomePainter).
## Every channel is uniform: a tileset `source` + a list of atlas `tiles` + a `density`.
## In the streamed world there is no void or wall to paint — the whole ground is
## walkable and blockers are sparse cover, so the old terrain/void/clump knobs are gone.

@export var id: StringName                          ## matches the biome's TileMapLayers in the scene

@export_group("Ground")
@export_range(0, 8, 1, "or_greater") var ground_source: int = 0  ## source id in the floor tileset
@export var ground_tiles: Array[Vector2i] = []      ## interior-grass atlas cells, hash-picked per tile

@export_group("Cover (blockers)")
@export_range(0, 8, 1, "or_greater") var blocker_source: int = 0 ## source id of the objects tileset
@export var blocker_tiles: Array[Vector2i] = []     ## object atlas cells (trees, boulders)
@export_range(0.0, 0.5, 0.001) var patch_thickness: float = 0.0     ## how thick trees are inside a wooded patch (0 = none, 0.5 = packed)
@export_range(0.0, 1.0, 0.01) var coverage: float = 1.0     ## how much of the biome is woods vs open (1 = all woods, low = rare groves)
@export_range(0, 128, 1, "or_greater") var patch_width: int = 0   ## typical patch width in tiles (0 = uniform woods, no patches)

@export_group("Decor (cosmetic)")
@export_range(0, 8, 1, "or_greater") var decor_source: int = 0   ## source id of the decor tileset
@export var decor_tiles: Array[Vector2i] = []       ## transparent atlas cells (flowers, tufts)
@export_range(0.0, 0.2, 0.001) var decor_density: float = 0.0    ## cosmetic overlay; per-tile probability

@export_group("Enemies")
@export var enemy_roster: Array[PackedScene] = []   ## reuses existing enemy scenes
@export_range(0.0, 0.1, 0.001) var enemy_density: float = 0.0    ## per-tile spawn probability at peak danger
@export_range(0.0, 1.0, 0.01) var danger_threshold: float = 0.45 ## danger below this = safe zone (no enemies)
@export_range(1.0, 6.0, 0.1) var danger_peak: float = 2.0        ## density multiplier at maximum danger

const _DANGER_EDGE := 0.12   ## smoothstep softness at the safe/dangerous border

## Multiplier applied to `enemy_density` for a cell of ambient danger `d` (0..1, from MacroMap):
## 0 below `danger_threshold` (a safe zone), ramping to `danger_peak` at full danger. So one
## flat density becomes contiguous enemy zones separated by empty ground.
func danger_multiplier(d: float) -> float:
	return smoothstep(danger_threshold, danger_threshold + _DANGER_EDGE, d) * danger_peak

@export_group("Generation")
@export_range(0, 16, 1) var region_weight: int = 1  ## relative frequency in the region grid (0 = never)
@export var allows_dungeon: bool = false            ## can a dungeon entrance spawn here (read by MacroMap)
@export var painter: Script                         ## the BiomePainter subclass that fills this biome
