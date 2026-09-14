class_name WorldGraph
extends RefCounted
## Every room graph of a planned World, joined: each macro cell's Rooms and inner Passages, the route
## Passages across macro-cell edges, each Side biome's one attachment Passage, shortcuts where
## Ideal-path stretches fold alongside one another, Room roles and the planned Object sites.
##
## Ownership is a warped power diagram. warp() displaces a tile by value noise whose strength is each
## macro cell's Biome border_warp, interpolated between cell centres and fading to nothing over a set
## piece's protected disc; owner_at() gives the one Room owning the displaced point, so every wall is
## a single ownership change. Positions in Rooms and Passages are unwarped; spots are tiles.
##
## Cells build in any order and every choice draws from a seed keyed by its place, so one plan always
## gives the same graph.

## The warp noise's lattice, in tiles.
const WARP_SCALE := 48.0
## Past a set piece's disc, the warp regains full strength over this many tiles.
const WARP_FALLOFF := 32.0
## Seeds generate() tries in all before giving up.
const SEED_ATTEMPTS := 32
const _INVERSE_STEPS := 16
## Side of the square bins, in unwarped tiles, that list which Rooms may own a point.
const _BIN := 8
@warning_ignore("integer_division")
const _BINS := WorldPlan.CELL / _BIN

var plan: WorldPlan
var cells: Dictionary[Vector2i, MacroCellGraph] = {}
## Every Room by key, in plan order.
var rooms: Dictionary[String, GeneratedRoom] = {}
## Every Room in plan order: GeneratedRoom.index indexes it.
var room_list: Array[GeneratedRoom] = []
## Every Passage by key.
var passages: Dictionary[String, RoomPassage] = {}
## Every Object site and landing by key.
var sites: Dictionary[String, ObjectSite] = {}
## Macro cell -> the set pieces in it and its eight neighbours, for the warp's falloff.
var _set_pieces_near: Dictionary[Vector2i, Array] = {}
var _noise_x: FastNoiseLite
var _noise_y: FastNoiseLite
## The strongest border_warp of any Biome.
var _strongest_warp := 0.0
## warp() and owner_index_at() run once per tile while interiors stream, so they keep what they last
## looked up: none of it changes a result.
var _amplitude_lattice := Vector2i(1 << 30, 1 << 30)
var _amplitude_corners := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _near_coord := Vector2i(1 << 30, 1 << 30)
## The set pieces near _near_coord: seed x, seed y and radius for each.
var _near := PackedFloat64Array()
var _warped_x := 0.0
var _warped_y := 0.0
var _bins_coord := Vector2i(1 << 30, 1 << 30)
## The macro cell at _bins_coord: its bins, and each of its Rooms' index, seed and squared radius.
## Empty bins where no Biome owns the cell.
var _bins: Array[PackedInt32Array] = []
var _bin_rooms := PackedInt32Array()
var _bin_x := PackedFloat64Array()
var _bin_y := PackedFloat64Array()
var _bin_r2 := PackedFloat64Array()
## Macro cell -> [bins, room indices, seed xs, seed ys, squared radii].
var _bins_by_cell: Dictionary[Vector2i, Array] = {}


## null, with an error, when the plan is null or a macro cell exhausts its attempts. order lists the
## macro cells to build first; any order gives the same graph.
static func build(world_plan: WorldPlan, order: Array[Vector2i] = []) -> WorldGraph:
	return _build(world_plan, order, null, {})


## The World for a seed or, when that seed builds none, for the first seed that does in a fixed
## sequence rolled from it: one seed always reaches the same World, and its plan.world_seed names
## the seed that built. first_plan is the seed's plan when the caller already made it. null, with an
## error, only when the content has problems or every attempt fails.
static func generate(content: WorldContent, world_seed: int, first_plan: WorldPlan = null) -> WorldGraph:
	if not content.is_valid():
		push_error("can't generate a World from content with problems:\n" + content.report())
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var attempt_seed := world_seed
	for attempt in SEED_ATTEMPTS:
		var world_plan := first_plan if attempt == 0 and first_plan != null else WorldPlanner.plan(content, attempt_seed)
		var graph := build(world_plan)
		if graph != null:
			if attempt > 0:
				push_warning("World seed %d built no World; seed %d did" % [world_seed, attempt_seed])
			return graph
		attempt_seed = maxi(rng.randi(), 1)
	push_error("World seed %d: none of %d seeds built a World" % [world_seed, SEED_ATTEMPTS])
	return null


## Rebuilds only macro-cell graphs belonging to `invalidated_biomes`. The World-level joins, roles
## and sites are cheap and are joined again because they connect those independently cached cells.
## A changed World plan cannot reuse cells: their RoomPlan references and coordinates may differ.
static func rebuild(world_plan: WorldPlan, previous: WorldGraph,
		invalidated_biomes: Dictionary[StringName, bool]) -> WorldGraph:
	if previous == null or previous.plan != world_plan:
		return build(world_plan)
	return _build(world_plan, [], previous, invalidated_biomes)


static func _build(world_plan: WorldPlan, order: Array[Vector2i], previous: WorldGraph,
		invalidated_biomes: Dictionary[StringName, bool]) -> WorldGraph:
	if world_plan == null:
		return null
	var graph := WorldGraph.new()
	graph.plan = world_plan
	graph._noise_x = _warp_noise(world_plan.seed_for(WorldHash.NS_WARP, "border/x"))
	graph._noise_y = _warp_noise(world_plan.seed_for(WorldHash.NS_WARP, "border/y"))
	for id in world_plan.biomes:
		graph._strongest_warp = maxf(graph._strongest_warp, world_plan.biomes[id].resource.border_warp)
	var coords: Array[Vector2i] = order.duplicate()
	for coord in world_plan.cells:
		if not coords.has(coord):
			coords.append(coord)
	for coord in coords:
		var cell: MacroCellGraph = null
		var biome := world_plan.cells[coord].biome
		if previous != null and not invalidated_biomes.has(biome):
			cell = previous.cells.get(coord)
		else:
			cell = MacroCellGraph.build(world_plan, coord)
		if cell == null:
			return null
		graph.cells[coord] = cell
	for key in world_plan.rooms:
		var room := graph.cells[world_plan.rooms[key].cell].room(key)
		# Passage and site lists are World-level joins and must not survive from a reused graph.
		room.passages.clear()
		room.sites.clear()
		room.teaching = null
		room.index = graph.room_list.size()
		graph.rooms[key] = room
		graph.room_list.append(room)
	graph._index_set_pieces()
	for coord in world_plan.cells:
		for passage in graph.cells[coord].passages:
			graph._link(passage)
	graph._link_edges()
	for key in graph.passages:
		graph.passages[key].spot = graph.tile_of(graph.passages[key].point)
	RoomRoles.assign_rosters(graph)
	RoomRoles.teach(graph)
	RoomRoles.breathe(graph)
	var planner := SitePlanner.new(graph)
	if not planner.place():
		return null
	planner.place_weighted()
	return graph


## The Room owning a tile, or null outside every macro cell a Biome owns.
func owner_at(tile: Vector2i) -> GeneratedRoom:
	var index := owner_index_at(tile)
	return room_list[index] if index >= 0 else null


## The index in room_list of the Room owning a tile, or -1 outside every macro cell a Biome owns.
## Streaming calls it once per tile, so it works in scalars and keeps what it last looked up.
func owner_index_at(tile: Vector2i) -> int:
	_warp_xy(tile.x + 0.5, tile.y + 0.5)
	var px := _warped_x
	var py := _warped_y
	var cx := floori(px / WorldPlan.CELL)
	var cy := floori(py / WorldPlan.CELL)
	if cx != _bins_coord.x or cy != _bins_coord.y:
		_select_bins(Vector2i(cx, cy))
	if _bins.is_empty():
		return -1
	var bin: PackedInt32Array = _bins[mini(floori((py - cy * WorldPlan.CELL) / _BIN), _BINS - 1) * _BINS \
			+ mini(floori((px - cx * WorldPlan.CELL) / _BIN), _BINS - 1)]
	if bin.size() == 1:
		return _bin_rooms[bin[0]]
	var best := -1
	var best_distance := INF
	for n in bin:
		var dx := px - _bin_x[n]
		var dy := py - _bin_y[n]
		var distance := dx * dx + dy * dy - _bin_r2[n]
		if distance < best_distance:
			best_distance = distance
			best = _bin_rooms[n]
	return best


## Where a tile-space point falls in the unwarped power diagram.
func warp(point: Vector2) -> Vector2:
	_warp_xy(point.x, point.y)
	return Vector2(_warped_x, _warped_y)


## warp() in doubles, into _warped_x and _warped_y.
func _warp_xy(px: float, py: float) -> void:
	_warped_x = px
	_warped_y = py
	var u := px / WorldPlan.CELL - 0.5
	var v := py / WorldPlan.CELL - 0.5
	var i := floori(u)
	var j := floori(v)
	if i != _amplitude_lattice.x or j != _amplitude_lattice.y:
		_amplitude_lattice = Vector2i(i, j)
		_amplitude_corners[0] = _cell_warp(Vector2i(i, j))
		_amplitude_corners[1] = _cell_warp(Vector2i(i + 1, j))
		_amplitude_corners[2] = _cell_warp(Vector2i(i, j + 1))
		_amplitude_corners[3] = _cell_warp(Vector2i(i + 1, j + 1))
	var top := lerpf(_amplitude_corners[0], _amplitude_corners[1], u - i)
	var bottom := lerpf(_amplitude_corners[2], _amplitude_corners[3], u - i)
	var amplitude := lerpf(top, bottom, v - j)
	if amplitude <= 0.0:
		return
	var cx := floori(px / WorldPlan.CELL)
	var cy := floori(py / WorldPlan.CELL)
	if cx != _near_coord.x or cy != _near_coord.y:
		_near_coord = Vector2i(cx, cy)
		_near.clear()
		for special: GeneratedRoom in _set_pieces_near.get(_near_coord, []):
			_near.append_array([special.seed.x, special.seed.y, special.radius])
	for n in range(0, _near.size(), 3):
		var dx := px - _near[n]
		var dy := py - _near[n + 1]
		amplitude *= smoothstep(0.0, WARP_FALLOFF, sqrt(dx * dx + dy * dy) - _near[n + 2])
	if amplitude <= 0.0:
		return
	_warped_x = px + _noise_x.get_noise_2d(px, py) * amplitude
	_warped_y = py + _noise_y.get_noise_2d(px, py) * amplitude


## Builds every macro cell's ownership bins now rather than on its first tile: streaming calls this
## behind the loading frame so no frame pays for a whole cell's bins.
func prepare_bins() -> void:
	for coord in cells:
		if not _bins_by_cell.has(coord):
			_bins_by_cell[coord] = _build_bins(cells[coord])


## The furthest, along either axis, any tile warping onto a point of rect can have moved: noise moves
## each axis by at most the amplitude, which interpolates between macro-cell centres and so never
## passes the strongest cell around. Interiors size their bounds by it.
func warp_bound(rect: Rect2i) -> float:
	var reach := rect.grow(ceili(_strongest_warp))
	var first := Vector2i(floori(float(reach.position.x) / WorldPlan.CELL - 0.5), floori(float(reach.position.y) / WorldPlan.CELL - 0.5))
	var last := Vector2i(floori(float(reach.end.x) / WorldPlan.CELL - 0.5), floori(float(reach.end.y) / WorldPlan.CELL - 0.5)) + Vector2i.ONE
	var strongest := 0.0
	for j in range(first.y, last.y + 1):
		for i in range(first.x, last.x + 1):
			strongest = maxf(strongest, _cell_warp(Vector2i(i, j)))
	return strongest


## The tile whose warped centre lands nearest an unwarped point.
func tile_of(point: Vector2) -> Vector2i:
	var best := point
	var best_error := INF
	var guess := point
	for _step in _INVERSE_STEPS:
		var landed := warp(guess)
		var error := landed.distance_squared_to(point)
		if error < best_error:
			best_error = error
			best = guess
		if error < 0.01:
			break
		guess += point - landed
	return Vector2i((best - Vector2(0.5, 0.5)).round())


## Every Room reachable from the spawn through Passages, by key.
func reachable() -> Dictionary[String, bool]:
	var reached: Dictionary[String, bool] = {plan.spawn.key: true}
	var queue: Array[String] = [plan.spawn.key]
	var next := 0
	while next < queue.size():
		var room := rooms[queue[next]]
		next += 1
		for passage in room.passages:
			var other := passage.other(room.key())
			if not reached.has(other):
				reached[other] = true
				queue.append(other)
	return reached


## One line per macro cell, Room, Passage and site.
func describe() -> String:
	var lines: Array[String] = []
	var roles: Dictionary[StringName, int] = {}
	for key in rooms:
		roles[rooms[key].role_name()] = roles.get(rooms[key].role_name(), 0) + 1
	var kinds: Dictionary[StringName, int] = {}
	for key in passages:
		kinds[passages[key].kind_name()] = kinds.get(passages[key].kind_name(), 0) + 1
	lines.append("World seed %d: %d macro cells, %d Rooms %s, %d Passages %s, %d sites" % [plan.world_seed, cells.size(),
			rooms.size(), roles, passages.size(), kinds, sites.size()])
	for coord in plan.cells:
		var cell := cells[coord]
		lines.append("")
		lines.append("cell %s %s: %d Rooms in %d attempts" % [cell.cell.key, cell.cell.biome, cell.rooms.size(), cell.attempts])
		for room in cell.rooms:
			var links: Array[String] = []
			for passage in room.passages:
				links.append("%s %s" % [passage.kind_name(), passage.other(room.key())])
			lines.append("  %-26s %-9s %-10s C%-3d route %-3d seed %s%s -> %s" % [room.key(), room.role_name(), room.plan.zone,
					room.plan.challenge, room.plan.route_index, room.seed.round(),
					" teaches %s" % room.teaching.resource_path.get_file().get_basename() if room.teaching else "", ", ".join(links)])
			for site in room.sites:
				lines.append("    %s at %s%s" % [site.key, site.spot, _site_detail(site)])
	return "\n".join(lines)


func _site_detail(site: ObjectSite) -> String:
	match site.kind:
		ObjectSite.Kind.SIGN:
			return " reveals " + site.reveal_key
		ObjectSite.Kind.DOOR:
			return " to %s %s" % [site.destination_biome, site.landing_key]
		ObjectSite.Kind.WEIGHTED:
			return " " + site.scene.resource_path.get_file()
	return ""


func _link(passage: RoomPassage) -> void:
	passages[passage.key] = passage
	rooms[passage.a].passages.append(passage)
	rooms[passage.b].passages.append(passage)


## Route Passages across the folded path's edges and along each Side biome's cells, the attachment
## Passages, then shortcuts.
func _link_edges() -> void:
	for index in range(1, plan.path.size()):
		_link_across(cells[plan.path[index - 1]].route()[-1], cells[plan.path[index]].route()[0], RoomPassage.Kind.ROUTE)
	for side in plan.content.parents:
		var biome := plan.biomes[side]
		_link_across(rooms[biome.attachment.key], cells[biome.cells[0]].route()[0], RoomPassage.Kind.ATTACHMENT)
		for n in range(1, biome.cells.size()):
			_link_across(cells[biome.cells[n - 1]].route()[-1], cells[biome.cells[n]].route()[0], RoomPassage.Kind.ROUTE)
	for coord in plan.cells:
		for direction: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN]:
			if plan.cells.has(coord + direction):
				_maybe_shortcut(coord, direction)


func _link_across(a: GeneratedRoom, b: GeneratedRoom, kind: RoomPassage.Kind) -> void:
	var passage := RoomPassage.new()
	passage.key = RoomPassage.pair(a.key(), b.key())
	passage.a = passage.key.get_slice("|", 0)
	passage.b = passage.key.get_slice("|", 1)
	passage.kind = kind
	passage.point = MacroCellGraph.port_point(plan, a.plan.cell, b.plan.cell - a.plan.cell)
	passage.width = MacroCellGraph.edge_width(plan, a.plan.cell, b.plan.cell)
	_link(passage)


## At most one per edge, between Ideal-path cells the route doesn't already join, with odds the mean
## of the two cells' Biome shortcut values. It opens where two ordinary Rooms' spans of the edge
## overlap enough for its width.
func _maybe_shortcut(coord: Vector2i, direction: Vector2i) -> void:
	var a := plan.cells[coord]
	var b := plan.cells[coord + direction]
	if a.path_index < 0 or b.path_index < 0 or absi(a.path_index - b.path_index) <= 1:
		return
	var rng := plan.rng(WorldHash.NS_PASSAGES, "shortcut/" + RoomPassage.pair(a.key, b.key))
	var odds := (plan.biomes[a.biome].resource.shortcuts + plan.biomes[b.biome].resource.shortcuts) / 2.0
	if rng.randf() >= odds:
		return
	var width := MacroCellGraph.edge_width(plan, a.coord, b.coord)
	var options: Array[Array] = []
	for room_a in cells[a.coord].rooms:
		if not room_a.is_ordinary():
			continue
		var span_a := MacroCellGraph.exposure(room_a, a.coord, direction)
		for room_b in cells[b.coord].rooms:
			if not room_b.is_ordinary():
				continue
			var span_b := MacroCellGraph.exposure(room_b, b.coord, -direction)
			var from := maxf(span_a.x, span_b.x)
			var to := minf(span_a.y, span_b.y)
			if to - from >= width + 2 * MacroCellGraph.BORDER_SLACK:
				options.append([room_a, room_b, (from + to) / 2.0])
	if options.is_empty():
		return
	var choice: Array = options[rng.randi_range(0, options.size() - 1)]
	var passage := RoomPassage.new()
	passage.key = RoomPassage.pair(choice[0].key(), choice[1].key())
	passage.a = passage.key.get_slice("|", 0)
	passage.b = passage.key.get_slice("|", 1)
	passage.kind = RoomPassage.Kind.SHORTCUT
	passage.width = width
	passage.point = Vector2(b.coord * WorldPlan.CELL)
	if direction == Vector2i.RIGHT:
		passage.point.y = choice[2]
	else:
		passage.point.x = choice[2]
	_link(passage)


func _index_set_pieces() -> void:
	for coord in plan.cells:
		var near: Array[GeneratedRoom] = []
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var cell: MacroCellGraph = cells.get(coord + Vector2i(dx, dy))
				if cell != null:
					near.append_array(cell.rooms.filter(func(room: GeneratedRoom) -> bool: return room.is_set_piece()))
		_set_pieces_near[coord] = near


func _cell_warp(coord: Vector2i) -> float:
	var cell: MacroCellPlan = plan.cells.get(coord)
	return plan.biomes[cell.biome].resource.border_warp if cell != null else 0.0


## Smooth value noise in [-1, 1] on a WARP_SCALE lattice.
static func _warp_noise(unit_seed: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_VALUE
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0 / WARP_SCALE
	noise.seed = unit_seed & 0x7fffffff
	return noise


func _select_bins(coord: Vector2i) -> void:
	_bins_coord = coord
	var cell: MacroCellGraph = cells.get(coord)
	if cell == null:
		_bins = []
		return
	if not _bins_by_cell.has(coord):
		_bins_by_cell[coord] = _build_bins(cell)
	var entry: Array = _bins_by_cell[coord]
	_bins = entry[0]
	_bin_rooms = entry[1]
	_bin_x = entry[2]
	_bin_y = entry[3]
	_bin_r2 = entry[4]


## For each bin of a macro cell, the indices into its Rooms whose power distance can be least
## somewhere in the bin, in the cell's order so ties resolve as a full scan would; then the Rooms'
## indices, seeds and squared radii.
func _build_bins(cell: MacroCellGraph) -> Array:
	var bins: Array[PackedInt32Array] = []
	var indices := PackedInt32Array()
	var xs := PackedFloat64Array()
	var ys := PackedFloat64Array()
	var r2s := PackedFloat64Array()
	for room in cell.rooms:
		indices.append(room.index)
		xs.append(room.seed.x)
		ys.append(room.seed.y)
		r2s.append(room.radius * room.radius)
	var reach := _BIN * sqrt(2.0) * 0.5
	var origin := cell.cell.coord * WorldPlan.CELL
	for by in _BINS:
		for bx in _BINS:
			var centre_x := origin.x + (bx + 0.5) * _BIN
			var centre_y := origin.y + (by + 0.5) * _BIN
			var lows := PackedFloat64Array()
			var least_high := INF
			for n in xs.size():
				var distance := sqrt((centre_x - xs[n]) * (centre_x - xs[n]) + (centre_y - ys[n]) * (centre_y - ys[n]))
				var near := maxf(distance - reach, 0.0)
				lows.append(near * near - r2s[n])
				least_high = minf(least_high, (distance + reach) * (distance + reach) - r2s[n])
			var bin := PackedInt32Array()
			for n in xs.size():
				if lows[n] <= least_high + 0.01:
					bin.append(n)
			bins.append(bin)
	return [bins, indices, xs, ys, r2s]
