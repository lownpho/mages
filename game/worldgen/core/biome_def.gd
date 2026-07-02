class_name BiomeDef
## What a biome IS at the config level (spec §10.4). One per world cell. Presentation refs
## (tilesets) are deliberately absent until Task 8. Spawn/loot tables are flat typed arrays
## keyed by room_type — not Dictionaries — so they stay deterministic and .tres-serializable.
extends Resource

@export var id: StringName                                     ## unique biome identity
@export var display_color: Color = Color.WHITE                 ## debug minimap fill (spec §12 tooling 1)
@export_range(0.0, 1.0, 0.01) var openness: float = 0.5        ## P(passage is OPEN vs DOOR) in L2 (spec §7.3)
@export_range(0.0, 1.0, 0.005) var decor_density: float = 0.0  ## per-tile P(FLOOR -> DECOR_FLOOR) (spec §8.1.5)
@export var room_type_table: Array[RoomTypeTableEntry] = []    ## weighted fill table (spec §7.4)
@export var spawn_tables: Array[SpawnTableEntry] = []          ## enemy options, keyed by room_type
@export var loot_tables: Array[LootTableEntry] = []            ## loot options, keyed by room_type

## Logical-class → tileset art mapping (Task 8). PRESENTATION only: deliberately outside
## CONFIG_HASH (spec §13 — tile-art selection is not part of the deterministic world), so it is
## NOT folded in hash_fold() below. null = the streamer falls back to another biome's tiles.
@export var presentation: BiomePresentation = null

# Precomputed at GenConfig.prepare(); generation loops read these integers, never the floats (§4.3.3).
var openness_threshold: int = 0
var decor_threshold: int = 0


func prepare() -> void:
	openness_threshold = WgHash.threshold(openness)
	decor_threshold = WgHash.threshold(decor_density)


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, display_color)
	h = WgHash.fold_var(h, openness)
	h = WgHash.fold_var(h, decor_density)
	for e in room_type_table:
		h = e.hash_fold(h)
	for e in spawn_tables:
		h = e.hash_fold(h)
	for e in loot_tables:
		h = e.hash_fold(h)
	return h
