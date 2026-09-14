class_name RoomInterior
extends RefCounted
## One Room's interior: the semantic class of every tile the Room owns, over bounds that hold all of
## them. Every Room in every Biome uses this one algorithm:
##
##   1. Tiles beside another owner (another Room, or no Room) are WALL, so each ownership change gets
##      a wall on both sides; the rest is FLOOR.
##   2. Each Passage's opening clears those walls on both of its sides.
##   3. A spine joins every Passage and Object spot to the Room's centre; tiles near it, and a clear
##      disc around each spot and the centre, never take rocks.
##   4. Walls deepen inward to the Biome's wall_depth, wandering by its wall_variation, on floor
##      rocks may cover outside a corridor as wide as each Passage's opening.
##   5. Noise rocks cover the Room's rockiness share of the rest (30% of it in set pieces).
##   6. The repair clears the fewest rocks and deepened walls joining the centre to every tile where
##      a Passage's opening meets the other Room, and to each spot. Only when those alone can't
##      join them does it also clear border walls, and then only walls facing no Room or a Room
##      later in the World's room list, so two Rooms never both clear the two sides of one wall.
##   7. Floor those joins don't reach fills with rock.
##
## It reads only the room graph and ownership, with noise keyed by the World seed and tile, so it
## is the same whichever Rooms were built first. step() does the work in slices that stop at a
## deadline; WorldInteriors owns the caches it reads and fills.

enum { FLOOR, WALL, ROCK }
## A tile inside the bounds that another Room owns, or none does.
const OUTSIDE := 255

## Radius of the clear disc around an Object spot, a landing and the Room's centre.
const SITE_CLEAR := 2.5
## The spine's half-width wanders between these, in tiles.
const SPINE_MIN := 1.5
const SPINE_MAX := 3.0
## How far a spine segment's middle may bend sideways, as a share of its length.
const SPINE_BEND := 0.2
## Tiles checked between deadline checks.
const _STEP_TILES := 64
## Chamfer distance steps to another owner, straight and diagonal, per tile.
const _CHAMFER := 5
const _CHAMFER_DIAGONAL := 7

enum _Phase { OWNERS, COPY, SHELL, OPENINGS, SPINE, WALLS, ROCKS, COSTS, CONNECT, CARVE, MARKS, FLOOD, POCKETS, DONE }

const _FAR := 1 << 30
const _BLOCKED := 255

var room: GeneratedRoom
## Holds every tile the Room can own.
var rect := Rect2i()
## One per tile of rect, row by row: FLOOR, WALL, ROCK or OUTSIDE.
var classes := PackedByteArray()
## Tiles the repair could not join to the centre; 0 when the Room is whole.
var unjoined := 0

var _field: WorldInteriors
var _phase := _Phase.OWNERS
var _cursor := 0
var _width := 0
## Owners over rect grown by one tile, row by row.
var _owners := PackedInt32Array()
## Tiles rocks keep off.
var _keep := PackedByteArray()
## Indices into rect the repair joins to _source: where openings meet the other Room, and each spot.
var _targets := PackedInt32Array()
var _crossings := PackedInt32Array()
var _source := -1
var _carved := PackedInt32Array()
var _segments: Array[PackedVector2Array] = []
## Spots and the centre, whose clear discs the spine phase stamps before the segments.
var _discs := PackedVector2Array()
var _spine_planned := false
var _stamp := 0
var _costs := PackedByteArray()
var _marks := PackedByteArray()
var _dist := PackedInt32Array()
var _prev := PackedInt32Array()
var _deque := PackedInt32Array()
var _head := 0
var _tail := 0
var _through_walls := false
## Whether the walls phase deepened any wall.
var _deepened := false


func _init(field: WorldInteriors, generated: GeneratedRoom) -> void:
	_field = field
	room = generated
	var low := Vector2(INF, INF)
	var high := -low
	for point in room.polygon:
		low = low.min(point)
		high = high.max(point)
	var bounds := Rect2i(Vector2i(low.floor()), Vector2i((high - low).ceil()) + Vector2i.ONE)
	rect = bounds.grow(ceili(field.graph.warp_bound(bounds)) + 2)
	_width = rect.size.x
	classes.resize(rect.size.x * rect.size.y)


func is_done() -> bool:
	return _phase == _Phase.DONE


## The class of a tile of the World: OUTSIDE unless this Room owns it.
func class_at(tile: Vector2i) -> int:
	if not rect.has_point(tile):
		return OUTSIDE
	return classes[(tile.y - rect.position.y) * _width + tile.x - rect.position.x]


## Works until done or past the deadline, in usec; true once done.
func step(deadline: int) -> bool:
	while _phase != _Phase.DONE:
		var finished := false
		match _phase:
			_Phase.OWNERS:
				finished = _fill_owners(deadline)
			_Phase.COPY:
				finished = _copy_owners(deadline)
			_Phase.SHELL:
				finished = _shell(deadline)
			_Phase.OPENINGS:
				finished = _open(deadline)
			_Phase.SPINE:
				finished = _spine(deadline)
			_Phase.WALLS:
				finished = _deepen(deadline)
			_Phase.ROCKS:
				finished = _rocks(deadline)
			_Phase.COSTS:
				finished = _find_costs(deadline)
			_Phase.CONNECT:
				finished = _connect(deadline)
			_Phase.CARVE:
				finished = _carve()
			_Phase.MARKS:
				finished = _mark_reached(deadline)
			_Phase.FLOOD:
				finished = _flood(deadline)
			_Phase.POCKETS:
				finished = _fill_pockets(deadline)
		if finished:
			_phase = (_phase + 1) as _Phase
			_cursor = 0
		if Time.get_ticks_usec() >= deadline:
			break
	if _phase == _Phase.DONE and _field != null:
		_owners = PackedInt32Array()
		_keep = PackedByteArray()
		_costs = PackedByteArray()
		_marks = PackedByteArray()
		_dist = PackedInt32Array()
		_prev = PackedInt32Array()
		_deque = PackedInt32Array()
		_carved = PackedInt32Array()
		_crossings = PackedInt32Array()
		_targets = PackedInt32Array()
		_segments.clear()
		_field = null
	return _phase == _Phase.DONE


## The owner blocks under the bounds and every Passage opening, so later phases read them in place.
func _fill_owners(deadline: int) -> bool:
	if not _field.fill_owners(rect.grow(1), deadline):
		return false
	for passage in room.passages:
		if not _field.fill_owners(WorldInteriors.opening_bounds(passage), deadline):
			return false
	return true


## Copies owners out of the blocks a run at a time; a block evicted since is worked out again.
func _copy_owners(deadline: int) -> bool:
	var outer := rect.grow(1)
	var owners := _owners
	_owners = PackedInt32Array()
	if owners.is_empty():
		owners.resize(outer.size.x * outer.size.y)
	var block_size := WorldInteriors.BLOCK
	while _cursor < outer.size.y:
		var y := outer.position.y + _cursor
		var base := _cursor * outer.size.x - outer.position.x
		var x := outer.position.x
		while x < outer.end.x:
			var local_x := posmod(x, block_size)
			var run := mini(block_size - local_x, outer.end.x - x)
			var block := _field.block_at(Vector2i(x, y))
			if block == null:
				for k in range(x, x + run):
					owners[base + k] = _field.graph.owner_index_at(Vector2i(k, y))
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
	return _cursor >= outer.size.y


func _shell(deadline: int) -> bool:
	var own := room.index
	var stride := _width + 2
	while _cursor < rect.size.y:
		var row := _cursor * _width
		var above := _cursor * stride + 1
		var here := above + stride
		var below := here + stride
		for x in _width:
			if _owners[here + x] != own:
				classes[row + x] = OUTSIDE
			elif _owners[here + x - 1] != own or _owners[here + x + 1] != own or _owners[above + x] != own or _owners[below + x] != own:
				classes[row + x] = WALL
			else:
				classes[row + x] = FLOOR
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	if _cursor < rect.size.y:
		return false
	_keep.resize(classes.size())
	return true


func _open(deadline: int) -> bool:
	while _cursor < room.passages.size():
		var passage := room.passages[_cursor]
		var partner := _field.graph.rooms[passage.other(room.key())].index
		var opening := _field.opening(passage)
		for tile: Vector2i in opening:
			if opening[tile] != room.index or not rect.has_point(tile):
				continue
			var index := _index(tile)
			classes[index] = FLOOR
			_keep[index] = 1
			for side: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if opening.get(tile + side, -1) == partner:
					_crossings.append(index)
					break
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return _cursor >= room.passages.size()


## Clear discs at each spot and the centre, then the spine one segment at a time.
func _spine(deadline: int) -> bool:
	if not _spine_planned:
		_spine_planned = true
		var hub := _field.graph.tile_of(room.seed)
		var spots: Array[Vector2i] = []
		var names: Array[String] = []
		for passage in room.passages:
			spots.append(passage.spot)
			names.append(passage.key)
		_targets.append_array(_crossings)
		for site in room.sites:
			spots.append(site.spot)
			names.append(site.key)
			_discs.append(Vector2(site.spot) + Vector2(0.5, 0.5))
			_add_target(site.spot)
		_discs.append(Vector2(hub) + Vector2(0.5, 0.5))
		if rect.has_point(hub) and classes[_index(hub)] == FLOOR:
			_source = _index(hub)
		elif not _crossings.is_empty():
			_source = _crossings[0]
		for n in spots.size():
			var from := Vector2(spots[n]) + Vector2(0.5, 0.5)
			var to := Vector2(hub) + Vector2(0.5, 0.5)
			var bend := _field.graph.plan.rng(WorldHash.NS_SPINE, "%s/%s" % [room.key(), names[n]]).randf_range(-SPINE_BEND, SPINE_BEND)
			var middle := from.lerp(to, 0.5) + (to - from).orthogonal() * bend
			_segments.append(PackedVector2Array([from, middle]))
			_segments.append(PackedVector2Array([middle, to]))
		return false
	while not _discs.is_empty():
		_keep_off(_discs[-1], SITE_CLEAR)
		_discs.remove_at(_discs.size() - 1)
		if Time.get_ticks_usec() >= deadline:
			return false
	while _cursor < _segments.size():
		var segment := _segments[_cursor]
		var steps := maxi(1, ceili(segment[0].distance_to(segment[1])))
		while _stamp <= steps:
			var point := segment[0].lerp(segment[1], float(_stamp) / steps)
			var wander := _field.spine_noise.get_noise_2d(point.x, point.y) * 0.5 + 0.5
			_keep_off(point, lerpf(SPINE_MIN, SPINE_MAX, wander))
			_stamp += 1
			if _stamp % 4 == 0 and Time.get_ticks_usec() >= deadline:
				return false
		_stamp = 0
		_cursor += 1
	return true


## Chamfer distance to another owner, a forward then a backward pass over the rows: floor rocks may
## cover within the wall depth turns WALL as the backward pass settles each row. First keeps the
## deepening off a corridor along each Passage's spine, as wide as its opening, past the deepest wall.
func _deepen(deadline: int) -> bool:
	var biome := _field.graph.plan.content.biomes[room.plan.biome]
	var deepest := biome.wall_depth + biome.wall_variation
	if deepest <= 1.0:
		return true
	var height := rect.size.y
	if _cursor == 0:
		while _stamp < room.passages.size():
			var radius := maxf(room.passages[_stamp].width * 0.5, 1.0) + 0.5
			var length := deepest + radius
			var travelled := 0.0
			for segment in [_segments[2 * _stamp], _segments[2 * _stamp + 1]]:
				var span: float = segment[0].distance_to(segment[1])
				var steps := maxi(1, ceili(span))
				for n in steps + 1:
					if travelled + span * n / steps > length:
						break
					_keep_off(segment[0].lerp(segment[1], float(n) / steps), radius)
				travelled += span
			_stamp += 1
			if Time.get_ticks_usec() >= deadline:
				return false
		_stamp = 0
		_dist.resize(classes.size())
		_cursor = 1
	var dist := _dist
	_dist = PackedInt32Array()
	var width := _width
	var reach := ceili(deepest * _CHAMFER)
	while _cursor <= 2 * height:
		if _cursor <= height:
			var y := _cursor - 1
			var row := y * width
			for x in width:
				var index := row + x
				if classes[index] == OUTSIDE:
					dist[index] = 0
					continue
				var best := (dist[index - 1] if x > 0 else 0) + _CHAMFER
				if y > 0:
					best = mini(best, dist[index - width] + _CHAMFER)
					best = mini(best, (dist[index - width - 1] if x > 0 else 0) + _CHAMFER_DIAGONAL)
					best = mini(best, (dist[index - width + 1] if x < width - 1 else 0) + _CHAMFER_DIAGONAL)
				dist[index] = mini(best, _CHAMFER) if y == 0 else best
		else:
			var y := 2 * height - _cursor
			var row := y * width
			for x in range(width - 1, -1, -1):
				var index := row + x
				var tile_class := classes[index]
				if tile_class == OUTSIDE:
					continue
				var best := mini(dist[index], (dist[index + 1] if x < width - 1 else 0) + _CHAMFER)
				if y < height - 1:
					best = mini(best, dist[index + width] + _CHAMFER)
					best = mini(best, (dist[index + width - 1] if x > 0 else 0) + _CHAMFER_DIAGONAL)
					best = mini(best, (dist[index + width + 1] if x < width - 1 else 0) + _CHAMFER_DIAGONAL)
				else:
					best = mini(best, _CHAMFER)
				dist[index] = best
				if tile_class != FLOOR or _keep[index] == 1 or best > reach:
					continue
				var wander := biome.wall_variation * _field.wall_noise.get_noise_2d(rect.position.x + x, rect.position.y + y)
				if best <= maxf(1.0, biome.wall_depth + wander) * _CHAMFER:
					classes[index] = WALL
					_deepened = true
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	_dist = dist if _cursor <= 2 * height else PackedInt32Array()
	return _cursor > 2 * height


func _rocks(deadline: int) -> bool:
	var rockiness := room.rockiness(_field.graph.plan.content)
	if rockiness <= 0.0:
		return true
	var threshold := WorldInteriors.rock_threshold(rockiness)
	var noise := _field.rock_noise
	while _cursor < rect.size.y:
		var row := _cursor * _width
		var y := rect.position.y + _cursor
		for x in _width:
			if classes[row + x] == FLOOR and _keep[row + x] == 0 and noise.get_noise_2d(rect.position.x + x, y) > threshold:
				classes[row + x] = ROCK
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return _cursor >= rect.size.y


## What entering each tile costs the repair: floor nothing, rock and deepened walls one, border
## walls it may clear one on the second pass; _BLOCKED where it can't pass.
func _find_costs(deadline: int) -> bool:
	if _source < 0:
		return true
	if _costs.size() != classes.size():
		_costs.resize(classes.size())
	while _cursor < rect.size.y:
		var row := _cursor * _width
		for index in range(row, row + _width):
			var tile_class := classes[index]
			if tile_class == FLOOR:
				_costs[index] = 0
			elif tile_class == ROCK:
				_costs[index] = 1
			elif tile_class == WALL and (_deepened and _inner(index) or _through_walls and _clearable(index)):
				_costs[index] = 1
			else:
				_costs[index] = _BLOCKED
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return _cursor >= rect.size.y


## 0-1 breadth-first search from the centre: rocks cost one, floor nothing. A second pass also
## lets it through the walls this Room may clear, when the first leaves a target unreached.
func _connect(deadline: int) -> bool:
	if _source < 0:
		return true
	var size := classes.size()
	if _cursor == 0:
		_dist.resize(size)
		_dist.fill(_FAR)
		_prev.resize(size)
		_prev.fill(-1)
		_deque.resize(size * 4 + 1)
		_head = 0
		_tail = 1
		_dist[_source] = 0
		_deque[0] = _source
		_cursor = 1
	var costs := _costs
	var dist := _dist
	_dist = PackedInt32Array()
	var prev := _prev
	_prev = PackedInt32Array()
	var deque := _deque
	_deque = PackedInt32Array()
	var capacity := deque.size()
	var head := _head
	var tail := _tail
	var width := _width
	var finished := true
	var pops := 0
	while head != tail:
		var at := deque[head]
		head += 1
		if head == capacity:
			head = 0
		var here := dist[at]
		var x := at % width
		for side in 4:
			var next := at
			if side == 0:
				if x == 0:
					continue
				next = at - 1
			elif side == 1:
				if x == width - 1:
					continue
				next = at + 1
			elif side == 2:
				if at < width:
					continue
				next = at - width
			else:
				next = at + width
				if next >= size:
					continue
			var cost := costs[next]
			if cost == _BLOCKED or here + cost >= dist[next]:
				continue
			dist[next] = here + cost
			prev[next] = at
			if cost == 0:
				head -= 1
				if head < 0:
					head = capacity - 1
				deque[head] = next
			else:
				deque[tail] = next
				tail += 1
				if tail == capacity:
					tail = 0
		pops += 1
		if pops & 31 == 0 and Time.get_ticks_usec() >= deadline:
			finished = false
			break
	_dist = dist
	_prev = prev
	_deque = deque
	_head = head
	_tail = tail
	if not finished:
		return false
	if not _through_walls:
		for target in _targets:
			if _dist[target] >= _FAR:
				_through_walls = true
				_phase = _Phase.COSTS
				_cursor = 0
				return false
	return true


## Clears the path from the centre to each target.
func _carve() -> bool:
	if _source < 0:
		unjoined = _targets.size()
		return true
	for target in _targets:
		if _dist[target] >= _FAR:
			unjoined += 1
			continue
		var at := target
		while at >= 0 and _dist[at] > 0:
			classes[at] = FLOOR
			_carved.append(at)
			at = _prev[at]
	return true


## Marks the floor the search reached for free, which the centre already joins.
func _mark_reached(deadline: int) -> bool:
	var size := classes.size()
	if _marks.size() != size:
		_marks.resize(size)
	if _dist.size() != size:
		return true
	while _cursor < rect.size.y:
		var row := _cursor * _width
		for index in range(row, row + _width):
			if _dist[index] == 0 and classes[index] == FLOOR:
				_marks[index] = 1
		_cursor += 1
		if Time.get_ticks_usec() >= deadline:
			break
	return _cursor >= rect.size.y


## Spreads the marks from the carved paths and the crossings over the floor they reach.
func _flood(deadline: int) -> bool:
	var size := classes.size()
	if _cursor == 0:
		_deque = PackedInt32Array()
		_deque.resize(size)
		_tail = 0
		for list: PackedInt32Array in [_carved, _crossings]:
			for index in list:
				if _marks[index] == 0 and classes[index] == FLOOR:
					_marks[index] = 1
					_deque[_tail] = index
					_tail += 1
		_cursor = 1
	var marks := _marks
	_marks = PackedByteArray()
	var stack := _deque
	_deque = PackedInt32Array()
	var top := _tail
	var width := _width
	var finished := true
	var pops := 0
	while top > 0:
		top -= 1
		var at := stack[top]
		var x := at % width
		for side in 4:
			var next := at - 1
			if side == 0:
				if x == 0:
					continue
			elif side == 1:
				if x == width - 1:
					continue
				next = at + 1
			elif side == 2:
				next = at - width
				if next < 0:
					continue
			else:
				next = at + width
				if next >= size:
					continue
			if marks[next] == 0 and classes[next] == FLOOR:
				marks[next] = 1
				stack[top] = next
				top += 1
		pops += 1
		if pops & 63 == 0 and Time.get_ticks_usec() >= deadline:
			finished = false
			break
	_marks = marks
	_deque = stack
	_tail = top
	return finished


func _fill_pockets(deadline: int) -> bool:
	var size := classes.size()
	while _cursor < size:
		var end := mini(_cursor + _STEP_TILES * 8, size)
		for index in range(_cursor, end):
			if classes[index] == FLOOR and _marks[index] == 0:
				classes[index] = ROCK
		_cursor = end
		if Time.get_ticks_usec() >= deadline:
			break
	return _cursor >= size


## A wall whose foreign neighbours are all no Room or a Room later in the room list: those Rooms
## never clear the wall facing this one.
func _clearable(index: int) -> bool:
	var stride := _width + 2
	var at := (floori(float(index) / _width) + 1) * stride + index % _width + 1
	for neighbour in [_owners[at - 1], _owners[at + 1], _owners[at - stride], _owners[at + stride]]:
		if neighbour != room.index and neighbour >= 0 and neighbour < room.index:
			return false
	return true


## A tile whose four neighbours this Room owns: a WALL there is a deepened one.
func _inner(index: int) -> bool:
	var stride := _width + 2
	var at := (floori(float(index) / _width) + 1) * stride + index % _width + 1
	var own := room.index
	return _owners[at - 1] == own and _owners[at + 1] == own and _owners[at - stride] == own and _owners[at + stride] == own


func _index(tile: Vector2i) -> int:
	return (tile.y - rect.position.y) * _width + tile.x - rect.position.x


func _add_target(tile: Vector2i) -> void:
	if rect.has_point(tile) and classes[_index(tile)] != OUTSIDE:
		_targets.append(_index(tile))


## Keeps rocks off every tile whose centre lies within radius of a point.
func _keep_off(point: Vector2, radius: float) -> void:
	var reach := ceili(radius)
	var centre := Vector2i(point.floor())
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var tile := centre + Vector2i(dx, dy)
			if not rect.has_point(tile):
				continue
			if (Vector2(tile) + Vector2(0.5, 0.5)).distance_squared_to(point) <= radius * radius:
				_keep[_index(tile)] = 1
