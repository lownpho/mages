class_name SignResource
extends Resource
## A Sign, written as a sub-resource of a Biome or Zone. Each stands exactly once in the World.

## Floated above the post. The label doesn't wrap, so break lines by hand.
@export_multiline var text := ""
## Reading the Sign reveals the nearest Boss led by this enemy. Must lead some Biome's Boss.
@export var reveals: CreatureResource
