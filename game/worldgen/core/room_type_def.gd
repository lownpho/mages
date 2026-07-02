class_name RoomTypeDef
## A room type: which structure generator builds its interior, how unique it is, where it may
## appear, and its population budget (spec §10.4). `generator_params` stays null until Task 6
## supplies typed per-generator Resources.
extends Resource

enum UniqueScope { NONE, BIOME, WORLD }

@export var id: StringName                                     ## unique room-type identity
@export var generator_id: StringName = &"empty"               ## structure generator (spec §8.2)
@export var generator_params: RoomGenParams = null            ## typed per-generator params (spec §8.2)
@export var unique_scope: UniqueScope = UniqueScope.NONE       ## NONE / BIOME / WORLD (spec §7.4, §5.4)
@export var allowed_biomes: Array[StringName] = []             ## biome ids this type may appear in
@export var enemy_groups_min: int = 0                          ## population budget (spec §9)
@export var enemy_groups_max: int = 0
@export var loot_min: int = 0
@export var loot_max: int = 0


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, generator_id)
	h = WgHash.fold_var(h, unique_scope)
	# Params are config too (spec §4.4); fold a marker for null so present-vs-absent differs.
	if generator_params != null:
		h = generator_params.hash_fold(WgHash.fold_var(h, 1))
	else:
		h = WgHash.fold_var(h, 0)
	for b in allowed_biomes:
		h = WgHash.fold_var(h, b)
	h = WgHash.fold_var(h, enemy_groups_min)
	h = WgHash.fold_var(h, enemy_groups_max)
	h = WgHash.fold_var(h, loot_min)
	h = WgHash.fold_var(h, loot_max)
	return h
