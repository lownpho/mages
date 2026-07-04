class_name RoomTypeDef
## A room type: which structure generator builds its interior, how unique it is, and its
## population budget. Where a NON-unique type may appear is decided solely by
## each biome's room_type_table — listing it there is the opt-in.
extends Resource

enum UniqueScope { NONE, BIOME, WORLD }

@export var id: StringName                                     ## unique room-type identity
@export var generator: RoomGenBase = null                      ## structure generator + its params; null = leave the room empty
@export var unique_scope: UniqueScope = UniqueScope.NONE       ## NONE / BIOME / WORLD
@export var unique_allowed_biomes: Array[StringName] = []      ## BIOME/WORLD-unique placement only; ignored for NONE
@export var enemy_groups_min: int = 0                          ## population budget
@export var enemy_groups_max: int = 0

## One specific scene (door, sign, altar, portal) placed at the room centre and instantiated by
## WgEntitySpawner. Deliberately NOT hashed (see hash_fold): like presentation it is an overlay
## on the finished room, not terrain, so swapping it never re-rolls a saved world.
@export var feature_scene: PackedScene = null


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, id)
	h = WgHash.fold_var(h, unique_scope)
	# The generator is config too; fold a marker for null so present-vs-absent differs.
	if generator != null:
		h = generator.hash_fold(WgHash.fold_var(h, 1))
	else:
		h = WgHash.fold_var(h, 0)
	for b in unique_allowed_biomes:
		h = WgHash.fold_var(h, b)
	h = WgHash.fold_var(h, enemy_groups_min)
	h = WgHash.fold_var(h, enemy_groups_max)
	return h
