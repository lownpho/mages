class_name WorldInteriors
extends RefCounted
## Every Room's interior as one field of World tiles: which Room owns a tile, and its semantic class.
## Ownership (in square blocks) and interiors build on demand and stay in least-recently-used caches.
## Evicting either and building it again gives the same tiles, whatever order Rooms and tiles are
## asked for in.
##
## Queries such as class_at() build what they need at once. Streaming instead calls fill_owners()
## and steps building() interiors, which stop at a deadline and pick up where they left off.

## Semantic classes. VOID is outside every Room: past the World's edge, or where no Biome owns the
## macro cell.
const FLOOR := RoomInterior.FLOOR
const WALL := RoomInterior.WALL
const ROCK := RoomInterior.ROCK
const VOID := 3

## Owner blocks are this many tiles square.
const BLOCK := 16
## An opening that joins no tile of one Room to one of the other grows its radius up to this many
## times.
const OPENING_GROWTH := 6
## A deadline that lets a step() finish in one call.
const NO_DEADLINE := 1 << 62

const _ROCK_SCALE := 6.0
const _SPINE_SCALE := 5.0


class OwnerBlock:
	var coord := Vector2i.ZERO
	var owners := PackedInt32Array()
	## Rows filled so far.
	var rows := 0


var graph: WorldGraph
var block_capacity := 1024
var interior_capacity := 160
## Noise keyed by the World seed alone and sampled by tile.
var rock_noise: FastNoiseLite
var spine_noise: FastNoiseLite

## Blocks are evicted oldest first, in the order _block_order holds from _block_head.
var _blocks: Dictionary[Vector2i, OwnerBlock] = {}
var _block_order: Array[Vector2i] = []
var _block_head := 0
## Interiors, least recently used first.
var _interiors: Dictionary[int, RoomInterior] = {}
var _building: Dictionary[int, RoomInterior] = {}
## Passage key -> {tile -> owner index} of its opening.
var _openings: Dictionary[String, Dictionary] = {}


func _init(world_graph: WorldGraph) -> void:
	graph = world_graph
	rock_noise = _noise(graph.plan.seed_for(WgHash.NS_ROCKS, "rocks"), _ROCK_SCALE, 2)
	spine_noise = _noise(graph.plan.seed_for(WgHash.NS_SPINE, "width"), _SPINE_SCALE, 1)


## The Room owning a tile, or null.
func owner_at(tile: Vector2i) -> GeneratedRoom:
	var index := owner_index(tile)
	return graph.room_list[index] if index >= 0 else null


## The owner's index in the graph's room list, or -1: from a filled block, else worked out directly.
func owner_index(tile: Vector2i) -> int:
	var coord := Vector2i(floori(float(tile.x) / BLOCK), floori(float(tile.y) / BLOCK))
	var block: OwnerBlock = _blocks.get(coord)
	var local := tile - coord * BLOCK
	if block == null or local.y >= block.rows:
		return graph.owner_index_at(tile)
	return block.owners[local.y * BLOCK + local.x]


## The cached block holding a tile, when its row is filled; null otherwise.
func block_at(tile: Vector2i) -> OwnerBlock:
	var coord := Vector2i(floori(float(tile.x) / BLOCK), floori(float(tile.y) / BLOCK))
	var block: OwnerBlock = _blocks.get(coord)
	if block == null or tile.y - coord.y * BLOCK >= block.rows:
		return null
	return block


## FLOOR, WALL, ROCK or VOID, building the owner's interior when it isn't cached.
func class_at(tile: Vector2i) -> int:
	var index := owner_index(tile)
	if index < 0:
		return VOID
	return interior(graph.room_list[index]).class_at(tile)


## A Room's finished interior, built at once when it isn't cached.
func interior(room: GeneratedRoom) -> RoomInterior:
	var cached: RoomInterior = _interiors.get(room.index)
	if cached != null:
		_interiors.erase(room.index)
		_interiors[room.index] = cached
		return cached
	var build := building(room)
	build.step(NO_DEADLINE)
	return finish(build)


## A Room's interior, finished or not: step() it, then hand it to finish().
func building(room: GeneratedRoom) -> RoomInterior:
	var cached: RoomInterior = _interiors.get(room.index)
	if cached != null:
		return cached
	var build: RoomInterior = _building.get(room.index)
	if build == null:
		build = RoomInterior.new(self, room)
		_building[room.index] = build
	return build


## Caches a finished interior, evicting the least recently used past capacity.
func finish(build: RoomInterior) -> RoomInterior:
	var index := build.room.index
	_building.erase(index)
	if _interiors.has(index):
		return _interiors[index]
	_interiors[index] = build
	while _interiors.size() > interior_capacity:
		_interiors.erase(_interiors.keys()[0])
	return build


## Fills the owner blocks covering a rect until the deadline; true once every one is full.
func fill_owners(rect: Rect2i, deadline: int) -> bool:
	var first := Vector2i(floori(float(rect.position.x) / BLOCK), floori(float(rect.position.y) / BLOCK))
	var last := Vector2i(floori(float(rect.end.x - 1) / BLOCK), floori(float(rect.end.y - 1) / BLOCK))
	for by in range(first.y, last.y + 1):
		for bx in range(first.x, last.x + 1):
			var coord := Vector2i(bx, by)
			var block: OwnerBlock = _blocks.get(coord)
			if block == null:
				block = OwnerBlock.new()
				block.coord = coord
				block.owners.resize(BLOCK * BLOCK)
				_blocks[coord] = block
				_block_order.append(coord)
				while _blocks.size() > block_capacity:
					_blocks.erase(_block_order[_block_head])
					_block_head += 1
				if _block_head > block_capacity:
					_block_order = _block_order.slice(_block_head)
					_block_head = 0
			if block.rows < BLOCK and not _fill(block, deadline):
				return false
	return true


## Drops every cached block, interior and opening.
func clear_caches() -> void:
	_blocks.clear()
	_block_order.clear()
	_block_head = 0
	_interiors.clear()
	_building.clear()
	_openings.clear()


## Tiles a Passage opens through the walls of its two Rooms: those of either Room within a disc
## about its spot whose four neighbours both Rooms own, so an opening never touches a third Room.
## The disc grows until the opening joins the two Rooms.
func opening(passage: RoomPassage) -> Dictionary:
	if _openings.has(passage.key):
		return _openings[passage.key]
	var a := graph.rooms[passage.a].index
	var b := graph.rooms[passage.b].index
	var centre := Vector2(passage.spot) + Vector2(0.5, 0.5)
	var radius := _opening_radius(passage)
	var bounds := opening_bounds(passage)
	var width := bounds.size.x
	var owners := PackedInt32Array()
	owners.resize(bounds.get_area())
	for y in bounds.size.y:
		var base := y * width - bounds.position.x
		var x := bounds.position.x
		while x < bounds.end.x:
			var run := mini(BLOCK - posmod(x, BLOCK), bounds.end.x - x)
			var block := block_at(Vector2i(x, bounds.position.y + y))
			if block == null:
				for k in range(x, x + run):
					owners[base + k] = graph.owner_index_at(Vector2i(k, bounds.position.y + y))
			else:
				var source := block.owners
				var from := posmod(bounds.position.y + y, BLOCK) * BLOCK + posmod(x, BLOCK) - x
				for k in range(x, x + run):
					owners[base + k] = source[from + k]
			x += run
	var offsets := PackedInt32Array([0, -1, 1, -width, width])
	var tiles: Dictionary[Vector2i, int] = {}
	for _grow in OPENING_GROWTH + 1:
		tiles = {}
		var reach := ceili(radius)
		for dy in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var tile := passage.spot + Vector2i(dx, dy)
				if (Vector2(tile) + Vector2(0.5, 0.5)).distance_squared_to(centre) > radius * radius:
					continue
				var at := (tile.y - bounds.position.y) * width + tile.x - bounds.position.x
				var inside := true
				for k in 5:
					var owner := owners[at + offsets[k]]
					if owner != a and owner != b:
						inside = false
						break
				if inside:
					tiles[tile] = owners[at]
		if _joins(tiles):
			break
		radius += 1.0
	_openings[passage.key] = tiles
	return tiles


## Holds every tile opening() reads for a Passage.
static func opening_bounds(passage: RoomPassage) -> Rect2i:
	var reach := ceili(_opening_radius(passage) + OPENING_GROWTH) + 1
	return Rect2i(passage.spot - Vector2i.ONE * reach, Vector2i.ONE * (2 * reach + 1))


static func _opening_radius(passage: RoomPassage) -> float:
	return maxf(passage.width * 0.5, 1.0) + 0.5


static func _joins(tiles: Dictionary[Vector2i, int]) -> bool:
	for tile in tiles:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			var other: int = tiles.get(tile + direction, tiles[tile])
			if other != tiles[tile]:
				return true
	return false


func _fill(block: OwnerBlock, deadline: int) -> bool:
	var origin := block.coord * BLOCK
	while block.rows < BLOCK:
		var base := block.rows * BLOCK
		var y := origin.y + block.rows
		for x in BLOCK:
			block.owners[base + x] = graph.owner_index_at(Vector2i(origin.x + x, y))
		block.rows += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return block.rows >= BLOCK


static func _noise(unit_seed: int, scale: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE_CUBIC
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	noise.fractal_octaves = octaves
	noise.frequency = 1.0 / scale
	noise.seed = unit_seed & 0x7fffffff
	return noise
