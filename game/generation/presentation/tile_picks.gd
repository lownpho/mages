class_name TilePicks
extends RefCounted
## Which tile of a tileset a World tile shows: the autotile mask and the weighted pick, shared by
## every streamer. Both are pure functions of a seed, the tile and the tileset, so a rebuilt chunk
## shows the same tiles and neighbouring chunks agree at their seams.
##
## A scatter pick takes EVERY tile of the tileset's first source, weighted by its `probability`. An
## autotile pick first narrows to the tiles whose terrain peering bits match the tile's 8-neighbour
## mask; masks the tileset doesn't author fall back to the scatter pick, so partial terrain sets
## degrade gracefully.

## Variant channels, kept distinct so a tile's wall variant never correlates with its floor variant.
const CH_FLOOR := 1
const CH_WALL := 2
const CH_ROCK := 3
const CH_DECORATION := 4

## The 8 neighbours of the autotile mask, bit i = NEIGHBOURS[i] is same-terrain. Order (N, NE, E,
## SE, S, SW, W, NW) pairs each offset with the TileSet peering bit it corresponds to, so masks
## computed from a class grid line up with masks read from the tileset's authored terrain data.
const NEIGHBOURS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const _PEERING: Array[int] = [
	TileSet.CELL_NEIGHBOR_TOP_SIDE, TileSet.CELL_NEIGHBOR_TOP_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_CORNER,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE, TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_CORNER,
	TileSet.CELL_NEIGHBOR_LEFT_SIDE, TileSet.CELL_NEIGHBOR_TOP_LEFT_CORNER,
]

## Tables whose total weight fits this get a direct lookup.
const _LOOKUP_MAX := 1 << 18

static var _tables: Dictionary = {}           # TileSet -> scatter table
static var _terrain_tables: Dictionary = {}   # TileSet -> {canonical mask -> table}


## A tileset's scatter table, built once: every tile of its first source with integer cumulative
## weights from each tile's `probability`, scaled ×1000 (at least 1 for any non-zero tile) so
## selection stays pure-integer. Fields: source_id, coords (Array[Vector2i]), cum
## (PackedInt64Array), total (int), and lookup (PackedInt32Array: for each value below total, the
## index of the tile it picks; empty past _LOOKUP_MAX). total is 0 for a null or empty tileset.
static func table(tileset: TileSet) -> Dictionary:
	if _tables.has(tileset):
		return _tables[tileset]
	var coords: Array[Vector2i] = []
	var cum := PackedInt64Array()
	var acc := 0
	var source_id := -1
	if tileset != null and tileset.get_source_count() > 0:
		source_id = tileset.get_source_id(0)
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if source != null:
			for i in source.get_tiles_count():
				var coord := source.get_tile_id(i)
				var data := source.get_tile_data(coord, 0)
				var weight := 1000
				if data != null:
					weight = maxi(1, roundi(data.probability * 1000.0))
					if data.probability <= 0.0:
						continue   # probability 0 -> never placed
				acc += weight
				coords.append(coord)
				cum.append(acc)
	var out := _table(source_id, coords, cum)
	_tables[tileset] = out
	return out


## A tileset's autotile tables, built once: canonical mask -> weighted table over the tiles of its
## first source that declare that mask through terrain peering bits (any terrain set or index).
## Tiles without terrain stay in the scatter table only. Empty when the tileset authors no terrain.
static func terrain_table(tileset: TileSet) -> Dictionary:
	if _terrain_tables.has(tileset):
		return _terrain_tables[tileset]
	var groups: Dictionary = {}   # mask -> Array of [coord, weight]
	var source_id := -1
	if tileset != null and tileset.get_source_count() > 0:
		source_id = tileset.get_source_id(0)
		var source := tileset.get_source(source_id) as TileSetAtlasSource
		if source != null:
			for i in source.get_tiles_count():
				var coord := source.get_tile_id(i)
				var data := source.get_tile_data(coord, 0)
				if data == null or data.terrain_set < 0 or data.terrain < 0 or data.probability <= 0.0:
					continue
				var mask := 0
				for bit in 8:
					if data.is_valid_terrain_peering_bit(_PEERING[bit]) \
							and data.get_terrain_peering_bit(_PEERING[bit]) == data.terrain:
						mask |= 1 << bit
				mask = canonical_mask(mask)
				if not groups.has(mask):
					groups[mask] = []
				groups[mask].append([coord, maxi(1, roundi(data.probability * 1000.0))])
	var by_mask: Dictionary = {}
	for mask in groups:
		var coords: Array[Vector2i] = []
		var cum := PackedInt64Array()
		var acc := 0
		for pair in groups[mask]:
			acc += pair[1]
			coords.append(pair[0])
			cum.append(acc)
		by_mask[mask] = _table(source_id, coords, cum)
	_terrain_tables[tileset] = by_mask
	return by_mask


static func _table(source_id: int, coords: Array[Vector2i], cum: PackedInt64Array) -> Dictionary:
	var total := cum[-1] if not cum.is_empty() else 0
	var lookup := PackedInt32Array()
	if total <= _LOOKUP_MAX:
		var from := 0
		for n in cum.size():
			var run := PackedInt32Array()
			run.resize(cum[n] - from)
			run.fill(n)
			lookup.append_array(run)
			from = cum[n]
	return {"source_id": source_id, "coords": coords, "cum": cum, "total": total, "lookup": lookup}


## A tile's pick from a table: hashes (seed, tile, channel) to a value in [0, total) and
## binary-searches the cumulative weights. The table must not be empty.
static func pick(world_seed: int, wx: int, wy: int, channel: int, t: Dictionary) -> Vector2i:
	return pick_hashed(world_seed, tile_hash(wx, wy), channel, t)


## The hash of a tile's coordinates that every pick of the tile starts from.
static func tile_hash(wx: int, wy: int) -> int:
	return tile_hash_in_row(wx, row_hash(wy))


## tile_hash() in two halves, so a row's tiles share the second.
static func row_hash(wy: int) -> int:
	return WgHash.splitmix64(wy)


static func tile_hash_in_row(wx: int, hashed_row: int) -> int:
	return WgHash.splitmix64(WgHash.splitmix64(wx) ^ hashed_row)


## pick() from a tile_hash(), for callers picking several layers of one tile.
static func pick_hashed(world_seed: int, hashed_tile: int, channel: int, t: Dictionary) -> Vector2i:
	var coords: Array[Vector2i] = t.coords
	if coords.size() <= 1:
		return coords[0]
	return coords[index(WgHash.splitmix64(world_seed ^ WgHash.splitmix64(hashed_tile ^ channel)), t.total, t.lookup, t.cum)]


## The index of the tile a pick hash selects from a table's fields: its weight's slot in [0, total),
## looked up, or found by binary search over the cumulative weights.
static func index(pick_hash: int, total: int, lookup: PackedInt32Array, cum: PackedInt64Array) -> int:
	var r := (pick_hash & 0x7fffffffffffffff) % total
	if not lookup.is_empty():
		return lookup[r]
	var lo := 0
	var hi := cum.size() - 1
	while lo < hi:
		@warning_ignore("integer_division")
		var mid := (lo + hi) / 2
		if cum[mid] <= r:
			lo = mid + 1
		else:
			hi = mid
	return lo


## Corner bits only matter when both adjacent sides are set (the standard 47-blob rule): clearing
## the meaningless ones collapses the 256 raw masks onto the ones tilesets actually author.
static func canonical_mask(m: int) -> int:
	if (m & 0b0000_0101) != 0b0000_0101:
		m &= ~0b0000_0010   # NE needs N+E
	if (m & 0b0001_0100) != 0b0001_0100:
		m &= ~0b0000_1000   # SE needs E+S
	if (m & 0b0101_0000) != 0b0101_0000:
		m &= ~0b0010_0000   # SW needs S+W
	if (m & 0b0100_0001) != 0b0100_0001:
		m &= ~0b1000_0000   # NW needs W+N
	return m
