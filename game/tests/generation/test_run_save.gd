extends Node
## The complete Run through GameState's lifecycle, on the small fixture World entered through the
## finite development World. A New Run is played (inventory, Map discovery, a Pin, a Boss reveal, an
## ordinary death beside a hurt survivor, a Fixed defeat, a reactive Object's state, position and
## health), quit and continued: Continue must rebuild the same World, restore every record and the
## discovered Map's pixels, keep offline time from counting toward respawn and still bring the dead
## member back once the delay passes in play. A save from another version hides Continue; debug seed
## and knob edits stop every write while movement and item actions don't; death deletes the Run and
## leaves the Bestiary and Grimoire files. Run:
##   godot --headless --path game res://tests/generation/test_run_save.tscn

const SAVE := "user://test_run_save.cfg"
const SPELL := "res://characters/player/spells/pew/pew1.tres"
const OTHER_SPELL := "res://characters/player/spells/blam/blam1.tres"
const GREETER := "res://tests/support/greeter.tscn"
## Where the player waits before walking into an Object, clear of its trigger.
const BESIDE := Vector2i(5, 0)

var _fails: Array[String] = []
var _plain: Dictionary[StringName, bool] = {}


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var debug_state := {"world_debug": _snapshot_state("world_debug"), "combat_lab": _snapshot_state("combat_lab")}
	DebugState.set_value("world_debug", "fly", false)
	var files := {GlobalBestiary.SAVE_PATH: _snapshot(GlobalBestiary.SAVE_PATH),
			GlobalGrimoire.SAVE_PATH: _snapshot(GlobalGrimoire.SAVE_PATH)}
	var real_bestiary := GlobalBestiary.to_dict()
	var real_grimoire := GlobalGrimoire.to_dict()
	GameState.save_path = SAVE
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)

	var world := await _test_quit_and_continue()
	if world != null:
		await _test_save_restrictions(world)
		_test_version_mismatch()
		await _test_death(world)

	GameState.save_path = GameState.SAVE_PATH
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""
	GlobalInventory.reset()
	GlobalMap.reset()
	for section in debug_state:
		_restore_state(section, debug_state[section])
	GlobalBestiary.restore(real_bestiary)
	GlobalGrimoire.restore(real_grimoire)
	for path in files:
		_restore(path, files[path])
	print("run save tests took %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
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


## Enters the development World on the small fixture, as the title's New or Continue would.
func _enter() -> Node2D:
	var world: Node2D = load("res://generation/dev/walk_world.tscn").instantiate()
	world.content_root = WorldFixture.SMALL
	add_child(world)
	await get_tree().process_frame
	world._set_flying(true) # enemies ignore the player
	return world


func _visit(world: Node2D, tile: Vector2i) -> void:
	world._teleport_to_tile(tile)
	await get_tree().process_frame


## Streams a tile's chunk out, from the farthest Room, and back in.
func _reload(world: Node2D, tile: Vector2i) -> void:
	var graph: WorldGraph = world._graph
	var far := graph.room_list[0]
	for room in graph.room_list:
		if graph.tile_of(room.seed).distance_squared_to(tile) > graph.tile_of(far.seed).distance_squared_to(tile):
			far = room
	await _visit(world, graph.tile_of(far.seed))
	var streamer: ChunkStreamer = world._streamer
	_check(not streamer.is_chunk_loaded(streamer.chunk_of(Vector2(tile * GameConstants.PX_PER_TILE))),
			"moving away unloaded the chunk at %s" % tile)
	await _visit(world, tile)


func _live(world: Node2D, key: String) -> Node2D:
	for node in world._entities.get_children():
		if node.get_meta("generated_key", "") == key and not node.is_queued_for_deletion():
			return node
	return null


## Enemies without a death throe die on the call, with no FSM frames needed.
func _dies_at_once(member: EncounterMember) -> bool:
	var id := member.enemy_id()
	if not _plain.has(id):
		var scene := load("%s/%s.tscn" % [member.enemy.resource_path.get_base_dir(), id]) as PackedScene
		var probe := scene.instantiate()
		_plain[id] = probe.death_state == ""
		probe.free()
	return _plain[id]


func _inventory_paths() -> Array[String]:
	var out: Array[String] = []
	for i in GlobalInventory.SPELL_SLOTS:
		var item := GlobalInventory.spell_slots.at(i).item
		out.append(item.resource_path if item != null else "")
	for i in GlobalInventory.BAG_SIZE:
		var item := GlobalInventory.bag_slots.at(i).item
		out.append(item.resource_path if item != null else "")
	return out


## Everything the Map shows: its records, derived markers and each discovered macro cell's pixels.
func _map_view(map: MapState) -> Dictionary:
	var entered: Array = map.entered_rooms.keys()
	entered.sort()
	var revealed: Array = map.revealed_bosses.keys()
	revealed.sort()
	var images := {}
	var bounds := map.discovered_bounds()
	var first := Vector2i((Vector2(bounds.position) / WorldPlan.CELL).floor())
	var last := Vector2i((Vector2(bounds.end) / WorldPlan.CELL).floor())
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := map.macro_image(Vector2i(x, y))
			if cell != null:
				images[Vector2i(x, y)] = [cell.floor_image.get_data(), cell.wall_image.get_data()]
	return {"entered": entered, "pins": map.pins.duplicate(), "revealed": revealed,
			"markers": var_to_str(map.markers), "images": images}


func _test_quit_and_continue() -> Node2D:
	# Not every fixture seed's Breathers draw a greeter.
	var fixture := WorldFixture.small()
	var world_seed := 0
	for candidate in fixture.seeds:
		for site: ObjectSite in fixture.graph(candidate).sites.values():
			if world_seed == 0 and site.kind == ObjectSite.Kind.WEIGHTED and site.scene.resource_path == GREETER:
				world_seed = candidate
	_check(world_seed != 0, "some small fixture seed plans a greeter")
	GameState.new_game()
	GameState.active_seed = world_seed
	var world := await _enter()
	_check(GameState.has_save(), "entering a new Run saved it")
	var graph: WorldGraph = world._graph
	var graph_text := WorldFixture.graph_snapshot(graph)
	var spawner: EncounterSpawner = world._encounter_spawner
	var defeats := spawner.defeats
	var everything := WorldFixture.encounter_world(graph)

	GlobalInventory.spell_slots.at(0).set_item(load(SPELL))
	GlobalInventory.bag_slots.at(1).set_item(load(OTHER_SPELL))

	# An ordinary encounter: one member dies, one is only hurt.
	var chosen: GeneratedEncounter = null
	for key in everything.encounters:
		var encounter := everything.encounters[key]
		if not encounter.fixed and encounter.members.size() >= 2 and encounter.members.slice(0, 2).all(_dies_at_once) \
				and encounter.members[1].enemy.max_health > 1:
			chosen = encounter
			break
	_check(chosen != null, "fixture has an ordinary encounter of two plain members")
	if chosen == null:
		return null
	var victim := chosen.members[0]
	var survivor := chosen.members[1]
	await _visit(world, chosen.centre)
	var victim_node := _live(world, victim.key)
	var survivor_node := _live(world, survivor.key)
	_check(victim_node != null and survivor_node != null, "the ordinary encounter streamed in")
	if victim_node == null or survivor_node == null:
		return null
	defeats.play_time += 30.0
	survivor_node.health = survivor_node.max_health - 1
	victim_node.die()
	await get_tree().process_frame
	_check(defeats.deaths.has(victim.key), "the ordinary death was recorded")

	# A Fixed-encounter leader, a Boss when one dies plainly.
	var leader: EncounterMember = null
	for key in everything.members:
		var member := everything.members[key]
		if member.fixed and member.leader and _dies_at_once(member) and (leader == null
				or graph.rooms[member.room_key].role == GeneratedRoom.Role.BOSS):
			leader = member
	_check(leader != null, "fixture has a plain Fixed-encounter leader")
	if leader == null:
		return null
	var boss_leader := graph.rooms[leader.room_key].role == GeneratedRoom.Role.BOSS
	await _visit(world, leader.tile)
	var leader_node := _live(world, leader.key)
	_check(leader_node != null, "the Fixed leader streamed in")
	if leader_node != null:
		leader_node.die()
	await get_tree().process_frame

	# A reactive Object's state.
	var site: ObjectSite = null
	for key in graph.sites:
		if graph.sites[key].kind == ObjectSite.Kind.WEIGHTED and graph.sites[key].scene.resource_path == GREETER:
			site = graph.sites[key]
			break
	_check(site != null, "fixture plans a greeter")
	if site == null:
		return null
	await _visit(world, site.spot + BESIDE)
	var greeter := _live(world, site.key)
	_check(greeter != null, "the greeter streamed in")
	if greeter != null:
		world._set_flying(false)
		world._player.global_position = greeter.global_position + Vector2(0, -4)
		for _frame in 4:
			await get_tree().physics_frame
		world._set_flying(true)
		_check(greeter.has_greeted(), "walking into the greeter changed its state")

	# A Pin on fog and a revealed, undiscovered Boss.
	var revealed_boss := ""
	for room in graph.room_list:
		if room.role == GeneratedRoom.Role.BOSS and room.key() != leader.room_key \
				and not GlobalMap.active.entered_rooms.has(room.key()):
			revealed_boss = room.key()
			break
	_check(revealed_boss != "", "fixture has an undiscovered Boss to reveal")
	GlobalMap.reveal_boss_room(revealed_boss)
	GlobalMap.toggle_pin(Vector2i(-3, -3), 0)

	# Where the player stands, hurt, as the Run is quit.
	await _visit(world, site.spot + BESIDE)
	world._player.health = world._player.max_health - 7
	var expected := {"seed": world.world_seed, "position": world._player.global_position,
			"health": world._player.health, "inventory": _inventory_paths(), "map": _map_view(GlobalMap.active),
			"defeated": defeats.defeated.duplicate(), "deaths": defeats.deaths.duplicate(),
			"play_time": defeats.play_time, "objects": world._object_spawner.saved_states()}
	_check(expected.defeated.has(leader.key), "the Fixed defeat was recorded")
	_check(not expected.objects.is_empty(), "the greeter's state is saved")
	GameState.persist() # Quit
	world.queue_free()
	await get_tree().process_frame

	# A fresh launch: nothing of the Run is left in memory.
	GlobalInventory.reset()
	GlobalMap.reset()
	GameState.active_seed = 0
	_check(GameState.has_save() and GameState.continue_game(), "Continue is offered for the quit Run")
	world = await _enter()

	_check(world.world_seed == expected.seed and WorldFixture.graph_snapshot(world._graph) == graph_text,
			"Continue rebuilt the saved World")
	_check(world._player.global_position == expected.position, "Continue restored the player's position: %s, want %s"
			% [world._player.global_position, expected.position])
	_check(world._player.health == expected.health, "Continue restored the player's health: %d, want %d"
			% [world._player.health, expected.health])
	_check(_inventory_paths() == expected.inventory, "Continue restored the inventory")
	var map_view := _map_view(GlobalMap.active)
	for part in ["entered", "pins", "revealed", "markers"]:
		_check(map_view[part] == expected.map[part], "Continue restored the Map's %s: %s, want %s"
				% [part, map_view[part], expected.map[part]])
	_check(map_view.images.keys() == expected.map.images.keys() and map_view.images == expected.map.images,
			"Continue redrew the discovered macro cells identically")
	var markers: Array = GlobalMap.active.markers
	_check(markers.any(func(m: Dictionary) -> bool: return m.room_key == revealed_boss and m.project),
			"the revealed Boss projects over fog after Continue")
	if boss_leader:
		_check(not markers.any(func(m: Dictionary) -> bool: return m.room_key == leader.room_key),
				"the defeated Boss has no marker after Continue")

	var restored: RunDefeats = world._encounter_spawner.defeats
	_check(restored.defeated == expected.defeated and restored.deaths == expected.deaths,
			"Continue restored the Run's defeats and death times")
	_check(restored.play_time >= expected.play_time and restored.play_time < expected.play_time + 1.0,
			"play time resumed from the save (%.2f, saved %.2f)" % [restored.play_time, expected.play_time])
	_check(world._object_spawner.saved_states() == expected.objects, "Continue restored Object states")
	var again := _live(world, site.key)
	_check(again != null and again.has_greeted(), "the restored greeter remembers greeting")

	await _visit(world, leader.tile)
	_check(_live(world, leader.key) == null, "the defeated Fixed leader stayed defeated after Continue")
	await _visit(world, chosen.centre)
	_check(_live(world, victim.key) == null, "the dead member respawned on Continue before its delay")
	var returned := _live(world, survivor.key)
	_check(returned != null and returned.health == returned.max_health, "the hurt survivor returned at full health")

	# The delay passing in play brings the dead member back on its next stream-in.
	restored.play_time += world._graph.plan.content.curve.respawn_delay
	await _reload(world, chosen.centre)
	_check(_live(world, victim.key) != null and not restored.deaths.has(victim.key),
			"the dead member respawned once its delay passed in play")
	return world


func _test_save_restrictions(world: Node2D) -> void:
	var saved := FileAccess.get_file_as_bytes(SAVE)
	await _visit(world, world._graph.tile_of(world._graph.room_list[0].seed))
	GlobalInventory.bag_slots.at(0).set_item(load(SPELL))
	_check(GameState.run_save_eligible and FileAccess.get_file_as_bytes(SAVE) != saved,
			"movement and an item change still save the Run")

	var layer: WorldDebugLayer = world._debug_layer
	_check(layer != null, "the development World has its debug layer")
	if layer == null:
		return
	saved = FileAccess.get_file_as_bytes(SAVE)
	layer._reseed(world.world_seed + 1)
	await get_tree().process_frame
	GlobalInventory.bag_slots.at(0).clear_item()
	GameState.persist()
	_check(not GameState.run_save_eligible and FileAccess.get_file_as_bytes(SAVE) == saved,
			"a seed edit stopped every Run write")

	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""
	GameState.persist()
	saved = FileAccess.get_file_as_bytes(SAVE)
	var biome: StringName = layer.tuner.content.biome_ids()[0]
	var rockiness: float = layer.tuner.pending[biome][&"rockiness"]
	layer.tuner.set_knob(biome, &"rockiness", 0.9 if rockiness != 0.9 else 0.8)
	GlobalInventory.bag_slots.at(0).set_item(load(OTHER_SPELL))
	GlobalMap.toggle_pin(Vector2i(-5, -5), 0)
	GameState.persist()
	_check(not GameState.run_save_eligible and FileAccess.get_file_as_bytes(SAVE) == saved,
			"a knob edit stopped every Run write")
	layer.tuner.revert_knob(biome, &"rockiness")
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""
	GameState.persist()


func _test_version_mismatch() -> void:
	var cfg := ConfigFile.new()
	_check(cfg.load(SAVE) == OK and cfg.get_value("run", "version", "") == GameState.app_version(),
			"the save carries this build's version")
	var bytes := FileAccess.get_file_as_bytes(SAVE)
	cfg.set_value("run", "version", GameState.app_version() + "-other")
	cfg.save(SAVE)
	_check(not GameState.has_save() and not GameState.continue_game() and not GameState.continuing_run(),
			"a save from another version isn't offered to Continue")
	_restore(SAVE, {"exists": true, "bytes": bytes})
	_check(GameState.has_save(), "restoring the version offers Continue again")


func _test_death(world: Node2D) -> void:
	# Collection progress to protect, written to their own files.
	var pickup := GlobalInventory.Slot.new(GlobalInventory.ItemType.BAG)
	pickup.item = load(SPELL)
	GlobalEvent.item_picked_up.emit(pickup)
	GlobalBestiary._save()
	var bestiary := GlobalBestiary.to_dict()
	var grimoire := GlobalGrimoire.to_dict()
	_check(not bestiary.kills.is_empty() and not grimoire.learned.is_empty(), "the Run left collection progress")

	# Death changes to the title; let it replace a stand-in rather than this test.
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	world._set_flying(false)
	world._player._on_hurt(world._player.health + 1000, world._player)
	await get_tree().process_frame
	await get_tree().process_frame
	var title := get_tree().current_scene
	_check(not FileAccess.file_exists(SAVE) and not GameState.has_save(), "death deleted the Run save")
	_check(GlobalMap.active == null and _inventory_paths().all(func(p: String) -> bool: return p == ""),
			"death discarded the Map and inventory")
	_check(title != null and title.scene_file_path == "res://scenes/title.tscn"
			and title.get_node("%ContinueButton").disabled, "the title offers no Continue after death")
	GlobalBestiary.restore({})
	GlobalBestiary._load()
	GlobalGrimoire.restore({})
	GlobalGrimoire._load()
	_check(GlobalBestiary.to_dict() == bestiary and GlobalGrimoire.to_dict() == grimoire,
			"the Bestiary and Grimoire files survived death")
	world.queue_free()
	if title != null and title != self:
		title.queue_free()
	await get_tree().process_frame


func _snapshot(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"exists": false, "bytes": PackedByteArray()}
	return {"exists": true, "bytes": FileAccess.get_file_as_bytes(path)}


func _restore(path: String, snap: Dictionary) -> void:
	if not snap["exists"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(snap["bytes"])
	f.close()


func _snapshot_state(section: String) -> Dictionary:
	var out := {}
	for key in DebugState.keys(section):
		out[key] = DebugState.get_value(section, key)
	return out


func _restore_state(section: String, values: Dictionary) -> void:
	for key in DebugState.keys(section):
		if not values.has(key):
			DebugState.erase(section, key)
	for key in values:
		DebugState.set_value(section, key, values[key])
