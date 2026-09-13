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
const _INVERSE_STEPS := 16

var plan: WorldPlan
var cells: Dictionary[Vector2i, MacroCellGraph] = {}
## Every Room by key, in plan order.
var rooms: Dictionary[String, GeneratedRoom] = {}
## Every Passage by key.
var passages: Dictionary[String, RoomPassage] = {}
## Every Object site and landing by key.
var sites: Dictionary[String, ObjectSite] = {}
## Macro cell -> the set pieces in it and its eight neighbours, for the warp's falloff.
var _set_pieces_near: Dictionary[Vector2i, Array] = {}
var _warp_seed := 0


## null, with an error, when the plan is null or a macro cell exhausts its attempts. order lists the
## macro cells to build first; any order gives the same graph.
static func build(world_plan: WorldPlan, order: Array[Vector2i] = []) -> WorldGraph:
	if world_plan == null:
		return null
	var graph := WorldGraph.new()
	graph.plan = world_plan
	graph._warp_seed = world_plan.seed_for(WgHash.NS_WARP, "border")
	var coords: Array[Vector2i] = order.duplicate()
	for coord in world_plan.cells:
		if not coords.has(coord):
			coords.append(coord)
	for coord in coords:
		var cell := MacroCellGraph.build(world_plan, coord)
		if cell == null:
			return null
		graph.cells[coord] = cell
	for key in world_plan.rooms:
		graph.rooms[key] = graph.cells[world_plan.rooms[key].cell].room(key)
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
	var point := warp(Vector2(tile) + Vector2(0.5, 0.5))
	var cell: MacroCellGraph = cells.get(Vector2i((point / WorldPlan.CELL).floor()))
	if cell == null:
		return null
	var best: GeneratedRoom
	var best_distance := INF
	for room in cell.rooms:
		var distance := point.distance_squared_to(room.seed) - room.radius * room.radius
		if distance < best_distance:
			best_distance = distance
			best = room
	return best


## Where a tile-space point falls in the unwarped power diagram.
func warp(point: Vector2) -> Vector2:
	var u := point.x / WorldPlan.CELL - 0.5
	var v := point.y / WorldPlan.CELL - 0.5
	var i := floori(u)
	var j := floori(v)
	var top := lerpf(_cell_warp(Vector2i(i, j)), _cell_warp(Vector2i(i + 1, j)), u - i)
	var bottom := lerpf(_cell_warp(Vector2i(i, j + 1)), _cell_warp(Vector2i(i + 1, j + 1)), u - i)
	var amplitude := lerpf(top, bottom, v - j)
	if amplitude <= 0.0:
		return point
	for special: GeneratedRoom in _set_pieces_near.get(Vector2i((point / WorldPlan.CELL).floor()), []):
		amplitude *= smoothstep(0.0, WARP_FALLOFF, point.distance_to(special.seed) - special.radius)
	if amplitude <= 0.0:
		return point
	return point + Vector2(_noise(point, 0), _noise(point, 1)) * amplitude


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
	var rng := plan.rng(WgHash.NS_PASSAGES, "shortcut/" + RoomPassage.pair(a.key, b.key))
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


## Smooth value noise in [-1, 1].
func _noise(point: Vector2, axis: int) -> float:
	var x := point.x / WARP_SCALE
	var y := point.y / WARP_SCALE
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_lattice(ix, iy, axis), _lattice(ix + 1, iy, axis), fx),
			lerpf(_lattice(ix, iy + 1, axis), _lattice(ix + 1, iy + 1, axis), fx), fy)


func _lattice(ix: int, iy: int, axis: int) -> float:
	var h := WgHash.splitmix64(_warp_seed ^ WgHash.splitmix64(ix * 73856093 ^ iy * 19349663 ^ axis * 83492791))
	return float(h & 0xFFFF) / 32767.5 - 1.0
