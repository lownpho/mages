class_name BiomeDef
## What a biome IS at the config level. A biome claims a `size_cells` rectangle of macro-cells
## on the world grid (one macro-cell = biome_slots × biome_slots room slots). Rooms are NOT
## listed here: a room type belongs to a biome by naming it in RoomTypeDef.biome — the biome's
## roster is the registry (gen_config.room_types) filtered on that, in registry order.
## Everything about a room (rarity, quotas, difficulty, size window, enemies) lives in the
## room's own .tres.
extends Resource

@export var id: StringName                                     ## unique biome identity
@export var display_color: Color = Color.WHITE                 ## debug minimap fill only — NOT hashed
@export var family: StringName = &""                           ## UI grouping (bestiary pages, sub-biome variants) — NOT hashed; &"" = ungrouped
@export var size_cells := Vector2i.ONE                         ## macro-cells this biome claims on the world grid (w×h)
@export_range(0.0, 1.0, 0.01) var open_passage_chance: float = 0.5   ## P(passage is OPEN vs DOOR) in L2
@export_range(-1.0, 1.0, 0.01) var bsp_stop_chance: float = -1.0     ## P(a splittable rect stops early — bigger rooms) in L2; -1 = inherit GenConfig.bsp_stop_chance
@export_range(-1.0, 1.0, 0.01) var room_extra_connection_chance: float = -1.0   ## P(slot has extra loops) in L2; -1 = inherit GenConfig.extra_connection_chance
@export_range(0.0, 1.0, 0.005) var decor_density: float = 0.0  ## per-tile P(FLOOR -> DECOR_FLOOR)
@export var fallback_room_type: StringName                     ## this biome's empty room, assigned when a tier fill finds nothing (must be one of the biome's own room types, with a universal size window)
## The starting biome places the player in a room of this type (find_spawn_position). PRESENTATION
## tier: it steers only where the player lands, never generation, so it is NOT folded into
## hash_fold below. &"" = fall back to the lowest-difficulty room heuristic.
@export var spawn_room_type: StringName = &""

## Organic-shell overrides, -1 = inherit the GenConfig dial. These are what make one biome's
## walls read differently from another's (thin/fat bands, ragged vs clean edges, corner bulk).
@export_group("Shell overrides (-1 = inherit)")
@export var wall_extra_depth: int = -1                         ## max extra wall rings of shell noise
@export var wall_outer_erode: int = -1                         ## max tiles the clearing-facing wall edge recedes
@export var wall_noise_period: int = -1                        ## tiles between wall-noise lattice samples
@export var corner_radius: int = -1                            ## room-corner rounding radius
@export var wall_inset_max: int = -1                           ## max per-side base wall inset

## Logical-class → tileset art mapping. PRESENTATION only: deliberately outside CONFIG_HASH
##, so it is NOT folded
## in hash_fold() below. null = the streamer falls back to the starting biome's tiles.
@export var presentation: BiomePresentation = null


## display_color, family and presentation are deliberately absent — all presentation-tier.
func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, size_cells)
	h = WgHash.fold_var(h, open_passage_chance)
	h = WgHash.fold_var(h, bsp_stop_chance)
	h = WgHash.fold_var(h, room_extra_connection_chance)
	h = WgHash.fold_var(h, decor_density)
	h = WgHash.fold_var(h, fallback_room_type)
	h = WgHash.fold_var(h, wall_extra_depth)
	h = WgHash.fold_var(h, wall_outer_erode)
	h = WgHash.fold_var(h, wall_noise_period)
	h = WgHash.fold_var(h, corner_radius)
	h = WgHash.fold_var(h, wall_inset_max)
	return h
