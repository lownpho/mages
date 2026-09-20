class_name SignResource
extends Resource
## A Sign, written as a sub-resource of a Biome or Zone. Each stands exactly once in the World.

## Floated above the post. The label doesn't wrap, so break lines by hand.
@export_multiline var text := ""
## Reading the Sign reveals the nearest Boss or Miniboss led by this enemy. Must lead one of them.
@export var reveals: CreatureResource
## Reading the Sign marks the first Room of this Biome on the Map, in its own colour. Independent of
## `reveals`.
@export var reveals_biome: BiomeResource
