class_name RoomTypeDef
## A room type: which structure generator builds its interior, how unique it is, and its
## population budget (spec §10.4). Where a NON-unique type may appear is decided solely by
## each biome's room_type_table — listing it there is the opt-in.
extends Resource

enum UniqueScope { NONE, BIOME, WORLD }

@export var id: StringName                                     ## unique room-type identity
@export var generator: RoomGenBase = null                      ## structure generator + its params; null = leave the room empty (spec §8.2)
@export var unique_scope: UniqueScope = UniqueScope.NONE       ## NONE / BIOME / WORLD (spec §7.4, §5.4)
@export var unique_allowed_biomes: Array[StringName] = []      ## BIOME/WORLD-unique placement only; ignored for NONE
@export var enemy_groups_min: int = 0                          ## population budget (spec §9)
@export var enemy_groups_max: int = 0
@export var loot_min: int = 0
@export var loot_max: int = 0


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, unique_scope)
	# The generator is config too (spec §4.4); fold a marker for null so present-vs-absent differs.
	if generator != null:
		h = generator.hash_fold(WgHash.fold_var(h, 1))
	else:
		h = WgHash.fold_var(h, 0)
	for b in unique_allowed_biomes:
		h = WgHash.fold_var(h, b)
	h = WgHash.fold_var(h, enemy_groups_min)
	h = WgHash.fold_var(h, enemy_groups_max)
	h = WgHash.fold_var(h, loot_min)
	h = WgHash.fold_var(h, loot_max)
	return h
