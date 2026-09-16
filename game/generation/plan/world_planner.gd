class_name WorldPlanner
extends RefCounted
## Plans the complete World from valid content and a World seed, before any geometry:
##
##   1. Each Biome orders its Zones by seed, the Spawn zone first, and lays their route Rooms end to
##      end; the spawn is the first. It reserves its set pieces as World-plan entries (the Boss near
##      the end of its final Zone, Minibosses late in their Zones, Rares anywhere in theirs), then
##      fills each Zone's room_count with ordinary off-route Rooms joining its route evenly.
##   2. The Biome's Room footprints size its stretch of macro cells, and its route is cut into that
##      many contiguous pieces of about equal footprint.
##   3. Each Ideal-path parent attaches its Side biomes at seeded interior route Rooms, apart from one
##      another and from its entrance and exit.
##   4. The Ideal path's cells fold through a grid, each Side biome's cells branching off its
##      attachment's cell, and each cell takes its irregular outline (MacroLattice).
##   5. Challenge rises along each route; off-route Rooms take their join's.
##
## Each step draws from its own RNG, seeded from the World seed, a namespace and a place key, so no
## step depends on another's draws.

const CELL_AREA := WorldPlan.CELL * WorldPlan.CELL
## The fold starts on a grid with this much more room than the cells need, and grows it by a row and
## a column after that many failed attempts.
const GRID_SLACK := 1.3
const FOLD_ATTEMPTS := 4
const FOLD_GROWTH := 32
## Cells an attempt may try per cell it must place before giving up.
const FOLD_BUDGET := 200
## How far chance loosens the fold's preference for hugging cells already placed.
const FOLD_JITTER := 1.25
## Attachment positions a parent draws, keeping the first where no attachment shares a route Room
## with a set piece, lies within ATTACHMENT_CELL_SLACK route Rooms of its cell's first or last, or
## shares a macro cell with another; otherwise the draw with the fewest such conflicts.
const ATTACHMENT_DRAWS := 64
const ATTACHMENT_CELL_SLACK := 3
## A macro cell's set pieces may claim this share of it, each a square around its protected disc.
const SET_PIECE_SHARE := 0.5
## How many set pieces may move to another cell before a Biome's stretch is left as it is.
const SET_PIECE_MOVES := 8

const _STEPS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]

var _plan := WorldPlan.new()
var _content: WorldContent
## Biome id -> route index -> the index in its Biome's cells of the cell holding that route Room.
var _stretches: Dictionary[StringName, PackedInt32Array] = {}
## Biome id -> route indices a set piece or the spawn already takes.
var _joined: Dictionary[StringName, Dictionary] = {}
## The fold places one cell per step: its Biome, its index in the Biome's cells, the step whose cell
## it borders (-1 for the first), and how many later steps border it.
var _step_biomes: Array[StringName] = []
var _step_stretches := PackedInt32Array()
var _step_anchors := PackedInt32Array()
var _step_needs := PackedInt32Array()
var _positions: Array[Vector2i] = []


## null, with an error, when the content has problems.
static func plan(content: WorldContent, world_seed: int, radii: Dictionary[StringName, int] = WorldPlan.DEFAULT_RADII) -> WorldPlan:
	if not content.is_valid():
		push_error("can't plan a World from content with problems:\n" + content.report())
		return null
	var planner := WorldPlanner.new()
	planner._content = content
	planner._plan.content = content
	planner._plan.world_seed = world_seed
	planner._plan.radii.assign(WorldPlan.DEFAULT_RADII)
	planner._plan.radii.merge(radii, true)
	for id in content.biome_ids():
		planner._plan_biome(id)
	for id in content.ideal_path:
		planner._attach_side_biomes(id)
	if not planner._fold():
		return null
	planner._place()
	planner._plan.lattice = MacroLattice.new(planner._plan)
	planner._rise()
	return planner._plan


# --- Biomes and Zones -----------------------------------------------------------------------------


func _plan_biome(id: StringName) -> void:
	var biome := BiomePlan.new()
	biome.id = id
	biome.resource = _content.biomes[id]
	biome.parent = _content.parents.get(id, &"")
	_plan.biomes[id] = biome
	var taken: Dictionary[int, bool] = {}
	_joined[id] = taken
	for zone_id in _zone_order(id):
		var zone := ZonePlan.new()
		zone.id = zone_id
		zone.biome = id
		zone.resource = _content.zones[id][zone_id]
		zone.order = biome.zones.size()
		zone.route_start = biome.route.size()
		biome.zones.append(zone)
		for _n in zone.resource.route_rooms:
			var room := _add_room(biome, zone, RoomPlan.Kind.ORDINARY)
			room.route_index = biome.route.size()
			room.join_index = room.route_index
			biome.route.append(room)
	if _content.spawn_zone == "%s/%s" % [id, biome.zones[0].id]:
		_plan.spawn = biome.route[0]
		_plan.spawn.kind = RoomPlan.Kind.SPAWN
		_plan.spawn.key = "spawn"
		taken[0] = true
	_reserve_set_pieces(biome)
	for zone in biome.zones:
		_fill_zone(biome, zone)
	_cut_stretch(biome)
	_separate_set_pieces(biome)


## Seeded, with the Spawn zone first.
func _zone_order(id: StringName) -> Array[StringName]:
	var order := _content.zone_ids(id)
	var spawn := &""
	if _content.spawn_zone.get_slice("/", 0) == id:
		spawn = StringName(_content.spawn_zone.get_slice("/", 1))
		order.erase(spawn)
	_shuffle(order, _plan.rng(WorldHash.NS_ZONE_ORDER, id))
	if spawn != &"":
		order.push_front(spawn)
	return order


func _add_room(biome: BiomePlan, zone: ZonePlan, kind: RoomPlan.Kind) -> RoomPlan:
	var room := RoomPlan.new()
	room.kind = kind
	room.biome = biome.id
	room.zone = zone.id
	zone.rooms.append(room)
	biome.rooms.append(room)
	return room


func _reserve_set_pieces(biome: BiomePlan) -> void:
	var taken: Dictionary = _joined[biome.id]
	var final := biome.zones[-1]
	var end := biome.route.size() - 1
	biome.boss = _add_set_piece(biome, final, RoomPlan.Kind.BOSS, biome.resource.boss, "boss/%s" % biome.id,
			_free_join(taken, end, final.route_start, end, true))
	for zone in biome.zones:
		var low := zone.route_start
		var high := zone.route_end() - 1
		var minibosses := zone.resource.minibosses
		# Late: spread over the Zone's later half, the first at its end.
		var late := ceili(zone.resource.route_rooms / 2.0)
		for n in minibosses.size():
			@warning_ignore("integer_division") # Whole counts and grid indices intentionally truncate.
			_add_set_piece(biome, zone, RoomPlan.Kind.MINIBOSS, minibosses[n], "miniboss/%s/%s/%d" % [biome.id, zone.id, n],
					_free_join(taken, high - n * late / minibosses.size(), low, high, true))
		var rng := _plan.rng(WorldHash.NS_SET_PIECES, "%s/%s" % [biome.id, zone.id])
		var rares := zone.resource.rares
		for n in rares.size():
			_add_set_piece(biome, zone, RoomPlan.Kind.RARE, rares[n], "rare/%s/%s/%d" % [biome.id, zone.id, n],
					_free_join(taken, rng.randi_range(low, high), low, high, false))


func _add_set_piece(biome: BiomePlan, zone: ZonePlan, kind: RoomPlan.Kind, encounter: FixedEncounterResource,
		key: String, join: int) -> RoomPlan:
	var room := _add_room(biome, zone, kind)
	room.key = key
	room.encounter = encounter
	room.join_index = join
	return room


## The route index in [low, high] nearest preferred that no set piece takes yet, searching earlier
## Rooms first when late, and takes it. preferred when every one is taken.
func _free_join(taken: Dictionary, preferred: int, low: int, high: int, late: bool) -> int:
	var order: Array[int] = []
	if late:
		order.assign(range(preferred, low - 1, -1) + range(preferred + 1, high + 1))
	else:
		for distance in high - low + 1:
			for index in [preferred - distance, preferred + distance]:
				if index >= low and index <= high and not order.has(index):
					order.append(index)
	for index in order:
		if not taken.has(index):
			taken[index] = true
			return index
	return preferred


## Fills the rest of the Zone's room_count with ordinary off-route Rooms joining its route evenly.
func _fill_zone(biome: BiomePlan, zone: ZonePlan) -> void:
	var ordinary := zone.resource.room_count - zone.rooms.size()
	for n in ordinary:
		var room := _add_room(biome, zone, RoomPlan.Kind.ORDINARY)
		@warning_ignore("integer_division") # Whole counts and grid indices intentionally truncate.
		room.join_index = zone.route_start + (2 * n + 1) * zone.resource.route_rooms / (2 * ordinary)


## Sizes the Biome's stretch of cells from its Rooms' footprints, never packing them tighter than
## their room size, and cuts its route into one contiguous piece per cell, of about equal footprint
## with their off-route Rooms. The count is capped so each cell's route Rooms can still cross it:
## about the square root of its Rooms. Each cell takes at least two route Rooms where the route
## has them, so its entry and exit fall to different Rooms.
func _cut_stretch(biome: BiomePlan) -> void:
	var route := biome.route.size()
	var weights := PackedInt64Array()
	weights.resize(route)
	var area := 0
	for room in biome.rooms:
		var footprint := _footprint(biome.resource, room.kind)
		weights[room.join_index] += footprint
		area += footprint
	@warning_ignore("integer_division") # Whole counts and grid indices intentionally truncate.
	var count := clampi((area + CELL_AREA - 1) / CELL_AREA, 1, maxi(1, route * route / biome.rooms.size()))
	var run := 2 if route >= 2 * count else 1
	var stretch := PackedInt32Array()
	stretch.resize(route)
	var cell := 0
	var cell_start := 0
	var before := 0
	for index in route:
		var later_cells := count - 1 - cell
		if later_cells > 0 and index - cell_start >= run and (before * count >= area * (cell + 1) or route - index <= later_cells * run):
			cell += 1
			cell_start = index
		stretch[index] = cell
		before += weights[index]
	_stretches[biome.id] = stretch
	biome.cells.resize(count)


## Moves set pieces out of macro cells too small for all their discs, one at a time, to the nearest
## free route position of a cell with room, inside the window their reservation allowed: a Boss in
## its final Zone's later half, a Miniboss in its Zone's later half, a Rare anywhere in its Zone. The
## stretch is recut after each move, since footprints follow joins.
func _separate_set_pieces(biome: BiomePlan) -> void:
	var taken: Dictionary = _joined[biome.id]
	var capacity := CELL_AREA * SET_PIECE_SHARE
	for _move in SET_PIECE_MOVES:
		var stretch := _stretches[biome.id]
		var cell_load: Dictionary[int, int] = {}
		for room in biome.rooms:
			if room.kind != RoomPlan.Kind.ORDINARY and room.kind != RoomPlan.Kind.SPAWN:
				cell_load[stretch[room.join_index]] = cell_load.get(stretch[room.join_index], 0) + _disc_square(room)
		var moved := false
		for room in biome.rooms:
			if room.kind == RoomPlan.Kind.ORDINARY or room.kind == RoomPlan.Kind.SPAWN:
				continue
			var cell := stretch[room.join_index]
			if cell_load[cell] <= capacity or cell_load[cell] == _disc_square(room):
				continue
			var window := _set_piece_window(biome, room)
			var best := -1
			for index in range(window.x, window.y + 1):
				if taken.has(index) or stretch[index] == cell or cell_load.get(stretch[index], 0) + _disc_square(room) > capacity:
					continue
				if best < 0 or absi(index - room.join_index) < absi(best - room.join_index):
					best = index
			if best >= 0:
				taken.erase(room.join_index)
				taken[best] = true
				room.join_index = best
				moved = true
				break
		if not moved:
			return
		_cut_stretch(biome)


## The square around a set piece's protected disc, with a margin for the Rooms beside it.
func _disc_square(room: RoomPlan) -> int:
	return disc_square(_plan.radii[room.kind_name()])


## The square around a protected disc of that radius, with a margin for the Rooms beside it.
static func disc_square(radius: int) -> int:
	var side := 2 * radius + 6
	return side * side


## The route positions a set piece may join, as (first, last).
func _set_piece_window(biome: BiomePlan, room: RoomPlan) -> Vector2i:
	var zone := biome.zone(room.zone)
	match room.kind:
		RoomPlan.Kind.BOSS:
			return Vector2i(zone.route_end() - ceili(zone.resource.route_rooms / 2.0), zone.route_end() - 1)
		RoomPlan.Kind.MINIBOSS:
			return Vector2i(ceili((zone.route_start + zone.route_end() - 1) / 2.0), zone.route_end() - 1)
	return Vector2i(zone.route_start, zone.route_end() - 1)


## Tiles a Room claims: an ordinary Room's square of room_size, or a set piece's protected disc when
## that is larger.
func _footprint(biome: BiomeResource, kind: RoomPlan.Kind) -> int:
	var ordinary := biome.room_size * biome.room_size
	if kind == RoomPlan.Kind.ORDINARY:
		return ordinary
	var radius := _plan.radii[RoomPlan.KIND_NAMES[kind]]
	return maxi(ordinary, roundi(PI * radius * radius))


# --- Side-biome attachments -----------------------------------------------------------------------


func _attach_side_biomes(parent_id: StringName) -> void:
	var sides: Array[StringName] = []
	for side in _content.parents:
		if _content.parents[side] == parent_id:
			sides.append(side)
	if sides.is_empty():
		return
	var rng := _plan.rng(WorldHash.NS_ATTACHMENTS, parent_id)
	_shuffle(sides, rng)
	var parent := _plan.biomes[parent_id]
	var stretch := _stretches[parent_id]
	var margin := WorldContent.ATTACHMENT_MARGIN
	var spacing := WorldContent.ATTACHMENT_SPACING
	# Validation keeps this at 0 or more.
	var slack := parent.route.size() - 1 - 2 * margin - (sides.size() - 1) * spacing
	var best := PackedInt32Array()
	var best_score := -1
	for _draw in ATTACHMENT_DRAWS:
		var offsets: Array[int] = []
		for _n in sides.size():
			offsets.append(rng.randi_range(0, slack))
		offsets.sort()
		var positions := PackedInt32Array()
		var per_cell: Dictionary[int, int] = {}
		var score := 0
		for n in offsets.size():
			var position := margin + offsets[n] + n * spacing
			positions.append(position)
			per_cell[stretch[position]] = per_cell.get(stretch[position], 0) + 1
			if _joined[parent_id].has(position):
				score += 1
			# Near either end of its cell's route, the route has few Rooms to reach that end's port from
			# the attachment's edge.
			var inside := 0
			while inside < ATTACHMENT_CELL_SLACK and position - inside - 1 >= 0 and position + inside + 1 < stretch.size() \
					and stretch[position - inside - 1] == stretch[position] and stretch[position + inside + 1] == stretch[position]:
				inside += 1
			score += ATTACHMENT_CELL_SLACK - inside
			# Two attachments beside a cell's entry and exit can leave its route no planar way through.
			if per_cell[stretch[position]] > 1:
				score += sides.size()
		if best_score < 0 or score < best_score:
			best = positions
			best_score = score
		if score == 0:
			break
	for n in sides.size():
		_plan.biomes[sides[n]].attachment = parent.route[best[n]]


# --- Folding the macro grid -----------------------------------------------------------------------


func _fold() -> bool:
	var last_ideal := -1
	for id in _content.ideal_path:
		for stretch in _plan.biomes[id].cells.size():
			last_ideal = _add_step(id, stretch, last_ideal)
			for side in _sides_at(id, stretch):
				var anchor := last_ideal
				for side_stretch in _plan.biomes[side].cells.size():
					anchor = _add_step(side, side_stretch, anchor)
	var count := _step_anchors.size()
	var width := ceili(sqrt(count * GRID_SLACK))
	var height := ceili(count * GRID_SLACK / width)
	for _growth in FOLD_GROWTH:
		for attempt in FOLD_ATTEMPTS:
			if _embed(Vector2i(width, height), _plan.rng(WorldHash.NS_MACRO_PATH, "%dx%d/%d" % [width, height, attempt])):
				return true
		width += 1
		height += 1
	push_error("no fold of %d macro cells fits a %d x %d grid" % [count, width, height])
	return false


## The Side biomes attaching in one of a parent's cells, in route order.
func _sides_at(parent_id: StringName, stretch: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for side in _content.parents:
		if _content.parents[side] == parent_id and _stretches[parent_id][_plan.biomes[side].attachment.route_index] == stretch:
			out.append(side)
	out.sort_custom(func(a: StringName, b: StringName) -> bool:
		return _plan.biomes[a].attachment.route_index < _plan.biomes[b].attachment.route_index)
	return out


func _add_step(biome_id: StringName, stretch: int, anchor: int) -> int:
	_step_biomes.append(biome_id)
	_step_stretches.append(stretch)
	_step_anchors.append(anchor)
	_step_needs.append(0)
	if anchor >= 0:
		_step_needs[anchor] += 1
	return _step_anchors.size() - 1


## Places each step's cell beside its anchor's without overlap, backtracking from dead ends within a
## budget. It tries the free cell with the fewest free neighbours first, which hugs the cells already
## placed and folds the path back alongside itself.
func _embed(grid: Vector2i, rng: RandomNumberGenerator) -> bool:
	var count := _step_anchors.size()
	var used := PackedByteArray()
	used.resize(grid.x * grid.y)
	_positions.resize(count)
	var options: Array[Array] = []
	options.resize(count)
	var everywhere: Array[Vector2i] = []
	for y in grid.y:
		for x in grid.x:
			everywhere.append(Vector2i(x, y))
	options[0] = _ordered(everywhere, used, grid, _step_needs[0], rng)
	var step := 0
	for _try in FOLD_BUDGET * count:
		if options[step].is_empty():
			if step == 0:
				return false
			step -= 1
			used[_positions[step].y * grid.x + _positions[step].x] = 0
			continue
		var cell: Vector2i = options[step].pop_back()
		_positions[step] = cell
		used[cell.y * grid.x + cell.x] = 1
		step += 1
		if step == count:
			return true
		var anchor := _positions[_step_anchors[step]]
		var beside: Array[Vector2i] = []
		for offset in _STEPS:
			beside.append(anchor + offset)
		options[step] = _ordered(beside, used, grid, _step_needs[step], rng)
	return false


## The free cells in the grid with room beside them for the steps bordering this one, best last.
func _ordered(cells: Array[Vector2i], used: PackedByteArray, grid: Vector2i, needs: int, rng: RandomNumberGenerator) -> Array:
	var scored: Array = []
	for cell in cells:
		if _is_free(cell, used, grid):
			var free := 0
			for offset in _STEPS:
				if _is_free(cell + offset, used, grid):
					free += 1
			if free >= needs:
				scored.append([free + rng.randf() * FOLD_JITTER, cell])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return scored.map(func(entry: Array) -> Vector2i: return entry[1])


static func _is_free(cell: Vector2i, used: PackedByteArray, grid: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < grid.x and cell.y < grid.y and used[cell.y * grid.x + cell.x] == 0


# --- Cells, Rooms and Challenge -------------------------------------------------------------------


func _place() -> void:
	var low := _positions[0]
	var high := _positions[0]
	for position in _positions:
		low = low.min(position)
		high = high.max(position)
	_plan.size = high - low + Vector2i.ONE
	for step in _positions.size():
		var biome := _plan.biomes[_step_biomes[step]]
		var cell := MacroCellPlan.new()
		cell.coord = _positions[step] - low
		cell.key = "%d,%d" % [cell.coord.x, cell.coord.y]
		cell.biome = biome.id
		cell.stretch_index = _step_stretches[step]
		biome.cells[cell.stretch_index] = cell.coord
		_plan.cells[cell.coord] = cell
		if not biome.is_side():
			cell.path_index = _plan.path.size()
			_plan.path.append(cell.coord)
	for index in _plan.path.size():
		var cell := _plan.cells[_plan.path[index]]
		if index > 0:
			cell.entry = _plan.path[index - 1] - cell.coord
		if index < _plan.path.size() - 1:
			cell.exit = _plan.path[index + 1] - cell.coord
	for side in _content.parents:
		var biome := _plan.biomes[side]
		var before := _plan.biomes[biome.parent].cells[_stretches[biome.parent][biome.attachment.route_index]]
		for n in biome.cells.size():
			var cell := _plan.cells[biome.cells[n]]
			cell.entry = before - cell.coord
			before = cell.coord
			if n < biome.cells.size() - 1:
				cell.exit = biome.cells[n + 1] - cell.coord
	for id in _plan.biomes:
		var biome := _plan.biomes[id]
		for room in biome.rooms:
			var cell := _plan.cells[biome.cells[_stretches[id][room.join_index]]]
			room.cell = cell.coord
			if room.kind == RoomPlan.Kind.ORDINARY:
				room.key = "%s/%d" % [cell.key, cell.rooms.size()]
			cell.rooms.append(room)
			_plan.rooms[room.key] = room


func _rise() -> void:
	var entry := 0
	for id in _content.ideal_path:
		_rise_route(_plan.biomes[id], entry)
		entry = _plan.biomes[id].resource.exit_challenge
	for side in _content.parents:
		_rise_route(_plan.biomes[side], _plan.biomes[side].attachment.challenge)


## Rounds a straight rise from entry at the first route Room to the Biome's exit at the last.
func _rise_route(biome: BiomePlan, entry: int) -> void:
	biome.entry_challenge = entry
	var last := biome.route.size() - 1
	var climb := biome.resource.exit_challenge - entry
	for room in biome.route:
		@warning_ignore("integer_division") # Whole counts and grid indices intentionally truncate.
		room.challenge = entry if last == 0 else entry + (2 * climb * room.route_index + last) / (2 * last)
	for room in biome.rooms:
		room.challenge = biome.route[room.join_index].challenge


static func _shuffle(items: Array, rng: RandomNumberGenerator) -> void:
	for index in range(items.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var swap: Variant = items[index]
		items[index] = items[other]
		items[other] = swap
