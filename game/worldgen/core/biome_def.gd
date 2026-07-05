class_name BiomeDef
## What a biome IS at the config level. One per world cell. Spawn tables
## are typed per-room-type Resources — not Dictionaries — so they stay deterministic and
## .tres-serializable.
extends Resource

@export var id: StringName                                     ## unique biome identity
@export var display_color: Color = Color.WHITE                 ## debug minimap fill only — NOT hashed
@export_range(0.0, 1.0, 0.01) var open_passage_chance: float = 0.5   ## P(passage is OPEN vs DOOR) in L2
@export_range(-1.0, 1.0, 0.01) var room_merge_chance: float = -1.0   ## P(slot merges into a bigger room) in L2; -1 = inherit GenConfig.room_merge_chance
@export_range(0.0, 1.0, 0.005) var decor_density: float = 0.0  ## per-tile P(FLOOR -> DECOR_FLOOR)
@export var room_type_table: Array[RoomTypeTableEntry] = []    ## quota (min/max) + weighted fill table — the SOLE opt-in for non-WORLD-unique room types
@export var spawn_tables: Array[RoomSpawnTable] = []           ## one enemy table per room type

## Logical-class → tileset art mapping. PRESENTATION only: deliberately outside CONFIG_HASH
##, so it is NOT folded
## in hash_fold() below. null = the streamer falls back to the starting biome's tiles.
@export var presentation: BiomePresentation = null


## display_color and presentation are deliberately absent — both are presentation.
func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, open_passage_chance)
	h = WgHash.fold_var(h, room_merge_chance)
	h = WgHash.fold_var(h, decor_density)
	for e in room_type_table:
		h = e.hash_fold(h)
	for e in spawn_tables:
		h = e.hash_fold(h)
	return h
