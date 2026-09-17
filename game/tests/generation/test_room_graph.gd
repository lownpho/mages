extends Node
## Headless tests for the room graphs, through WorldGraph's public output: every unsealed Room reachable from
## the spawn; exact Zone quotas and roles; route Passages inside and between macro cells; sealed Side
## biomes; isolated set pieces owning their protected discs; shortcuts; Passage spots on their
## borders; Teaching rooms; planned Object sites, reveals, doors and landings with their spacing;
## place-derived keys. On the shipped World at three seeds and the small fixture; repeated and
## shuffled builds give the same graph; and on the fixture, every spatial knob and set-piece radius
## at its slider's ends, then all at minimum and all at maximum. Run:
##   godot --headless --path game res://tests/generation/test_room_graph.tscn

const VARIATION_SEEDS := 12
## The share of two room sizes Signs, Professors, Warp doors and landings keep apart.
const SITE_SPACING := SitePlanner.MIN_SPACING
## Samples per ring of a protected disc.
const DISC_SAMPLES := 16

var _fails: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var shipped := WorldFixture.shipped()
	var small := WorldFixture.small()
	_check(shipped.content.is_valid() and small.content.is_valid(), "test Worlds have content problems")
	for fixture: WorldFixture in [shipped, small]:
		for world_seed in fixture.seeds:
			_check_graph(fixture.graph(world_seed), "%s seed %d" % [_name(fixture), world_seed], SITE_SPACING)
		_test_repeated_builds(fixture)
	_test_introductions_vary(small)
	_test_sweep(small)
	print("room graph tests took %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails.slice(0, 300):
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


static func _name(fixture: WorldFixture) -> String:
	return fixture.content.root.trim_suffix("/").get_file()


## spacing_floor: the share of two room sizes every pair of Signs, Professors, doors and landings must
## keep; 0 skips spacing.
func _check_graph(graph: WorldGraph, label: String, spacing_floor: float) -> void:
	if graph == null:
		_fails.append("%s: built no room graph" % label)
		return
	_check_rooms(graph, label)
	_check_reachable(graph, label)
	_check_route(graph, label)
	_check_isolation(graph, label)
	_check_discs(graph, label)
	_check_passage_spots(graph, label)
	_check_teaching(graph, label)
	_check_sites(graph, label, spacing_floor)


## Every planned Room has one generated Room with a shape; Zones keep their exact route and total
## quotas; set pieces keep their roles, and only ordinary Rooms teach, test or breathe.
func _check_rooms(graph: WorldGraph, label: String) -> void:
	var plan := graph.plan
	_check(graph.rooms.size() == plan.rooms.size(), "%s: %d Rooms for %d planned" % [label, graph.rooms.size(), plan.rooms.size()])
	for key in plan.rooms:
		var room: GeneratedRoom = graph.rooms.get(key)
		if room == null or room.plan != plan.rooms[key]:
			_fails.append("%s: planned Room %s has no generated Room" % [label, key])
			continue
		_check(room.polygon.size() >= 3 and plan.lattice.cell_at(room.seed_point.x, room.seed_point.y) == room.plan.cell and Geometry2D.is_point_in_polygon(room.seed_point, room.polygon),
				"%s: %s (%s) has no shape around its seed %s in macro cell %s: %d corners" % [label, key, room.role_name(), room.seed_point,
				room.plan.cell, room.polygon.size()])
		var kind_roles := {RoomPlan.Kind.SPAWN: GeneratedRoom.Role.SPAWN, RoomPlan.Kind.BOSS: GeneratedRoom.Role.BOSS,
				RoomPlan.Kind.MINIBOSS: GeneratedRoom.Role.MINIBOSS, RoomPlan.Kind.RARE: GeneratedRoom.Role.RARE}
		if room.is_set_piece():
			_check(room.role == kind_roles[room.plan.kind] and room.radius == plan.radii[room.plan.kind_name()],
					"%s: set piece %s has role %s, radius %s" % [label, key, room.role_name(), room.radius])
		else:
			_check(room.role in [GeneratedRoom.Role.TESTING, GeneratedRoom.Role.TEACHING, GeneratedRoom.Role.BREATHER],
					"%s: ordinary Room %s has role %s" % [label, key, room.role_name()])
		_check((room.role == GeneratedRoom.Role.TEACHING) == (room.teaching != null), "%s: %s is %s teaching %s" % [label, key, room.role_name(), room.teaching])
	for id in plan.biomes:
		for zone in plan.biomes[id].zones:
			var owned := graph.rooms.values().filter(func(room: GeneratedRoom) -> bool: return room.plan.biome == id and room.plan.zone == zone.id)
			var route := owned.filter(func(room: GeneratedRoom) -> bool: return room.plan.is_on_route())
			_check(owned.size() == zone.resource.room_count and route.size() == zone.resource.route_rooms,
					"%s: %s/%s has %d Rooms, %d on the route; authored %d, %d" % [label, id, zone.id, owned.size(), route.size(),
					zone.resource.room_count, zone.resource.route_rooms])


## Passages are shared by both their Rooms, and every Room is reachable from the spawn through them.
func _check_reachable(graph: WorldGraph, label: String) -> void:
	for key in graph.passages:
		var passage := graph.passages[key]
		_check(passage.key == RoomPassage.pair(passage.a, passage.b) and passage.a != passage.b, "%s: Passage %s is keyed badly" % [label, key])
		for end in [passage.a, passage.b]:
			var room: GeneratedRoom = graph.rooms.get(end)
			_check(room != null and room.passages.count(passage) == 1, "%s: Passage %s isn't listed once by %s" % [label, key, end])
	for key in graph.rooms:
		for passage in graph.rooms[key].passages:
			_check(graph.passages.get(passage.key) == passage, "%s: %s lists unknown Passage %s" % [label, key, passage.key])
	var reached := {graph.plan.spawn.key: true}
	var queue: Array[String] = [graph.plan.spawn.key]
	var next := 0
	while next < queue.size():
		for passage in graph.rooms[queue[next]].passages:
			var other := passage.other(queue[next])
			if not reached.has(other):
				reached[other] = true
				queue.append(other)
		next += 1
	for key in reached:
		_check(not graph.plan.biomes[graph.rooms[key].plan.biome].resource.sealed, "%s: sealed Room %s is reachable" % [label, key])
	var stranded := graph.rooms.keys().filter(func(key: String) -> bool: return not graph.plan.biomes[graph.rooms[key].plan.biome].resource.sealed and not reached.has(key))
	_check(stranded.is_empty(), "%s: %d Rooms unreachable from the spawn, e.g. %s" % [label, stranded.size(), stranded.slice(0, 3)])


## Consecutive route Rooms share a route Passage, across macro cells and Biomes too. A Side biome's
## only Passage out is its attachment. Shortcuts join ordinary Rooms of neighbouring Ideal-path cells
## the route doesn't join, at most one per edge.
func _check_route(graph: WorldGraph, label: String) -> void:
	var plan := graph.plan
	var ideal := plan.ideal_route()
	for n in range(1, ideal.size()):
		var passage: RoomPassage = graph.passages.get(RoomPassage.pair(ideal[n - 1].key, ideal[n].key))
		var a := plan.biomes[ideal[n - 1].biome]
		var b := plan.biomes[ideal[n].biome]
		if a != b and (a.resource.sealed or b.resource.sealed):
			_check(passage == null, "%s: sealed border has a route Passage" % label)
			continue
		_check(passage != null and passage.kind == RoomPassage.Kind.ROUTE, "%s: Ideal-path route Rooms %s and %s share no route Passage" % [label, ideal[n - 1].key, ideal[n].key])
	var edges := {}
	for key in graph.passages:
		var passage := graph.passages[key]
		var a := graph.rooms[passage.a].plan
		var b := graph.rooms[passage.b].plan
		var side_a := plan.biomes[a.biome].is_side()
		var side_b := plan.biomes[b.biome].is_side()
		match passage.kind:
			RoomPassage.Kind.ATTACHMENT:
				var side := plan.biomes[b.biome if side_b else a.biome]
				var inner := b if side_b else a
				var outer := a if side_b else b
				_check(side_a != side_b and side.parent == outer.biome and outer == side.attachment and inner == side.route[0],
						"%s: attachment Passage %s doesn't join a Side biome's first route Room to its attachment" % [label, key])
			RoomPassage.Kind.SHORTCUT:
				var cell_a := plan.cells[a.cell]
				var cell_b := plan.cells[b.cell]
				_check(not a.is_set_piece() and not b.is_set_piece() and absi(a.cell.x - b.cell.x) + absi(a.cell.y - b.cell.y) == 1
						and cell_a.path_index >= 0 and cell_b.path_index >= 0 and absi(cell_a.path_index - cell_b.path_index) > 1,
						"%s: shortcut %s doesn't join ordinary Rooms of folded Ideal-path cells" % [label, key])
				var edge := RoomPassage.pair(str(a.cell), str(b.cell))
				_check(not edges.has(edge), "%s: two shortcuts cross macro-cell edge %s" % [label, edge])
				edges[edge] = true
			RoomPassage.Kind.ROUTE:
				_check(a.is_on_route() and b.is_on_route() and (a.biome == b.biome and absi(a.route_index - b.route_index) == 1
						or a.biome != b.biome and not side_a and not side_b), "%s: route Passage %s doesn't join consecutive route Rooms" % [label, key])
			_:
				_check(a.cell == b.cell, "%s: %s Passage %s crosses macro cells" % [label, passage.kind_name(), key])
		if a.biome != b.biome:
			_check(passage.kind in [RoomPassage.Kind.ROUTE, RoomPassage.Kind.SHORTCUT, RoomPassage.Kind.ATTACHMENT],
					"%s: %s Passage %s joins Biomes %s and %s" % [label, passage.kind_name(), key, a.biome, b.biome])
			if side_a or side_b:
				_check(passage.kind == RoomPassage.Kind.ATTACHMENT, "%s: Side biome leaks through %s Passage %s" % [label, passage.kind_name(), key])
	for side in plan.content.parents:
		var biome := plan.biomes[side]
		for n in range(1, biome.route.size()):
			var passage: RoomPassage = graph.passages.get(RoomPassage.pair(biome.route[n - 1].key, biome.route[n].key))
			_check(passage != null and passage.kind == RoomPassage.Kind.ROUTE, "%s: %s's route breaks between %s and %s" % [label, side, biome.route[n - 1].key, biome.route[n].key])
		var ways_in := graph.passages.values().filter(func(passage: RoomPassage) -> bool:
			return (graph.rooms[passage.a].plan.biome == side) != (graph.rooms[passage.b].plan.biome == side))
		_check(ways_in.size() == (0 if biome.resource.sealed or plan.biomes[biome.parent].resource.sealed else 1), "%s: Side biome %s has %d Passages out" % [label, side, ways_in.size()])


## Bosses, Minibosses and Rares have exactly one Passage, to an ordinary Room of their macro cell.
## The spawn holds only the player.
func _check_isolation(graph: WorldGraph, label: String) -> void:
	for key in graph.rooms:
		var room := graph.rooms[key]
		if room.is_isolated():
			var ok := room.passages.size() == 1 and room.passages[0].kind == RoomPassage.Kind.SET_PIECE
			if ok:
				var other := graph.rooms[room.passages[0].other(key)]
				ok = other.is_ordinary() and other.plan.cell == room.plan.cell
			_check(ok, "%s: set piece %s has Passages %s" % [label, key, room.passages.map(func(passage: RoomPassage) -> String: return "%s %s" % [passage.kind_name(), passage.key])])
			_check(not room.plan.is_on_route(), "%s: set piece %s is on the route" % [label, key])
		else:
			_check(room.passages.all(func(passage: RoomPassage) -> bool:
				return passage.kind != RoomPassage.Kind.SET_PIECE or graph.rooms[passage.other(key)].is_isolated()),
					"%s: %s has a set-piece Passage to a Room that isn't a set piece" % [label, key])
		if room.is_set_piece():
			_check(room.sites.is_empty(), "%s: set piece %s holds sites %s" % [label, key, room.sites.map(func(site: ObjectSite) -> String: return site.key)])


## Every tile within a set piece's protected radius belongs to it, and every Room owns its seed.
func _check_discs(graph: WorldGraph, label: String) -> void:
	for key in graph.rooms:
		var room := graph.rooms[key]
		_check(graph.owner_at(graph.tile_of(room.seed_point)) == room, "%s: %s doesn't own its seed's tile" % [label, key])
		if not room.is_set_piece():
			continue
		for ring: float in [0.0, room.radius * 0.5, room.radius - 1.0]:
			for n in DISC_SAMPLES:
				var tile := Vector2i((room.seed_point + Vector2.from_angle(TAU * n / DISC_SAMPLES) * ring - Vector2(0.5, 0.5)).round())
				if Vector2(tile).distance_to(room.seed_point - Vector2(0.5, 0.5)) > room.radius - 0.75:
					continue
				var tile_owner := graph.owner_at(tile)
				if tile_owner != room:
					_fails.append("%s: tile %s in %s's radius %s belongs to %s" % [label, tile, key, room.radius, tile_owner.key() if tile_owner else "nothing"])
					return


## A Passage's spot belongs to one of its Rooms and lies beside the other.
func _check_passage_spots(graph: WorldGraph, label: String) -> void:
	for key in graph.passages:
		var passage := graph.passages[key]
		var tile_owner := graph.owner_at(passage.spot)
		var other := passage.b if tile_owner != null and tile_owner.key() == passage.a else passage.a
		var beside := false
		if tile_owner != null and (tile_owner.key() == passage.a or tile_owner.key() == passage.b):
			var reach := passage.width
			for dy in range(-reach, reach + 1):
				for dx in range(-reach, reach + 1):
					var near := graph.owner_at(passage.spot + Vector2i(dx, dy))
					if near != null and near.key() == other:
						beside = true
						break
				if beside:
					break
		_check(beside, "%s: %s Passage %s opens at %s, owned by %s" % [label, passage.kind_name(), key, passage.spot, tile_owner.key() if tile_owner else "nothing"])


## Each route teaches every enemy its Zones field once, Hazards excepted, in a Room fielding it at a
## Challenge its effective Entry challenge has reached, never before its first eligible route
## position, and in the order those positions come. Zones' lowest-entry non-Hazard enemies, and
## Hazards entering no later, are eligible from their first Room.
func _check_teaching(graph: WorldGraph, label: String) -> void:
	var plan := graph.plan
	var routes: Array[Array] = [plan.content.ideal_path.map(func(id: StringName) -> BiomePlan: return plan.biomes[id])]
	for side in plan.content.parents:
		routes.append([plan.biomes[side]])
	for biome_id in plan.biomes:
		for zone in plan.biomes[biome_id].zones:
			var roster := graph.rooms[zone.rooms[0].key].roster
			var authored: Dictionary = plan.biomes[biome_id].resource.roster.duplicate()
			authored.merge(zone.resource.roster)
			_check(roster.size() == authored.size() and authored.keys().all(func(enemy: CreatureResource) -> bool: return roster.has(enemy)),
					"%s: %s/%s's roster isn't its Biome's and Zone's" % [label, biome_id, zone.id])
			if not authored.is_empty():
				var fighters := authored.keys().filter(func(enemy: CreatureResource) -> bool: return not enemy.is_hazard())
				var lowest: int = (fighters if not fighters.is_empty() else authored.keys()).map(func(enemy: CreatureResource) -> int: return authored[enemy]).min()
				var first := plan.biomes[biome_id].route[zone.route_start].challenge
				for enemy: CreatureResource in authored:
					if authored[enemy] <= lowest:
						_check(roster[enemy] <= first, "%s: lowest-entry %s isn't eligible from %s/%s's first Room" % [label, enemy.resource_path.get_file(), biome_id, zone.id])
	for biomes: Array in routes:
		var first_eligible: Dictionary[CreatureResource, int] = {}
		var offset := 0
		var offsets := {}
		for biome: BiomePlan in biomes:
			offsets[biome.id] = offset
			for index in biome.route.size():
				var roster := graph.rooms[biome.route[index].key].roster
				for enemy in roster:
					if not first_eligible.has(enemy) and not enemy.is_hazard() and roster[enemy] <= biome.route[index].challenge:
						first_eligible[enemy] = offset + index
			offset += biome.route.size()
		var taught: Dictionary[CreatureResource, GeneratedRoom] = {}
		for biome: BiomePlan in biomes:
			for room_plan in biome.rooms:
				var room := graph.rooms[room_plan.key]
				if room.teaching == null:
					continue
				_check(not taught.has(room.teaching), "%s: %s is taught twice on %s's route" % [label, room.teaching.resource_path.get_file(), biome.id])
				taught[room.teaching] = room
		var route_name := "+".join(biomes.map(func(biome: BiomePlan) -> String: return biome.id))
		_check(taught.size() == first_eligible.size(), "%s: %s teaches %d enemies, fields %d" % [label, route_name, taught.size(), first_eligible.size()])
		var order: Array[Array] = []
		for enemy in taught:
			var room := taught[enemy]
			var at: int = offsets[room.plan.biome] + room.plan.join_index
			_check(room.roster.has(enemy) and room.roster[enemy] <= room.plan.challenge and at >= first_eligible.get(enemy, 0),
					"%s: %s teaches %s at route %d, Challenge %d; first eligible at %d" % [label, room.key(), enemy.resource_path.get_file(),
					at, room.plan.challenge, first_eligible.get(enemy, -1)])
			order.append([first_eligible.get(enemy, 0), at, enemy.resource_path.get_file()])
		order.sort()
		for n in range(1, order.size()):
			_check(order[n][1] >= order[n - 1][1] or order[n][0] == order[n - 1][0],
					"%s: %s is taught at %d, before %s at %d though it becomes eligible later" % [label, order[n][2], order[n][1], order[n - 1][2], order[n - 1][1]])


## Every authored Sign stands once, and each Biome's Professors and Warp doors; their Rooms are
## Breathers that don't teach. Doors land in ordinary non-Breather Rooms of a permitted Biome. Signs
## reveal the nearest Boss their enemy leads. Chance Breathers hold at most one weighted Object from
## their choices. Sites own their spots, follow their Rooms' keys, and keep apart.
func _check_sites(graph: WorldGraph, label: String, spacing_floor: float) -> void:
	var plan := graph.plan
	var content := plan.content
	var by_kind := {}
	for key in graph.sites:
		var site := graph.sites[key]
		var room: GeneratedRoom = graph.rooms.get(site.room_key)
		by_kind.get_or_add(site.kind, []).append(site)
		if room == null:
			_fails.append("%s: site %s is in no Room" % [label, key])
			continue
		_check(key.begins_with(site.room_key + "/") and room.sites.has(site), "%s: site %s isn't keyed by and listed in its Room" % [label, key])
		_check(graph.owner_at(site.spot) == room, "%s: site %s's spot %s isn't in its Room" % [label, key, site.spot])
		_check(room.is_ordinary(), "%s: site %s stands in set piece %s" % [label, key, site.room_key])
		if site.kind == ObjectSite.Kind.LANDING:
			_check(room.role != GeneratedRoom.Role.BREATHER, "%s: landing %s is in a Breather" % [label, key])
		else:
			_check(room.role == GeneratedRoom.Role.BREATHER, "%s: Object %s stands in a %s room" % [label, key, room.role_name()])
		if site.kind == ObjectSite.Kind.WEIGHTED:
			_check(room.sites.size() == 1, "%s: weighted Object %s shares its Breather" % [label, key])
			var zone := plan.biomes[room.plan.biome].zone(room.plan.zone)
			_check(plan.biomes[room.plan.biome].resource.breather_objects.has(site.scene) or zone.resource.breather_objects.has(site.scene),
					"%s: weighted Object %s isn't one of its Room's choices" % [label, key])
		for other in room.sites:
			_check(other == site or other.spot != site.spot, "%s: sites %s and %s share spot %s" % [label, key, other.key, site.spot])
	for id in plan.biomes:
		var biome := plan.biomes[id]
		for kind: ObjectSite.Kind in [ObjectSite.Kind.PROFESSOR, ObjectSite.Kind.DOOR]:
			var placed: Array = by_kind.get(kind, []).filter(func(site: ObjectSite) -> bool: return graph.rooms[site.room_key].plan.biome == id)
			var authored := biome.resource.professors if kind == ObjectSite.Kind.PROFESSOR else (0 if biome.resource.sealed else biome.resource.warp_doors)
			_check(placed.size() == authored, "%s: %s has %d %ss, authored %d" % [label, id, placed.size(), ObjectSite.KIND_NAMES[kind], authored])
		var signs: Array = biome.resource.signs.duplicate()
		for zone in biome.zones:
			signs.append_array(zone.resource.signs)
		for sign_resource: SignResource in signs:
			var placed: Array = by_kind.get(ObjectSite.Kind.SIGN, []).filter(func(site: ObjectSite) -> bool: return site.sign_resource == sign_resource)
			_check(placed.size() == 1, "%s: Sign \"%s\" stands %d times" % [label, sign_resource.text.get_slice("\n", 0), placed.size()])
			if placed.size() != 1:
				continue
			var sign_site: ObjectSite = placed[0]
			var room := graph.rooms[sign_site.room_key]
			_check(room.plan.biome == id and (biome.resource.signs.has(sign_resource) or biome.zone(room.plan.zone).resource.signs.has(sign_resource)),
					"%s: Sign %s stands outside the Biome or Zone authoring it" % [label, sign_site.key])
			var led := plan.set_pieces().filter(func(piece: RoomPlan) -> bool:
				return (piece.kind == RoomPlan.Kind.BOSS or piece.kind == RoomPlan.Kind.MINIBOSS) \
						and piece.encounter.leader == sign_resource.reveals)
			led.sort_custom(func(a: RoomPlan, b: RoomPlan) -> bool:
				return Vector2(sign_site.spot).distance_to(graph.rooms[a.key].seed_point) < Vector2(sign_site.spot).distance_to(graph.rooms[b.key].seed_point))
			if sign_resource.reveals == null:
				_check(sign_site.reveal_key == "", "%s: Sign %s reveals %s though it names no enemy" % [label, sign_site.key, sign_site.reveal_key])
			else:
				var revealed: GeneratedRoom = graph.rooms.get(sign_site.reveal_key)
				_check(not led.is_empty() and sign_site.reveal_key == led[0].key and revealed != null \
						and revealed.role in [GeneratedRoom.Role.BOSS, GeneratedRoom.Role.MINIBOSS],
						"%s: Sign %s reveals %s, not the nearest Boss or Miniboss its enemy leads" % [label, sign_site.key, sign_site.reveal_key])
	var total_signs := 0
	for id in plan.biomes:
		total_signs += plan.biomes[id].resource.signs.size()
		for zone in plan.biomes[id].zones:
			total_signs += zone.resource.signs.size()
	_check(by_kind.get(ObjectSite.Kind.SIGN, []).size() == total_signs, "%s: %d Signs for %d authored" % [label, by_kind.get(ObjectSite.Kind.SIGN, []).size(), total_signs])
	var doors: Array = by_kind.get(ObjectSite.Kind.DOOR, [])
	_check(by_kind.get(ObjectSite.Kind.LANDING, []).size() == doors.size(), "%s: %d landings for %d doors" % [label, by_kind.get(ObjectSite.Kind.LANDING, []).size(), doors.size()])
	for door: ObjectSite in doors:
		_check(not plan.biomes[door.destination_biome].resource.sealed, "%s: door %s leads to a sealed Biome" % [label, door.key])
		var from := graph.rooms[door.room_key].plan.biome
		var allowed: Array[StringName] = []
		if content.parents.has(from):
			allowed = [content.parents[from]]
		else:
			var index := content.ideal_path.find(from)
			for neighbour in [index - 1, index + 1]:
				if neighbour >= 0 and neighbour < content.ideal_path.size():
					allowed.append(content.ideal_path[neighbour])
		var landing: ObjectSite = graph.sites.get(door.landing_key)
		_check(allowed.has(door.destination_biome) and landing != null and landing.kind == ObjectSite.Kind.LANDING and landing.door_key == door.key
				and landing.room_key == door.destination_room and graph.rooms[landing.room_key].plan.biome == door.destination_biome,
				"%s: door %s from %s leads to %s %s, landing %s" % [label, door.key, from, door.destination_biome, door.destination_room, door.landing_key])
	if spacing_floor <= 0.0:
		return
	var far: Array = []
	for kind: ObjectSite.Kind in [ObjectSite.Kind.SIGN, ObjectSite.Kind.PROFESSOR, ObjectSite.Kind.DOOR, ObjectSite.Kind.LANDING]:
		far.append_array(by_kind.get(kind, []))
	var closest := INF
	var example := ""
	for i in far.size():
		for j in range(i + 1, far.size()):
			var a: ObjectSite = far[i]
			var b: ObjectSite = far[j]
			var gap := 2.0 * maxi(plan.biomes[graph.rooms[a.room_key].plan.biome].resource.room_size, plan.biomes[graph.rooms[b.room_key].plan.biome].resource.room_size)
			var ratio := Vector2(a.spot).distance_to(Vector2(b.spot)) / gap
			if ratio < closest:
				closest = ratio
				example = "%s and %s %.0f apart, want %.0f" % [a.key, b.key, Vector2(a.spot).distance_to(Vector2(b.spot)), gap]
	print("%s: closest sites keep %.2f of two room sizes (%s)" % [label, closest, example])
	_check(closest >= spacing_floor, "%s: sites keep only %.2f of two room sizes, want %.2f: %s" % [label, closest, spacing_floor, example])


## Building one seed, another, then the first again gives the first graph both times, and building
## macro cells in shuffled order changes nothing.
func _test_repeated_builds(fixture: WorldFixture) -> void:
	var first := WorldFixture.graph_snapshot(fixture.graph(fixture.seeds[0]))
	var other := WorldFixture.graph_snapshot(fixture.graph(fixture.seeds[1]))
	var again := WorldFixture.graph_snapshot(fixture.graph(fixture.seeds[0]))
	_check(first != other, "%s: seeds %d and %d built the same graph" % [_name(fixture), fixture.seeds[0], fixture.seeds[1]])
	_check_same(first, again, "%s seed %d built a different graph the second time" % [_name(fixture), fixture.seeds[0]])
	var plan := fixture.plan(fixture.seeds[0])
	var order: Array[Vector2i] = plan.cells.keys()
	WorldPlanner._shuffle(order, WorldHash.rng(424242))
	order.reverse()
	_check_same(first, WorldFixture.graph_snapshot(WorldGraph.build(plan, order)), "%s seed %d built a different graph in shuffled cell order" % [_name(fixture), fixture.seeds[0]])


func _check_same(expected: String, actual: String, message: String) -> void:
	if expected == actual:
		return
	var a := expected.split("\n")
	var b := actual.split("\n")
	var line := 0
	while line < mini(a.size(), b.size()) and a[line] == b[line]:
		line += 1
	_fails.append("%s:\n    first: %s\n    again: %s" % [message, a[line].left(200) if line < a.size() else "", b[line].left(200) if line < b.size() else ""])


## Over several seeds, introductions sharing a route position and Entry challenge come in more than
## one order.
func _test_introductions_vary(fixture: WorldFixture) -> void:
	var orders := {}
	for world_seed in VARIATION_SEEDS:
		var graph := fixture.graph(world_seed)
		if graph == null:
			_fails.append("%s seed %d: built no room graph" % [_name(fixture), world_seed])
			continue
		var first := graph.plan.biomes[graph.plan.content.ideal_path[0]]
		var teaching := first.rooms.map(func(room_plan: RoomPlan) -> GeneratedRoom: return graph.rooms[room_plan.key]).filter(func(room: GeneratedRoom) -> bool:
			return room.teaching != null and room.roster[room.teaching] == 0)
		teaching.sort_custom(func(a: GeneratedRoom, b: GeneratedRoom) -> bool:
			return a.plan.join_index < b.plan.join_index or (a.plan.join_index == b.plan.join_index and a.plan.is_on_route() and not b.plan.is_on_route()))
		orders[str(teaching.map(func(room: GeneratedRoom) -> String: return room.teaching.resource_path.get_file()))] = true
	_check(orders.size() > 1, "%s: Entry-challenge-0 introductions came in one order over %d seeds: %s" % [_name(fixture), VARIATION_SEEDS, orders.keys()])


## The fixture keeps every graph guarantee with each knob and each set-piece radius at its slider's
## ends, then with all at minimum and all at maximum.
func _test_sweep(fixture: WorldFixture) -> void:
	var world_seed := fixture.seeds[0]
	for knob in WorldFixture.KNOBS:
		for end in 2:
			fixture.set_knob(knob, WorldFixture.knob_range(knob)[end])
			_check_graph(fixture.graph(world_seed), "%s %s at %s" % [_name(fixture), knob, WorldFixture.knob_range(knob)[end]], SITE_SPACING)
			fixture.restore_knobs()
	for kind in WorldPlan.DEFAULT_RADII:
		for radius in [WorldPlan.RADIUS_MIN, WorldPlan.RADIUS_MAX]:
			var radii: Dictionary[StringName, int] = WorldPlan.DEFAULT_RADII.duplicate()
			radii[kind] = radius
			_check_graph(fixture.graph(world_seed, radii), "%s %s radius %d" % [_name(fixture), kind, radius], SITE_SPACING)
	for end in 2:
		for knob in WorldFixture.KNOBS:
			fixture.set_knob(knob, WorldFixture.knob_range(knob)[end])
		var radius := WorldPlan.RADIUS_MIN if end == 0 else WorldPlan.RADIUS_MAX
		_check_graph(fixture.graph(world_seed, WorldFixture.radii_at(radius)), "%s all at %s" % [_name(fixture), "minimum" if end == 0 else "maximum"], SITE_SPACING)
		fixture.restore_knobs()
