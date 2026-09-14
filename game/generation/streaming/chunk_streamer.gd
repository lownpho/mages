class_name ChunkStreamer
extends Node2D
## Streams the finite World's tiles around a target: each frame it wants the chunks covering the camera's view grown by prefetch_tiles, unloads chunks
## past a larger hysteresis margin, and skips chunks beyond the World's finite bounds and the ring
## of wall-art border chunks around them. The prefetch is in tiles rather than whole chunks so the
## lead ahead of a walking player is the same on every side without streaming more than it needs.
##
## Missing chunks wait in one queue, nearest the target first. Every frame, on every platform and on
## the main thread, the queue's head works through its ChunkTiles (owners, Room interiors, classes,
## picks) until the frame's budget is spent. Its WgChunk then enters the tree empty and receives one
## layer at a time, each built by the engine at once; a layer waits for the next frame when its build
## would overrun this one, judged by the slowest recent layer. At most _MAX_LOADS_PER_FRAME chunks
## finish per frame; the budget left then goes on the next chunk's picks. Chunks are small, so no
## single layer build approaches the budget. Budget an empty queue leaves over builds the interiors
## of Rooms ahead of the target, nearest first, so a chunk rarely waits on a whole Room. Unloaded
## chunks are freed inside the budget too,
## one at a time, before anything else. Interiors and owners stay cached in WorldInteriors, so an
## unloaded chunk streams back in with the same tiles.

signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)

## Streaming work per frame, in usec, stopping short of the 2 ms web budget by the most one step of
## work can run past its deadline. Desktop gets a third, matching the bench's headless threshold, as
## desktop runs the same work about three times faster.
const WEB_BUDGET_USEC := 1350
const DESKTOP_BUDGET_USEC := 450
const _MAX_LOADS_PER_FRAME := 1   ## smooth bursts; remaining chunks enter the tree next frame
const _UNLOAD_MARGIN := 2         ## chunks; unload radius = load radius + this (hysteresis)
## Chunks of wall art streamed just outside the World so its edge never shows void.
const _BORDER_CHUNKS := 4
## Building ahead is optional, so it stops starting interior steps this long before the frame's
## deadline, the most one such step takes, and never runs past it.
const _AHEAD_MARGIN_USEC := 250

@export var chunk_tiles := 8
## Tiles streamed beyond each side of the camera's view: at walking speed (10 tiles a second) about
## a second of lead.
@export var prefetch_tiles := 12
## Rooms reaching within this many tiles of the camera's view get their interiors built ahead.
@export var interior_lookahead_tiles := 48

## What streaming follows. Assigned after build_world().
var target: Node2D = null
var graph: WorldGraph = null
var interiors: WorldInteriors = null
var presentation: WorldPresentation = null
var frame_budget_usec := WEB_BUDGET_USEC if OS.has_feature("web") else DESKTOP_BUDGET_USEC

## Pause or resume the per-frame loop; loaded chunks stay.
var streaming := true:
	set(on):
		streaming = on
		set_process(on)

## Usec of streaming work in the last frame, including cells entering the tree.
var last_work_usec := 0
## That frame's work split into replanning, freeing unloaded chunks, the queue and building ahead.
var last_work_split := PackedInt32Array([0, 0, 0, 0])
## Observable selective-rebuild boundary: chunks dropped by the most recent rebuild.
var invalidated_chunks_last_rebuild: Array[Vector2i] = []

var _chunks: Dictionary[Vector2i, WgChunk] = {}
## Chunk coord -> [ChunkTiles, WgChunk], for chunks still being built.
var _jobs: Dictionary[Vector2i, Array] = {}
var _queue: Array[Vector2i] = []
var _world_chunks := Vector2i.ZERO
## The first and last chunk the target wants.
var _first := Vector2i(1 << 30, 1 << 30)
var _last := Vector2i(1 << 30, 1 << 30)
## A decaying maximum of what setting and building one layer took, in usec.
var _layer_usec := 0
## Unloaded chunks still in the tree, freed a layer at a time, and what freeing one layer took at
## most lately.
var _retired: Array[WgChunk] = []
var _retire_usec := 0
## A layer that waited for this frame, which goes before any other work.
var _layer_waiting := false
## Rooms whose interiors are built ahead, nearest the target first, and the next to look at.
var _ahead: Array[GeneratedRoom] = []
var _ahead_next := 0
## Rooms request_interiors() asked for, built after the lookahead.
var _wanted: Array[GeneratedRoom] = []
## Each Room's unwarped cell bounds, grown by the most the warp moves a tile, by room index.
var _room_bounds: Array[Rect2] = []


## Streams a new World, dropping every chunk, job and cache of the last.
func build_world(world_graph: WorldGraph) -> void:
	_clear_chunks()
	invalidated_chunks_last_rebuild.clear()
	_install_world(world_graph)


## Installs a rebuilt graph while retaining loaded chunks wholly outside changed Biomes. A World-plan
## change invalidates every tile because macro-cell placement may have moved. Pending jobs always
## go: they hold builders for the previous graph and have not produced an observable chunk yet.
func rebuild_world(world_graph: WorldGraph, invalidated_biomes: Dictionary[StringName, bool],
		plan_changed := false) -> void:
	invalidated_chunks_last_rebuild.clear()
	for coord in _jobs.keys():
		_drop(_jobs[coord][1])
	_jobs.clear()
	_queue.clear()
	for coord in _chunks.keys():
		if plan_changed or _chunk_touches_biomes(coord, graph, world_graph, invalidated_biomes):
			chunk_unloaded.emit(coord)
			invalidated_chunks_last_rebuild.append(coord)
			_retired.append(_chunks[coord])
			_chunks.erase(coord)
	_install_world(world_graph)


func _install_world(world_graph: WorldGraph) -> void:
	graph = world_graph
	graph.prepare_bins()
	interiors = WorldInteriors.new(graph)
	_wanted.clear()
	_room_bounds.clear()
	for room in graph.room_list:
		var low := Vector2(INF, INF)
		var high := -low
		for point in room.polygon:
			low = low.min(point)
			high = high.max(point)
		var bounds := Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()) + Vector2i.ONE)
		_room_bounds.append(Rect2(bounds.grow(ceili(graph.warp_bound(bounds)))))
	presentation = WorldPresentation.new(interiors)
	var tiles := graph.plan.size * WorldPlan.CELL
	_world_chunks = Vector2i(ceili(float(tiles.x) / chunk_tiles), ceili(float(tiles.y) / chunk_tiles))
	_first = Vector2i(1 << 30, 1 << 30)


func _chunk_touches_biomes(coord: Vector2i, old_graph: WorldGraph, new_graph: WorldGraph,
		biomes: Dictionary[StringName, bool]) -> bool:
	# Include the one-tile autotile ring. Looking through both graphs catches either side of a
	# border that moved when border_warp changed, while chunks wholly owned by other Biomes survive.
	var tiles := Rect2i(coord * chunk_tiles, Vector2i.ONE * chunk_tiles).grow(1)
	for y in range(tiles.position.y, tiles.end.y):
		for x in range(tiles.position.x, tiles.end.x):
			var tile := Vector2i(x, y)
			var old_room := old_graph.owner_at(tile)
			var new_room := new_graph.owner_at(tile)
			if (old_room != null and biomes.has(old_room.plan.biome)) or \
					(new_room != null and biomes.has(new_room.plan.biome)):
				return true
	return false


func loaded_chunks() -> int:
	return _chunks.size()


func queued_chunks() -> int:
	return _queue.size()


func is_chunk_loaded(coord: Vector2i) -> bool:
	return _chunks.has(coord)


func loaded_chunk_coords() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(_chunks.keys())
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func chunk_of(world_position: Vector2) -> Vector2i:
	var chunk_px := float(chunk_tiles * GameConstants.PX_PER_TILE)
	return Vector2i(floori(world_position.x / chunk_px), floori(world_position.y / chunk_px))


## The spawn Room's centre, which its interior keeps clear, in world pixels.
func spawn_position() -> Vector2:
	return (Vector2(graph.tile_of(graph.rooms[graph.plan.spawn.key].seed)) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE


## Builds one chunk at once, outside the tree: tests compare these.
func assemble_chunk(coord: Vector2i) -> WgChunk:
	var chunk := _new_chunk(coord)
	var tiles := presentation.chunk(coord, chunk_tiles)
	tiles.step(WorldInteriors.NO_DEADLINE)
	while not tiles.apply_layer(chunk):
		pass
	return chunk


## Loads every chunk the target needs now, ignoring the frame budget: for a start or a teleport
## behind a loading frame.
func prepare() -> void:
	_update_streaming(false)


## Drops cached owners and interiors; loaded chunks stay.
func clear_caches() -> void:
	interiors.clear_caches()


func _process(_delta: float) -> void:
	if streaming and graph != null and target != null:
		_update_streaming(true)


func _update_streaming(budgeted: bool) -> void:
	var started := Time.get_ticks_usec()
	var deadline := started + frame_budget_usec if budgeted else WorldInteriors.NO_DEADLINE
	var half := Vector2.ONE * prefetch_tiles * GameConstants.PX_PER_TILE
	var camera := get_viewport().get_camera_2d() if is_inside_tree() else null
	if camera != null and camera.zoom.x > 0.0 and camera.zoom.y > 0.0:
		half += get_viewport_rect().size * 0.5 / camera.zoom
	elif is_inside_tree():
		# No camera, as behind the title: the view is the viewport at 1:1 around the target.
		half += get_viewport_rect().size * 0.5
	var first := chunk_of(target.global_position - half)
	var last := chunk_of(target.global_position + half)
	var calm := true
	if first != _first or last != _last:
		_first = first
		_last = last
		_replan()
		calm = false
	var replanned := Time.get_ticks_usec()
	# One layer always goes in a frame that didn't replan, so an overestimate can't stall freeing.
	while not _retired.is_empty() and (not budgeted or calm or Time.get_ticks_usec() + _retire_usec <= deadline):
		calm = false
		var freeing := Time.get_ticks_usec()
		var chunk: WgChunk = _retired[-1]
		if chunk.get_child_count() > 0:
			chunk.get_child(chunk.get_child_count() - 1).free()
		else:
			_retired.pop_back().free()
		_retire_usec = maxi(_retire_usec - (_retire_usec >> 4), Time.get_ticks_usec() - freeing)
	var retired := Time.get_ticks_usec()
	var loads := 0
	var waited := _layer_waiting
	_layer_waiting = false
	var fresh := true
	var index := 0
	while index < _queue.size() and Time.get_ticks_usec() < deadline:
		var coord := _queue[index]
		if not _jobs.has(coord):
			_jobs[coord] = [presentation.chunk(coord, chunk_tiles), _new_chunk(coord)]
		var job: Array = _jobs[coord]
		var tiles: ChunkTiles = job[0]
		var chunk: WgChunk = job[1]
		if not tiles.is_done():
			fresh = false
			if not tiles.step(deadline):
				break
		if budgeted and loads >= _MAX_LOADS_PER_FRAME:
			# Picks for the chunks after, but no more chunks finish this frame.
			index += 1
			continue
		if not chunk.is_inside_tree():
			add_child(chunk)
		while not tiles.is_applied():
			var setting := Time.get_ticks_usec()
			if budgeted and not (waited and fresh) and setting + _layer_usec > deadline:
				_layer_waiting = true
				break
			fresh = false
			tiles.apply_layer(chunk)
			_layer_usec = maxi(_layer_usec - (_layer_usec >> 4), Time.get_ticks_usec() - setting)
		if not tiles.is_applied():
			break
		_jobs.erase(coord)
		_queue.remove_at(index)
		_chunks[coord] = chunk
		chunk_loaded.emit(coord)
		loads += 1
	var queued := Time.get_ticks_usec()
	if _queue.is_empty():
		_build_ahead(deadline - _AHEAD_MARGIN_USEC if budgeted else deadline)
	last_work_usec = Time.get_ticks_usec() - started
	last_work_split = PackedInt32Array([replanned - started, retired - replanned, queued - retired, started + last_work_usec - queued])


func _build_ahead(deadline: int) -> void:
	while _ahead_next < _ahead.size() and Time.get_ticks_usec() < deadline:
		var build := interiors.building(_ahead[_ahead_next])
		if not build.is_done():
			if not build.step(deadline):
				return
			interiors.finish(build)
		_ahead_next += 1
	while not _wanted.is_empty() and Time.get_ticks_usec() < deadline:
		var wanted := interiors.building(_wanted[0])
		if not wanted.is_done() and not wanted.step(deadline):
			return
		interiors.finish(wanted)
		_wanted.pop_front()


## Queues Rooms whose interiors something off the streaming path wants, such as the Map, for the
## budget the queue and the lookahead leave over. Earlier requests go first.
func request_interiors(rooms: Array[GeneratedRoom]) -> void:
	for room in rooms:
		if not _wanted.has(room):
			_wanted.append(room)


## The Rooms whose unwarped cells, grown by the warp, reach the lookahead around the target.
func _plan_ahead() -> void:
	_ahead.clear()
	_ahead_next = 0
	var chunk_px := float(chunk_tiles * GameConstants.PX_PER_TILE)
	var reach := Rect2(Vector2(_first) * chunk_px, Vector2(_last - _first + Vector2i.ONE) * chunk_px).grow(
			(interior_lookahead_tiles - prefetch_tiles) * GameConstants.PX_PER_TILE)
	var area := Rect2(reach.position / GameConstants.PX_PER_TILE, reach.size / GameConstants.PX_PER_TILE)
	var first_cell := Vector2i((area.position / WorldPlan.CELL).floor()) - Vector2i.ONE
	var last_cell := Vector2i((area.end / WorldPlan.CELL).floor()) + Vector2i.ONE
	var centre := target.global_position / GameConstants.PX_PER_TILE
	for y in range(first_cell.y, last_cell.y + 1):
		for x in range(first_cell.x, last_cell.x + 1):
			var cell: MacroCellGraph = graph.cells.get(Vector2i(x, y))
			if cell == null:
				continue
			for room in cell.rooms:
				if _room_bounds[room.index].intersects(area):
					_ahead.append(room)
	# Nearest first, by a native sort of squared distance above each Room's place in the list.
	var keys := PackedInt64Array()
	for n in _ahead.size():
		keys.append((int(_ahead[n].seed.distance_squared_to(centre)) << 20) | n)
	keys.sort()
	var nearest: Array[GeneratedRoom] = []
	for key in keys:
		nearest.append(_ahead[key & 0xFFFFF])
	_ahead = nearest


## Rebuilds the queue for the wanted chunks, nearest the target first, and unloads what fell past the
## hysteresis margin.
func _replan() -> void:
	var keep := Rect2i(_first, _last - _first + Vector2i.ONE).grow(_UNLOAD_MARGIN)
	for coord in _chunks.keys():
		if not keep.has_point(coord):
			chunk_unloaded.emit(coord)
			_retired.append(_chunks[coord])
			_chunks.erase(coord)
	# Nearest the target first, earlier rows then columns on ties: the distance in 1/256ths of a
	# chunk squared above each chunk's place in row order, sorted natively.
	var centre := target.global_position / float(chunk_tiles * GameConstants.PX_PER_TILE) - Vector2(0.5, 0.5)
	var wanted: Array[Vector2i] = []
	var keys := PackedInt64Array()
	for y in range(maxi(_first.y, -_BORDER_CHUNKS), mini(_last.y, _world_chunks.y + _BORDER_CHUNKS - 1) + 1):
		for x in range(maxi(_first.x, -_BORDER_CHUNKS), mini(_last.x, _world_chunks.x + _BORDER_CHUNKS - 1) + 1):
			if not _chunks.has(Vector2i(x, y)):
				keys.append((int(centre.distance_squared_to(Vector2(x, y)) * 256.0) << 20) | wanted.size())
				wanted.append(Vector2i(x, y))
	keys.sort()
	_queue.clear()
	var queued: Dictionary[Vector2i, bool] = {}
	for key in keys:
		_queue.append(wanted[key & 0xFFFFF])
		queued[wanted[key & 0xFFFFF]] = true
	for coord in _jobs.keys():
		if not queued.has(coord):
			_drop(_jobs[coord][1])
			_jobs.erase(coord)
	_plan_ahead()


func _new_chunk(coord: Vector2i) -> WgChunk:
	var chunk := WgChunk.new()
	chunk.setup(coord, Vector2(coord * chunk_tiles * GameConstants.PX_PER_TILE), chunk_tiles)
	return chunk


func _clear_chunks() -> void:
	for chunk in _retired:
		chunk.queue_free()
	_retired.clear()
	for coord in _chunks:
		chunk_unloaded.emit(coord)
		_chunks[coord].queue_free()
	_chunks.clear()
	for coord in _jobs:
		_drop(_jobs[coord][1])
	_jobs.clear()
	_queue.clear()


func _exit_tree() -> void:
	for coord in _jobs:
		_drop(_jobs[coord][1])
	_jobs.clear()


## Frees an unfinished chunk, which may already have entered the tree.
static func _drop(chunk: WgChunk) -> void:
	if chunk.is_inside_tree():
		chunk.queue_free()
	else:
		chunk.free()
