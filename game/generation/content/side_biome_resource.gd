class_name SideBiomeResource
extends Resource
## One Side biome record in world.tres: a dead-end Biome attached to a Room on its parent's Ideal path.

@export var biome: BiomeResource
## Must be a Biome on the Ideal path.
@export var parent: BiomeResource
