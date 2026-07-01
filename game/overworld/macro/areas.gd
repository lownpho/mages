extends RefCounted
## Sub-area placement: bakes each biome's lattice cell into a GRID×GRID grid of area-cells,
## assigning every area-cell an AreaResource *type* from that biome's `area_set`. Types repeat
## (unlike biomes): the forced-min weighted bake pins each `required` type into ≥1 cell, then
## weighted-fills the rest so instance counts track `weight`. Pure function of the seed, keyed
## per biome node, so biomes bake independently and identically on rebuild.
##
## Geometry (which tile is which area-cell, area-cell centres) lives in MacroMap, which owns the
## cell/warp maths; this module is only the per-(node, area-cell) → type map. MacroMap.area_at
## drives the lookup and registers the branch trails.
##
## NOTE (transition): `class_name` is intentionally omitted (see macro_map.gd) — MacroMap
## preloads this file. No later group references it directly; they go through MacroMap's
## `area_at` / `area_instances`.

# Area-cells per biome cell along one axis. CELL (1500) / GRID (3) = 500-tile area-cells →
# GRID*GRID = 9 instances per biome, comfortably above any biome's required-type count (1–2).
# Each instance branches a trail off the network, so keeping the count modest also keeps the
# guaranteed-clear network (and every is_trail caller) light.
const GRID := 3
const COUNT := GRID * GRID

const _CH_SHUFFLE := 50   # per-(node, area-cell) shuffle order
const _CH_FILL := 51      # per-(node, area-cell) weighted fill roll

var _seed: int
var _baked: Dictionary = {}   # int node_index -> Array[AreaResource] of size COUNT (index = area-cell)


## `node_biomes`: node_index -> BiomeResource. Bakes each occupied biome's area-cells up front.
func setup(world_seed: int, node_biomes: Dictionary) -> void:
	_seed = world_seed
	_baked.clear()
	for node in node_biomes:
		_baked[node] = _bake_biome(node, node_biomes[node].area_set)


## The AreaResource owning area-cell `index` in biome `node`, or null (empty area_set / off-world).
func type_at(node: int, index: int) -> Resource:
	var arr: Array = _baked.get(node, [])
	if index < 0 or index >= arr.size():
		return null
	return arr[index]


# Forced-min weighted placement over the biome's COUNT area-cells (ports the old
# `_bake_region_biomes`): Hash-shuffle the cells, force each required type into the first cells
# (guaranteeing ≥1 instance), then weighted-fill the rest — every type participates in the fill,
# so counts track weight and a type may fill several cells.
func _bake_biome(node: int, area_set: Array) -> Array:
	var out: Array = []
	out.resize(COUNT)

	var types: Array = []
	for a in area_set:
		if a != null:
			types.append(a)
	if types.is_empty():
		return out   # all null: nothing to place

	# Deterministic area-cell order, keyed per biome node.
	var order: Array[int] = []
	for i in COUNT:
		order.append(i)
	var s := _seed
	var nn := node
	order.sort_custom(func(a: int, b: int) -> bool:
		return Hash.value(s, nn, a, _CH_SHUFFLE) < Hash.value(s, nn, b, _CH_SHUFFLE))

	var forced: Array = []
	for a in types:
		if a.required:
			forced.append(a)
	if forced.size() > COUNT:
		push_warning("Areas: biome node %d has %d required types but only %d area-cells — some will be missing" % [node, forced.size(), COUNT])

	var total_w := 0.0
	for a in types:
		total_w += maxf(a.weight, 0.0)

	for k in COUNT:
		var cell_index: int = order[k]
		out[cell_index] = forced[k] if k < forced.size() else _weighted_pick(node, cell_index, types, total_w)
	return out


# Weighted type for one area-cell, keyed on (node, area-cell) so it's stable. All types (required
# included) accumulate into the roll, so counts stay proportional to weight.
func _weighted_pick(node: int, cell_index: int, types: Array, total_w: float) -> Resource:
	if total_w <= 0.0:
		return types[0]
	var roll := Hash.value(_seed, node, cell_index, _CH_FILL) * total_w
	for a in types:
		roll -= maxf(a.weight, 0.0)
		if roll < 0.0:
			return a
	return types[types.size() - 1]
