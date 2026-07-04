class_name AdjacencyRules
## World-layout adjacency constraints. Both lists are ordered arrays of ordered
## biome-pair Resources so placement and hashing are fully deterministic.
extends Resource

@export var required: Array[BiomePairRule] = []   ## each pair must share ≥1 border
@export var forbidden: Array[BiomePairRule] = []  ## each pair must never share a border


func hash_fold(h: int) -> int:
	for r in required:
		h = r.hash_fold(h)
	for r in forbidden:
		h = r.hash_fold(h)
	return h
