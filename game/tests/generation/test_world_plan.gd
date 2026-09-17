extends Node
## Headless tests for the World plan, through its public output: macro cells and the folded path,
## seeded Zone order and exact quotas, set-piece entries, Side-biome attachments, Challenge and keys,
## on the shipped World at three seeds and on the small fixture; the same seed plans the same World
## however many plans come between; seeds vary what they should; and Room-size and radius extremes
## still plan. Run:
##   godot --headless --path game res://tests/generation/test_world_plan.tscn

const VARIATION_SEEDS := 12

var _fails: Array[String] = []


func _ready() -> void:
	var shipped := WorldFixture.shipped()
	var small := WorldFixture.small()
	_check(shipped.content.is_valid() and small.content.is_valid(), "test Worlds have content problems")
	for fixture: WorldFixture in [shipped, small]:
		for world_seed in fixture.seeds:
			_check_plan(fixture.plan(world_seed), "%s seed %d" % [fixture.content.root.get_base_dir().get_file(), world_seed])
	_test_repeated_builds(shipped)
	_test_seeds_vary(shipped)
	_test_extremes(small)
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails.slice(0, 40):
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


static func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


func _check_plan(plan: WorldPlan, label: String) -> void:
	if plan == null:
		_fails.append("%s: planned nothing" % label)
		return
	_check_cells(plan, label)
	_check_quotas(plan, label)
	_check_set_pieces(plan, label)
	_check_attachments(plan, label)
	_check_challenge(plan, label)


## Every Biome owns a contiguous stretch of cells no other Biome shares. The Ideal path folds through
## its Biomes' stretches in order; each Side biome branches off its attachment's cell.
func _check_cells(plan: WorldPlan, label: String) -> void:
	var owned := 0
	var listed := 0
	for id in plan.biomes:
		var biome := plan.biomes[id]
		owned += biome.cells.size()
		_check(not biome.cells.is_empty(), "%s: %s has no macro cells" % [label, id])
		for n in biome.cells.size():
			var cell: MacroCellPlan = plan.cells.get(biome.cells[n])
			if cell == null:
				_fails.append("%s: %s's cell %s isn't in the plan" % [label, id, biome.cells[n]])
				continue
			listed += cell.rooms.size()
			_check(Rect2i(Vector2i.ZERO, plan.size).has_point(cell.coord), "%s: cell %s lies outside the %s grid" % [label, cell.key, plan.size])
			_check(cell.biome == id and cell.stretch_index == n, "%s: %s's cell %d is %s's cell %d" % [label, id, n, cell.biome, cell.stretch_index])
			_check(cell.key == "%d,%d" % [cell.coord.x, cell.coord.y], "%s: cell %s has key %s" % [label, cell.coord, cell.key])
			_check(cell.rooms.any(func(room: RoomPlan) -> bool: return room.is_on_route()), "%s: cell %s holds no route Room" % [label, cell.key])
	_check(owned == plan.cells.size(), "%s: Biomes list %d cells but the plan has %d" % [label, owned, plan.cells.size()])
	_check(listed == plan.rooms.size(), "%s: cells list %d Rooms but the plan has %d" % [label, listed, plan.rooms.size()])
	var expected: Array[Vector2i] = []
	for id in plan.content.ideal_path:
		expected.append_array(plan.biomes[id].cells)
	_check(plan.path == expected, "%s: the path doesn't run through the Ideal path's Biomes' cells in order" % label)
	for index in plan.path.size():
		var cell := plan.cells[plan.path[index]]
		var entry := plan.path[index - 1] - cell.coord if index > 0 else Vector2i.ZERO
		var exit := plan.path[index + 1] - cell.coord if index < plan.path.size() - 1 else Vector2i.ZERO
		_check(cell.path_index == index and cell.entry == entry and cell.exit == exit,
				"%s: path cell %d (%s) has index %d, entry %s, exit %s" % [label, index, cell.key, cell.path_index, cell.entry, cell.exit])
		if index > 0:
			_check(_adjacent(plan.path[index - 1], cell.coord), "%s: path cells %s and %s share no edge" % [label, plan.path[index - 1], cell.coord])
	for side in plan.content.parents:
		var biome := plan.biomes[side]
		if biome.attachment == null:
			continue
		var before := biome.attachment.cell
		for n in biome.cells.size():
			var cell := plan.cells[biome.cells[n]]
			var exit := biome.cells[n + 1] - cell.coord if n < biome.cells.size() - 1 else Vector2i.ZERO
			_check(_adjacent(before, cell.coord) and cell.entry == before - cell.coord and cell.exit == exit and cell.path_index == -1,
					"%s: %s's cell %d (%s) doesn't continue its branch from %s" % [label, side, n, cell.key, before])
			before = cell.coord


## Zones take a seeded order with the Spawn zone first, and carry their exact quotas: route Rooms end
## to end along the Biome's route, and room_count Rooms joining the route inside the Zone.
func _check_quotas(plan: WorldPlan, label: String) -> void:
	var content := plan.content
	var total := 0
	for id in content.biome_ids():
		var biome: BiomePlan = plan.biomes.get(id)
		if biome == null:
			_fails.append("%s: Biome %s isn't planned" % [label, id])
			continue
		total += biome.rooms.size()
		var order: Array[StringName] = []
		for zone in biome.zones:
			order.append(zone.id)
		var zone_ids := content.zone_ids(id)
		_check(order.size() == zone_ids.size() and zone_ids.all(func(zone_id: StringName) -> bool: return order.has(zone_id)),
				"%s: %s orders Zones %s, not its Zone files %s" % [label, id, order, zone_ids])
		if content.spawn_zone.get_slice("/", 0) == id:
			_check(order[0] == StringName(content.spawn_zone.get_slice("/", 1)), "%s: %s's Zone order %s doesn't start at the Spawn zone" % [label, id, order])
		_check(biome.route.size() == content.route_rooms(id), "%s: %s has %d route Rooms, its Zones %d" % [label, id, biome.route.size(), content.route_rooms(id)])
		_check(biome.rooms.size() == content.room_count(id), "%s: %s has %d Rooms, its Zones %d" % [label, id, biome.rooms.size(), content.room_count(id)])
		var route_start := 0
		for n in biome.zones.size():
			var zone := biome.zones[n]
			var resource: ZoneResource = content.zones[id][zone.id]
			var where := "%s/%s" % [id, zone.id]
			_check(zone.resource == resource and zone.order == n and zone.route_start == route_start,
					"%s: %s is Zone %d from route %d, want %d from %d" % [label, where, zone.order, zone.route_start, n, route_start])
			var route := zone.rooms.filter(func(room: RoomPlan) -> bool: return room.is_on_route())
			_check(route.size() == resource.route_rooms, "%s: %s has %d route Rooms, authored %d" % [label, where, route.size(), resource.route_rooms])
			_check(zone.rooms.size() == resource.room_count, "%s: %s has %d Rooms, authored %d" % [label, where, zone.rooms.size(), resource.room_count])
			for k in route.size():
				_check(route[k] == biome.route[route_start + k] and route[k].route_index == route_start + k,
						"%s: %s's route Room %d isn't route position %d" % [label, where, k, route_start + k])
			for room in zone.rooms:
				_check(room.biome == id and room.zone == zone.id, "%s: %s is listed in %s" % [label, room.key, where])
				var join := plan.join_of(room)
				_check(join.is_on_route() and join.zone == zone.id, "%s: %s joins the route outside %s" % [label, room.key, where])
				_check(room.cell == join.cell and plan.cells[room.cell].rooms.has(room), "%s: %s isn't in its join's macro cell" % [label, room.key])
				_check(plan.rooms.get(room.key) == room, "%s: key %s doesn't find its Room" % [label, room.key])
				if not room.is_set_piece():
					_check(room.key.begins_with(plan.cells[room.cell].key + "/"), "%s: ordinary Room key %s doesn't extend its cell's" % [label, room.key])
			route_start += resource.route_rooms
	_check(total == content.world_room_count() and plan.rooms.size() == total,
			"%s: %d Rooms planned, %d keyed, %d authored" % [label, total, plan.rooms.size(), content.world_room_count()])


## One spawn opens the Ideal path. Every Biome reserves its Boss in its final Zone, and every Zone its
## Minibosses and Rares, off-route with their World-plan entry keys.
func _check_set_pieces(plan: WorldPlan, label: String) -> void:
	var content := plan.content
	var spawns := plan.set_pieces().filter(func(room: RoomPlan) -> bool: return room.kind == RoomPlan.Kind.SPAWN)
	var spawn := plan.spawn
	_check(spawns.size() == 1 and spawns[0] == spawn, "%s: %d spawns" % [label, spawns.size()])
	if spawn == null:
		return
	_check(spawn == plan.biomes[content.ideal_path[0]].route[0] and "%s/%s" % [spawn.biome, spawn.zone] == content.spawn_zone,
			"%s: the spawn isn't the Spawn zone's first route Room" % label)
	_check(spawn.key == "spawn" and spawn.challenge == 0 and spawn.cell == plan.path[0], "%s: spawn %s at %s has Challenge %d" % [label, spawn.key, spawn.cell, spawn.challenge])
	for id in plan.biomes:
		var biome := plan.biomes[id]
		var bosses := biome.rooms.filter(func(room: RoomPlan) -> bool: return room.kind == RoomPlan.Kind.BOSS)
		var final := biome.zones[-1]
		if biome.resource.boss == null:
			_check(bosses.is_empty() and biome.boss == null, "%s: %s should have no Boss" % [label, id])
		else:
			_check(bosses.size() == 1 and bosses[0] == biome.boss, "%s: %s has %d Bosses" % [label, id, bosses.size()])
			_check(biome.boss.zone == final.id and biome.boss.encounter == biome.resource.boss and biome.boss.key == "boss/%s" % id,
					"%s: %s's Boss %s is in Zone %s, not its final Zone %s" % [label, id, biome.boss.key, biome.boss.zone, final.id])
			_check(biome.boss.join_index >= final.route_end() - ceili(final.resource.route_rooms / 2.0),
					"%s: %s's Boss joins route %d, not near its end %d" % [label, id, biome.boss.join_index, biome.route.size() - 1])
		for zone in biome.zones:
			for entry: Array in [[RoomPlan.Kind.MINIBOSS, zone.resource.minibosses], [RoomPlan.Kind.RARE, zone.resource.rares]]:
				var authored: Array = entry[1]
				var placed := zone.rooms.filter(func(room: RoomPlan) -> bool: return room.kind == entry[0])
				_check(placed.size() == authored.size(), "%s: %s/%s places %d of %d %ss" % [label, id, zone.id, placed.size(), authored.size(), RoomPlan.KIND_NAMES[entry[0]]])
				for room: RoomPlan in placed:
					var n := room.key.get_slice("/", 3).to_int()
					_check(room.key == "%s/%s/%s/%d" % [room.kind_name(), id, zone.id, n] and n < authored.size() and room.encounter == authored[n],
							"%s: set piece %s doesn't hold its authored encounter" % [label, room.key])
					if room.kind == RoomPlan.Kind.MINIBOSS:
						_check(room.join_index * 2 >= zone.route_start + zone.route_end() - 1, "%s: Miniboss %s joins route %d, early in %s" % [label, room.key, room.join_index, zone.id])
	for room in plan.set_pieces():
		if room.kind != RoomPlan.Kind.SPAWN:
			_check(not room.is_on_route() and room.join_index >= 0, "%s: set piece %s is on the route" % [label, room.key])
			_check(plan.join_of(room) != spawn, "%s: set piece %s joins the spawn" % [label, room.key])


## Each Side biome attaches at one ordinary interior route Room of its parent, apart from its
## siblings.
func _check_attachments(plan: WorldPlan, label: String) -> void:
	for id in plan.biomes:
		var biome := plan.biomes[id]
		if not plan.content.parents.has(id):
			_check(not biome.is_side() and biome.attachment == null, "%s: Ideal-path %s is attached" % [label, id])
			continue
		var attachment := biome.attachment
		_check(biome.parent == plan.content.parents[id], "%s: %s's parent is %s" % [label, id, biome.parent])
		if attachment == null:
			_fails.append("%s: %s has no attachment" % [label, id])
			continue
		var parent := plan.biomes[biome.parent]
		var last := parent.route.size() - 1
		_check(attachment.biome == biome.parent and attachment.is_on_route() and parent.route[attachment.route_index] == attachment
				and not attachment.is_set_piece(), "%s: %s attaches at %s, not an ordinary route Room of %s" % [label, id, attachment.key, biome.parent])
		_check(attachment.route_index >= WorldContent.ATTACHMENT_MARGIN and attachment.route_index <= last - WorldContent.ATTACHMENT_MARGIN,
				"%s: %s attaches at route %d of 0-%d, too near its parent's entrance or exit" % [label, id, attachment.route_index, last])
		for other in plan.biomes:
			var sibling := plan.biomes[other]
			if other != id and sibling.parent == biome.parent and sibling.attachment != null:
				_check(absi(sibling.attachment.route_index - attachment.route_index) >= WorldContent.ATTACHMENT_SPACING,
						"%s: %s and %s attach at routes %d and %d" % [label, id, other, attachment.route_index, sibling.attachment.route_index])


## Challenge rises from 0 at the spawn to each Ideal-path Biome's exit and carries on; Side routes rise
## from their attachment's Challenge to their own exit; off-route Rooms take their join's.
func _check_challenge(plan: WorldPlan, label: String) -> void:
	var entry := 0
	for id in plan.content.ideal_path:
		_check_rise(plan.biomes[id], entry, label)
		entry = plan.biomes[id].resource.exit_challenge
	for side in plan.content.parents:
		var biome := plan.biomes[side]
		if biome.attachment != null:
			_check_rise(biome, biome.attachment.challenge, label)
	var previous := 0
	for room in plan.ideal_route():
		_check(room.challenge >= previous, "%s: Challenge drops to %d at %s on the Ideal path" % [label, room.challenge, room.key])
		previous = room.challenge
	for key in plan.rooms:
		var room := plan.rooms[key]
		_check(room.challenge == plan.join_of(room).challenge, "%s: %s has Challenge %d, its join %d" % [label, key, room.challenge, plan.join_of(room).challenge])


func _check_rise(biome: BiomePlan, entry: int, label: String) -> void:
	var route := biome.route
	_check(biome.entry_challenge == entry and route[0].challenge == entry, "%s: %s's route starts at Challenge %d, want %d" % [label, biome.id, route[0].challenge, entry])
	if route.size() > 1:
		_check(route[-1].challenge == biome.resource.exit_challenge, "%s: %s's route ends at Challenge %d, not its exit %d" % [label, biome.id, route[-1].challenge, biome.resource.exit_challenge])
	for n in range(1, route.size()):
		_check(route[n].challenge >= route[n - 1].challenge, "%s: %s's Challenge drops at route %d" % [label, biome.id, n])


## Planning one seed, then another, then the first again gives the first World both times.
func _test_repeated_builds(fixture: WorldFixture) -> void:
	var first := WorldFixture.snapshot(fixture.plan(fixture.seeds[0]))
	var other := WorldFixture.snapshot(fixture.plan(fixture.seeds[1]))
	var again := WorldFixture.snapshot(fixture.plan(fixture.seeds[0]))
	_check(first != other, "seeds %d and %d planned the same World" % [fixture.seeds[0], fixture.seeds[1]])
	if first != again:
		var a := first.split("\n")
		var b := again.split("\n")
		var line := 0
		while line < mini(a.size(), b.size()) and a[line] == b[line]:
			line += 1
		_fails.append("seed %d planned a different World the second time:\n    first: %s\n    again: %s" % [fixture.seeds[0],
				a[line] if line < a.size() else "", b[line] if line < b.size() else ""])


## Over several seeds, Zone orders, Side-biome attachments and their order, Rare positions and the
## fold all change.
func _test_seeds_vary(fixture: WorldFixture) -> void:
	var content := fixture.content
	var seen := {}
	for world_seed in VARIATION_SEEDS:
		var plan := fixture.plan(world_seed)
		_see(seen, "path", plan.path)
		for id in plan.biomes:
			var biome := plan.biomes[id]
			_see(seen, "zones %s" % id, biome.zones.map(func(zone: ZonePlan) -> StringName: return zone.id))
			if biome.is_side():
				_see(seen, "attachment %s" % id, biome.attachment.route_index)
				_see(seen, "before %s" % id, plan.biomes.keys().filter(func(other: StringName) -> bool:
					return plan.biomes[other].parent == biome.parent and plan.biomes[other].attachment.route_index < biome.attachment.route_index))
		for room in plan.set_pieces():
			if room.kind == RoomPlan.Kind.RARE:
				_see(seen, room.key, room.join_index)
	_check(seen["path"].size() > 1, "the fold never changed over %d seeds" % VARIATION_SEEDS)
	for id in content.biome_ids():
		var free_zones := content.zone_count(id) - (1 if content.spawn_zone.begins_with("%s/" % id) else 0)
		if free_zones > 1:
			_check(seen["zones %s" % id].size() > 1, "%s's Zone order never changed over %d seeds" % [id, VARIATION_SEEDS])
		if content.parents.has(id):
			_check(seen["attachment %s" % id].size() > 1, "%s's attachment never moved over %d seeds" % [id, VARIATION_SEEDS])
			_check(seen["before %s" % id].size() > 1, "%s's order among its parent's Side biomes never changed" % id)
	for key: String in seen:
		if key.begins_with("rare/"):
			_check(seen[key].size() > 1, "Rare %s never moved over %d seeds" % [key, VARIATION_SEEDS])


func _see(seen: Dictionary, what: String, value: Variant) -> void:
	var values: Dictionary = seen.get_or_add(what, {})
	values[str(value)] = true


## The plan holds its guarantees with every Biome's Rooms at the smallest and largest room size, and
## every set-piece radius at its slider's ends.
func _test_extremes(fixture: WorldFixture) -> void:
	var cells := {}
	for room_size in [16, 64]:
		fixture.set_knob(&"room_size", room_size)
		var plan := fixture.plan(fixture.seeds[0])
		_check_plan(plan, "small at room_size %d" % room_size)
		cells[room_size] = plan.cells.size() if plan != null else 0
	fixture.restore_knobs()
	_check(cells[64] > cells[16], "larger Rooms should need more macro cells: %d at room_size 16, %d at 64" % [cells[16], cells[64]])
	for radius in [WorldPlan.RADIUS_MIN, WorldPlan.RADIUS_MAX]:
		_check_plan(fixture.plan(fixture.seeds[0], WorldFixture.radii_at(radius)), "small at radius %d" % radius)
