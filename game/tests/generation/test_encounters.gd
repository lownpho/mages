extends Node
## Encounters at the generated-output boundary, on the shipped World at three seeds and the small
## fixture: eligibility, weighted distinct-type limits, group ranges, walkable-area counts, Teaching
## dips and once-per-route introductions, Fixed membership and placement, Hazard eligibility and
## density, clearances, loose packs, untouching enemies and spread centres, repeated/shuffled build
## order and decoration independence; then live spawning in the development World and its debug
## counts. Run:
##   godot --headless --path game res://tests/generation/test_encounters.tscn

var _fails: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var small := WorldFixture.small()
	var shipped := WorldFixture.shipped()
	_check(small.content.is_valid() and shipped.content.is_valid(), "test Worlds have content problems")
	for fixture: WorldFixture in [shipped, small]:
		for world_seed in fixture.seeds:
			_check_world(fixture.graph(world_seed), "%s seed %d" % ["shipped" if fixture == shipped else "small", world_seed])
	_test_order_independence(small)
	_test_centre_spread(shipped)
	_test_weights(small)
	_test_curve_interpolation()
	_test_fixed_dictionary_order()
	_test_fixed_ignores_density(small)
	_test_decoration_independence(small)
	await _test_development_runtime()
	print("encounter tests took %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails.slice(0, 80):
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


## encounters_per_tile ramps between its keys; types_per_encounter, a whole count, still steps.
func _test_curve_interpolation() -> void:
	var curve := ChallengeCurveResource.new()
	curve.encounters_per_tile = {0: 0.002, 4: 0.003, 10: 0.003}
	curve.types_per_encounter = {0: 1, 5: 3}
	for at: Array in [[0, 0.002], [2, 0.0025], [4, 0.003], [7, 0.003], [10, 0.003], [99, 0.003]]:
		_check(is_equal_approx(curve.encounter_density(at[0]), at[1]),
				"density at Challenge %d is %f, not %f" % [at[0], curve.encounter_density(at[0]), at[1]])
	for at: Array in [[0, 1], [4, 1], [5, 3], [99, 3]]:
		_check(curve.encounter_types(at[0]) == at[1],
				"types at Challenge %d is %d, not %d" % [at[0], curve.encounter_types(at[0]), at[1]])

func _check_world(graph: WorldGraph, label: String) -> void:
	_check(graph != null, "%s built a graph" % label)
	if graph == null:
		return
	var generated := WorldFixture.encounter_world(graph)
	var curve := graph.plan.content.curve
	for room in graph.room_list:
		var room_encounters := generated.for_room(room)
		_check(generated.built_count(room) == room_encounters.size(),
				"%s: %s exposes its encounter count" % [label, room.key()])
		if room.role == GeneratedRoom.Role.TEACHING:
			_check(not room_encounters.is_empty(), "%s: Teaching room %s has no encounter" % [label, room.key()])
		_check_hazards(graph, generated, room, label)
		_check_apart(generated, room, label)
		if room.role in [GeneratedRoom.Role.SPAWN, GeneratedRoom.Role.BREATHER]:
			_check(room_encounters.is_empty(), "%s: %s %s has encounters" % [label, room.role_name(), room.key()])
			continue
		if room.is_set_piece():
			_check_fixed(graph, generated, room, room_encounters, label)
			continue
		if room.roster.is_empty():
			_check(room_encounters.is_empty(), "%s: empty-roster room %s has encounters" % [label, room.key()])
			continue
		var challenge := room.plan.challenge - curve.teach_dip if room.teaching != null else room.plan.challenge
		challenge = maxi(0, challenge)
		var expected := generated.walkable_tiles(room).size() * curve.encounter_density(challenge)
		var allowed := [floori(expected), ceili(expected)]
		if room.teaching != null:
			allowed.append(1)
		_check(room_encounters.size() in allowed,
				"%s: %s count %d isn't seeded rounding of %.3f" % [label, room.key(), room_encounters.size(), expected])
		for encounter in room_encounters:
			_check_ordinary(graph, room, encounter, challenge, label)
	_check(generated.members.size() > 0, "%s generated no encounter members" % label)
	_check_introductions(graph, generated, label)


## Each route introduces every enemy in exactly one Room's encounters: the Ideal path as one route,
## each Side route on its own.
func _check_introductions(graph: WorldGraph, generated: WorldEncounters, label: String) -> void:
	var plan := graph.plan
	var routes: Array[Array] = [plan.content.ideal_path.map(func(id: StringName) -> BiomePlan: return plan.biomes[id])]
	for side in plan.content.parents:
		routes.append([plan.biomes[side]])
	for biomes: Array in routes:
		var fielded: Dictionary[CreatureResource, bool] = {}
		var introduced: Dictionary[CreatureResource, Dictionary] = {}
		for biome: BiomePlan in biomes:
			for route_room in biome.route:
				var roster := graph.rooms[route_room.key].roster
				for enemy in roster:
					if roster[enemy] <= route_room.challenge and not enemy.is_hazard():
						fielded[enemy] = true
			for room_plan in biome.rooms:
				var room := graph.rooms[room_plan.key]
				for encounter in generated.for_room(room):
					for member in encounter.members:
						if member.teaching:
							introduced.get_or_add(member.enemy, {})[room.key()] = true
		var route_name := "+".join(biomes.map(func(biome: BiomePlan) -> String: return biome.id))
		for enemy in introduced:
			_check(introduced[enemy].size() == 1, "%s: %s introduces %s in %d Rooms" % [label, route_name,
					enemy.resource_path.get_file(), introduced[enemy].size()])
		_check(introduced.size() == fielded.size(), "%s: %s introduces %d of its %d enemies" % [label, route_name,
				introduced.size(), fielded.size()])


func _check_ordinary(graph: WorldGraph, room: GeneratedRoom, encounter: GeneratedEncounter,
		challenge: int, label: String) -> void:
	var counts := encounter.enemy_counts()
	var selected: Dictionary[CreatureResource, bool] = {}
	var spread := WorldEncounters.PACK_SPREAD * sqrt(encounter.members.size()) * WorldEncounters.PACK_STRETCH
	for member in encounter.members:
		_check(member.key.begins_with(encounter.key + "/member/") and member.encounter_key == encounter.key,
				"%s: member key does not follow encounter %s" % [label, encounter.key])
		_check(graph.owner_at(member.tile) == room and graph.plan != null,
				"%s: %s member lies outside %s" % [label, member.key, room.key()])
		_check(Vector2(member.tile).distance_to(Vector2(encounter.centre)) <= spread,
				"%s: %s lies outside encounter spread" % [label, member.key])
		_check(not member.hazard, "%s: encounter member %s is marked as a Hazard" % [label, member.key])
		if member.teaching:
			_check(member.enemy == room.teaching, "%s: wrong Teaching member in %s" % [label, room.key()])
		else:
			selected[member.enemy] = true
	for enemy in selected:
		_check(room.roster.has(enemy) and room.roster[enemy] <= challenge and not enemy.is_hazard(),
				"%s: ineligible selected type %s in %s" % [label, enemy.resource_path, room.key()])
	_check(selected.size() <= graph.plan.content.curve.encounter_types(challenge),
			"%s: %s exceeds its distinct-type limit" % [label, encounter.key])
	for enemy in counts:
		_check(counts[enemy] >= enemy.group_min and counts[enemy] <= enemy.group_max,
				"%s: %s group of %d is outside %d-%d" % [label, enemy.resource_path, counts[enemy], enemy.group_min, enemy.group_max])
	if room.teaching != null:
		_check(encounter.challenge == maxi(0, room.plan.challenge - graph.plan.content.curve.teach_dip),
				"%s: %s did not use the Teaching dip" % [label, room.key()])
		_check(counts.has(room.teaching) and encounter.members.any(func(member: EncounterMember) -> bool:
			return member.enemy == room.teaching and member.teaching),
				"%s: %s does not introduce its planned enemy" % [label, room.key()])
	for site in room.sites:
		var clearance := WorldEncounters.LANDING_CLEARANCE if site.kind == ObjectSite.Kind.LANDING else WorldEncounters.OBJECT_CLEARANCE
		for member in encounter.members:
			_check(Vector2(member.tile).distance_to(Vector2(site.spot)) >= clearance,
					"%s: %s violates site clearance at %s" % [label, member.key, site.key])


## Hazards stand only in Testing and Teaching rooms, at the Room's own undipped Challenge and their
## seeded density, clear of Object sites, keyed by Room and enemy, and belong to no encounter.
func _check_hazards(graph: WorldGraph, generated: WorldEncounters, room: GeneratedRoom, label: String) -> void:
	var hazards := generated.hazards_for_room(room)
	if room.role not in [GeneratedRoom.Role.TESTING, GeneratedRoom.Role.TEACHING]:
		_check(hazards.is_empty(), "%s: %s %s has Hazards" % [label, room.role_name(), room.key()])
		return
	var counts: Dictionary[CreatureResource, int] = {}
	for member in hazards:
		_check(member.hazard and member.enemy.is_hazard() and member.encounter_key == ""
				and member.key.begins_with("%s/hazard/%s/" % [room.key(), member.enemy_id()])
				and generated.members.get(member.key) == member,
				"%s: %s isn't a Hazard of %s" % [label, member.key, room.key()])
		_check(room.roster.has(member.enemy) and room.roster[member.enemy] <= room.plan.challenge,
				"%s: ineligible Hazard %s" % [label, member.key])
		_check(graph.owner_at(member.tile) == room, "%s: Hazard %s lies outside %s" % [label, member.key, room.key()])
		counts[member.enemy] = counts.get(member.enemy, 0) + 1
		for site in room.sites:
			var clearance := WorldEncounters.LANDING_CLEARANCE if site.kind == ObjectSite.Kind.LANDING else WorldEncounters.OBJECT_CLEARANCE
			_check(Vector2(member.tile).distance_to(Vector2(site.spot)) >= clearance,
					"%s: Hazard %s violates site clearance at %s" % [label, member.key, site.key])
	var floor_size := generated.walkable_tiles(room).size()
	for enemy in room.roster:
		if not enemy.is_hazard() or room.roster[enemy] > room.plan.challenge:
			continue
		var expected := floor_size * enemy.hazards_per_tile
		_check(counts.get(enemy, 0) in [floori(expected), ceili(expected)],
				"%s: %s holds %d %s, not seeded rounding of %.2f" % [label, room.key(), counts.get(enemy, 0),
				enemy.resource_path.get_file(), expected])


## No two generated enemies of a Room share or touch a tile.
func _check_apart(generated: WorldEncounters, room: GeneratedRoom, label: String) -> void:
	var enemies := generated.hazards_for_room(room)
	for encounter in generated.for_room(room):
		enemies.append_array(encounter.members)
	for a in enemies.size():
		for b in range(a + 1, enemies.size()):
			var gap := (enemies[a].tile - enemies[b].tile).abs()
			_check(maxi(gap.x, gap.y) >= 2, "%s: %s touches %s" % [label, enemies[a].key, enemies[b].key])


## Ordinary encounter centres spread over their Rooms: their nearest-centre distances clearly beat
## the same number of centres dropped on random floor tiles.
func _test_centre_spread(fixture: WorldFixture) -> void:
	var generated := WorldFixture.encounter_world(fixture.graph(fixture.seeds[0]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var spread := 0.0
	var random := 0.0
	for room in generated.graph.room_list:
		var room_encounters := generated.for_room(room)
		if room.role != GeneratedRoom.Role.TESTING or room_encounters.size() < 2:
			continue
		var floor_tiles := generated.walkable_tiles(room)
		var dropped: Array[Vector2i] = []
		for _encounter in room_encounters:
			dropped.append(floor_tiles[rng.randi_range(0, floor_tiles.size() - 1)])
		spread += _mean_nearest(room_encounters.map(func(encounter: GeneratedEncounter) -> Vector2i: return encounter.centre))
		random += _mean_nearest(dropped)
	_check(random > 0.0, "shipped World has Testing rooms with several encounters")
	print("encounter centres: mean nearest %.1f, random floor %.1f" % [spread, random])
	_check(spread > random * 1.25, "encounter centres don't spread (%.1f vs random %.1f)" % [spread, random])


static func _mean_nearest(points: Array) -> float:
	var total := 0.0
	for a in points.size():
		var nearest := INF
		for b in points.size():
			if a != b:
				nearest = minf(nearest, Vector2(points[a]).distance_to(Vector2(points[b])))
		total += nearest
	return total / points.size()


func _check_fixed(graph: WorldGraph, _generated: WorldEncounters, room: GeneratedRoom,
		room_encounters: Array[GeneratedEncounter], label: String) -> void:
	_check(room_encounters.size() == 1, "%s: Fixed Room %s does not hold one encounter" % [label, room.key()])
	if room_encounters.is_empty():
		return
	var encounter := room_encounters[0]
	var authored := room.plan.encounter
	var expected: Dictionary[CreatureResource, int] = {authored.leader: 1}
	for escort in authored.escorts:
		expected[escort] = expected.get(escort, 0) + authored.escorts[escort]
	_check(encounter.fixed and encounter.enemy_counts() == expected,
			"%s: Fixed membership differs in %s" % [label, room.key()])
	_check(not encounter.members.is_empty() and encounter.members[0].leader
			and encounter.members[0].enemy == authored.leader,
			"%s: Fixed leader is not explicit in %s" % [label, room.key()])
	if authored.centred:
		_check(encounter.members[0].tile == graph.tile_of(room.seed_point),
				"%s: centred leader in %s is not on the Room centre" % [label, room.key()])


func _test_order_independence(fixture: WorldFixture) -> void:
	var graph := fixture.graph(fixture.seeds[0])
	var expected := WorldFixture.encounter_snapshot(WorldFixture.encounter_world(graph))
	var repeated := fixture.graph(fixture.seeds[0])
	var reversed := repeated.room_list.duplicate()
	reversed.reverse()
	_check(WorldFixture.encounter_snapshot(WorldFixture.encounter_world(repeated, reversed)) == expected,
			"repeated encounter output changed when Rooms were requested in reverse")
	var shuffled := repeated.room_list.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	for index in range(shuffled.size() - 1, 0, -1):
		var other := rng.randi_range(0, index)
		var held: GeneratedRoom = shuffled[index]
		shuffled[index] = shuffled[other]
		shuffled[other] = held
	_check(WorldFixture.encounter_snapshot(WorldFixture.encounter_world(repeated, shuffled)) == expected,
			"encounter output changed when Rooms were requested in shuffled order")


func _test_weights(fixture: WorldFixture) -> void:
	var graph := fixture.graph(fixture.seeds[0])
	var room: GeneratedRoom
	for candidate in graph.room_list:
		if candidate.role != GeneratedRoom.Role.TESTING or candidate.plan.challenge >= 3:
			continue
		var eligible := candidate.roster.keys().filter(func(enemy: CreatureResource) -> bool:
			return candidate.roster[enemy] <= candidate.plan.challenge and not enemy.is_hazard())
		if eligible.size() >= 2:
			room = candidate
			break
	_check(room != null, "fixture has a low-Challenge Testing Room for weighted selection")
	if room == null:
		return
	var choices: Array[CreatureResource] = []
	choices.assign(room.roster.keys().filter(func(enemy: CreatureResource) -> bool:
		return room.roster[enemy] <= room.plan.challenge and not enemy.is_hazard()))
	choices.sort_custom(func(a: CreatureResource, b: CreatureResource) -> bool: return a.resource_path < b.resource_path)
	var heavy := choices[0]
	var light := choices[1]
	var old_heavy := heavy.weight
	var old_light := light.weight
	heavy.weight = 100
	light.weight = 1
	var original_seed := graph.plan.world_seed
	var heavy_picks := 0
	var light_picks := 0
	var field := WorldFixture.interiors(graph)
	for sample in 80:
		graph.plan.world_seed = 10_000 + sample
		for encounter in WorldEncounters.new(graph, field).for_room(room):
			var counts := encounter.enemy_counts()
			heavy_picks += int(counts.has(heavy))
			light_picks += int(counts.has(light))
	graph.plan.world_seed = original_seed
	heavy.weight = old_heavy
	light.weight = old_light
	_check(heavy_picks > light_picks * 8,
			"global weights did not favour the heavy type (%d vs %d)" % [heavy_picks, light_picks])


func _test_fixed_dictionary_order() -> void:
	var fixture := WorldFixture.shipped()
	var graph := fixture.graph(fixture.seeds[0])
	var room: GeneratedRoom
	for candidate in graph.room_list:
		if candidate.is_set_piece() and candidate.plan.encounter != null and candidate.plan.encounter.escorts.size() >= 2:
			room = candidate
			break
	_check(room != null, "shipped content has a Fixed encounter with multiple escort types")
	if room == null:
		return
	var field := WorldFixture.interiors(graph)
	var expected := _room_snapshot(WorldEncounters.new(graph, field).for_room(room))
	var authored := room.plan.encounter
	var before := authored.escorts.duplicate()
	var reversed: Dictionary[CreatureResource, int] = {}
	var keys := authored.escorts.keys()
	keys.reverse()
	for enemy in keys:
		reversed[enemy] = authored.escorts[enemy]
	authored.escorts = reversed
	var actual := _room_snapshot(WorldEncounters.new(graph, field).for_room(room))
	authored.escorts = before
	_check(actual == expected, "Fixed encounter output depends on escort Dictionary order")


## Fixed encounters ignore the density curve: scaling it changes ordinary counts but no set piece.
func _test_fixed_ignores_density(fixture: WorldFixture) -> void:
	var graph := fixture.graph(fixture.seeds[0])
	var field := WorldFixture.interiors(graph)
	var set_pieces := graph.room_list.filter(func(room: GeneratedRoom) -> bool: return room.is_isolated())
	_check(not set_pieces.is_empty(), "fixture has Fixed encounters")
	var before: Array[String] = []
	var generated := WorldEncounters.new(graph, field)
	for room: GeneratedRoom in set_pieces:
		before.append(_room_snapshot(generated.for_room(room)))
	var testing := graph.room_list.filter(func(room: GeneratedRoom) -> bool: return room.role == GeneratedRoom.Role.TESTING)
	var counts := testing.map(func(room: GeneratedRoom) -> int: return generated.for_room(room).size())
	var curve := graph.plan.content.curve
	var authored := curve.encounters_per_tile.duplicate()
	for step in curve.encounters_per_tile:
		curve.encounters_per_tile[step] *= 10.0
	var denser := WorldEncounters.new(graph, field)
	var after: Array[String] = []
	for room: GeneratedRoom in set_pieces:
		after.append(_room_snapshot(denser.for_room(room)))
	var ordinary_changed := testing.map(func(room: GeneratedRoom) -> int: return denser.for_room(room).size()) != counts
	curve.encounters_per_tile = authored
	_check(ordinary_changed, "scaling the density curve changed no ordinary Room")
	_check(after == before, "the density curve changed a Fixed encounter")


func _test_decoration_independence(fixture: WorldFixture) -> void:
	var graph := fixture.graph(fixture.seeds[0])
	var expected := WorldFixture.encounter_snapshot(WorldFixture.encounter_world(graph))
	var biome: BiomeResource = fixture.content.biomes[&"forest"]
	var zone_id: StringName = fixture.content.zones[&"forest"].keys()[0]
	var zone: ZoneResource = fixture.content.zones[&"forest"][zone_id]
	var old_biome := biome.decoration_density
	var old_zone := zone.decoration_density
	biome.decoration_density = 0.99
	zone.decoration_density = 0.91
	var changed := WorldFixture.encounter_snapshot(WorldFixture.encounter_world(fixture.graph(fixture.seeds[0])))
	biome.decoration_density = old_biome
	zone.decoration_density = old_zone
	_check(changed == expected, "decoration-only edits changed encounter output")


func _test_development_runtime() -> void:
	# Entering the World saves the Run; keep that off the player's save.
	GameState.save_path = "user://test_encounters_save.cfg"
	var world: Node = load("res://scenes/world.tscn").instantiate()
	world.world_seed = 7
	add_child(world)
	await get_tree().process_frame
	var keys: Array[String] = world._encounter_spawner.live_member_keys()
	_check(not keys.is_empty(), "development World streamed no live encounter enemies")
	var live := 0
	for enemy in world._entities.get_children():
		if enemy.has_meta("generated_key"):
			live += 1
			var member: EncounterMember = world._encounters.members.get(enemy.get_meta("generated_key"))
			_check(member != null and enemy.get_meta("encounter_key") == member.encounter_key
					and enemy.get_meta("room_key") == member.room_key,
					"live enemy %s doesn't carry its member's place-derived keys" % enemy.get_meta("generated_key"))
	_check(live == keys.size(), "live generated enemies (%d) differ from spawner keys (%d)" % [live, keys.size()])
	# The debug overlays report built Rooms' counts; the Map builds a hovered Room on demand.
	var layer: Node = world._debug_layer
	_check(layer != null, "development World has its debug layer")
	if layer != null:
		var room: GeneratedRoom = world._graph.rooms[world._encounters.members[keys[0]].room_key] if not keys.is_empty() else null
		_check(room != null and layer._world_overlay.encounters.built_count(room) == world._encounters.for_room(room).size(),
				"World overlay doesn't report a streamed Room's encounter count")
		var far: GeneratedRoom = world._graph.room_list[-1]
		layer._map.hovered = null
		layer._map._update_hover(layer._map.screen_at(far.seed_point))
		_check(layer._map.hovered == far and layer._map.tooltip_text.ends_with("encounters %d" % world._encounters.encounter_count(far)),
				"debug Map hover doesn't report %s's encounter count: %s" % [far.key(), layer._map.tooltip_text])
	world.queue_free()
	await get_tree().process_frame
	DirAccess.remove_absolute(GameState.save_path)


static func _room_snapshot(room_encounters: Array[GeneratedEncounter]) -> String:
	var lines: Array[String] = []
	for encounter in room_encounters:
		for member in encounter.members:
			lines.append("%s:%s:%s:%s" % [member.key, member.enemy.resource_path, member.tile, member.leader])
	return "\n".join(lines)
