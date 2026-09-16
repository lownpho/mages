class_name MacroCellGraph
extends RefCounted
## The room graph inside one planned macro cell: every Room's seed and power-diagram cell, and the
## Passages between its own Rooms. It reads only the World plan, so cells build in any order.
##
## The cell is its MacroLattice outline, a convex polygon. Each attempt partitions it before deciding
## which Room is which:
##   1. Set pieces reserve their protected discs against edges no route crosses.
##   2. Each Room leaving the cell by a port takes a seed just inside it; a Room with several ports
##      takes a weighted seed whose disc reaches them all.
##   3. The rest of the cell's exact Room count fills a jittered lattice by largest clearance, never
##      taking a port's span from its Room.
##   4. Over the borders wide enough for a Passage, a simple path of exactly the cell's route length
##      runs from the spawn or entry port through every port Room at its route position.
##   5. Route Rooms take the path in order; each off-route Room takes the free Room nearest its join.
## An attempt is kept when ports are covered, every Room but the set pieces connects without them,
## every set piece borders an ordinary Room and the path exists. Otherwise the next attempt, from its
## own seed, tries again; running out is a generation bug.

const ATTEMPTS := 256
const DIRECTIONS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const HALF := WorldPlan.CELL * 0.5
## Ports stay this far from their edge's corners.
const PORT_MARGIN := 30.0
## How far inside its edge a port Room's seed sits, drawn per attempt: from PORT_INSET up to three
## quarters of a Room the cell's quota would make, at most PORT_DEPTH_MAX, and as far to either side
## of its port. Deep seeds keep fill seeds from walling a port Room against its edge; varied places
## let consecutive port Rooms meet around the others.
const PORT_INSET := 6.0
const PORT_DEPTH_MAX := 45.0
const PORT_TRIALS := 8
## Of a set piece's 32 placement trials, the first this many also keep off the lines between ports.
const CORRIDOR_TRIALS := 24
## Tiles a Passage's border needs beyond its width.
const BORDER_SLACK := 2
## Squared tiles by which another seed must lose a port's span to the port's Room.
const PORT_GUARD := 16.0
## Fixed route Rooms farther apart than this many natural Room spacings per step get the Rooms
## between them seeded along the gap instead of left to the route search.
const BRIDGE_REACH := 0.8
## Rooms a route search may try before the attempt gives up: a fresh partition is cheaper than an
## exhaustive search of a poor one.
const PATH_BUDGET := 1500
## Tiles a seed keeps inside the outline along each axis, and the steps toward the cell's centre that
## bring a seed that far in.
const SEED_INSET := 2.0
const PULL_STEPS := 32
## Tiles at a time a set piece's disc moves in from a slanted edge until it fits.
const PROTECTED_STEP := 1.5


## A route or attachment Passage leaving the cell: the Room it leaves from, which edge, and the span
## of that edge the Room must cover.
class Port:
	var room: GeneratedRoom
	var direction := Vector2i.ZERO
	var kind := RoomPassage.Kind.ROUTE
	## On the edge, unwarped. Both cells sharing the edge derive the same point.
	var point := Vector2.ZERO
	var width := 2
	## Unit vectors along the edge and into the cell.
	var tangent := Vector2.ZERO
	var inward := Vector2.ZERO

	func half_span() -> float:
		return ceili(width / 2.0) + BORDER_SLACK


var cell: MacroCellPlan
## The cell's outline, clockwise.
var outline := PackedVector2Array()
var rooms: Array[GeneratedRoom] = []
var ports: Array[Port] = []
## The Passages between this cell's own Rooms. WorldGraph adds those crossing its edges.
var passages: Array[RoomPassage] = []
## Room-pair key -> the unwarped ends of a shared border wide enough for a Passage.
var borders: Dictionary[String, PackedVector2Array] = {}
var attempts := 0
var _by_key: Dictionary[String, GeneratedRoom] = {}
## One attempt's partition: the Rooms whose seeds are fixed to their plan Rooms, then anonymous ones.
var _shapes: Array[GeneratedRoom] = []
## Shape index -> the shapes sharing a wide enough border.
var _adjacent: Array[PackedInt32Array] = []
## The deepest a port Room's seed may sit this attempt.
var _port_depth := PORT_INSET
var _corridors: Array[Array] = []
## Corridor points no other seed may take: [point, owner Room, the Room across from it].
var _guards: Array[Array] = []
## Why each attempt before the kept one failed: reason -> attempts.
var failures: Dictionary[String, int] = {}
var _lattice: MacroLattice
## The outline's bounding box.
var _bounds := Rect2()
## Each outline side's unit normal into the cell and its offset along that normal.
var _side_normals := PackedVector2Array()
var _side_offsets := PackedFloat64Array()


## null, with an error, when every attempt fails.
static func build(plan: WorldPlan, coord: Vector2i) -> MacroCellGraph:
	var graph := MacroCellGraph.new()
	graph.cell = plan.cells[coord]
	graph._lattice = plan.lattice
	graph.outline = plan.lattice.outline(coord)
	graph._bounds = Rect2(graph.outline[0], Vector2.ZERO)
	for point in graph.outline:
		graph._bounds = graph._bounds.expand(point)
	var inner := plan.lattice.centre(coord)
	for n in graph.outline.size():
		var from := graph.outline[n]
		var to := graph.outline[(n + 1) % graph.outline.size()]
		if from.distance_squared_to(to) < 0.0001:
			continue
		var normal := (to - from).orthogonal().normalized()
		if normal.dot(inner - from) < 0.0:
			normal = -normal
		graph._side_normals.append(normal)
		graph._side_offsets.append(normal.dot(from))
	for room_plan in graph.cell.rooms:
		var generated_room := GeneratedRoom.new()
		generated_room.plan = room_plan
		graph.rooms.append(generated_room)
		graph._by_key[room_plan.key] = generated_room
	graph._add_ports(plan)
	graph._chain_ports()
	for attempt in ATTEMPTS:
		graph.attempts = attempt + 1
		if graph._attempt(plan, plan.rng(WorldHash.NS_CELL_GRAPH, "%s/%d" % [graph.cell.key, attempt])):
			graph._connect(plan)
			return graph
	push_error("World seed %d: exhausted %d room-graph attempts in macro cell %s (%s, %d Rooms, %d on the route): %s" % [
			plan.world_seed, ATTEMPTS, graph.cell.key, graph.cell.biome, graph.rooms.size(), graph.route().size(), graph.failures])
	return null


## The route Rooms in route order.
func route() -> Array[GeneratedRoom]:
	return rooms.filter(func(generated_room: GeneratedRoom) -> bool: return generated_room.plan.is_on_route())


func room(key: String) -> GeneratedRoom:
	return _by_key.get(key)


## Where the Passage across the edge from coord toward direction opens, unwarped. Hashed from the
## edge, so both cells agree without reading each other.
static func port_point(plan: WorldPlan, coord: Vector2i, direction: Vector2i) -> Vector2:
	var other := coord + direction
	var edge := RoomPassage.pair("%d,%d" % [coord.x, coord.y], "%d,%d" % [other.x, other.y])
	var along := plan.rng(WorldHash.NS_PORTS, edge).randf_range(PORT_MARGIN, WorldPlan.CELL - PORT_MARGIN)
	return plan.lattice.edge_point(coord, direction, along / WorldPlan.CELL)


## A Passage's width between two cells' Biomes: the mean of their passage widths.
static func edge_width(plan: WorldPlan, a: Vector2i, b: Vector2i) -> int:
	return roundi((plan.biomes[plan.cells[a].biome].resource.passage_width + plan.biomes[plan.cells[b].biome].resource.passage_width) / 2.0)


## The span of the edge toward direction that a Room's polygon covers, as (from, to) in tiles along
## the edge from its first end; (INF, -INF) when the Room doesn't reach it.
static func exposure(plan: WorldPlan, generated_room: GeneratedRoom, coord: Vector2i, direction: Vector2i) -> Vector2:
	var span := Vector2(INF, -INF)
	for point in generated_room.polygon:
		if plan.lattice.on_edge(coord, direction, point):
			var along := plan.lattice.along_edge(coord, direction, point)
			span = Vector2(minf(span.x, along), maxf(span.y, along))
	return span


func _add_ports(plan: WorldPlan) -> void:
	var path := route()
	if cell.entry != Vector2i.ZERO:
		_add_port(plan, path[0], cell.entry, RoomPassage.Kind.ROUTE)
	if cell.exit != Vector2i.ZERO:
		_add_port(plan, path[-1], cell.exit, RoomPassage.Kind.ROUTE)
	for side in plan.content.parents:
		var biome := plan.biomes[side]
		if biome.attachment.cell == cell.coord:
			_add_port(plan, _by_key[biome.attachment.key], biome.cells[0] - cell.coord, RoomPassage.Kind.ATTACHMENT)


func _add_port(plan: WorldPlan, owner: GeneratedRoom, direction: Vector2i, kind: RoomPassage.Kind) -> void:
	var port := Port.new()
	port.room = owner
	port.direction = direction
	port.kind = kind
	port.point = port_point(plan, cell.coord, direction)
	port.width = edge_width(plan, cell.coord, cell.coord + direction)
	port.tangent = plan.lattice.edge_tangent(cell.coord, direction)
	port.inward = plan.lattice.inward(cell.coord, direction)
	ports.append(port)


## The straight lines between consecutive ports in route order, which set pieces keep off when they
## can: [from, to, clearance beyond a disc's radius].
func _chain_ports() -> void:
	var path := route()
	var ordered := ports.duplicate()
	ordered.sort_custom(func(a: Port, b: Port) -> bool: return path.find(a.room) < path.find(b.room))
	for n in range(1, ordered.size()):
		_corridors.append([ordered[n - 1].point, ordered[n].point, maxf(ordered[n - 1].half_span(), ordered[n].half_span()) + PORT_INSET])


func _clear_of_corridors(special: GeneratedRoom) -> bool:
	for corridor in _corridors:
		var closest := Geometry2D.get_closest_point_to_segment(special.seed_point, corridor[0], corridor[1])
		if special.seed_point.distance_to(closest) < special.radius + corridor[2]:
			return false
	return true


func _room_ports(owner: GeneratedRoom) -> Array[Port]:
	return ports.filter(func(port: Port) -> bool: return port.room == owner)


func _attempt(plan: WorldPlan, rng: RandomNumberGenerator) -> bool:
	_shapes.clear()
	_port_depth = clampf(WorldPlan.CELL / sqrt(float(rooms.size())) * 0.75, PORT_INSET + 4.0, PORT_DEPTH_MAX)
	# 1. Set pieces, against edges no route crosses, those facing no other macro cell first.
	var ranked: Array[Array] = []
	for direction in DIRECTIONS:
		var rank := 0
		if ports.any(func(port: Port) -> bool: return port.direction == direction):
			rank = 2
		elif plan.cells.has(cell.coord + direction):
			rank = 1
		ranked.append([rank, rng.randf(), direction])
	ranked.sort()
	for room_now in rooms:
		if room_now.is_set_piece():
			room_now.radius = plan.radii[room_now.plan.kind_name()]
			if not _place_protected(room_now, ranked, rng):
				return _fail("set piece placement")
			_shapes.append(room_now)
	# 2. Port Rooms.
	for room_now in rooms:
		var room_ports := _room_ports(room_now)
		if room_now.is_set_piece() or room_ports.is_empty():
			continue
		room_now.radius = 0.0
		var placed := false
		# Nearer the port on each trial, clear of the seeds already fixed.
		for trial in PORT_TRIALS:
			var reach := lerpf(_port_depth, PORT_INSET, float(trial) / PORT_TRIALS)
			var depth := rng.randf_range(PORT_INSET, reach)
			var sideways := rng.randf_range(-reach, reach)
			var sum := Vector2.ZERO
			for port in room_ports:
				sum += port.point + port.inward * depth
			room_now.seed_point = sum / room_ports.size()
			if room_ports.size() == 1:
				room_now.seed_point += room_ports[0].tangent * sideways
			room_now.seed_point = _pull_inside(room_now.seed_point)
			if _shapes.all(func(other: GeneratedRoom) -> bool:
				return room_now.seed_point.distance_to(other.seed_point) >= other.radius + 3.0 \
						and not room_ports.any(func(port: Port) -> bool: return _takes_port(port, other.seed_point, other.radius))):
				placed = true
				break
		if not placed:
			return _fail("port Rooms crowd")
		_shapes.append(room_now)
	if not _bridge_route(plan, rng):
		return false
	var fixed := _shapes.size()
	for n in fixed:
		for port in ports:
			if port.room != _shapes[n] and _takes_port(port, _shapes[n].seed_point, _shapes[n].radius):
				return _fail("port taken")
		if _guarded(_shapes[n], _shapes[n].seed_point, _shapes[n].radius):
			return _fail("corridor blocked")
	# 3. The rest of the quota, anonymous until the route is found.
	var candidates: Array[Vector2] = []
	var step := clampf(plan.biomes[cell.biome].resource.room_size * 0.4, 6, 16)
	var y := _bounds.position.y + step * 0.5
	while y < _bounds.end.y:
		var x := _bounds.position.x + step * 0.5
		while x < _bounds.end.x:
			var candidate := Vector2(x, y) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * step
			if _inside(candidate, SEED_INSET) and not ports.any(func(port: Port) -> bool: return _takes_port(port, candidate, 0.0)) \
					and not _guarded(null, candidate, 0.0):
				candidates.append(candidate)
			x += step
		y += step
	var clearances := PackedFloat32Array()
	clearances.resize(candidates.size())
	for n in candidates.size():
		var clearance := INF
		for other in _shapes:
			clearance = minf(clearance, candidates[n].distance_to(other.seed_point) - other.radius)
		clearances[n] = clearance
	for _n in rooms.size() - fixed:
		var best := -1
		var best_clearance := -INF
		for n in candidates.size():
			if clearances[n] > best_clearance:
				best_clearance = clearances[n]
				best = n
		if best < 0 or best_clearance < 3:
			return _fail("no clearance for ordinary seeds")
		var shape := GeneratedRoom.new()
		shape.seed_point = candidates[best]
		_shapes.append(shape)
		for n in candidates.size():
			clearances[n] = minf(clearances[n], candidates[n].distance_to(shape.seed_point))
		clearances[best] = -INF
	PowerCells.polygons(_shapes, outline)
	# Partition checks that hold whichever Room is which.
	for shape in _shapes:
		if shape.polygon.size() < 3:
			return _fail("empty Room")
	for port in ports:
		var span := exposure(plan, port.room, cell.coord, port.direction)
		var along := plan.lattice.along_edge(cell.coord, port.direction, port.point)
		if span.x > along - port.half_span() or span.y < along + port.half_span():
			return _fail("port uncovered")
	var slack := plan.biomes[cell.biome].resource.passage_width + BORDER_SLACK
	_adjacent.clear()
	_adjacent.resize(_shapes.size())
	var edges: Dictionary[Vector2i, PackedVector2Array] = {}
	for i in _shapes.size():
		for j in range(i + 1, _shapes.size()):
			var edge := PowerCells.border(_shapes[i], _shapes[j])
			if edge.size() == 2 and edge[0].distance_to(edge[1]) >= slack:
				edges[Vector2i(i, j)] = edge
				_adjacent[i].append(j)
				_adjacent[j].append(i)
	if not _connected(fixed):
		return _fail("ordinary Rooms disconnected")
	# 4. and 5.
	var path := _find_route(fixed, rng)
	if path.is_empty():
		return _fail("no route of the right length")
	_assign(path, fixed)
	borders.clear()
	for pair_indices in edges:
		borders[RoomPassage.pair(_shapes[pair_indices.x].key(), _shapes[pair_indices.y].key())] = edges[pair_indices]
	return true


## Against the best-ranked edges, or behind its own port for a spawn the route leaves at once: as near
## the edge as the whole disc fits inside the outline, which a slanted or bowed edge pushes further in.
func _place_protected(special: GeneratedRoom, ranked: Array[Array], rng: RandomNumberGenerator) -> bool:
	var margin := minf(special.radius + 1.0, HALF)
	var own := _room_ports(special)
	for trial in 32:
		var anchor := Vector2.ZERO
		var inward := Vector2.ZERO
		if not own.is_empty():
			for port in own:
				anchor += port.point / own.size()
				inward += port.inward / own.size()
		else:
			@warning_ignore("integer_division") # Whole counts and grid indices intentionally truncate.
			var direction: Vector2i = ranked[mini(trial / 8, ranked.size() - 1)][2]
			var along := rng.randf_range(margin, WorldPlan.CELL - margin)
			anchor = _lattice.edge_point(cell.coord, direction, along / WorldPlan.CELL)
			inward = _lattice.inward(cell.coord, direction)
		var depth := margin
		special.seed_point = anchor + inward * depth
		while not _disc_inside(special) and depth < HALF and inward != Vector2.ZERO:
			depth += PROTECTED_STEP
			special.seed_point = anchor + inward * depth
		var inside := _disc_inside(special)
		var clear := inside and _shapes.all(func(other: GeneratedRoom) -> bool:
			return special.seed_point.distance_to(other.seed_point) > special.radius + other.radius + 3.0)
		clear = clear and ports.all(func(port: Port) -> bool:
			return port.room == special or special.seed_point.distance_to(port.point) > special.radius + port.half_span() + PORT_INSET + 2.0)
		if clear and trial < CORRIDOR_TRIALS and own.is_empty():
			clear = _clear_of_corridors(special)
		if clear:
			return true
		if not own.is_empty():
			return false
	return false


## The spawn and port Rooms fix their route positions. Where two of them are consecutive, or too far
## apart for free Rooms to bridge in the steps between, the Rooms between sit evenly along the gap
## and the corridor through the chain is guarded, so the fill can't wall consecutive Rooms apart.
func _bridge_route(plan: WorldPlan, rng: RandomNumberGenerator) -> bool:
	_guards.clear()
	var path := route()
	var spacing := WorldPlan.CELL / sqrt(float(rooms.size()))
	var half := plan.biomes[cell.biome].resource.passage_width / 2.0 + BORDER_SLACK
	var previous := -1
	for step in path.size():
		if not _shapes.has(path[step]):
			continue
		if previous >= 0:
			var gap := step - previous
			var a := path[previous]
			var b := path[step]
			# Consecutive port Rooms far apart meet halfway: each moves toward the other.
			if gap == 1 and a.is_ordinary() and b.is_ordinary() and a.seed_point.distance_to(b.seed_point) > spacing * BRIDGE_REACH:
				var pull := (a.seed_point.distance_to(b.seed_point) - spacing * BRIDGE_REACH) * 0.5 / a.seed_point.distance_to(b.seed_point)
				var from := a.seed_point
				a.seed_point = a.seed_point.lerp(b.seed_point, pull)
				b.seed_point = b.seed_point.lerp(from, pull)
			var toward := (b.seed_point - a.seed_point).normalized()
			var start := a.seed_point + toward * a.radius
			var end := b.seed_point - toward * b.radius
			if gap == 1 or start.distance_to(end) > gap * spacing * BRIDGE_REACH:
				# Bowed to a random side, so the Rooms left to either side of the chain vary by attempt.
				var bow := toward.orthogonal() * rng.randf_range(-1.5, 1.5) * spacing
				for t in range(1, gap):
					var between := path[previous + t]
					between.radius = 0.0
					between.seed_point = start.lerp(end, float(t) / gap) + bow * sin(PI * t / gap) + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2))
					between.seed_point = _pull_inside(between.seed_point)
					if _shapes.any(func(other: GeneratedRoom) -> bool: return between.seed_point.distance_to(other.seed_point) < other.radius + 3.0):
						return _fail("bridge crowded")
					_shapes.append(between)
				for t in gap:
					_guard_pair(path[previous + t], path[previous + t + 1], half)
		previous = step
	return true


## The segment between two seeds, each half owned by its nearer seed, and the middle of their border.
## How much closer another seed is than a half's owner varies linearly along the half, so guarding
## each half's ends guards all of it.
func _guard_pair(a: GeneratedRoom, b: GeneratedRoom, half: float) -> void:
	var delta := b.seed_point - a.seed_point
	var length := delta.length()
	if length < 0.01:
		return
	var middle := a.seed_point + delta * clampf((length * length + a.radius * a.radius - b.radius * b.radius) / (2.0 * length * length), 0.0, 1.0)
	_guards.append([a.seed_point, a, b])
	_guards.append([middle, a, b])
	_guards.append([b.seed_point, b, a])
	var across := delta.orthogonal() / length
	for t: float in [-1.0, 1.0]:
		_guards.append([middle + across * half * t, a, b])


## Whether a seed of that weight, other than the guards' own Rooms, would take a guarded point.
func _guarded(shape: GeneratedRoom, seed_point: Vector2, weight: float) -> bool:
	for guard in _guards:
		var owner: GeneratedRoom = guard[1]
		if shape == owner or shape == guard[2]:
			continue
		var point: Vector2 = guard[0]
		if point.distance_squared_to(seed_point) - weight * weight <= point.distance_squared_to(owner.seed_point) - owner.radius * owner.radius + PORT_GUARD:
			return true
	return false


## Whether a seed of that weight would take any point of the port's span from the port's Room.
func _takes_port(port: Port, seed_point: Vector2, weight: float) -> bool:
	for t: float in [-1.0, 0.0, 1.0]:
		var q: Vector2 = port.point + port.tangent * port.half_span() * t
		var own: float = q.distance_squared_to(port.room.seed_point) - port.room.radius * port.room.radius
		if q.distance_squared_to(seed_point) - weight * weight <= own + PORT_GUARD:
			return true
	return false


## Every shape but the Boss, Miniboss and Rare discs connects without them, and each of those borders
## an ordinary one.
func _connected(fixed: int) -> bool:
	var isolated := func(index: int) -> bool: return index < fixed and _shapes[index].is_isolated()
	var start := -1
	for index in _shapes.size():
		if not isolated.call(index):
			start = index
			break
	var reached := PackedByteArray()
	reached.resize(_shapes.size())
	reached[start] = 1
	var queue := PackedInt32Array([start])
	var next := 0
	while next < queue.size():
		for other in _adjacent[queue[next]]:
			if reached[other] == 0 and not isolated.call(other):
				reached[other] = 1
				queue.append(other)
		next += 1
	for index in _shapes.size():
		if isolated.call(index):
			if not Array(_adjacent[index]).any(func(other: int) -> bool: return other >= fixed or _shapes[other].is_ordinary()):
				return false
		elif reached[index] == 0:
			return false
	return true


## Shape indices for the route, in order: a simple path through borders, the spawn and each port
## Room at its route position, anonymous shapes elsewhere. Backtracks within a budget, pruning moves
## that can no longer reach the next fixed Room in time, and prefers hugging the path so far.
func _find_route(fixed: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var path := route()
	var length := path.size()
	var required: Dictionary[int, int] = {}
	for step in length:
		var index := _shapes.find(path[step])
		if index >= 0:
			required[step] = index
	var used := PackedByteArray()
	used.resize(_shapes.size())
	var chosen := PackedInt32Array()
	chosen.resize(length)
	var options: Array[PackedInt32Array] = []
	options.resize(length)
	var everyone := PackedInt32Array()
	for index in _shapes.size():
		everyone.append(index)
	options[0] = _route_options(everyone, 0, fixed, required, used, length, rng)
	var step := 0
	for _try in PATH_BUDGET:
		if options[step].is_empty():
			if step == 0:
				return PackedInt32Array()
			step -= 1
			used[chosen[step]] = 0
			continue
		# Packed arrays copy on write: take the list out, shorten it, put it back.
		var remaining := options[step]
		var node := remaining[-1]
		remaining.remove_at(remaining.size() - 1)
		options[step] = remaining
		chosen[step] = node
		used[node] = 1
		step += 1
		if step == length:
			return chosen
		options[step] = _route_options(_adjacent[node], step, fixed, required, used, length, rng)
	return PackedInt32Array()


## The shapes a route step may take, best last.
func _route_options(nodes: PackedInt32Array, step: int, fixed: int, required: Dictionary[int, int],
		used: PackedByteArray, length: int, rng: RandomNumberGenerator) -> PackedInt32Array:
	var next_required := -1
	for later in range(step + 1, length):
		if required.has(later):
			next_required = later
			break
	var hops := PackedInt32Array()
	if next_required >= 0:
		hops = _hops_to(required[next_required], fixed, used)
	var scored: Array[Array] = []
	for node in nodes:
		if used[node] == 1:
			continue
		if required.has(step):
			if node != required[step]:
				continue
		elif node < fixed:
			continue
		if next_required >= 0 and hops[node] > next_required - step:
			continue
		var open := 0
		for other in _adjacent[node]:
			if used[other] == 0 and other >= fixed:
				open += 1
		scored.append([open + rng.randf() * 1.5, node])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := PackedInt32Array()
	for entry in scored:
		out.append(entry[1])
	return out


## Route Rooms take the path's shapes; each off-route ordinary Room, in plan order, takes the free
## shape fewest borders from its join, nearest it on ties.
func _assign(path: PackedInt32Array, fixed: int) -> void:
	var owners: Dictionary[int, GeneratedRoom] = {}
	var route_rooms := route()
	for step in path.size():
		owners[path[step]] = route_rooms[step]
	var shape_of: Dictionary[String, int] = {}
	for step in path.size():
		shape_of[route_rooms[step].key()] = path[step]
	for index in fixed:
		shape_of[_shapes[index].key()] = index
		owners[index] = _shapes[index]
	for room_now in rooms:
		if room_now.plan.is_on_route() or room_now.is_set_piece():
			continue
		var join := shape_of[cell.rooms.filter(func(other: RoomPlan) -> bool: return other.is_on_route() and other.route_index == room_now.plan.join_index)[0].key]
		var distance := _hops_from(join)
		var best := -1
		for index in range(fixed, _shapes.size()):
			if owners.has(index):
				continue
			if best < 0 or distance[index] < distance[best] or (distance[index] == distance[best]
					and _shapes[index].seed_point.distance_squared_to(_shapes[join].seed_point) < _shapes[best].seed_point.distance_squared_to(_shapes[join].seed_point)):
				best = index
		owners[best] = room_now
	for index in range(fixed, _shapes.size()):
		var owner := owners[index]
		owner.seed_point = _shapes[index].seed_point
		owner.radius = 0.0
		owner.polygon = _shapes[index].polygon
		_shapes[index] = owner


## Hops from a fixed shape to each shape, stepping only through unused anonymous ones.
func _hops_to(target: int, fixed: int, used: PackedByteArray) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(_shapes.size())
	distance.fill(1 << 20)
	distance[target] = 0
	var queue := PackedInt32Array([target])
	var next := 0
	while next < queue.size():
		var at := queue[next]
		next += 1
		for other in _adjacent[at]:
			if distance[other] > distance[at] + 1:
				distance[other] = distance[at] + 1
				if other >= fixed and used[other] == 0:
					queue.append(other)
	return distance


func _hops_from(from: int) -> PackedInt32Array:
	var distance := PackedInt32Array()
	distance.resize(_shapes.size())
	distance.fill(1 << 20)
	distance[from] = 0
	var queue := PackedInt32Array([from])
	var next := 0
	while next < queue.size():
		var at := queue[next]
		next += 1
		for other in _adjacent[at]:
			if distance[other] > distance[at] + 1:
				distance[other] = distance[at] + 1
				queue.append(other)
	return distance


## Route Passages first, then a spanning tree over the other borders in hashed order with hashed
## loops, then each set piece's one Passage: to an ordinary neighbour on the route nearest its join
## where it can.
func _connect(plan: WorldPlan) -> void:
	passages.clear()
	var width := plan.biomes[cell.biome].resource.passage_width
	var union: Dictionary[String, String] = {}
	for room_now in rooms:
		union[room_now.key()] = room_now.key()
	var path := route()
	for n in range(1, path.size()):
		_join(union, path[n - 1].key(), path[n].key())
		_add_passage(path[n - 1], path[n], RoomPassage.Kind.ROUTE, width)
	var order: Array[Array] = []
	for pair_key in borders:
		var a := _by_key[pair_key.get_slice("|", 0)]
		var b := _by_key[pair_key.get_slice("|", 1)]
		if not a.is_isolated() and not b.is_isolated() and not _has_passage(pair_key):
			order.append([plan.seed_for(WorldHash.NS_PASSAGES, pair_key), pair_key])
	order.sort()
	for entry in order:
		var pair_key: String = entry[1]
		var a := _by_key[pair_key.get_slice("|", 0)]
		var b := _by_key[pair_key.get_slice("|", 1)]
		if _join(union, a.key(), b.key()):
			_add_passage(a, b, RoomPassage.Kind.TREE, width)
		else:
			var odds := (plan.biomes[a.plan.biome].resource.loops + plan.biomes[b.plan.biome].resource.loops) / 2.0
			if plan.rng(WorldHash.NS_PASSAGES, "loop/" + pair_key).randf() < odds:
				_add_passage(a, b, RoomPassage.Kind.LOOP, width)
	for special in rooms:
		if not special.is_isolated():
			continue
		var best: GeneratedRoom = null
		var best_score := []
		for pair_key in borders:
			var ends := pair_key.split("|")
			if not ends.has(special.key()):
				continue
			var other := _by_key[ends[1] if ends[0] == special.key() else ends[0]]
			if not other.is_ordinary():
				continue
			var away := absi(other.plan.route_index - special.plan.join_index) if other.plan.is_on_route() else 1 << 20
			var score := [away, plan.seed_for(WorldHash.NS_PASSAGES, pair_key)]
			if best == null or score < best_score:
				best = other
				best_score = score
		_add_passage(special, best, RoomPassage.Kind.SET_PIECE, width)


func _has_passage(pair_key: String) -> bool:
	return passages.any(func(passage: RoomPassage) -> bool: return passage.key == pair_key)


func _add_passage(a: GeneratedRoom, b: GeneratedRoom, kind: RoomPassage.Kind, width: int) -> void:
	var passage := RoomPassage.new()
	passage.key = RoomPassage.pair(a.key(), b.key())
	passage.a = passage.key.get_slice("|", 0)
	passage.b = passage.key.get_slice("|", 1)
	passage.kind = kind
	passage.width = width
	var edge := borders[passage.key]
	passage.point = (edge[0] + edge[1]) / 2.0
	passages.append(passage)


## Unites two Rooms' sets; false when they were already one.
static func _join(union: Dictionary[String, String], a: String, b: String) -> bool:
	var root_a := _find(union, a)
	var root_b := _find(union, b)
	if root_a == root_b:
		return false
	union[root_b] = root_a
	return true


static func _find(union: Dictionary[String, String], key: String) -> String:
	while union[key] != key:
		union[key] = union[union[key]]
		key = union[key]
	return key


## Whether a point lies in this macro cell at least inset tiles from every side of its convex outline.
func _inside(point: Vector2, inset: float) -> bool:
	for n in _side_normals.size():
		if _side_normals[n].dot(point) - _side_offsets[n] < inset:
			return false
	return true


## The point, or the first place SEED_INSET inside the outline on its way to the cell's centre: a seed
## outside its macro cell would lie outside its own clipped cell.
func _pull_inside(point: Vector2) -> Vector2:
	var centre := _lattice.centre(cell.coord)
	for _step in PULL_STEPS:
		if _inside(point, SEED_INSET):
			return point
		point = point.move_toward(centre, SEED_INSET)
	return point


## Whether a protected disc, with a tile to spare, lies wholly inside the outline.
func _disc_inside(special: GeneratedRoom) -> bool:
	return _inside(special.seed_point, special.radius + 1.0)


func _fail(reason: String) -> bool:
	failures[reason] = failures.get(reason, 0) + 1
	return false
