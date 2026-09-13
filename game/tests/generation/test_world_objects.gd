extends Node
## Objects and Warp doors at the generated-output and spawner/runtime boundaries.
##
## On the shipped World at its three seeds and on the small fixture: generated setup data for every
## Object, authored Sign, Professor and Warp-door counts, Objects only in Breathers and never in set
## pieces or the spawn, Signs revealing only the Boss their enemy leads, and Warp doors leading to a
## permitted Biome's ordinary non-Breather Room wearing its door art, the same on a second build.
##
## In a streamed rig with the real player on the small fixture: every planned Object stands once at
## its spot, a Sign reveals its Boss on the Map, every landing is clear floor away from encounters,
## a Warp door carries the player to its landing keeping its facing and streams the destination in,
## a fountain's cooldown resets on reload, and a reactive NPC's state survives unloading and a
## restore but not a new Run, while fountains, Signs and doors keep none. Run:
##   godot --headless --path game res://tests/generation/test_world_objects.tscn

const GREETER := "res://tests/support/greeter.tscn"
## Far enough that a chunk passes the streamer's unload hysteresis.
const AWAY_TILES := 100
## Where the player waits before walking into an Object, clear of its trigger.
const BESIDE := Vector2i(5, 0)
## Every Warp door's permitted destination Biomes.
const SHIPPED_TARGETS := {&"glade": [&"deepwood"], &"deepwood": [&"glade", &"wastelands"],
		&"wastelands": [&"deepwood", &"fruit"], &"fruit": [&"wastelands"], &"hive": [&"deepwood"],
		&"mycelium": [&"deepwood"], &"moon": [&"wastelands"], &"hell": [&"wastelands"]}
const SMALL_TARGETS := {&"meadow": [&"forest"], &"forest": [&"meadow"], &"burrow": [&"forest"],
		&"hollow": [&"forest"]}

var _fails: Array[String] = []


func _ready() -> void:
	var shipped := WorldFixture.shipped()
	for world_seed in shipped.seeds:
		_check_setup_data(shipped, world_seed, SHIPPED_TARGETS, "shipped %d" % world_seed)
	var small := WorldFixture.small()
	var chosen: WorldGraph = null
	for world_seed in small.seeds:
		var graph := _check_setup_data(small, world_seed, SMALL_TARGETS, "small %d" % world_seed)
		if chosen == null and _weighted(graph, GREETER) != null and _weighted(graph, "fountain") != null:
			chosen = graph
	_check(chosen != null, "some small fixture seed holds both a greeter and a fountain")
	if chosen != null:
		await _test_runtime(chosen)
	if _fails.is_empty():
		print("ALL PASS")
		get_tree().quit(0)
	else:
		for fail in _fails:
			print("  FAIL: ", fail)
		print("FAILED: %d" % _fails.size())
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_fails.append(message)


func _check_setup_data(fixture: WorldFixture, world_seed: int, targets: Dictionary, label: String) -> WorldGraph:
	var graph := fixture.graph(world_seed)
	var objects := WorldObjects.new(graph)
	var content := graph.plan.content
	var placed: Dictionary[String, int] = {}
	for key in graph.sites:
		var site := graph.sites[key]
		var room := graph.rooms[site.room_key]
		var data := objects.setup_data(site)
		_check(data.key == key and data.room_key == site.room_key and data.kind == site.kind_name(),
				"%s: %s's setup data names %s" % [label, key, data])
		_check(room.is_ordinary(), "%s: site %s stands in set piece %s" % [label, key, site.room_key])
		if not site.is_object():
			_check(objects.scene_for(site) == null, "%s: landing %s builds a scene" % [label, key])
			continue
		var count_key := "%s/%s" % [room.plan.biome, site.kind_name()]
		placed[count_key] = placed.get(count_key, 0) + 1
		_check(room.role == GeneratedRoom.Role.BREATHER, "%s: Object %s stands in a %s Room" % [label, key, room.role_name()])
		match site.kind:
			ObjectSite.Kind.SIGN:
				_check(objects.scene_for(site) == WorldObjects.SIGN_SCENE and data.text == site.sign_resource.text,
						"%s: Sign %s isn't set up with its text" % [label, key])
				var reveals := site.sign_resource.reveals
				var boss: GeneratedRoom = graph.rooms.get(data.reveal_key)
				if reveals == null:
					_check(data.reveal_key == "", "%s: Sign %s reveals %s though it names no enemy" % [label, key, data.reveal_key])
				else:
					_check(boss != null and boss.role == GeneratedRoom.Role.BOSS and boss.plan.encounter.leader == reveals,
							"%s: Sign %s reveals %s, not a Boss led by %s" % [label, key, data.reveal_key, reveals.resource_path])
			ObjectSite.Kind.DOOR:
				_check(objects.scene_for(site) == WorldObjects.DOOR_SCENE, "%s: door %s doesn't use the door scene" % [label, key])
				var destination: GeneratedRoom = graph.rooms.get(data.destination_room)
				if destination == null:
					_fails.append("%s: door %s leads to no Room (%s)" % [label, key, data.destination_room])
					continue
				_check((targets[room.plan.biome] as Array).has(destination.plan.biome),
						"%s: door %s from %s leads to %s" % [label, key, room.plan.biome, destination.plan.biome])
				_check(destination.is_ordinary() and destination.role != GeneratedRoom.Role.BREATHER,
						"%s: door %s lands in a %s Room" % [label, key, destination.role_name()])
				_check(graph.owner_at(data.landing) == destination, "%s: door %s's landing %s is outside %s" % [label, key, data.landing, destination.key()])
				_check(data.art == content.biomes[destination.plan.biome].presentation.door_style,
						"%s: door %s doesn't wear %s's art" % [label, key, destination.plan.biome])
			ObjectSite.Kind.WEIGHTED:
				_check(site.scene != null and objects.scene_for(site) == site.scene, "%s: weighted Object %s builds another scene" % [label, key])
	for id in content.biomes:
		var biome := content.biomes[id]
		var signs := biome.signs.size()
		for zone in graph.plan.biomes[id].zones:
			signs += zone.resource.signs.size()
		for pair: Array in [["sign", signs], ["professor", biome.professors], ["door", biome.warp_doors]]:
			var count: int = placed.get("%s/%s" % [id, pair[0]], 0)
			_check(count == pair[1], "%s: %s holds %d %ss, authored %d" % [label, id, count, pair[0], pair[1]])
	_check(graph.rooms[graph.plan.spawn.key].sites.is_empty(), "%s: the spawn holds sites" % label)
	_check(_setup_snapshot(fixture.graph(world_seed)) == _setup_snapshot(graph), "%s: a second build changes Object setup data" % label)
	return graph


static func _setup_snapshot(graph: WorldGraph) -> String:
	var objects := WorldObjects.new(graph)
	var keys: Array[String] = []
	keys.assign(graph.sites.keys())
	keys.sort()
	var lines: Array[String] = []
	for key in keys:
		var scene := objects.scene_for(graph.sites[key])
		lines.append("%s %s %s" % [graph.sites[key].spot, scene.resource_path if scene else "-", objects.setup_data(graph.sites[key])])
	return "\n".join(lines)


## The first weighted Object, in key order, whose scene path contains the text.
static func _weighted(graph: WorldGraph, path_part: String) -> ObjectSite:
	var keys: Array[String] = []
	keys.assign(graph.sites.keys())
	keys.sort()
	for key in keys:
		var site := graph.sites[key]
		if site.kind == ObjectSite.Kind.WEIGHTED and site.scene.resource_path.contains(path_part):
			return site
	return null


static func _first(graph: WorldGraph, kind: ObjectSite.Kind) -> ObjectSite:
	var keys: Array[String] = []
	keys.assign(graph.sites.keys())
	keys.sort()
	for key in keys:
		if graph.sites[key].kind == kind:
			return graph.sites[key]
	return null


func _test_runtime(graph: WorldGraph) -> void:
	GlobalMap.revealed_boss_keys.clear()
	var rig := _rig(graph)
	await _test_instances(rig)
	await _test_sign(rig)
	await _test_landings(rig)
	await _test_warp(rig)
	await _test_fountain(rig)
	await _test_state(rig)
	rig.viewport.queue_free()
	await get_tree().process_frame
	GlobalMap.revealed_boss_keys.clear()


## A one-pixel viewport around the real player, whose own camera the streamer follows.
func _rig(graph: WorldGraph) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i.ONE
	add_child(viewport)
	var root := Node2D.new()
	viewport.add_child(root)
	var streamer := ChunkStreamer.new()
	root.add_child(streamer)
	var entities := Node2D.new()
	root.add_child(entities)
	var enemies := EncounterSpawner.new()
	enemies.streamer = streamer
	enemies.enemies_parent = entities
	root.add_child(enemies)
	var objects := ObjectSpawner.new()
	objects.streamer = streamer
	objects.objects_parent = entities
	root.add_child(objects)
	var player: CharacterBody2D = load("res://characters/player/player.tscn").instantiate()
	entities.add_child(player)
	player.grant_spawn_grace(1e9)
	streamer.build_world(graph)
	var encounters := WorldEncounters.new(graph, streamer.interiors)
	enemies.build_world(encounters, RunDefeats.new())
	objects.build_world(WorldObjects.new(graph), true)
	streamer.target = player
	return {"viewport": viewport, "streamer": streamer, "enemies": enemies, "objects": objects,
			"player": player, "layer": player.collision_layer, "graph": graph, "encounters": encounters}


## A ghost player moves around without tripping any Object.
func _ghost(rig: Dictionary, on: bool) -> void:
	rig.player.collision_layer = 0 if on else rig.layer


func _physics(frames: int) -> void:
	for _frame in frames:
		await get_tree().physics_frame


func _visit(rig: Dictionary, tile: Vector2i) -> void:
	rig.player.global_position = (Vector2(tile) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE
	rig.streamer.prepare()
	await get_tree().process_frame


## Waits beside a site, clear of its trigger, long enough for a door to arm.
func _approach(rig: Dictionary, site: ObjectSite) -> Node2D:
	_ghost(rig, true)
	await _visit(rig, site.spot + BESIDE)
	await _physics(4)
	var live := _live_with(rig, site.key)
	return live[0] if live.size() == 1 else null


## Walks into an Object's trigger.
func _enter(rig: Dictionary, node: Node2D) -> void:
	_ghost(rig, false)
	rig.player.global_position = node.global_position + Vector2(0, -4)
	await _physics(4)


## Streams the site's chunk out and back in, returning beside the site.
func _reload(rig: Dictionary, site: ObjectSite) -> void:
	_ghost(rig, true)
	var world_tiles: Vector2i = rig.graph.plan.size * WorldPlan.CELL
	await _visit(rig, site.spot + Vector2i(AWAY_TILES if site.spot.x < world_tiles.x >> 1 else -AWAY_TILES, 0))
	_check(_live_with(rig, site.key).is_empty(), "moving away unloaded %s" % site.key)
	await _visit(rig, site.spot + BESIDE)


func _live_with(rig: Dictionary, key: String) -> Array[Node2D]:
	var out: Array[Node2D] = []
	for node: Node2D in rig.objects.live_objects():
		if node.get_meta("generated_key", "") == key:
			out.append(node)
	return out


func _test_instances(rig: Dictionary) -> void:
	var graph: WorldGraph = rig.graph
	var objects: WorldObjects = rig.objects.world_objects
	var planned: Array[String] = []
	for key in graph.sites:
		# No Professor scene exists yet, so Professor sites build nothing.
		if graph.sites[key].is_object() and graph.sites[key].kind != ObjectSite.Kind.PROFESSOR:
			planned.append(key)
			_check(objects.scene_for(graph.sites[key]) != null, "Object %s has no scene" % key)
	planned.sort()
	_check(not planned.is_empty(), "the fixture plans Objects")
	_ghost(rig, true)
	for key in planned:
		var site := graph.sites[key]
		await _visit(rig, site.spot)
		var live := _live_with(rig, key)
		_check(live.size() == 1, "%s stands %d times once its chunk loads" % [key, live.size()])
		if live.size() == 1:
			_check(live[0].position == (Vector2(site.spot) + Vector2(0.5, 0.5)) * GameConstants.PX_PER_TILE,
					"%s stands at %s, not its spot %s" % [key, live[0].position, site.spot])
		var seen: Dictionary[String, bool] = {}
		for node: Node2D in rig.objects.live_objects():
			var node_key: String = node.get_meta("generated_key")
			_check(not seen.has(node_key), "%s stands twice while %s loads" % [node_key, key])
			seen[node_key] = true
	var first := graph.sites[planned[0]]
	await _visit(rig, first.spot)
	var before := _live_with(rig, first.key)
	var before_id := before[0].get_instance_id() if before.size() == 1 else 0
	await _reload(rig, first)
	var after := _live_with(rig, first.key)
	_check(after.size() == 1 and before.size() == 1 and after[0].get_instance_id() != before_id,
			"reloading %s's chunk builds it again, once" % first.key)
	var spawn_tile := Vector2i((rig.streamer.spawn_position() / GameConstants.PX_PER_TILE).floor())
	await _visit(rig, spawn_tile)
	for node: Node2D in rig.objects.live_objects() + rig.enemies.live_members():
		var room: GeneratedRoom = rig.streamer.interiors.owner_at(Vector2i((node.position / GameConstants.PX_PER_TILE).floor()))
		_check(room == null or room.role != GeneratedRoom.Role.SPAWN, "%s stands in the spawn" % node.name)


func _test_sign(rig: Dictionary) -> void:
	var site := _first(rig.graph, ObjectSite.Kind.SIGN)
	_check(site != null and site.reveal_key != "", "the fixture has a revealing Sign")
	if site == null:
		return
	var sign_node := await _approach(rig, site)
	_check(sign_node != null and GlobalMap.revealed_boss_keys.is_empty(), "Sign %s stands and nothing is revealed before reading" % site.key)
	if sign_node == null:
		return
	await _enter(rig, sign_node)
	_check(sign_node.get_node("Label").visible, "reading Sign %s shows its text" % site.key)
	_check(GlobalMap.revealed_boss_keys.size() == 1 and GlobalMap.revealed_boss_keys.has(site.reveal_key)
			and rig.graph.rooms[site.reveal_key].role == GeneratedRoom.Role.BOSS,
			"reading Sign %s reveals %s, want only its Boss %s" % [site.key, GlobalMap.revealed_boss_keys.keys(), site.reveal_key])


## Every landing is clear ordinary floor with its destination's encounters kept away.
func _test_landings(rig: Dictionary) -> void:
	var graph: WorldGraph = rig.graph
	for key in graph.sites:
		var landing := graph.sites[key]
		if landing.kind != ObjectSite.Kind.LANDING:
			continue
		_check(rig.streamer.interiors.class_at(landing.spot) == WorldInteriors.FLOOR, "landing %s isn't floor" % key)
		for encounter: GeneratedEncounter in rig.encounters.for_room(graph.rooms[landing.room_key]):
			for member in encounter.members:
				_check(Vector2(member.tile).distance_to(Vector2(landing.spot)) >= WorldEncounters.LANDING_CLEARANCE,
						"member %s stands %.1f tiles from landing %s" % [member.key, Vector2(member.tile).distance_to(Vector2(landing.spot)), key])


func _test_warp(rig: Dictionary) -> void:
	var door := _first(rig.graph, ObjectSite.Kind.DOOR)
	_check(door != null, "the fixture has a Warp door")
	if door == null:
		return
	var landing: Vector2i = rig.graph.sites[door.landing_key].spot
	var door_node := await _approach(rig, door)
	_check(door_node != null, "door %s stands" % door.key)
	if door_node == null:
		return
	var arrivals: Array[Array] = []
	rig.objects.warped.connect(func(body: Node2D, room_key: String) -> void: arrivals.append([body, room_key]))
	rig.player.animated_sprite.flip_h = true
	await _enter(rig, door_node)
	for _frame in 20:
		if not arrivals.is_empty():
			break
		await get_tree().physics_frame
	_check(arrivals.size() == 1 and arrivals[0][0] == rig.player and arrivals[0][1] == door.destination_room,
			"walking into door %s warps the player once to %s: %s" % [door.key, door.destination_room, arrivals])
	var tile := Vector2i((rig.player.global_position / GameConstants.PX_PER_TILE).floor())
	_check(tile == landing, "door %s put the player at %s, not its landing %s" % [door.key, tile, landing])
	var room: GeneratedRoom = rig.streamer.interiors.owner_at(tile)
	_check(room != null and room.key() == door.destination_room and room.is_ordinary() and room.role != GeneratedRoom.Role.BREATHER,
			"door %s landed in %s" % [door.key, room.key() if room else "no Room"])
	_check(rig.streamer.interiors.class_at(tile) == WorldInteriors.FLOOR, "door %s landed off floor" % door.key)
	_check(rig.player.animated_sprite.flip_h, "warping through %s turned the player around" % door.key)
	_check(rig.streamer.is_chunk_loaded(rig.streamer.chunk_of(rig.player.global_position)), "the landing streamed in with the arrival")
	for enemy in rig.enemies.live_members():
		_check(enemy.global_position.distance_to(rig.player.global_position) > 4 * GameConstants.PX_PER_TILE,
				"%s waits within four tiles of the arrival" % enemy.get_meta("generated_key"))


func _test_fountain(rig: Dictionary) -> void:
	var site := _weighted(rig.graph, "fountain")
	var fountain := await _approach(rig, site)
	_check(fountain != null, "fountain %s stands" % site.key)
	if fountain == null:
		return
	rig.player.health = 1
	await _enter(rig, fountain)
	_check(rig.player.health == rig.player.max_health, "fountain %s healed the player to %d" % [site.key, rig.player.health])
	var sprite: AnimatedSprite2D = fountain.get_node("AnimatedSprite2D")
	_check(String(sprite.animation).ends_with("_dormant"), "a used fountain shows %s" % sprite.animation)
	await _reload(rig, site)
	var again := _live_with(rig, site.key)
	_check(again.size() == 1 and String(again[0].get_node("AnimatedSprite2D").animation).ends_with("_flow"),
			"fountain %s's cooldown resets when its chunk reloads" % site.key)


## Runs last: the Sign, door and fountain above were all used and must have left no state.
func _test_state(rig: Dictionary) -> void:
	var site := _weighted(rig.graph, GREETER)
	var spawner: ObjectSpawner = rig.objects
	var greeter := await _approach(rig, site)
	_check(greeter != null and not greeter.has_greeted(), "greeter %s stands and hasn't greeted" % site.key)
	if greeter == null:
		return
	await _enter(rig, greeter)
	_check(greeter.has_greeted(), "walking up to greeter %s changes its state" % site.key)
	var saved := spawner.saved_states()
	_check(saved.size() == 1 and saved.has(site.key) and saved[site.key] == {"greeted": true},
			"saved Object states are %s, want only the greeter's" % saved)
	await _reload(rig, site)
	var reloaded := _live_with(rig, site.key)
	_check(reloaded.size() == 1 and reloaded[0].has_greeted(), "greeter %s remembers greeting after its chunk reloads" % site.key)
	spawner.build_world(WorldObjects.new(rig.graph), true)
	var fresh := _live_with(rig, site.key)
	_check(fresh.size() == 1 and not fresh[0].has_greeted() and spawner.saved_states().is_empty(),
			"a new Run's greeter %s starts without state" % site.key)
	spawner.restore_states(saved)
	spawner.build_world(WorldObjects.new(rig.graph))
	var restored := _live_with(rig, site.key)
	_check(restored.size() == 1 and restored[0].has_greeted(), "restored state reaches greeter %s's setup" % site.key)
