extends Node
## The normal game on the shipped World after the cutover, driven through the real title and World
## scenes: New starts in the backdrop's already planned World, whose spawn streams tiles,
## encounters and Objects and builds the Map; Quit returns to a title offering Continue, which plans
## the saved seed itself and restores the Map; a knob edit then stops every write while the World
## keeps playing; and the console's reload warns about unsaved knobs before rebuilding. Run:
##   godot --headless --path game res://tests/generation/test_game_lifecycle.tscn

const TITLE := "res://scenes/title.tscn"
const SAVE := "user://test_game_lifecycle_save.cfg"

var _fails: Array[String] = []


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var debug_state := {"world_debug": _snapshot_state("world_debug")}
	# Fly left on by a debug session must not carry into a Run.
	DebugState.set_value("world_debug", "fly", true)
	GameState.save_path = SAVE
	if FileAccess.file_exists(SAVE):
		DirAccess.remove_absolute(SAVE)
	# The root is still setting up this scene; the title joins it a frame later.
	await get_tree().process_frame

	await _test_new_quit_continue()

	# Leave whatever scene the lifecycle ended in.
	var scene := get_tree().current_scene
	if scene != null and scene != self:
		scene.queue_free()
	get_tree().current_scene = self
	await get_tree().process_frame
	GameState.clear_save()
	GameState.save_path = GameState.SAVE_PATH
	GameState.run_save_eligible = true
	GameState.run_save_disabled_reason = ""
	GlobalInventory.reset()
	for section in debug_state:
		_restore_state(section, debug_state[section])
	print("game lifecycle tests took %.1f s" % ((Time.get_ticks_msec() - started) / 1000.0))
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


## Opens the title as the current scene, so its scene changes replace it rather than this test.
func _open_title() -> Control:
	var title: Control = load(TITLE).instantiate()
	get_tree().root.add_child(title)
	get_tree().current_scene = title
	var backdrop: CanvasLayer = title.get_node("TitleBackdrop")
	if backdrop.graph == null:
		await backdrop.planned
	return title


## Waits for a deferred scene change to land.
func _scene_after_change() -> Node:
	for _frame in 3:
		await get_tree().process_frame
	return get_tree().current_scene


func _test_new_quit_continue() -> void:
	var title := await _open_title()
	var backdrop_graph: WorldGraph = title.get_node("TitleBackdrop").graph
	_check(title.get_node("%ContinueButton").disabled != GameState.has_save(),
			"the title's Continue follows whether a save exists")
	title._on_new()
	var world: Node = await _scene_after_change()
	_check(world != null and world.scene_file_path == "res://scenes/world.tscn", "New opened the World")
	if world == null or world.scene_file_path != "res://scenes/world.tscn":
		return
	_check(world._graph == backdrop_graph and GameState.active_seed == backdrop_graph.plan.world_seed,
			"New reused the backdrop's seed and plan")
	_check(not world._flying and world._player.process_mode == Node.PROCESS_MODE_INHERIT,
			"New starts on foot despite a stored debug Fly")
	var graph_text := WorldFixture.graph_snapshot(world._graph)
	_check(world._streamer.loaded_chunks() > 0, "the spawn's chunks streamed in")
	_check(GlobalMap.active != null and GlobalMap.active.graph == world._graph
			and GlobalMap.active.entered_rooms.has(world._graph.plan.spawn.key),
			"the Map follows the World and discovered the spawn")
	_check(GameState.has_save(), "entering the New Run saved it")
	_check(get_tree().get_first_node_in_group("pickups").get_child_count() > 0,
			"the starter hand lies beside the player")

	# Walk to a Room with an encounter and an Object nearby, streaming both in.
	var encounter_room: GeneratedRoom = null
	var object_room: GeneratedRoom = null
	for room in world._graph.room_list:
		if encounter_room == null and room.role == GeneratedRoom.Role.TESTING:
			encounter_room = room
		if object_room == null and room.sites.any(func(site: ObjectSite) -> bool:
				return site.kind == ObjectSite.Kind.WEIGHTED):
			object_room = room
	world._set_flying(true)
	for room in [encounter_room, object_room]:
		world._teleport_to_tile(world._graph.tile_of(room.seed_point))
		await get_tree().process_frame
	_check(not world._encounter_spawner.live_members().is_empty(), "encounters streamed in around the player")
	_check(not world._object_spawner.live_objects().is_empty(), "Objects streamed in around the player")
	var entered: Array = GlobalMap.active.entered_rooms.keys()
	entered.sort()
	_check(entered.size() >= 3, "walking discovered the Rooms on the way (%d)" % entered.size())

	# Quit from the HUD.
	world.get_node("UI").get_node("%QuitButton").pressed.emit()
	title = await _scene_after_change()
	_check(title != null and title.scene_file_path == TITLE, "Quit returned to the title")
	if title == null or title.scene_file_path != TITLE:
		return
	var backdrop: CanvasLayer = title.get_node("TitleBackdrop")
	if backdrop.graph == null:
		await backdrop.planned
	_check(not title.get_node("%ContinueButton").disabled, "the title offers Continue after Quit")
	var second_backdrop_graph: WorldGraph = backdrop.graph

	title._on_continue()
	world = await _scene_after_change()
	_check(world != null and world.scene_file_path == "res://scenes/world.tscn", "Continue opened the World")
	if world == null or world.scene_file_path != "res://scenes/world.tscn":
		return
	_check(world._graph != second_backdrop_graph and world._graph.plan.world_seed == backdrop_graph.plan.world_seed,
			"Continue planned the saved seed rather than the backdrop's")
	_check(not world._flying, "Continue starts on foot despite a stored debug Fly")
	_check(WorldFixture.graph_snapshot(world._graph) == graph_text, "Continue planned the same World")
	var restored: Array = GlobalMap.active.entered_rooms.keys()
	restored.sort()
	_check(restored == entered, "Continue restored the Map's entered Rooms")
	_check(not world._encounter_spawner.live_members().is_empty(), "encounters streamed in on Continue")

	# Save restrictions after the cutover: play saves, a knob edit stops every write.
	var layer: WorldDebugLayer = world._debug_layer
	_check(layer != null, "the World has its debug layer")
	if layer == null:
		return
	var saved := FileAccess.get_file_as_bytes(SAVE)
	world._teleport_to_tile(world._graph.tile_of(encounter_room.seed_point))
	GameState.persist()
	_check(FileAccess.get_file_as_bytes(SAVE) != saved, "movement still saves the Run")
	saved = FileAccess.get_file_as_bytes(SAVE)
	var biome: StringName = layer.tuner.content.biome_ids()[0]
	var rockiness: float = layer.tuner.pending[biome][&"rockiness"]
	layer.tuner.set_knob(biome, &"rockiness", 0.3 if rockiness != 0.3 else 0.2)
	GameState.persist()
	GlobalMap.toggle_pin(Vector2i(2, 2), 0)
	_check(not GameState.can_save_run() and FileAccess.get_file_as_bytes(SAVE) == saved,
			"a knob edit stopped every Run write after the cutover")

	# Reload warns about the unsaved knob with its Biome, then rebuilds on a second reload.
	var console := get_node_or_null("/root/DebugConsole")
	_check(console != null, "the debug console is present")
	if console == null:
		return
	var graph_before: WorldGraph = world._graph
	console._run("reload")
	_check(String(console._lines[-1]).contains(String(biome)) and world._graph == graph_before,
			"reload names the Biome with unsaved knobs and keeps the World: %s" % console._lines[-1])
	console._run("reload")
	_check(world._graph != graph_before and layer.tuner.unsaved_biomes().is_empty()
			and layer.tuner.graph == world._graph, "a second reload rebuilt the World from reread content")
	_check(world._graph.plan.world_seed == graph_before.plan.world_seed
			and GlobalMap.active.entered_rooms.size() == restored.size(),
			"reload kept the seed and the Run's Map")

	# A death followed by New must bind the fresh minimap to the fresh Run.
	world._set_flying(false)
	world._player._die(world._player)
	title = await _scene_after_change()
	_check(title != null and title.scene_file_path == TITLE, "death returned to the title")
	if title == null or title.scene_file_path != TITLE:
		return
	backdrop = title.get_node("TitleBackdrop")
	if backdrop.graph == null:
		await backdrop.planned
	title._on_new()
	world = await _scene_after_change()
	_check(world != null and world.scene_file_path == "res://scenes/world.tscn",
			"New after death opened the World")
	if world == null or world.scene_file_path != "res://scenes/world.tscn":
		return
	var minimap: Control = world.get_node("UI/Strip/VBox/MapPanel/Minimap")
	_check(minimap._state == GlobalMap.active and minimap._player == world._player,
			"New after death bound the minimap to the fresh Map and player")


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
