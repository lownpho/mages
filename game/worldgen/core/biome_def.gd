class_name BiomeDef
## What a biome IS at the config level. One per world cell. Rooms are NOT listed here: a room
## type belongs to a biome by naming it in RoomTypeDef.biome — the biome's roster is the
## registry (gen_config.room_types) filtered on that, in registry order. Everything about a
## room (rarity, quotas, difficulty, enemies) lives in the room's own .tres.
extends Resource

@export var id: StringName                                     ## unique biome identity
@export var display_color: Color = Color.WHITE                 ## debug minimap fill only — NOT hashed
@export_range(0.0, 1.0, 0.01) var open_passage_chance: float = 0.5   ## P(passage is OPEN vs DOOR) in L2
@export_range(-1.0, 1.0, 0.01) var room_merge_chance: float = -1.0   ## P(slot merges into a bigger room) in L2; -1 = inherit GenConfig.room_merge_chance
@export_range(-1.0, 1.0, 0.01) var room_extra_connection_chance: float = -1.0   ## P(slot has extra loops) in L2; -1 = inherit GenConfig.extra_connection_chance
@export_range(0.0, 1.0, 0.005) var decor_density: float = 0.0  ## per-tile P(FLOOR -> DECOR_FLOOR)
@export var fallback_room_type: StringName                     ## this biome's empty room, assigned when a tier fill finds nothing (must be one of the biome's own room types)

## Logical-class → tileset art mapping. PRESENTATION only: deliberately outside CONFIG_HASH
##, so it is NOT folded
## in hash_fold() below. null = the streamer falls back to the starting biome's tiles.
@export var presentation: BiomePresentation = null


## display_color and presentation are deliberately absent — both are presentation.
func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, open_passage_chance)
	h = WgHash.fold_var(h, room_merge_chance)
	h = WgHash.fold_var(h, room_extra_connection_chance)
	h = WgHash.fold_var(h, decor_density)
	h = WgHash.fold_var(h, fallback_room_type)
	return h
