class_name BiomePairRule
## An ordered pair of biome ids for one adjacency rule. Two StringNames in
## a fixed order (not a Dictionary/Vector2i) so both the rule and its hash are deterministic.
extends Resource

@export var biome_a: StringName
@export var biome_b: StringName


func hash_fold(h: int) -> int:
	h = WgHash.fold_var(h, biome_a)
	h = WgHash.fold_var(h, biome_b)
	return h
