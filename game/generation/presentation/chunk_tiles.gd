class_name ChunkTiles
extends RefCounted
## One streaming chunk's tiles, worked out as plain cell arrays before any reaches a TileMapLayer.
## step() gathers the chunk's owners, the interiors of every Room owning a tile of it (and of the ring
## around it when an autotiled layer's masks read that ring), the class of each tile and then every
## layer's picks,
## stopping at a deadline and resuming where it left off. apply_layer() then sets one layer's cells
## on a WorldChunk, and builds that layer at once when the chunk is in the tree, so a streamer can
## spread a chunk's layers over frames.
##
## Every tile lays floor beneath it, since wall and tree art is transparent around its trunk. Walls
## and void autotile against walls and void (and rocks, where rocks use the wall art); floor
## autotiles against floor.

enum _Phase { OWNERS, COPY, ROOMS, INTERIORS, CLASSES, PICKS, DONE }

const _FLOOR := WorldInteriors.FLOOR
const _WALL := WorldInteriors.WALL
const _ROCK := WorldInteriors.ROCK
const _VOID := WorldInteriors.VOID


## One TileMapLayer the chunk fills, with its tileset's pick table.
class CellLayer:
	var index := 0
	var biome := &""
	## &"floor", &"wall", &"rock" or &"decoration".
	var kind := &""
	## A Zone's own decoration layer's key; &"" for the Biome's layers.
	var zone_key := &""
	var presentation: BiomePresentation
	var tileset: TileSet
	var source_id := -1
	var autotile := false
	var terrain: Dictionary
	var coords: Array[Vector2i] = []
	var cum := PackedInt64Array()
	var lookup := PackedInt32Array()
	var total := 0


var coord := Vector2i.ZERO
## The chunk's tiles; at most 256 on a side, as cells pack their place into a byte each.
var rect := Rect2i()
## The layers with cells, in the order they were first needed.
var layers: Array[CellLayer] = []

var _presentation: WorldPresentation
var _interiors: WorldInteriors
var _phase := _Phase.OWNERS
var _cursor := 0
## Owners and classes over rect grown by one tile, row by row.
var _owners := PackedInt32Array()
var _classes := PackedByteArray()
var _outer := Rect2i()
var _rooms: Dictionary[int, RoomInterior] = {}
## Whether any tile's art autotiles, so masks read the ring's classes.
var _needs_ring := false
var _pending: Array[RoomInterior] = []
var _layer_by_key: Dictionary[String, CellLayer] = {}
## Art -> [floor, wall, rock, decoration] layers, each null when its tileset is.
var _layers_by_art: Dictionary = {}
## Two ints per cell: layer index << 16 | local y << 8 | local x, then atlas y << 16 | atlas x.
## Grouped by layer once picked: layer n's cells run from _layer_starts[n] to _layer_starts[n + 1].
var _cells := PackedInt32Array()
var _cell_count := 0
var _layer_starts := PackedInt32Array()
var _apply_layer := 0


func _init(presentation: WorldPresentation, chunk_coord: Vector2i, chunk_tiles: int) -> void:
	_presentation = presentation
	_interiors = presentation.interiors
	coord = chunk_coord
	rect = Rect2i(chunk_coord * chunk_tiles, Vector2i.ONE * chunk_tiles)
	_outer = rect.grow(1)


func is_done() -> bool:
	return _phase == _Phase.DONE


## Works until done or past the deadline, in usec; true once every layer's cells are known.
func step(deadline: int) -> bool:
	while _phase != _Phase.DONE:
		var finished := false
		match _phase:
			_Phase.OWNERS:
				finished = _interiors.fill_owners(_outer, deadline)
			_Phase.COPY:
				finished = _copy_owners(deadline)
			_Phase.ROOMS:
				finished = _gather_rooms()
			_Phase.INTERIORS:
				finished = _build_interiors(deadline)
			_Phase.CLASSES:
				finished = _find_classes(deadline)
			_Phase.PICKS:
				finished = _pick(deadline)
		if finished:
			_phase = (_phase + 1) as _Phase
			_cursor = 0
		if Time.get_ticks_usec() >= deadline:
			break
	if _phase == _Phase.DONE and not _rooms.is_empty():
		_rooms.clear()
		_owners = PackedInt32Array()
		_classes = PackedByteArray()
		_layers_by_art.clear()
	return _phase == _Phase.DONE


func is_applied() -> bool:
	return _phase == _Phase.DONE and _apply_layer >= layers.size()


## Sets the next layer's cells on the chunk, building the layer at once when the chunk is in the
## tree; true once every layer is set. Call once step() is done.
func apply_layer(chunk: WorldChunk) -> bool:
	if _apply_layer < layers.size():
		var layer := layers[_apply_layer]
		var target := _target_layer(chunk, layer)
		for n in range(_layer_starts[_apply_layer], _layer_starts[_apply_layer + 1], 2):
			var place := _cells[n]
			var atlas := _cells[n + 1]
			target.set_cell(Vector2i(place & 0xFF, (place >> 8) & 0xFF), layer.source_id, Vector2i(atlas & 0xFFFF, atlas >> 16))
		if chunk.is_inside_tree():
			target.update_internals()
		_apply_layer += 1
	return _apply_layer >= layers.size()


## Copies owners out of the blocks a run at a time; a block evicted since is worked out again.
func _copy_owners(deadline: int) -> bool:
	var owners := _owners
	_owners = PackedInt32Array()
	if owners.is_empty():
		owners.resize(_outer.size.x * _outer.size.y)
	var block_size := WorldInteriors.BLOCK
	while _cursor < _outer.size.y:
		var y := _outer.position.y + _cursor
		var base := _cursor * _outer.size.x - _outer.position.x
		var x := _outer.position.x
		while x < _outer.end.x:
			var local_x := posmod(x, block_size)
			var run := mini(block_size - local_x, _outer.end.x - x)
			var block := _interiors.block_at(Vector2i(x, y))
			if block == null:
				for k in range(x, x + run):
					owners[base + k] = _interiors.graph.owner_index_at(Vector2i(k, y))
			else:
				var source := block.owners
				var from := posmod(y, block_size) * block_size + local_x - x
				for k in range(x, x + run):
					owners[base + k] = source[from + k]
			x += run
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	_owners = owners
	return _cursor >= _outer.size.y


func _gather_rooms() -> bool:
	var seen: Dictionary[int, bool] = {}
	for y in range(1, _outer.size.y - 1):
		for x in range(1, _outer.size.x - 1):
			var owner := _owners[y * _outer.size.x + x]
			if not seen.has(owner):
				seen[owner] = true
				var presentation := _presentation.art(owner, _outer.position + Vector2i(x, y)).presentation
				_needs_ring = _needs_ring or presentation.floor_autotile or presentation.wall_autotile
	for index in _owners.size():
		var owner := _owners[index]
		if not _needs_ring and not _inner(index):
			continue
		if owner >= 0 and not _rooms.has(owner):
			var build := _interiors.building(_interiors.graph.room_list[owner])
			_rooms[owner] = build
			if not build.is_done():
				_pending.append(build)
	return true


func _build_interiors(deadline: int) -> bool:
	while not _pending.is_empty():
		var build := _pending[-1]
		if not build.step(deadline):
			return false
		_rooms[build.room.index] = _interiors.finish(build)
		_pending.pop_back()
	return true


func _find_classes(deadline: int) -> bool:
	if _classes.is_empty():
		_classes.resize(_outer.size.x * _outer.size.y)
	while _cursor < _outer.size.y:
		var base := _cursor * _outer.size.x
		var y := _outer.position.y + _cursor
		for x in _outer.size.x:
			if not _needs_ring and not _inner(base + x):
				continue
			var owner := _owners[base + x]
			_classes[base + x] = _VOID if owner < 0 else _rooms[owner].class_at(Vector2i(_outer.position.x + x, y))
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return _cursor >= _outer.size.y


func _inner(index: int) -> bool:
	var x := index % _outer.size.x
	return x > 0 and x < _outer.size.x - 1 and index >= _outer.size.x and index < _owners.size() - _outer.size.x


func _pick(deadline: int) -> bool:
	var world_seed := _presentation.world_seed
	var stride := _outer.size.x
	var offsets := PackedInt32Array()
	for offset in TilePicks.NEIGHBOURS:
		offsets.append(offset.y * stride + offset.x)
	# TilePicks.tile_hash() in parts: each column's half once.
	var columns := PackedInt64Array()
	for lx in rect.size.x:
		columns.append(WorldHash.splitmix64(rect.position.x + lx))
	var cells := _cells
	_cells = PackedInt32Array()
	if cells.is_empty():
		cells.resize(rect.get_area() * 4)
	var count := _cell_count
	var last_owner := -2
	var art: WorldPresentation.Art
	var floor_layer: CellLayer
	var wall_layer: CellLayer
	var rock_layer: CellLayer
	var decoration_layer: CellLayer
	# The floor's scatter pick, unpacked: this loop runs once per tile.
	var floor_code := 0
	var floor_coords: Array[Vector2i] = []
	var floor_lookup := PackedInt32Array()
	var floor_total := 1
	var decoration_threshold := 0
	while _cursor < rect.size.y:
		var ly := _cursor
		var wy := rect.position.y + ly
		var hashed_row := TilePicks.row_hash(wy)
		for lx in rect.size.x:
			var at := (ly + 1) * stride + lx + 1
			var owner := _owners[at]
			if owner != last_owner or owner < 0:
				last_owner = owner
				art = _presentation.art(owner, Vector2i(rect.position.x + lx, wy))
				var art_layers := _art_layers(art)
				floor_layer = art_layers[0]
				wall_layer = art_layers[1]
				rock_layer = art_layers[2]
				decoration_layer = art_layers[3]
				floor_code = floor_layer.index << 16 if floor_layer != null else -1
				if floor_layer != null and not floor_layer.autotile and not floor_layer.lookup.is_empty():
					floor_coords = floor_layer.coords
					floor_lookup = floor_layer.lookup
					floor_total = floor_layer.total
				else:
					floor_lookup = PackedInt32Array()
				decoration_threshold = art.decoration_threshold if decoration_layer != null else 0
			var hashed := WorldHash.splitmix64(columns[lx] ^ hashed_row)
			var tile_class := _classes[at]
			var place := (ly << 8) | lx
			if floor_code >= 0:
				var floor_atlas: Vector2i
				if not floor_lookup.is_empty():
					floor_atlas = floor_coords[floor_lookup[(WorldHash.splitmix64(world_seed ^ WorldHash.splitmix64(hashed ^ TilePicks.CH_FLOOR)) & 0x7fffffffffffffff) % floor_total]]
				else:
					floor_atlas = _pick_from(floor_layer, world_seed, hashed, TilePicks.CH_FLOOR, _mask(at, offsets, false, false) if floor_layer.autotile else 0)
				cells[count] = floor_code | place
				cells[count + 1] = (floor_atlas.y << 16) | floor_atlas.x
				count += 2
			var layer: CellLayer = null
			var atlas := Vector2i.ZERO
			if tile_class == _FLOOR:
				if decoration_threshold > 0 and WorldPresentation.decorates(art, hashed):
					layer = decoration_layer
					atlas = _pick_from(layer, art.decoration_seed, hashed, TilePicks.CH_DECORATION, 0)
			elif tile_class == _ROCK and not art.rocks_as_walls:
				layer = rock_layer
				if layer != null:
					atlas = _pick_from(layer, world_seed, hashed, TilePicks.CH_ROCK, 0)
			else:
				layer = wall_layer
				if layer != null:
					atlas = _pick_from(layer, world_seed, hashed, TilePicks.CH_WALL, _mask(at, offsets, true, art.rocks_as_walls) if layer.autotile else 0)
			if layer != null:
				cells[count] = (layer.index << 16) | place
				cells[count + 1] = (atlas.y << 16) | atlas.x
				count += 2
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	_cells = cells
	_cell_count = count
	if _cursor < rect.size.y:
		return false
	_group_cells()
	return true


## Reorders the picked cells so each layer's lie together.
func _group_cells() -> void:
	_layer_starts.resize(layers.size() + 1)
	_layer_starts.fill(0)
	for n in range(0, _cell_count, 2):
		_layer_starts[(_cells[n] >> 16) + 1] += 2
	for n in layers.size():
		_layer_starts[n + 1] += _layer_starts[n]
	var next := _layer_starts.duplicate()
	var grouped := PackedInt32Array()
	grouped.resize(_cell_count)
	for n in range(0, _cell_count, 2):
		var layer := _cells[n] >> 16
		grouped[next[layer]] = _cells[n]
		grouped[next[layer] + 1] = _cells[n + 1]
		next[layer] += 2
	_cells = grouped


static func _pick_from(layer: CellLayer, pick_seed: int, hashed: int, channel: int, mask: int) -> Vector2i:
	if layer.autotile:
		var table: Dictionary = layer.terrain.get(mask, {})
		if not table.is_empty():
			return TilePicks.pick_hashed(pick_seed, hashed, channel, table)
	if layer.coords.size() <= 1:
		return layer.coords[0]
	return layer.coords[TilePicks.index(WorldHash.splitmix64(pick_seed ^ WorldHash.splitmix64(hashed ^ channel)), layer.total, layer.lookup, layer.cum)]


## The canonical 8-neighbour mask of a tile of the chunk: walls count walls and void, and rocks when
## they draw as walls; floor counts floor.
func _mask(at: int, offsets: PackedInt32Array, walls: bool, rocks_as_walls: bool) -> int:
	var mask := 0
	for bit in 8:
		var neighbour := _classes[at + offsets[bit]]
		var same := neighbour == _FLOOR
		if walls:
			same = neighbour == _WALL or neighbour == _VOID or (rocks_as_walls and neighbour == _ROCK)
		if same:
			mask |= 1 << bit
	return TilePicks.canonical_mask(mask)


func _art_layers(art: WorldPresentation.Art) -> Array:
	if not _layers_by_art.has(art):
		var presentation := art.presentation
		_layers_by_art[art] = [
			_layer(art.biome, &"floor", &"", presentation, presentation.floor_tileset, presentation.floor_autotile),
			_layer(art.biome, &"wall", &"", presentation, presentation.wall_tileset, presentation.wall_autotile),
			_layer(art.biome, &"rock", &"", presentation, presentation.rock_tileset, false),
			_layer(art.biome, &"decoration", art.zone_key if art.zone_decoration else &"", presentation, art.decoration_tileset, false),
		]
	return _layers_by_art[art]


## The chunk's layer for a Biome's kind of art (or a Zone's decoration), created on first use; null
## when the tileset has no tiles.
func _layer(biome: StringName, kind: StringName, zone_key: StringName, presentation: BiomePresentation, tileset: TileSet, autotile: bool) -> CellLayer:
	if tileset == null or TilePicks.table(tileset).total <= 0:
		return null
	var key := "%s|%s|%s" % [biome, zone_key, kind]
	if not _layer_by_key.has(key):
		var table := TilePicks.table(tileset)
		var layer := CellLayer.new()
		layer.index = layers.size()
		layer.biome = biome
		layer.kind = kind
		layer.zone_key = zone_key
		layer.presentation = presentation
		layer.tileset = tileset
		layer.source_id = table.source_id
		layer.coords = table.coords
		layer.cum = table.cum
		layer.lookup = table.lookup
		layer.total = table.total
		layer.terrain = TilePicks.terrain_table(tileset) if autotile else {}
		layer.autotile = autotile
		_layer_by_key[key] = layer
		layers.append(layer)
	return _layer_by_key[key]


static func _target_layer(chunk: WorldChunk, layer: CellLayer) -> TileMapLayer:
	if layer.zone_key != &"":
		return chunk.decoration_layer(layer.zone_key, layer.tileset)
	return chunk.layer_for(layer.biome, layer.presentation, layer.kind)
