class_name WorldResource
extends Resource
## The World's topology, authored once in world.tres at the root of a content folder. Every Biome
## folder under biomes/ must appear here exactly once: on the Ideal path, or as a Side biome.

## The Ideal path's Biomes in order. The first holds the Spawn zone.
@export var ideal_path: Array[BiomeResource] = []
## Each Side biome and the Ideal-path Biome it attaches to.
@export var side_biomes: Array[SideBiomeResource] = []
