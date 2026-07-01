class_name BiomeNode extends Resource
## One vertex of the WorldGraph: the biome that sits at this graph position. Kept separate
## from BiomeResource so graph *topology* (nodes + edges) stays distinct from biome
## *content*; node↔biome is 1:1 since every biome is unique.
##
## `biome` is typed as Resource (not BiomeResource) only because the rewrite's
## BiomeResource omits its class_name during the transition — it always holds a
## BiomeResource .tres.

@export var biome: Resource   ## the BiomeResource .tres for this node
