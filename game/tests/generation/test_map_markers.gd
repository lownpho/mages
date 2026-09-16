extends Node
## World Map coverage at the public MapState boundary: Room-key discovery, lazy macro images,
## Passage stubs, derived markers/reveals/defeats, fog Pins and the two views' edge projection.

const MAP_VIEW := preload("res://gui/map/map_view.gd")
const MINIMAP_VIEW := preload("res://gui/minimap/minimap_view.gd")

var fails: Array[String] = []


func _ready() -> void:
	var graph := WorldFixture.small().graph(2)
	_check(graph != null, "small World graph builds")
	if graph != null:
		_test_discovery_images_and_stubs(graph)
		_test_shortcut_stub()
		_test_markers(graph)
		_test_reveal_defeat_and_save(graph)
		_test_warp_arrival(graph)
		_test_projection()
	if fails.is_empty():
		print("ALL PASS")
	else:
		print("FAILED: %d" % fails.size())
		for failure in fails:
			print("  FAIL: ", failure)
	get_tree().quit(0 if fails.is_empty() else 1)


func _state(graph: WorldGraph, defeated: Dictionary = {}) -> MapState:
	var state := MapState.new()
	state.setup(graph,WorldFixture.interiors(graph), defeated)
	return state


func _test_discovery_images_and_stubs(graph: WorldGraph) -> void:
	var state := _state(graph)
	var room := graph.rooms[graph.plan.spawn.key]
	var entry := graph.tile_of(room.seed_point)
	_check(state.macro_build_count() == 0 and state.built_macro_cells().is_empty(),
			"setup builds no Map images")
	_check(state.discover_at(entry), "entering a Room discovers it")
	_check(state.entered_rooms.keys() == [room.key()], "discovery records the Room key")
	_check(state.macro_build_count() == 0, "Room discovery leaves images lazy")

	var another := _owned_tile(graph, room, entry)
	_check(another != Vector2i.MAX and state.is_tile_discovered(another),
			"another tile of the entered Room is discovered")
	var neighbour: GeneratedRoom = graph.rooms[room.passages[0].other(room.key())]
	_check(not state.is_tile_discovered(graph.tile_of(neighbour.seed_point)),
			"an adjacent Room remains fogged")

	var cell_coord := Vector2i(floori(float(entry.x) / WorldPlan.CELL),
			floori(float(entry.y) / WorldPlan.CELL))
	var image := state.macro_image(cell_coord)
	_check(image != null and state.macro_build_count() == 1, "the requested macro-cell image builds once")
	_check(state.macro_image(cell_coord) == image and state.macro_build_count() == 1,
			"a requested macro-cell image is reused")
	if image != null:
		var local := entry - image.rect.position
		_check(image.floor_image.get_pixelv(local).a > 0.0, "entered Room floor appears in its image")
		var cls := state.interiors.interior(room).class_at(entry)
		var want_wall := cls == WorldInteriors.WALL or cls == WorldInteriors.ROCK
		_check((image.wall_image.get_pixelv(local).a > 0.0) == want_wall,
				"wall image follows the semantic wall/rock class")
		_check_semantic_overlay(state, room, WorldInteriors.WALL, "wall")
		_check_semantic_overlay(state, room, WorldInteriors.ROCK, "rock")

	var stub := _outgoing_stub(state, room)
	_check(stub != Vector2i.MAX, "entered Room has an outgoing Passage stub")
	if stub != Vector2i.MAX:
		var stub_coord := Vector2i(floori(float(stub.x) / WorldPlan.CELL),
				floori(float(stub.y) / WorldPlan.CELL))
		var stub_image := state.macro_image(stub_coord)
		var local_stub := stub - stub_image.rect.position
		_check(stub_image.floor_image.get_pixelv(local_stub).a > 0.0,
				"outgoing Passage paints a floor stub into the fogged Room")
		_check(not state.is_tile_discovered(stub), "a Passage stub does not discover its destination Room")

	var region := Rect2(Vector2(cell_coord * WorldPlan.CELL), Vector2.ONE * WorldPlan.CELL)
	var layers := state.images_in(region, 4)
	_check(layers.size() == 1 and layers[0].texel_tiles == 4,
			"a view receives the requested macro cell and downsampled wall level")


func _test_shortcut_stub() -> void:
	var graph := WorldFixture.shipped().graph(7)
	var shortcut: RoomPassage = null
	var ordinary: RoomPassage = null
	for passage in graph.passages.values():
		if passage.kind == RoomPassage.Kind.SHORTCUT and shortcut == null:
			shortcut = passage
		elif passage.kind != RoomPassage.Kind.SHORTCUT and ordinary == null:
			ordinary = passage
	_check(shortcut != null, "shipped fixture exercises a shortcut Passage")
	for passage in [ordinary, shortcut]:
		if passage == null:
			continue
		var state := _state(graph)
		var room: GeneratedRoom = graph.rooms[passage.a]
		state.discover_at(graph.tile_of(room.seed_point))
		var stub := _stub_for_passage(state, room, passage)
		_check(stub != Vector2i.MAX, "%s Passage has a fog-side stub" % passage.kind_name())
		if stub != Vector2i.MAX:
			var coord := Vector2i(floori(float(stub.x) / WorldPlan.CELL),
					floori(float(stub.y) / WorldPlan.CELL))
			var image := state.macro_image(coord)
			_check(image.floor_image.get_pixelv(stub - image.rect.position).a > 0.0,
					"%s Passage uses the same visible floor stub" % passage.kind_name())


func _test_markers(graph: WorldGraph) -> void:
	var state := _state(graph)
	for room in graph.room_list:
		state.discover_at(graph.tile_of(room.seed_point))
	var by_object: Dictionary[String, Dictionary] = {}
	var boss_rooms: Dictionary[String, bool] = {}
	for marker in state.markers:
		if marker.kind == MapState.MARKER_BOSS:
			boss_rooms[marker.room_key] = true
		elif marker.has("object_key"):
			by_object[marker.object_key] = marker

	for room in graph.room_list:
		_check(boss_rooms.has(room.key()) == (room.role == GeneratedRoom.Role.BOSS),
				"only Boss Rooms have Boss markers after discovery (%s)" % room.key())
	var professors := 0
	for key in graph.sites:
		var site: ObjectSite = graph.sites[key]
		if site.kind == ObjectSite.Kind.LANDING:
			_check(not by_object.has(key), "landing %s has no marker" % key)
			continue
		if site.kind == ObjectSite.Kind.PROFESSOR:
			professors += 1
			_check(by_object.has(key) and by_object[key].kind == MapState.MARKER_NPC,
					"Professor %s is marked as an NPC" % key)
		_check(by_object.has(key), "%s Object %s has a marker" % [site.kind_name(), key])
		if not by_object.has(key):
			continue
		var want := _expected_kind(site)
		_check(by_object[key].kind == want, "%s marker kind is %d, want %d" % [key,
				by_object[key].kind, want])
	_check(professors > 0, "the fixture plans a Professor")

	# Mutating the real Object state owner cannot affect a graph-derived marker.
	var before := state.markers.duplicate(true)
	var spawner := ObjectSpawner.new()
	var marked_key: String = by_object.keys()[0]
	spawner.states[marked_key] = {"used": true, "greeted": true}
	_check(not spawner.states[marked_key].is_empty() and state.markers == before,
			"using an Object does not change its derived marker")
	spawner.free()


func _test_reveal_defeat_and_save(graph: WorldGraph) -> void:
	var boss: GeneratedRoom = null
	for room in graph.room_list:
		if room.role == GeneratedRoom.Role.BOSS:
			boss = room
			break
	_check(boss != null, "fixture has a Boss")
	if boss == null:
		return
	var defeated: Dictionary[String, bool] = {}
	var state := _state(graph, defeated)
	_check(state.reveal_boss_room(boss.key()), "an Object can reveal a Boss Room key")
	_check(not state.is_tile_discovered(graph.tile_of(boss.seed_point)), "revealing a Boss leaves its Room fogged")
	var markers := state.markers
	_check(markers.size() == 1 and markers[0].kind == MapState.MARKER_BOSS
			and markers[0].project, "an undiscovered revealed Boss is marked for edge projection")
	defeated[boss.key() + "/encounter/0/member/0"] = true
	_check(state.markers.is_empty(), "defeating the Boss leader removes its marker")

	var fog_room: GeneratedRoom = null
	for room in graph.room_list:
		if room != boss:
			fog_room = room
			break
	var pin := graph.tile_of(fog_room.seed_point)
	state.add_pin(pin)
	_check(state.pins == [pin] and not state.is_tile_discovered(pin), "a Pin may be placed in fog")
	var saved := state.to_dict()
	_check(saved.has("entered_rooms") and saved.has("pins") and saved.has("revealed_bosses")
			and not saved.has("markers"), "save exposes records, not generated marker lists")
	var restored := _state(graph, defeated)
	restored.restore(saved)
	_check(restored.pins == [pin] and restored.revealed_bosses.has(boss.key()),
			"Pins and revealed Boss keys restore")
	defeated.clear()
	_check(restored.markers.size() == 1, "restored markers reconstruct from records and defeat keys")

	var global_state := _state(graph)
	GlobalMap.active = global_state
	GlobalMap.revealed_boss_keys.clear()
	GlobalMap.reveal_boss_room(boss.key())
	_check(global_state.revealed_bosses.has(boss.key()),
			"the Object-facing GlobalMap reveal reaches the active MapState")
	GlobalMap.reset()


func _test_warp_arrival(graph: WorldGraph) -> void:
	var landing: ObjectSite = null
	for site in graph.sites.values():
		if site.kind == ObjectSite.Kind.LANDING:
			landing = site
			break
	_check(landing != null, "fixture has a Warp-door landing")
	if landing == null:
		return
	var state := _state(graph)
	GlobalMap.active = state
	var spawner := ObjectSpawner.new()
	var body := Node2D.new()
	spawner._warp(body, landing.room_key, landing.spot)
	_check(state.entered_rooms.has(landing.room_key), "Warp arrival immediately discovers its Room")
	body.free()
	spawner.free()
	GlobalMap.reset()


func _test_projection() -> void:
	var full: Control = MAP_VIEW.new()
	full.size = Vector2(100, 60)
	var minimap: Control = MINIMAP_VIEW.new()
	minimap.size = Vector2(30, 30)
	var full_edge: Vector2 = full._project_to_border(Vector2(180, -40))
	var mini_edge: Vector2 = minimap._project_to_border(Vector2(-20, 50))
	_check(is_equal_approx(full_edge.x, full.size.x) or is_equal_approx(full_edge.y, 0.0),
			"full Map projects an off-screen reveal to its edge")
	_check(is_equal_approx(mini_edge.x, 0.0) or is_equal_approx(mini_edge.y, minimap.size.y),
			"minimap projects an off-screen reveal to its edge")
	full.free()
	minimap.free()


func _outgoing_stub(state: MapState, room: GeneratedRoom) -> Vector2i:
	for passage in room.passages:
		var tile := _stub_for_passage(state, room, passage)
		if tile != Vector2i.MAX:
			return tile
	return Vector2i.MAX


func _stub_for_passage(state: MapState, room: GeneratedRoom, passage: RoomPassage) -> Vector2i:
	for tile: Vector2i in state.interiors.opening(passage):
		var tile_owner := state.graph.owner_at(tile)
		if tile_owner != null and tile_owner.key() != room.key():
			return tile
	return Vector2i.MAX


func _check_semantic_overlay(state: MapState, room: GeneratedRoom, wanted_class: int,
		label: String) -> void:
	var rooms: Array[GeneratedRoom] = [room]
	for candidate in state.graph.room_list:
		if candidate != room:
			rooms.append(candidate)
	for candidate in rooms:
		var interior := state.interiors.interior(candidate)
		for y in range(interior.rect.position.y, interior.rect.end.y):
			for x in range(interior.rect.position.x, interior.rect.end.x):
				var tile := Vector2i(x, y)
				if interior.class_at(tile) != wanted_class:
					continue
				var coord := Vector2i(floori(float(tile.x) / WorldPlan.CELL),
						floori(float(tile.y) / WorldPlan.CELL))
				if not state.graph.plan.cells.has(coord):
					continue
				state.discover_at(state.graph.tile_of(candidate.seed_point))
				var image := state.macro_image(coord)
				_check(image.wall_image.get_pixelv(tile - image.rect.position).a > 0.0,
						"discovered %s is present in the wall overlay" % label)
				return
	_check(false, "fixture has a %s tile for the visual check" % label)


func _owned_tile(graph: WorldGraph, room: GeneratedRoom, except: Vector2i) -> Vector2i:
	var interior := WorldFixture.interiors(graph).interior(room)
	for y in range(interior.rect.position.y, interior.rect.end.y):
		for x in range(interior.rect.position.x, interior.rect.end.x):
			var tile := Vector2i(x, y)
			if tile != except and graph.owner_at(tile) == room:
				return tile
	return Vector2i.MAX


func _expected_kind(site: ObjectSite) -> int:
	match site.kind:
		ObjectSite.Kind.SIGN:
			return MapState.MARKER_SIGN
		ObjectSite.Kind.PROFESSOR:
			return MapState.MARKER_NPC
		ObjectSite.Kind.DOOR:
			return MapState.MARKER_DOOR
		ObjectSite.Kind.WEIGHTED:
			var node := site.scene.instantiate()
			var kind := MapState.MARKER_FOUNTAIN if node is Fountain else MapState.MARKER_NPC
			node.free()
			return kind
	return -1


func _check(condition: bool, message: String) -> void:
	if not condition:
		fails.append(message)
